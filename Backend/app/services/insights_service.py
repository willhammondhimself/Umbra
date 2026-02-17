import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session
from app.models.session_event import SessionEvent
from app.schemas.insights import (
    DistractionPattern,
    FocusTrend,
    HeatmapEntry,
    OptimalSessionLength,
    SmartGoal,
)


async def get_focus_heatmap(
    db: AsyncSession, user_id: uuid.UUID, days: int = 30
) -> list[HeatmapEntry]:
    """Aggregate focused time by hour-of-day and day-of-week from sessions.

    Uses Python-side aggregation for cross-database compatibility
    (SQLite strftime vs Postgres extract).
    """
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)

    result = await db.execute(
        select(Session).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        )
    )
    sessions = result.scalars().all()

    # Aggregate by (hour, day_of_week)
    grid: dict[tuple[int, int], float] = defaultdict(float)
    for s in sessions:
        st = s.start_time
        # Python weekday(): Monday=0 .. Sunday=6
        dow = st.weekday()
        hour = st.hour
        grid[(hour, dow)] += s.focused_seconds / 60.0

    return [
        HeatmapEntry(hour=hour, day_of_week=dow, focused_minutes=round(minutes, 1))
        for (hour, dow), minutes in sorted(grid.items())
    ]


async def get_focus_trend(
    db: AsyncSession, user_id: uuid.UUID, days: int = 30
) -> list[FocusTrend]:
    """Daily focus trend: focused_minutes, session_count, distraction_count per day.

    Uses func.date() for cross-database date grouping (works on both
    SQLite and Postgres).
    """
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)

    date_expr = func.date(Session.start_time)

    result = await db.execute(
        select(
            date_expr.label("day"),
            func.coalesce(func.sum(Session.focused_seconds), 0).label(
                "focused_seconds"
            ),
            func.count(Session.id).label("session_count"),
            func.coalesce(func.sum(Session.distraction_count), 0).label(
                "distraction_count"
            ),
        )
        .where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        )
        .group_by(date_expr)
        .order_by(date_expr)
    )

    rows = result.all()
    return [
        FocusTrend(
            date=str(row.day),
            focused_minutes=round((row.focused_seconds or 0) / 60.0, 1),
            session_count=row.session_count,
            distraction_count=row.distraction_count,
        )
        for row in rows
    ]


async def get_distraction_patterns(
    db: AsyncSession, user_id: uuid.UUID, days: int = 30
) -> list[DistractionPattern]:
    """Top distracting apps from session events.

    Joins session_events with sessions to filter by user and date range,
    then groups by app_name for DISTRACTION events.
    """
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)

    result = await db.execute(
        select(
            SessionEvent.app_name,
            func.count(SessionEvent.id).label("count"),
            func.coalesce(func.sum(SessionEvent.duration_seconds), 0).label(
                "total_duration"
            ),
        )
        .join(Session, Session.id == SessionEvent.session_id)
        .where(
            Session.user_id == user_id,
            Session.start_time >= start,
            SessionEvent.event_type == "DISTRACTION",
            SessionEvent.app_name.isnot(None),
        )
        .group_by(SessionEvent.app_name)
        .order_by(func.count(SessionEvent.id).desc())
        .limit(10)
    )

    return [
        DistractionPattern(
            app_name=row.app_name,
            count=row.count,
            total_duration_seconds=row.total_duration,
        )
        for row in result.all()
    ]


async def get_optimal_session_length(
    db: AsyncSession, user_id: uuid.UUID
) -> OptimalSessionLength:
    """Calculate optimal session length based on focus ratio.

    Buckets sessions by duration into common intervals (15m, 25m, 45m, 60m, 90m),
    computes average focus_ratio per bucket, and returns the bucket with the
    highest ratio. Minimum 3 sessions per bucket to be considered.
    """
    result = await db.execute(
        select(Session).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.duration_seconds > 0,
        )
    )
    sessions = result.scalars().all()

    # Duration bucket boundaries in seconds: (label_minutes, min_seconds, max_seconds)
    buckets = [
        (15, 0, 20 * 60),
        (25, 20 * 60, 35 * 60),
        (45, 35 * 60, 52 * 60),
        (60, 52 * 60, 75 * 60),
        (90, 75 * 60, float("inf")),
    ]

    bucket_data: dict[int, list[float]] = {label: [] for label, _, _ in buckets}

    for s in sessions:
        ratio = s.focused_seconds / s.duration_seconds if s.duration_seconds > 0 else 0
        for label, lo, hi in buckets:
            if lo <= s.duration_seconds < hi:
                bucket_data[label].append(ratio)
                break

    # Find the bucket with the highest average focus ratio (min 3 samples)
    best_label = 25  # sensible default
    best_ratio = 0.0
    best_count = 0

    for label, ratios in bucket_data.items():
        if len(ratios) >= 3:
            avg = sum(ratios) / len(ratios)
            if avg > best_ratio:
                best_ratio = avg
                best_label = label
                best_count = len(ratios)

    # If no bucket has enough samples, use the bucket with the most sessions
    if best_count == 0:
        for label, ratios in bucket_data.items():
            if len(ratios) > best_count:
                best_count = len(ratios)
                best_label = label
                best_ratio = (
                    sum(ratios) / len(ratios) if ratios else 0.0
                )

    return OptimalSessionLength(
        recommended_minutes=best_label,
        avg_focus_ratio=round(best_ratio, 3),
        sample_size=best_count,
    )


