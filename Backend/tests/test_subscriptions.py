import pytest
from httpx import AsyncClient


async def test_get_subscription_status_free(client: AsyncClient):
    """Test subscription status for user with no subscription."""
    response = await client.get("/subscriptions/status")
    assert response.status_code == 200
    data = response.json()
    assert data["is_pro"] is False
    assert data["product_id"] is None
    assert data["status"] is None


async def test_verify_subscription(client: AsyncClient):
    """Test verifying and registering a subscription."""
    response = await client.post(
        "/subscriptions/verify",
        json={
            "original_transaction_id": "test_txn_12345",
            "product_id": "com.willhammond.tether.pro.monthly",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["product_id"] == "com.willhammond.tether.pro.monthly"
    assert data["status"] == "active"
    assert data["original_transaction_id"] == "test_txn_12345"


async def test_verify_then_check_status(client: AsyncClient):
    """Test that verified subscription shows as pro."""
    # Verify subscription
    await client.post(
        "/subscriptions/verify",
        json={
            "original_transaction_id": "test_txn_67890",
            "product_id": "com.willhammond.tether.pro.yearly",
        },
    )

    # Check status
    response = await client.get("/subscriptions/status")
    assert response.status_code == 200
    data = response.json()
    assert data["is_pro"] is True
    assert data["product_id"] == "com.willhammond.tether.pro.yearly"


async def test_verify_updates_existing(client: AsyncClient):
    """Test that re-verifying updates the subscription."""
    # First verify
    await client.post(
        "/subscriptions/verify",
        json={
            "original_transaction_id": "test_txn_update",
            "product_id": "com.willhammond.tether.pro.monthly",
        },
    )

    # Re-verify with different product (upgrade)
    response = await client.post(
        "/subscriptions/verify",
        json={
            "original_transaction_id": "test_txn_update",
            "product_id": "com.willhammond.tether.pro.yearly",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["product_id"] == "com.willhammond.tether.pro.yearly"


async def test_webhook_endpoint_exists(client: AsyncClient):
    """Test that the webhook endpoint is reachable."""
    response = await client.post("/subscriptions/webhook")
    assert response.status_code == 200
    assert response.json()["status"] == "received"
