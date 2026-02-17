"""AI Coaching Service — provider-agnostic LLM integration.

Provides session summaries, coaching nudges, and AI-powered goal suggestions
using pluggable LLM providers (OpenAI, Anthropic). Falls back to rule-based
responses when no provider is configured or rate limits are exceeded.
"""

import json
import logging
import uuid
from abc import ABC, abstractmethod
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session
from app.models.session_event import SessionEvent
from app.models.task import Task

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# LLM Provider Abstraction
# ---------------------------------------------------------------------------


class LLMProvider(ABC):
    """Abstract base for LLM providers."""

    @abstractmethod
    async def generate(self, system_prompt: str, user_prompt: str) -> str:
        """Generate a response from the LLM."""
        ...


class OpenAIProvider(LLMProvider):
    """OpenAI-compatible provider (GPT-4o-mini default)."""

    def __init__(self, api_key: str, model: str = "gpt-4o-mini"):
        self.api_key = api_key
        self.model = model

    async def generate(self, system_prompt: str, user_prompt: str) -> str:
        from openai import AsyncOpenAI

        client = AsyncOpenAI(api_key=self.api_key)
        response = await client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            max_tokens=500,
            temperature=0.7,
        )
        return response.choices[0].message.content or ""


class AnthropicProvider(LLMProvider):
    """Anthropic-compatible provider (Claude Sonnet default)."""

    def __init__(self, api_key: str, model: str = "claude-sonnet-4-6"):
        self.api_key = api_key
        self.model = model

    async def generate(self, system_prompt: str, user_prompt: str) -> str:
        from anthropic import AsyncAnthropic

        client = AsyncAnthropic(api_key=self.api_key)
        response = await client.messages.create(
            model=self.model,
            max_tokens=500,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
        )
        return response.content[0].text


def create_provider(settings) -> LLMProvider | None:
    """Factory: create the configured LLM provider, or None if unconfigured."""
    if settings.AI_PROVIDER == "openai" and settings.OPENAI_API_KEY:
        return OpenAIProvider(
            settings.OPENAI_API_KEY,
            settings.AI_MODEL or "gpt-4o-mini",
        )
    elif settings.AI_PROVIDER == "anthropic" and settings.ANTHROPIC_API_KEY:
        return AnthropicProvider(
            settings.ANTHROPIC_API_KEY,
            settings.AI_MODEL or "claude-sonnet-4-6",
        )
    return None


# ---------------------------------------------------------------------------
# Prompt Templates
# ---------------------------------------------------------------------------

SESSION_SUMMARY_PROMPT = (
    "You are a supportive productivity coach. Analyze this focus session and "
    "provide brief, encouraging feedback (2-3 sentences). Focus on specific "
    "achievements and one suggestion for improvement."
)

SESSION_SUMMARY_USER = (
    "Session data:\n"
    "- Duration: {duration_minutes} minutes\n"
    "- Focused time: {focused_minutes} minutes ({focus_ratio:.0%} focus ratio)\n"
    "- Distractions: {distraction_count}\n"
    "- Tasks completed: {tasks_completed}"
)

COACHING_NUDGE_PROMPT = (
    "You are a productivity coach. Based on the user's recent patterns, "
    "provide one brief, actionable nudge (1-2 sentences). Be specific "
    "and encouraging."
)

COACHING_NUDGE_USER = (
    "User patterns:\n"
    "- Average daily focus: {avg_daily_focus_min} minutes\n"
    "- Most productive hour: {peak_hour}:00\n"
    "- Top distractor: {top_distractor}\n"
    "- Current streak: {streak_days} days"
)

GOAL_SUGGESTION_PROMPT = (
    "You are a productivity coach. Suggest 3 specific, achievable goals "
    "for this week based on the user's history. Format as a JSON array: "
    '[{{"goal": "...", "target": "...", "reasoning": "..."}}]'
)

GOAL_SUGGESTION_USER = (
    "Recent performance:\n"
    "- Avg daily focus: {avg_daily_focus_min} minutes\n"
    "- Sessions per day: {avg_sessions_per_day:.1f}\n"
    "- Focus ratio: {avg_focus_ratio:.0%}\n"
    "- Distraction trend: {distraction_trend}"
)


# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------


async def _check_rate_limit(
    redis_client, user_id: uuid.UUID, limit: int = 20
) -> bool:
    """Check and increment daily rate limit. Returns True if within limit."""
    key = f"ai_rate:{user_id}:{date.today().isoformat()}"
    count = await redis_client.incr(key)
    if count == 1:
        await redis_client.expire(key, 86400)
    return count <= limit


# ---------------------------------------------------------------------------
# Data Helpers
# ---------------------------------------------------------------------------


