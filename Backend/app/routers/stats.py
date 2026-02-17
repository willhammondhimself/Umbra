from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.stats import StatsResponse
from app.services import stats_service

router = APIRouter(prefix="/stats", tags=["stats"])


@router.get("", response_model=StatsResponse)
async def get_stats(
    period: str = Query(default="weekly", pattern="^(daily|weekly|monthly)$"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await stats_service.get_stats(db, user.id, period=period)
