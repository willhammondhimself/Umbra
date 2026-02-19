import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.social import (
    ActivityItem,
    EncourageRequest,
    FriendResponse,
    GroupCreate,
    GroupResponse,
    InviteLinkResponse,
    InviteRequest,
    LeaderboardEntry,
    PingRequest,
    ReactionRequest,
    ReactionResponse,
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
        result = await social_service.send_invite(
            db, user.id, data.email, req.app.state.redis, req.app.state.apns_client
        )
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


@router.post("/friends/invite-link", response_model=InviteLinkResponse, status_code=201)
async def create_invite_link(
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        result = await social_service.generate_invite_link(
            db, user.id, req.app.state.redis
        )
        return result
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS
            if "limit" in str(e)
            else status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/friends/join/{invite_code}")
async def join_invite_link(
    invite_code: str,
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        await social_service.accept_invite_link(
            db, user.id, invite_code, req.app.state.redis
        )
        return {"status": "accepted"}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.get("/groups", response_model=list[GroupResponse])
async def list_groups(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await social_service.get_groups(db, user.id)


@router.post("/groups", response_model=GroupResponse, status_code=201)
async def create_group(
    data: GroupCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        group = await social_service.create_group(db, user.id, data.name)
        return group
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


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
    req: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        await social_service.send_encourage(
            db, user.id, data.to_user_id, data.message, req.app.state.apns_client
        )
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
        await social_service.send_ping(
            db, user.id, data.to_user_id, req.app.state.redis, req.app.state.apns_client
        )
        return {"status": "sent"}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS
            if "limit" in str(e)
            else status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/sessions/{session_id}/react", response_model=ReactionResponse, status_code=201)
async def react_to_session(
    session_id: uuid.UUID,
    data: ReactionRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        result = await social_service.react_to_session(
            db, user.id, session_id, data.reaction_type
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.get("/sessions/{session_id}/reactions", response_model=list[ReactionResponse])
async def get_session_reactions(
    session_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        return await social_service.get_session_reactions(db, user.id, session_id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.get("/social/activity", response_model=list[ActivityItem])
async def get_activity_feed(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await social_service.get_friend_activity(db, user.id)
