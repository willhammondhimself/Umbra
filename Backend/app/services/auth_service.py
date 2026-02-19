import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
import httpx
from jose import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.user import User


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    """Verify a password against a bcrypt hash."""
    return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))

# Apple JWKS endpoint
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

# Google token info endpoint
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"


async def verify_apple_token(identity_token: str) -> dict:
    """Verify Apple identity token using JWKS. Returns decoded claims."""
    async with httpx.AsyncClient() as client:
        # Fetch Apple's public keys
        resp = await client.get(APPLE_JWKS_URL)
        resp.raise_for_status()
        jwks = resp.json()

    # Decode the token header to find the key ID
    unverified_header = jwt.get_unverified_header(identity_token)
    kid = unverified_header.get("kid")

    # Find the matching key
    key = None
    for k in jwks.get("keys", []):
        if k["kid"] == kid:
            key = k
            break

    if key is None:
        raise ValueError("Apple JWKS key not found")

    # Verify and decode the token
    claims = jwt.decode(
        identity_token,
        key,
        algorithms=["RS256"],
        audience=settings.APPLE_TEAM_ID or None,
        issuer=APPLE_ISSUER,
    )
    return claims


async def verify_google_token(identity_token: str) -> dict:
    """Verify Google identity token using tokeninfo endpoint. Returns claims."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            GOOGLE_TOKENINFO_URL,
            params={"id_token": identity_token},
        )
        if resp.status_code != 200:
            raise ValueError("Invalid Google token")
        claims = resp.json()

    # Verify audience matches our client ID
    if settings.GOOGLE_CLIENT_ID and claims.get("aud") != settings.GOOGLE_CLIENT_ID:
        raise ValueError("Google token audience mismatch")

    return claims


async def upsert_user(
    db: AsyncSession,
    provider: str,
    provider_id: str,
    email: str,
    display_name: str | None = None,
) -> User:
    """Create or update user from OAuth provider data."""
    result = await db.execute(
        select(User).where(User.auth_provider_id == provider_id)
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            id=uuid.uuid4(),
            email=email,
            display_name=display_name or email.split("@")[0],
            auth_provider=provider,
            auth_provider_id=provider_id,
            settings_json={"visibility": "private"},
        )
        db.add(user)
    else:
        # Update fields that may have changed
        if display_name:
            user.display_name = display_name
        user.updated_at = datetime.now(timezone.utc)

    await db.flush()
    await db.refresh(user)
    return user


def issue_tokens(user_id: str | uuid.UUID) -> dict:
    """Issue JWT access + refresh token pair."""
    now = datetime.now(timezone.utc)

    access_payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    access_token = jwt.encode(access_payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

    refresh_payload = {
        "sub": str(user_id),
        "type": "refresh",
        "jti": str(uuid.uuid4()),
        "iat": now,
        "exp": now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    }
    refresh_token = jwt.encode(refresh_payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    }


async def refresh_tokens(refresh_token: str, redis_client) -> dict:
    """Validate refresh token and issue new pair. Rotate by blacklisting old refresh token."""
    try:
        payload = jwt.decode(
            refresh_token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
        )
    except Exception:
        raise ValueError("Invalid refresh token")

    if payload.get("type") != "refresh":
        raise ValueError("Not a refresh token")

    jti = payload.get("jti")
    if jti:
        # Check if this refresh token has been revoked
        is_revoked = await redis_client.get(f"revoked_refresh:{jti}")
        if is_revoked:
            raise ValueError("Refresh token has been revoked")

        # Revoke the old refresh token
        ttl = settings.REFRESH_TOKEN_EXPIRE_DAYS * 86400
        await redis_client.setex(f"revoked_refresh:{jti}", ttl, "1")

    user_id = payload["sub"]
    return issue_tokens(user_id)


async def register_user(
    db: AsyncSession,
    email: str,
    password: str,
    display_name: str | None = None,
) -> User:
    """Register a new user with email/password."""
    result = await db.execute(select(User).where(User.email == email))
    existing = result.scalar_one_or_none()
    if existing:
        raise ValueError("An account with this email already exists")

    user = User(
        id=uuid.uuid4(),
        email=email,
        display_name=display_name or email.split("@")[0],
        auth_provider="email",
        auth_provider_id=f"email:{email}",
        password_hash=hash_password(password),
        email_verified=False,
        settings_json={"visibility": "private"},
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    return user


async def login_with_email(
    db: AsyncSession,
    email: str,
    password: str,
) -> User:
    """Authenticate user with email/password."""
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user is None or user.password_hash is None:
        raise ValueError("Invalid email or password")

    if not verify_password(password, user.password_hash):
        raise ValueError("Invalid email or password")

    return user


def issue_email_verification_token(user_id: str | uuid.UUID) -> str:
    """Issue a short-lived token for email verification."""
    payload = {
        "sub": str(user_id),
        "type": "email_verify",
        "exp": datetime.now(timezone.utc) + timedelta(hours=24),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def issue_password_reset_token(user_id: str | uuid.UUID) -> str:
    """Issue a short-lived token for password reset."""
    payload = {
        "sub": str(user_id),
        "type": "password_reset",
        "exp": datetime.now(timezone.utc) + timedelta(hours=1),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def verify_special_token(token: str, expected_type: str) -> str:
    """Verify and decode a special-purpose token. Returns user_id."""
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except Exception:
        raise ValueError("Invalid or expired token")

    if payload.get("type") != expected_type:
        raise ValueError("Invalid token type")

    return payload["sub"]