async def _get_session_data(
    db: AsyncSession, user_id: uuid.UUID, session_id: uuid.UUID
) -> dict | None:
    """Fetch session data for summary generation."""
    result = await db.execute(
        select(Session).where(
            Session.id == session_id,
            Session.user_id == user_id,
        )
    )
    session = result.scalar_one_or_none()
    if session is None:
        return None

    # Count completed tasks during this session (status=2 means done)
    tasks_result = await db.execute(
        select(func.count(Task.id)).where(
            Task.user_id == user_id,
            Task.status == 2,
            Task.updated_at >= session.start_time,
            Task.updated_at <= (session.end_time or datetime.now(UTC)),
        )
    )
    tasks_completed = tasks_result.scalar() or 0

    duration_seconds = session.duration_seconds or 0
    focused_seconds = session.focused_seconds or 0
    focus_ratio = focused_seconds / duration_seconds if duration_seconds > 0 else 0.0

    return {
        "duration_minutes": round(duration_seconds / 60, 1),
        "focused_minutes": round(focused_seconds / 60, 1),
        "focus_ratio": focus_ratio,
        "distraction_count": session.distraction_count or 0,
        "tasks_completed": tasks_completed,
    }


async def _get_user_patterns(db: AsyncSession, user_id: uuid.UUID) -> dict:
    """Gather recent patterns for coaching nudges."""
    now = datetime.now(UTC)
    start = now - timedelta(days=14)

    # Recent sessions
    result = await db.execute(
        select(Session).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        )
    )
    sessions = result.scalars().all()

    if not sessions:
        return {
            "avg_daily_focus_min": 0,
            "peak_hour": 9,
            "top_distractor": "none",
            "streak_days": 0,
        }

    # Average daily focus
    days_span = max((now - start).days, 1)
    total_focused = sum(s.focused_seconds for s in sessions)
    avg_daily_focus_min = round(total_focused / days_span / 60, 1)

    # Peak hour (hour with most focused seconds)
    hour_focus: dict[int, int] = {}
    for s in sessions:
        hour = s.start_time.hour
        hour_focus[hour] = hour_focus.get(hour, 0) + s.focused_seconds
    peak_hour = max(hour_focus, key=hour_focus.get) if hour_focus else 9

    # Top distractor
    distraction_result = await db.execute(
        select(SessionEvent.app_name, func.count(SessionEvent.id).label("cnt"))
        .join(Session, Session.id == SessionEvent.session_id)
        .where(
            Session.user_id == user_id,
            Session.start_time >= start,
            SessionEvent.event_type == "DISTRACTION",
            SessionEvent.app_name.isnot(None),
        )
        .group_by(SessionEvent.app_name)
        .order_by(func.count(SessionEvent.id).desc())
        .limit(1)
    )
    top_row = distraction_result.first()
    top_distractor = top_row.app_name if top_row else "none"

    # Streak calculation
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
    streak_days = _calculate_streak(raw_dates)

    return {
        "avg_daily_focus_min": avg_daily_focus_min,
        "peak_hour": peak_hour,
        "top_distractor": top_distractor,
        "streak_days": streak_days,
    }


async def _get_trend_data(db: AsyncSession, user_id: uuid.UUID) -> dict:
    """Gather trend data for goal suggestions."""
    now = datetime.now(UTC)
    start = now - timedelta(days=14)

    result = await db.execute(
        select(Session).where(
            Session.user_id == user_id,
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= start,
        )
    )
    sessions = result.scalars().all()

    if not sessions:
        return {
            "avg_daily_focus_min": 0,
            "avg_sessions_per_day": 0.0,
            "avg_focus_ratio": 0.0,
            "distraction_trend": "no data",
        }

    days_span = max((now - start).days, 1)
    total_focused = sum(s.focused_seconds for s in sessions)
    total_duration = sum(s.duration_seconds for s in sessions)
    avg_focus_ratio = total_focused / total_duration if total_duration > 0 else 0.0

    # Compare first vs second week distractions for trend
    midpoint = now - timedelta(days=7)
    # Normalize: SQLite may return naive datetimes, Postgres returns aware
    midpoint_naive = midpoint.replace(tzinfo=None)
    week1_distractions = sum(
        s.distraction_count
        for s in sessions
        if (s.start_time.replace(tzinfo=None) if s.start_time.tzinfo else s.start_time)
        < midpoint_naive
    )
    week2_distractions = sum(
        s.distraction_count
        for s in sessions
        if (s.start_time.replace(tzinfo=None) if s.start_time.tzinfo else s.start_time)
        >= midpoint_naive
    )

    if week1_distractions == 0 and week2_distractions == 0:
        distraction_trend = "stable"
    elif week2_distractions < week1_distractions:
        distraction_trend = "improving"
    elif week2_distractions > week1_distractions:
        distraction_trend = "increasing"
    else:
        distraction_trend = "stable"

    return {
        "avg_daily_focus_min": round(total_focused / days_span / 60, 1),
        "avg_sessions_per_day": round(len(sessions) / days_span, 1),
        "avg_focus_ratio": avg_focus_ratio,
        "distraction_trend": distraction_trend,
    }


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