async def get_smart_goals(
    db: AsyncSession, user_id: uuid.UUID
) -> list[SmartGoal]:
    """Generate personalized goals based on recent performance.

    Compares the current week's stats to the previous week's stats and
    suggests improvement targets.
    """
    now = datetime.now(timezone.utc)
    current_week_start = now - timedelta(days=7)
    previous_week_start = now - timedelta(days=14)

    async def _week_stats(start: datetime, end: datetime) -> dict:
        result = await db.execute(
            select(
                func.coalesce(func.sum(Session.focused_seconds), 0).label(
                    "focused_seconds"
                ),
                func.count(Session.id).label("session_count"),
                func.coalesce(func.sum(Session.distraction_count), 0).label(
                    "distraction_count"
                ),
            ).where(
                Session.user_id == user_id,
                Session.is_complete == True,  # noqa: E712
                Session.start_time >= start,
                Session.start_time < end,
            )
        )
        row = result.one()
        return {
            "focused_seconds": row.focused_seconds,
            "session_count": row.session_count,
            "distraction_count": row.distraction_count,
        }

    current = await _week_stats(current_week_start, now)
    previous = await _week_stats(previous_week_start, current_week_start)

    # Calculate streak
    date_expr = func.date(Session.start_time)
    streak_result = await db.execute(
        select(date_expr.label("session_date"))
        .where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
        )
        .group_by(date_expr)
        .order_by(date_expr.desc())
    )
    raw_dates = [row.session_date for row in streak_result.all()]
    streak = _calculate_streak(raw_dates)

    goals: list[SmartGoal] = []

    # Goal 1: Daily focus target (10% improvement over last week's daily average)
    current_daily_focus = current["focused_seconds"] / 7 / 60  # minutes
    if previous["focused_seconds"] > 0:
        prev_daily_focus = previous["focused_seconds"] / 7 / 60
        target_focus = round(prev_daily_focus * 1.1, 0)
    else:
        target_focus = 60.0  # Default: 60 minutes per day
    goals.append(
        SmartGoal(
            goal_type="daily_focus",
            target_value=target_focus,
            current_value=round(current_daily_focus, 1),
            description=f"Focus for {int(target_focus)} minutes daily",
        )
    )

    # Goal 2: Session count target
    current_sessions = current["session_count"]
    if previous["session_count"] > 0:
        target_sessions = max(previous["session_count"] + 1, current_sessions)
    else:
        target_sessions = 5  # Default: 5 sessions per week
    goals.append(
        SmartGoal(
            goal_type="session_count",
            target_value=float(target_sessions),
            current_value=float(current_sessions),
            description=f"Complete {target_sessions} focus sessions this week",
        )
    )

    # Goal 3: Distraction reduction (reduce by 20%)
    current_distractions = current["distraction_count"]
    if previous["distraction_count"] > 0:
        target_distractions = max(
            0, round(previous["distraction_count"] * 0.8)
        )
    else:
        target_distractions = 0
    goals.append(
        SmartGoal(
            goal_type="distraction_reduction",
            target_value=float(target_distractions),
            current_value=float(current_distractions),
            description=(
                f"Keep distractions below {int(target_distractions)} this week"
                if target_distractions > 0
                else "Stay distraction-free this week"
            ),
        )
    )

    # Goal 4: Streak goal
    target_streak = max(streak + 1, 3)
    goals.append(
        SmartGoal(
            goal_type="streak",
            target_value=float(target_streak),
            current_value=float(streak),
            description=f"Build a {target_streak}-day focus streak",
        )
    )

    return goals


def _calculate_streak(raw_dates: list) -> int:
    """Calculate consecutive days with sessions ending at today."""
    if not raw_dates:
        return 0

    dates: list[date] = []
    for d in raw_dates:
        if isinstance(d, str):
            dates.append(date.fromisoformat(d))
        elif isinstance(d, date):
            dates.append(d)

    today = date.today()
    streak = 0
    expected = today

    for d in dates:
        if d == expected:
            streak += 1
            expected -= timedelta(days=1)
        elif d < expected:
            break

    return streak
