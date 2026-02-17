import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session


async def get_stats(
    db: AsyncSession,
    user_id: uuid.UUID,
    period: str = "weekly",
) -> dict:
    now = datetime.now(timezone.utc)

    if period == "daily":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "weekly":
        start = now - timedelta(days=7)
    elif period == "monthly":
        start = now - timedelta(days=30)
    else:
        start = now - timedelta(days=7)

    # Aggregate stats
    result = await db.execute(
        select(
            func.coalesce(func.sum(Session.focused_seconds), 0).label("focused_seconds"),
            func.coalesce(func.sum(Session.duration_seconds), 0).label("total_seconds"),
            func.count(Session.id).label("session_count"),
            func.coalesce(func.sum(Session.distraction_count), 0).label("distraction_count"),
        ).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        )
    )
    row = result.one()

    # Daily breakdown using date() function (works on both SQLite and Postgres)
    date_expr = func.date(Session.start_time)
    daily_result = await db.execute(
        select(
            date_expr.label("day"),
            func.sum(Session.focused_seconds).label("focused_seconds"),
            func.count(Session.id).label("session_count"),
        ).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        ).group_by(
            date_expr
        ).order_by(
            date_expr
        )
    )
    daily = [
        {
            "date": str(d.day),
            "focused_seconds": d.focused_seconds or 0,
            "session_count": d.session_count,
        }
        for d in daily_result.all()
    ]

    # Streak calculation
    streak = await calculate_streak(db, user_id)

    return {
        "period": period,
        "focused_seconds": row.focused_seconds,
        "total_seconds": row.total_seconds,
        "session_count": row.session_count,
        "distraction_count": row.distraction_count,
        "current_streak": streak,
        "daily_breakdown": daily,
    }


async def calculate_streak(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Calculate consecutive days with completed sessions ending today."""
    date_expr = func.date(Session.start_time)
    result = await db.execute(
        select(
            date_expr.label("session_date"),
        ).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
        ).group_by(
            date_expr
        ).order_by(
            date_expr.desc()
        )
    )
    raw_dates = [row.session_date for row in result.all()]

    if not raw_dates:
        return 0

    # Parse string dates from SQLite or date objects from Postgres
    dates = []
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
