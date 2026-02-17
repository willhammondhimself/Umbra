import hashlib
import hmac
import json
import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.webhook import Webhook
from app.services.webhook_service import VALID_EVENTS, deliver_webhook, fire_webhooks


# ── Webhook CRUD endpoint tests ─────────────────────────────────────


@pytest.mark.asyncio
async def test_create_webhook(client):
    response = await client.post("/webhooks", json={
        "url": "https://example.com/webhook",
        "events": ["session.start", "session.end"],
    })
    assert response.status_code == 201
    data = response.json()
    assert data["url"] == "https://example.com/webhook"
    assert data["events"] == ["session.start", "session.end"]
    assert data["is_active"] is True
    assert len(data["secret"]) == 64  # 32 bytes hex
    assert data["user_id"] is not None


@pytest.mark.asyncio
async def test_create_webhook_invalid_event(client):
    response = await client.post("/webhooks", json={
        "url": "https://example.com/webhook",
        "events": ["invalid.event"],
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_create_webhook_empty_events(client):
    response = await client.post("/webhooks", json={
        "url": "https://example.com/webhook",
        "events": [],
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_list_webhooks(client):
    await client.post("/webhooks", json={
        "url": "https://example.com/hook1",
        "events": ["session.start"],
    })
    await client.post("/webhooks", json={
        "url": "https://example.com/hook2",
        "events": ["task.complete"],
    })

    response = await client.get("/webhooks")
    assert response.status_code == 200
    webhooks = response.json()
    assert len(webhooks) >= 2


@pytest.mark.asyncio
async def test_delete_webhook(client):
    create_resp = await client.post("/webhooks", json={
        "url": "https://example.com/hook",
        "events": ["session.start"],
    })
    webhook_id = create_resp.json()["id"]

    delete_resp = await client.delete(f"/webhooks/{webhook_id}")
    assert delete_resp.status_code == 204

    # Verify it's gone
    list_resp = await client.get("/webhooks")
    webhook_ids = [w["id"] for w in list_resp.json()]
    assert webhook_id not in webhook_ids


@pytest.mark.asyncio
async def test_delete_nonexistent_webhook(client):
    fake_id = str(uuid.uuid4())
    response = await client.delete(f"/webhooks/{fake_id}")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_test_webhook_not_found(client):
    fake_id = str(uuid.uuid4())
    response = await client.post(f"/webhooks/{fake_id}/test")
    assert response.status_code == 404


# ── Webhook delivery service tests ──────────────────────────────────


@pytest.fixture
def sample_webhook():
    """Create a sample Webhook model object for service tests."""
    wh = Webhook(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        url="https://example.com/webhook",
        events=["session.start", "session.end"],
        secret="a" * 64,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )
    return wh


@pytest.mark.asyncio
async def test_deliver_webhook_success(sample_webhook):
    """Webhook delivery succeeds on 200 response."""
    mock_response = httpx.Response(200, text="OK")
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(return_value=mock_response)

    result = await deliver_webhook(
        sample_webhook, "session.start", {"test": True}, http_client=mock_client
    )
    assert result is True
    mock_client.post.assert_called_once()

    # Verify HMAC signature in headers
    call_args = mock_client.post.call_args
    headers = call_args.kwargs["headers"]
    assert headers["X-Tether-Event"] == "session.start"
    assert headers["X-Tether-Signature"].startswith("sha256=")

    # Verify the signature is correct
    body = call_args.kwargs["content"]
    expected_sig = hmac.new(
        sample_webhook.secret.encode("utf-8"),
        body.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    assert headers["X-Tether-Signature"] == f"sha256={expected_sig}"


@pytest.mark.asyncio
async def test_deliver_webhook_retries_on_failure(sample_webhook):
    """Webhook delivery retries 3 times on HTTP errors."""
    mock_response_500 = httpx.Response(500, text="Server Error")
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(return_value=mock_response_500)

    with patch("app.services.webhook_service.asyncio.sleep", new_callable=AsyncMock):
        result = await deliver_webhook(
            sample_webhook, "session.start", {"test": True}, http_client=mock_client
        )

    assert result is False
    assert mock_client.post.call_count == 3


@pytest.mark.asyncio
async def test_deliver_webhook_retries_on_network_error(sample_webhook):
    """Webhook delivery retries on network exceptions."""
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=httpx.ConnectError("Connection refused"))

    with patch("app.services.webhook_service.asyncio.sleep", new_callable=AsyncMock):
        result = await deliver_webhook(
            sample_webhook, "session.start", {"test": True}, http_client=mock_client
        )

    assert result is False
    assert mock_client.post.call_count == 3


@pytest.mark.asyncio
async def test_deliver_webhook_succeeds_on_retry(sample_webhook):
    """Webhook delivery succeeds on second attempt after initial failure."""
    mock_response_500 = httpx.Response(500, text="Error")
    mock_response_200 = httpx.Response(200, text="OK")
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=[mock_response_500, mock_response_200])

    with patch("app.services.webhook_service.asyncio.sleep", new_callable=AsyncMock):
        result = await deliver_webhook(
            sample_webhook, "session.start", {"test": True}, http_client=mock_client
        )

    assert result is True
    assert mock_client.post.call_count == 2


# ── fire_webhooks service tests ──────────────────────────────────────


@pytest.mark.asyncio
async def test_fire_webhooks(db_session: AsyncSession, test_user):
    """fire_webhooks delivers to matching webhooks only."""
    # Create two webhooks - one matching, one not
    wh1 = Webhook(
        user_id=test_user.id,
        url="https://example.com/hook1",
        events=["session.start"],
        secret="s" * 64,
        is_active=True,
    )
    wh2 = Webhook(
        user_id=test_user.id,
        url="https://example.com/hook2",
        events=["task.complete"],
        secret="t" * 64,
        is_active=True,
    )
    db_session.add(wh1)
    await db_session.flush()
    db_session.add(wh2)
    await db_session.commit()

    mock_response = httpx.Response(200, text="OK")
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(return_value=mock_response)

    delivered = await fire_webhooks(
        db_session, test_user.id, "session.start", {"data": "test"},
        http_client=mock_client,
    )

    assert delivered == 1  # Only wh1 matches session.start
    mock_client.post.assert_called_once()


@pytest.mark.asyncio
async def test_fire_webhooks_skips_inactive(db_session: AsyncSession, test_user):
    """fire_webhooks skips inactive webhooks."""
    wh = Webhook(
        user_id=test_user.id,
        url="https://example.com/hook",
        events=["session.start"],
        secret="s" * 64,
        is_active=False,
    )
    db_session.add(wh)
    await db_session.commit()

    mock_client = AsyncMock(spec=httpx.AsyncClient)

    delivered = await fire_webhooks(
        db_session, test_user.id, "session.start", {"data": "test"},
        http_client=mock_client,
    )

    assert delivered == 0
    mock_client.post.assert_not_called()


@pytest.mark.asyncio
async def test_fire_webhooks_no_webhooks(db_session: AsyncSession, test_user):
    """fire_webhooks returns 0 when user has no webhooks."""
    mock_client = AsyncMock(spec=httpx.AsyncClient)

    delivered = await fire_webhooks(
        db_session, test_user.id, "session.start", {"data": "test"},
        http_client=mock_client,
    )

    assert delivered == 0
