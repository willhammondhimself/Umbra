import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.insights import (
    AICoachingNudge,
    AIGoalsResponse,
    AISessionSummary,
    HeatmapEntry,
    InsightsResponse,
    SmartGoal,
)
from app.services import insights_service
from app.services.ai_coaching_service import (
    create_provider,
    generate_coaching_nudge,
    generate_goal_suggestions,
    generate_session_summary,
)

router = APIRouter(prefix="/insights", tags=["insights"])


@router.get("", response_model=InsightsResponse)
async def get_insights(
    days: int = Query(default=30, ge=7, le=90),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    heatmap = await insights_service.get_focus_heatmap(db, user.id, days=days)
    trends = await insights_service.get_focus_trend(db, user.id, days=days)
    top_distractors = await insights_service.get_distraction_patterns(
        db, user.id, days=days
    )
    optimal_session = await insights_service.get_optimal_session_length(db, user.id)
    goals = await insights_service.get_smart_goals(db, user.id)

    return InsightsResponse(
        heatmap=heatmap,
        trends=trends,
        top_distractors=top_distractors,
        optimal_session=optimal_session,
        goals=goals,
    )


@router.get("/heatmap", response_model=list[HeatmapEntry])
async def get_heatmap(
    days: int = Query(default=30, ge=7, le=90),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await insights_service.get_focus_heatmap(db, user.id, days=days)


@router.get("/goals", response_model=list[SmartGoal])
async def get_goals(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await insights_service.get_smart_goals(db, user.id)


# ---------------------------------------------------------------------------
# AI Coaching Endpoints
# ---------------------------------------------------------------------------


@router.post("/session-summary", response_model=AISessionSummary)
async def session_summary(
    session_id: uuid.UUID,
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate an AI-powered summary for a completed focus session."""
    provider = create_provider(settings)
    redis_client = getattr(req.app.state, "redis", None)

    result = await generate_session_summary(
        db, user.id, session_id, provider, redis_client
    )
    return AISessionSummary(
        summary=result["summary"],
        is_ai_generated=result["is_ai_generated"],
    )


@router.get("/nudge", response_model=AICoachingNudge)
async def coaching_nudge(
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a coaching nudge based on recent productivity patterns."""
    provider = create_provider(settings)
    redis_client = getattr(req.app.state, "redis", None)

    result = await generate_coaching_nudge(db, user.id, provider, redis_client)
    return AICoachingNudge(
        nudge=result["nudge"],
        is_ai_generated=result["is_ai_generated"],
    )


@router.get("/goals/ai", response_model=AIGoalsResponse)
async def ai_goals(
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate AI-powered goal suggestions for the week."""
    provider = create_provider(settings)
    redis_client = getattr(req.app.state, "redis", None)

    result = await generate_goal_suggestions(db, user.id, provider, redis_client)
    return AIGoalsResponse(
        goals=result["goals"],
        is_ai_generated=result["is_ai_generated"],
    )
