import uuid
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.services.auth_service import hash_password


@pytest.fixture
async def email_user(db_session: AsyncSession) -> User:
    """Create a user with email/password auth."""
    user = User(
        id=uuid.uuid4(),
        email="emailuser@example.com",
        display_name="Email User",
        auth_provider="email",
        auth_provider_id="email:emailuser@example.com",
        password_hash=hash_password("TestPass123!"),
        email_verified=False,
        settings_json={"visibility": "private"},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


async def test_register_new_user(client: AsyncClient):
    """Test registering a new email account."""
    response = await client.post(
        "/auth/register",
        json={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
            "display_name": "New User",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


async def test_register_duplicate_email(client: AsyncClient):
    """Test that registering with existing email fails."""
    # Register first user
    await client.post(
        "/auth/register",
        json={"email": "dup@example.com", "password": "SecurePass123!"},
    )

    # Try to register again with same email
    response = await client.post(
        "/auth/register",
        json={"email": "dup@example.com", "password": "AnotherPass123!"},
    )
    assert response.status_code == 409


async def test_register_weak_password(client: AsyncClient):
    """Test that short passwords are rejected."""
    response = await client.post(
        "/auth/register",
        json={"email": "weak@example.com", "password": "short"},
    )
    assert response.status_code == 422  # Pydantic validation error


async def test_login_with_email(client: AsyncClient, email_user: User):
    """Test email login with correct credentials."""
    response = await client.post(
        "/auth/login/email",
        json={"email": "emailuser@example.com", "password": "TestPass123!"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data


async def test_login_wrong_password(client: AsyncClient, email_user: User):
    """Test email login with wrong password."""
    response = await client.post(
        "/auth/login/email",
        json={"email": "emailuser@example.com", "password": "WrongPassword!"},
    )
    assert response.status_code == 401


async def test_login_nonexistent_email(client: AsyncClient):
    """Test email login with non-existent email."""
    response = await client.post(
        "/auth/login/email",
        json={"email": "nobody@example.com", "password": "AnyPassword123!"},
    )
    assert response.status_code == 401


async def test_password_reset_request(client: AsyncClient, email_user: User):
    """Test password reset request (should always return 200 to prevent email enumeration)."""
    response = await client.post(
        "/auth/password-reset/request",
        json={"email": "emailuser@example.com"},
    )
    assert response.status_code == 200

    # Non-existent email should also return 200
    response = await client.post(
        "/auth/password-reset/request",
        json={"email": "nobody@example.com"},
    )
    assert response.status_code == 200


async def test_password_reset_confirm_invalid_token(client: AsyncClient):
    """Test password reset with invalid token."""
    response = await client.post(
        "/auth/password-reset/confirm",
        json={"token": "invalid.token.here", "new_password": "NewSecure123!"},
    )
    assert response.status_code == 400


async def test_email_verification_invalid_token(client: AsyncClient):
    """Test email verification with invalid token."""
    response = await client.get("/auth/verify-email/invalid.token")
    assert response.status_code == 400


async def test_register_then_login_flow(client: AsyncClient):
    """Test full registration → login flow."""
    # Register
    reg_response = await client.post(
        "/auth/register",
        json={"email": "flow@example.com", "password": "FlowPass123!"},
    )
    assert reg_response.status_code == 200

    # Login with same credentials
    login_response = await client.post(
        "/auth/login/email",
        json={"email": "flow@example.com", "password": "FlowPass123!"},
    )
    assert login_response.status_code == 200
    assert login_response.json()["access_token"]
