import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.social import (
    EncourageRequest,
    FriendResponse,
    GroupResponse,
    InviteRequest,
    LeaderboardEntry,
    PingRequest,
)
from app.services import social_service

router = APIRouter(tags=["social"])


@router.get("/friends", response_model=list[FriendResponse])
async def list_friends(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await social_service.get_friends(db, user.id)


@router.post("/friends/invite", status_code=201)
async def invite_friend(
    data: InviteRequest,
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        result = await social_service.send_invite(db, user.id, data.email, req.app.state.redis)
        return result
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS
            if "limit" in str(e)
            else status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/friends/{friendship_id}/accept")
async def accept_friend(
    friendship_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    success = await social_service.accept_invite(db, user.id, friendship_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Invite not found or cannot accept"
        )
    return {"status": "accepted"}


@router.get("/groups", response_model=list[GroupResponse])
async def list_groups(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await social_service.get_groups(db, user.id)


@router.get("/groups/{group_id}/leaderboard", response_model=list[LeaderboardEntry])
async def group_leaderboard(
    group_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        return await social_service.get_leaderboard(db, group_id, user.id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(e))


@router.post("/social/encourage", status_code=201)
async def encourage(
    data: EncourageRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        await social_service.send_encourage(db, user.id, data.to_user_id, data.message)
        return {"status": "sent"}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/social/ping", status_code=201)
async def ping(
    data: PingRequest,
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        await social_service.send_ping(db, user.id, data.to_user_id, req.app.state.redis)
        return {"status": "sent"}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS
            if "limit" in str(e)
            else status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
