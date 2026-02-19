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
from app.schemas.auth import (
    EmailLoginRequest,
    LoginRequest,
    PasswordResetConfirm,
    PasswordResetRequest,
    RefreshRequest,
    RegisterRequest,
    SettingsUpdateRequest,
    TokenResponse,
    UserResponse,
)
from app.services import auth_service
from app.services.email_service import send_password_reset_email, send_verification_email

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


# --- Email/Password Auth ---


@router.post("/register", response_model=TokenResponse)
async def register(request: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Register a new account with email and password."""
    try:
        user = await auth_service.register_user(
            db=db,
            email=request.email,
            password=request.password,
            display_name=request.display_name,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(e),
        )

    # Send verification email (non-blocking, don't fail registration)
    token = auth_service.issue_email_verification_token(user.id)
    await send_verification_email(user.email, token)

    tokens = auth_service.issue_tokens(user.id)
    return TokenResponse(**tokens)


@router.post("/login/email", response_model=TokenResponse)
async def login_email(request: EmailLoginRequest, db: AsyncSession = Depends(get_db)):
    """Sign in with email and password."""
    try:
        user = await auth_service.login_with_email(
            db=db,
            email=request.email,
            password=request.password,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )

    tokens = auth_service.issue_tokens(user.id)
    return TokenResponse(**tokens)


@router.get("/verify-email/{token}")
async def verify_email(token: str, db: AsyncSession = Depends(get_db)):
    """Verify email address from verification link."""
    try:
        user_id = auth_service.verify_special_token(token, "email_verify")
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user.email_verified = True
    await db.flush()
    return {"status": "verified"}


@router.post("/password-reset/request")
async def request_password_reset(
    request: PasswordResetRequest, db: AsyncSession = Depends(get_db)
):
    """Request a password reset email."""
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    # Always return success to avoid email enumeration
    if user and user.auth_provider == "email":
        token = auth_service.issue_password_reset_token(user.id)
        await send_password_reset_email(user.email, token)

    return {"status": "ok"}


@router.post("/password-reset/confirm")
async def confirm_password_reset(
    request: PasswordResetConfirm, db: AsyncSession = Depends(get_db)
):
    """Reset password using reset token."""
    try:
        user_id = auth_service.verify_special_token(request.token, "password_reset")
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    user.password_hash = auth_service.hash_password(request.new_password)
    await db.flush()
    return {"status": "password_updated"}


# --- OAuth + Common ---


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


@router.patch("/settings")
async def update_settings(
    data: SettingsUpdateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update user settings (visibility, preferences)."""
    current_settings = user.settings_json or {}
    current_settings.update(data.settings_json)
    user.settings_json = current_settings
    await db.flush()
    return {"status": "updated"}


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
    db_user = await db.get(User, user.id)
    if db_user:
        await db.delete(db_user)
        await db.flush()