# ---------------------------------------------------------------------------
# Fallback (Rule-Based) Responses
# ---------------------------------------------------------------------------


def _fallback_session_summary(
    duration_min: float,
    focused_min: float,
    distractions: int,
    tasks_completed: int,
) -> str:
    """Rule-based session summary when LLM is unavailable."""
    focus_ratio = focused_min / duration_min if duration_min > 0 else 0

    if focus_ratio >= 0.9:
        quality = "excellent"
    elif focus_ratio >= 0.75:
        quality = "solid"
    elif focus_ratio >= 0.5:
        quality = "decent"
    else:
        quality = "challenging"

    parts = [
        f"You completed a {quality} {duration_min:.0f}-minute session "
        f"with {focused_min:.0f} minutes of focused work."
    ]

    if tasks_completed > 0:
        parts.append(
            f" You finished {tasks_completed} task{'s' if tasks_completed > 1 else ''}!"
        )

    if distractions == 0:
        parts.append(" Zero distractions — impressive discipline!")
    elif distractions <= 2:
        parts.append(
            f" Only {distractions} distraction{'s' if distractions > 1 else ''}"
            " — keep that focus strong."
        )
    else:
        parts.append(
            f" You had {distractions} distractions. Try closing unnecessary "
            "apps before your next session."
        )

    return "".join(parts)


def _fallback_nudge(
    avg_focus_min: float, peak_hour: int, top_distractor: str
) -> str:
    """Rule-based coaching nudge when LLM is unavailable."""
    if avg_focus_min < 30:
        return (
            f"Try scheduling a 25-minute focus session around {peak_hour}:00 "
            "today — that's when you tend to do your best work."
        )
    elif top_distractor and top_distractor != "none":
        return (
            f"Consider blocking {top_distractor} during your next session. "
            f"Your peak focus time is around {peak_hour}:00."
        )
    else:
        return (
            f"You're averaging {avg_focus_min:.0f} minutes of focus daily. "
            "Push for 10% more today and build on your momentum!"
        )


def _fallback_goals(
    avg_daily_focus_min: float,
    avg_sessions_per_day: float,
    avg_focus_ratio: float,
) -> list[dict]:
    """Rule-based goal suggestions when LLM is unavailable."""
    target_focus = max(30, round(avg_daily_focus_min * 1.1))
    target_sessions = max(2, round(avg_sessions_per_day * 1.1))

    return [
        {
            "goal": f"Focus for {target_focus} minutes daily",
            "target": f"{target_focus} min/day",
            "reasoning": (
                f"You currently average {avg_daily_focus_min:.0f} minutes. "
                "A 10% increase is achievable and builds consistency."
            ),
        },
        {
            "goal": f"Complete {target_sessions} focus sessions daily",
            "target": f"{target_sessions} sessions/day",
            "reasoning": (
                f"You average {avg_sessions_per_day:.1f} sessions. "
                "Adding one more builds the habit."
            ),
        },
        {
            "goal": "Maintain a 3-day focus streak",
            "target": "3 consecutive days",
            "reasoning": (
                "Streaks reinforce habits. Start with 3 days "
                "and extend from there."
            ),
        },
    ]


# ---------------------------------------------------------------------------
# Main Service Functions
# ---------------------------------------------------------------------------


async def generate_session_summary(
    db: AsyncSession,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
    provider: LLMProvider | None,
    redis_client=None,
) -> dict:
    """Generate AI summary for a completed session.

    Returns dict with 'summary' and 'is_ai_generated' keys.
    """
    session_data = await _get_session_data(db, user_id, session_id)
    if session_data is None:
        return {"summary": "Session not found.", "is_ai_generated": False}

    # Check rate limit
    if redis_client and not await _check_rate_limit(redis_client, user_id):
        return {
            "summary": _fallback_session_summary(
                session_data["duration_minutes"],
                session_data["focused_minutes"],
                session_data["distraction_count"],
                session_data["tasks_completed"],
            ),
            "is_ai_generated": False,
        }

    # Try LLM generation
    if provider is not None:
        try:
            user_prompt = SESSION_SUMMARY_USER.format(**session_data)
            summary = await provider.generate(SESSION_SUMMARY_PROMPT, user_prompt)

            # Cache the result
            if redis_client:
                cache_key = f"ai_summary:{session_id}"
                await redis_client.set(cache_key, summary, ex=86400)

            return {"summary": summary, "is_ai_generated": True}
        except Exception:
            logger.exception("LLM generation failed for session summary")

    # Fallback
    return {
        "summary": _fallback_session_summary(
            session_data["duration_minutes"],
            session_data["focused_minutes"],
            session_data["distraction_count"],
            session_data["tasks_completed"],
        ),
        "is_ai_generated": False,
    }


