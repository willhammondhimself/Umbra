from datetime import datetime, timezone

import pytest


@pytest.mark.asyncio
async def test_stats_empty(client):
    response = await client.get("/stats?period=weekly")
    assert response.status_code == 200
    data = response.json()
    assert data["period"] == "weekly"
    assert data["focused_seconds"] == 0
    assert data["session_count"] == 0
    assert data["current_streak"] == 0


@pytest.mark.asyncio
async def test_stats_with_sessions(client):
    now = datetime.now(timezone.utc).isoformat()

    # Create a completed session
    create_resp = await client.post("/sessions", json={"start_time": now})
    session_id = create_resp.json()["id"]
    await client.patch(f"/sessions/{session_id}", json={
        "end_time": now,
        "duration_seconds": 3600,
        "focused_seconds": 3000,
        "distraction_count": 2,
        "is_complete": True,
    })

    response = await client.get("/stats?period=weekly")
    assert response.status_code == 200
    data = response.json()
    assert data["focused_seconds"] == 3000
    assert data["session_count"] == 1
    assert data["distraction_count"] == 2


@pytest.mark.asyncio
async def test_stats_daily_period(client):
    response = await client.get("/stats?period=daily")
    assert response.status_code == 200
    assert response.json()["period"] == "daily"


@pytest.mark.asyncio
async def test_stats_monthly_period(client):
    response = await client.get("/stats?period=monthly")
    assert response.status_code == 200
    assert response.json()["period"] == "monthly"


@pytest.mark.asyncio
async def test_stats_invalid_period(client):
    response = await client.get("/stats?period=yearly")
    assert response.status_code == 422
