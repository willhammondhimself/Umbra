import uuid
from datetime import datetime, timezone

import pytest


@pytest.mark.asyncio
async def test_create_session(client):
    now = datetime.now(timezone.utc).isoformat()
    response = await client.post("/sessions", json={
        "start_time": now,
    })
    assert response.status_code == 201
    data = response.json()
    assert data["is_complete"] is False
    assert data["duration_seconds"] == 0


@pytest.mark.asyncio
async def test_list_sessions(client):
    now = datetime.now(timezone.utc).isoformat()
    await client.post("/sessions", json={"start_time": now})
    await client.post("/sessions", json={"start_time": now})

    response = await client.get("/sessions")
    assert response.status_code == 200
    assert len(response.json()) >= 2


@pytest.mark.asyncio
async def test_list_sessions_pagination(client):
    now = datetime.now(timezone.utc).isoformat()
    for _ in range(5):
        await client.post("/sessions", json={"start_time": now})

    response = await client.get("/sessions?limit=2&offset=0")
    assert response.status_code == 200
    assert len(response.json()) == 2


@pytest.mark.asyncio
async def test_update_session(client):
    now = datetime.now(timezone.utc).isoformat()
    create_resp = await client.post("/sessions", json={"start_time": now})
    session_id = create_resp.json()["id"]

    response = await client.patch(f"/sessions/{session_id}", json={
        "end_time": now,
        "duration_seconds": 3600,
        "focused_seconds": 3000,
        "distraction_count": 3,
        "is_complete": True,
    })
    assert response.status_code == 200
    data = response.json()
    assert data["is_complete"] is True
    assert data["duration_seconds"] == 3600
    assert data["focused_seconds"] == 3000


@pytest.mark.asyncio
async def test_update_nonexistent_session(client):
    response = await client.patch(
        f"/sessions/{uuid.uuid4()}", json={"is_complete": True}
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_append_events(client):
    now = datetime.now(timezone.utc)
    create_resp = await client.post("/sessions", json={
        "start_time": now.isoformat(),
    })
    session_id = create_resp.json()["id"]

    response = await client.post(f"/sessions/{session_id}/events", json={
        "events": [
            {
                "event_type": "START",
                "timestamp": now.isoformat(),
            },
            {
                "event_type": "DISTRACTION",
                "timestamp": now.isoformat(),
                "app_name": "Slack",
                "duration_seconds": 30,
            },
        ]
    })
    assert response.status_code == 201
    events = response.json()
    assert len(events) == 2
    assert events[0]["event_type"] == "START"
    assert events[1]["app_name"] == "Slack"


@pytest.mark.asyncio
async def test_append_events_dedup(client):
    now = datetime.now(timezone.utc)
    create_resp = await client.post("/sessions", json={
        "start_time": now.isoformat(),
    })
    session_id = create_resp.json()["id"]

    event_data = {
        "events": [{
            "event_type": "START",
            "timestamp": now.isoformat(),
        }]
    }

    # First batch
    resp1 = await client.post(f"/sessions/{session_id}/events", json=event_data)
    assert resp1.status_code == 201
    assert len(resp1.json()) == 1

    # Same event again — should be deduped (returns 404 since all are dupes)
    resp2 = await client.post(f"/sessions/{session_id}/events", json=event_data)
    assert resp2.status_code == 404


@pytest.mark.asyncio
async def test_append_events_nonexistent_session(client):
    response = await client.post(f"/sessions/{uuid.uuid4()}/events", json={
        "events": [{"event_type": "START", "timestamp": datetime.now(timezone.utc).isoformat()}]
    })
    assert response.status_code == 404