async def generate_coaching_nudge(
    db: AsyncSession,
    user_id: uuid.UUID,
    provider: LLMProvider | None,
    redis_client=None,
) -> dict:
    """Generate a coaching nudge based on recent patterns.

    Returns dict with 'nudge' and 'is_ai_generated' keys.
    Caches results for 1 hour.
    """
    # Check cache (1hr TTL)
    if redis_client:
        cache_key = f"ai_nudge:{user_id}"
        cached = await redis_client.get(cache_key)
        if cached:
            return {"nudge": cached, "is_ai_generated": True}

    patterns = await _get_user_patterns(db, user_id)

    # Check rate limit
    if redis_client and not await _check_rate_limit(redis_client, user_id):
        return {
            "nudge": _fallback_nudge(
                patterns["avg_daily_focus_min"],
                patterns["peak_hour"],
                patterns["top_distractor"],
            ),
            "is_ai_generated": False,
        }

    # Try LLM generation
    if provider is not None:
        try:
            user_prompt = COACHING_NUDGE_USER.format(**patterns)
            nudge = await provider.generate(COACHING_NUDGE_PROMPT, user_prompt)

            # Cache for 1 hour
            if redis_client:
                await redis_client.set(cache_key, nudge, ex=3600)

            return {"nudge": nudge, "is_ai_generated": True}
        except Exception:
            logger.exception("LLM generation failed for coaching nudge")

    # Fallback
    return {
        "nudge": _fallback_nudge(
            patterns["avg_daily_focus_min"],
            patterns["peak_hour"],
            patterns["top_distractor"],
        ),
        "is_ai_generated": False,
    }


async def generate_goal_suggestions(
    db: AsyncSession,
    user_id: uuid.UUID,
    provider: LLMProvider | None,
    redis_client=None,
) -> dict:
    """Generate AI-powered goal suggestions.

    Returns dict with 'goals' list and 'is_ai_generated' key.
    Caches results for 24 hours.
    """
    # Check cache (24hr TTL)
    if redis_client:
        cache_key = f"ai_goals:{user_id}"
        cached = await redis_client.get(cache_key)
        if cached:
            try:
                goals = json.loads(cached)
                return {"goals": goals, "is_ai_generated": True}
            except json.JSONDecodeError:
                pass

    trend_data = await _get_trend_data(db, user_id)

    # Check rate limit
    if redis_client and not await _check_rate_limit(redis_client, user_id):
        return {
            "goals": _fallback_goals(
                trend_data["avg_daily_focus_min"],
                trend_data["avg_sessions_per_day"],
                trend_data["avg_focus_ratio"],
            ),
            "is_ai_generated": False,
        }

    # Try LLM generation
    if provider is not None:
        try:
            user_prompt = GOAL_SUGGESTION_USER.format(**trend_data)
            raw = await provider.generate(GOAL_SUGGESTION_PROMPT, user_prompt)

            # Parse JSON from LLM response
            goals = _parse_goals_json(raw)
            if goals:
                # Cache for 24 hours
                if redis_client:
                    await redis_client.set(cache_key, json.dumps(goals), ex=86400)

                return {"goals": goals, "is_ai_generated": True}
        except Exception:
            logger.exception("LLM generation failed for goal suggestions")

    # Fallback
    return {
        "goals": _fallback_goals(
            trend_data["avg_daily_focus_min"],
            trend_data["avg_sessions_per_day"],
            trend_data["avg_focus_ratio"],
        ),
        "is_ai_generated": False,
    }


def _parse_goals_json(raw: str) -> list[dict] | None:
    """Extract a JSON array of goals from LLM response text."""
    # Try direct parse first
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return _validate_goals(parsed)
    except json.JSONDecodeError:
        pass

    # Try extracting JSON from markdown code blocks or surrounding text
    start = raw.find("[")
    end = raw.rfind("]")
    if start != -1 and end != -1 and end > start:
        try:
            parsed = json.loads(raw[start : end + 1])
            if isinstance(parsed, list):
                return _validate_goals(parsed)
        except json.JSONDecodeError:
            pass

    return None


def _validate_goals(goals: list) -> list[dict]:
    """Ensure each goal dict has the required keys."""
    validated = []
    for g in goals:
        if isinstance(g, dict) and all(k in g for k in ("goal", "target", "reasoning")):
            validated.append(
                {
                    "goal": str(g["goal"]),
                    "target": str(g["target"]),
                    "reasoning": str(g["reasoning"]),
                }
            )
    return validated if validated else None
