import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.services.auth_service import issue_tokens, upsert_user


@pytest.mark.asyncio
async def test_issue_tokens():
    user_id = uuid.uuid4()
    tokens = issue_tokens(user_id)
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    assert tokens["token_type"] == "bearer"
    assert tokens["expires_in"] == 3600


@pytest.mark.asyncio
async def test_upsert_user_creates_new(db_session: AsyncSession):
    user = await upsert_user(
        db=db_session,
        provider="apple",
        provider_id="apple_new_123",
        email="new@example.com",
        display_name="New User",
    )
    assert user.email == "new@example.com"
    assert user.display_name == "New User"
    assert user.auth_provider == "apple"
    assert user.auth_provider_id == "apple_new_123"


@pytest.mark.asyncio
async def test_upsert_user_updates_existing(db_session: AsyncSession):
    # Create initial user
    user1 = await upsert_user(
        db=db_session,
        provider="google",
        provider_id="google_upsert_789",
        email="upsert@example.com",
        display_name="Original",
    )
    original_id = user1.id

    # Upsert with same provider_id should update, not create
    user2 = await upsert_user(
        db=db_session,
        provider="google",
        provider_id="google_upsert_789",
        email="upsert@example.com",
        display_name="Updated",
    )
    assert user2.id == original_id
    assert user2.display_name == "Updated"


@pytest.mark.asyncio
async def test_get_me_authenticated(client):
    response = await client.get("/auth/me")
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "test@example.com"
    assert data["display_name"] == "Test User"


@pytest.mark.asyncio
async def test_login_invalid_provider(client):
    response = await client.post(
        "/auth/login",
        json={"provider": "invalid", "identity_token": "xxx"},
    )
    assert response.status_code == 400
