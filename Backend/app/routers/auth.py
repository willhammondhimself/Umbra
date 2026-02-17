import json

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.project import Project
from app.models.session import Session
from app.models.session_event import SessionEvent
from app.models.task import Task
from app.models.user import User
from app.schemas.auth import LoginRequest, RefreshRequest, TokenResponse, UserResponse
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate via Apple or Google identity token, upsert user, return JWT pair."""
    try:
        if request.provider == "apple":
            claims = await auth_service.verify_apple_token(request.identity_token)
            provider_id = claims["sub"]
            email = claims.get("email", "")
            display_name = None
        elif request.provider == "google":
            claims = await auth_service.verify_google_token(request.identity_token)
            provider_id = claims["sub"]
            email = claims.get("email", "")
            display_name = claims.get("name")
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported auth provider. Use 'apple' or 'google'.",
            )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )

    user = await auth_service.upsert_user(
        db=db,
        provider=request.provider,
        provider_id=provider_id,
        email=email,
        display_name=display_name,
    )

    tokens = auth_service.issue_tokens(user.id)
    return TokenResponse(**tokens)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(request: RefreshRequest, req: Request):
    """Rotate refresh token and issue new access + refresh pair."""
    redis_client = req.app.state.redis
    try:
        tokens = await auth_service.refresh_tokens(request.refresh_token, redis_client)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )
    return TokenResponse(**tokens)


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(get_current_user)):
    """Return the currently authenticated user."""
    return user


@router.get("/account/export")
async def export_account(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """GDPR: Export all user data as JSON."""
    projects = (await db.execute(
        select(Project).where(Project.user_id == user.id)
    )).scalars().all()

    tasks = (await db.execute(
        select(Task).where(Task.user_id == user.id)
    )).scalars().all()

    sessions = (await db.execute(
        select(Session).where(Session.user_id == user.id)
    )).scalars().all()

    session_ids = [s.id for s in sessions]
    events = []
    if session_ids:
        events = (await db.execute(
            select(SessionEvent).where(SessionEvent.session_id.in_(session_ids))
        )).scalars().all()

    def serialize(obj):
        d = {c.name: getattr(obj, c.name) for c in obj.__table__.columns}
        for k, v in d.items():
            if hasattr(v, "isoformat"):
                d[k] = v.isoformat()
            elif hasattr(v, "hex"):
                d[k] = str(v)
        return d

    export = {
        "user": serialize(user),
        "projects": [serialize(p) for p in projects],
        "tasks": [serialize(t) for t in tasks],
        "sessions": [serialize(s) for s in sessions],
        "session_events": [serialize(e) for e in events],
    }

    return export


@router.delete("/account", status_code=204)
async def delete_account(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """GDPR: Cascade delete all user data."""
    await db.delete(user)
    await db.flush()
