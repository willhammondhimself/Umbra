import uuid
from datetime import datetime, timedelta, timezone

import pytest


def _session_time(days_ago: int = 0, hour: int = 10) -> str:
    """Helper to create an ISO timestamp N days ago at a given hour."""
    dt = datetime.now(timezone.utc) - timedelta(days=days_ago)
    dt = dt.replace(hour=hour, minute=0, second=0, microsecond=0)
    return dt.isoformat()


async def _create_completed_session(
    client,
    days_ago: int = 0,
    hour: int = 10,
    duration_seconds: int = 1500,
    focused_seconds: int = 1200,
    distraction_count: int = 1,
) -> dict:
    """Create a completed session via the API."""
    start = _session_time(days_ago=days_ago, hour=hour)
    resp = await client.post("/sessions", json={"start_time": start})
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    end_dt = datetime.fromisoformat(start) + timedelta(seconds=duration_seconds)
    resp = await client.patch(
        f"/sessions/{session_id}",
        json={
            "end_time": end_dt.isoformat(),
            "duration_seconds": duration_seconds,
            "focused_seconds": focused_seconds,
            "distraction_count": distraction_count,
            "is_complete": True,
        },
    )
    assert resp.status_code == 200
    return resp.json()


async def _add_distraction_event(
    client, session_id: str, app_name: str, duration_seconds: int = 30
) -> None:
    """Add a DISTRACTION event to a session."""
    now = datetime.now(timezone.utc).isoformat()
    resp = await client.post(
        f"/sessions/{session_id}/events",
        json={
            "events": [
                {
                    "event_type": "DISTRACTION",
                    "timestamp": now,
                    "app_name": app_name,
                    "duration_seconds": duration_seconds,
                }
            ]
        },
    )
    assert resp.status_code == 201


# --- /insights endpoint ---


@pytest.mark.asyncio
async def test_insights_empty(client):
    """Insights with no sessions should return valid empty/default structure."""
    response = await client.get("/insights")
    assert response.status_code == 200
    data = response.json()
    assert data["heatmap"] == []
    assert data["trends"] == []
    assert data["top_distractors"] == []
    assert data["optimal_session"]["recommended_minutes"] == 25
    assert data["optimal_session"]["sample_size"] == 0
    assert isinstance(data["goals"], list)
    assert len(data["goals"]) == 4


@pytest.mark.asyncio
async def test_insights_with_sessions(client):
    """Insights with session data should populate all fields."""
    # Create sessions across different days and hours
    s1 = await _create_completed_session(
        client, days_ago=0, hour=9, duration_seconds=1500, focused_seconds=1300
    )
    s2 = await _create_completed_session(
        client, days_ago=1, hour=14, duration_seconds=2700, focused_seconds=2400
    )
    s3 = await _create_completed_session(
        client, days_ago=2, hour=9, duration_seconds=1500, focused_seconds=1200
    )

    # Add distraction events
    await _add_distraction_event(client, s1["id"], "Slack", duration_seconds=45)
    await _add_distraction_event(client, s2["id"], "Twitter", duration_seconds=60)
    await _add_distraction_event(client, s2["id"], "Slack", duration_seconds=30)

    response = await client.get("/insights?days=30")
    assert response.status_code == 200
    data = response.json()

    # Heatmap should have entries
    assert len(data["heatmap"]) > 0
    for entry in data["heatmap"]:
        assert 0 <= entry["hour"] <= 23
        assert 0 <= entry["day_of_week"] <= 6
        assert entry["focused_minutes"] >= 0

    # Trends should have daily entries
    assert len(data["trends"]) > 0
    for trend in data["trends"]:
        assert trend["focused_minutes"] >= 0
        assert trend["session_count"] >= 1

    # Distractors should have Slack and Twitter
    assert len(data["top_distractors"]) > 0
    app_names = [d["app_name"] for d in data["top_distractors"]]
    assert "Slack" in app_names

    # Optimal session should return a recommendation
    assert data["optimal_session"]["recommended_minutes"] > 0

    # Goals should be present
    assert len(data["goals"]) == 4
    goal_types = {g["goal_type"] for g in data["goals"]}
    assert goal_types == {"daily_focus", "session_count", "distraction_reduction", "streak"}


@pytest.mark.asyncio
async def test_insights_days_parameter_validation(client):
    """Days parameter must be between 7 and 90."""
    # Too small
    resp = await client.get("/insights?days=3")
    assert resp.status_code == 422

    # Too large
    resp = await client.get("/insights?days=100")
    assert resp.status_code == 422

    # Valid boundaries
    resp = await client.get("/insights?days=7")
    assert resp.status_code == 200

    resp = await client.get("/insights?days=90")
    assert resp.status_code == 200


# --- /insights/heatmap endpoint ---


@pytest.mark.asyncio
async def test_heatmap_empty(client):
    """Heatmap with no sessions returns empty list."""
    response = await client.get("/insights/heatmap")
    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.asyncio
async def test_heatmap_with_sessions(client):
    """Heatmap aggregates focused time by hour and day of week."""
    await _create_completed_session(
        client, days_ago=0, hour=10, focused_seconds=1800
    )
    await _create_completed_session(
        client, days_ago=0, hour=10, focused_seconds=1200
    )
    await _create_completed_session(
        client, days_ago=1, hour=14, focused_seconds=900
    )

    response = await client.get("/insights/heatmap?days=7")
    assert response.status_code == 200
    data = response.json()

    assert len(data) >= 2  # At least 2 distinct (hour, dow) combos
    for entry in data:
        assert "hour" in entry
        assert "day_of_week" in entry
        assert "focused_minutes" in entry
        assert entry["focused_minutes"] > 0


# --- /insights/goals endpoint ---


@pytest.mark.asyncio
async def test_goals_empty(client):
    """Goals with no sessions should return default goals."""
    response = await client.get("/insights/goals")
    assert response.status_code == 200
    data = response.json()

    assert len(data) == 4
    goal_types = {g["goal_type"] for g in data}
    assert "daily_focus" in goal_types
    assert "session_count" in goal_types
    assert "distraction_reduction" in goal_types
    assert "streak" in goal_types

    # Default daily_focus target should be 60 minutes
    daily_goal = next(g for g in data if g["goal_type"] == "daily_focus")
    assert daily_goal["target_value"] == 60.0
    assert daily_goal["current_value"] == 0.0


@pytest.mark.asyncio
async def test_goals_with_history(client):
    """Goals should reflect actual session data."""
    # Create sessions in the "previous week" window (8-14 days ago)
    for i in range(8, 13):
        await _create_completed_session(
            client,
            days_ago=i,
            duration_seconds=1800,
            focused_seconds=1500,
            distraction_count=3,
        )

    # Create sessions in the "current week" window (0-6 days ago)
    for i in range(0, 4):
        await _create_completed_session(
            client,
            days_ago=i,
            duration_seconds=1800,
            focused_seconds=1600,
            distraction_count=2,
        )

    response = await client.get("/insights/goals")
    assert response.status_code == 200
    data = response.json()

    # Session count goal should target previous week + 1
    session_goal = next(g for g in data if g["goal_type"] == "session_count")
    assert session_goal["current_value"] == 4.0
    assert session_goal["target_value"] >= 5.0  # prev was 5, target is max(5+1, 4)

    # Distraction reduction goal: previous week had 3*5=15 distractions
    distraction_goal = next(
        g for g in data if g["goal_type"] == "distraction_reduction"
    )
    assert distraction_goal["current_value"] == 8.0  # 2*4
    # Target should be 80% of previous (15*0.8=12)
    assert distraction_goal["target_value"] == 12.0

    # Daily focus goal: previous daily avg = (1500*5)/7/60 ~ 17.86, target = 17.86*1.1 ~ 20
    daily_goal = next(g for g in data if g["goal_type"] == "daily_focus")
    assert daily_goal["target_value"] > 0


# --- Distraction patterns ---


@pytest.mark.asyncio
async def test_distraction_patterns(client):
    """Distractions are grouped by app name and sorted by count."""
    s1 = await _create_completed_session(client, days_ago=0)
    s2 = await _create_completed_session(client, days_ago=1)

    # Add multiple distractions for Slack (3 total) and one for Twitter
    now = datetime.now(timezone.utc)
    for i, (sid, app, dur) in enumerate([
        (s1["id"], "Slack", 30),
        (s1["id"], "Twitter", 60),
        (s2["id"], "Slack", 45),
    ]):
        ts = (now + timedelta(seconds=i)).isoformat()
        resp = await client.post(
            f"/sessions/{sid}/events",
            json={
                "events": [
                    {
                        "event_type": "DISTRACTION",
                        "timestamp": ts,
                        "app_name": app,
                        "duration_seconds": dur,
                    }
                ]
            },
        )
        assert resp.status_code == 201

    response = await client.get("/insights")
    data = response.json()
    distractors = data["top_distractors"]

    assert len(distractors) == 2
    # Slack should be first (count=2 vs 1)
    assert distractors[0]["app_name"] == "Slack"
    assert distractors[0]["count"] == 2
    assert distractors[0]["total_duration_seconds"] == 75  # 30 + 45
    assert distractors[1]["app_name"] == "Twitter"
    assert distractors[1]["count"] == 1
    assert distractors[1]["total_duration_seconds"] == 60


# --- Optimal session length ---


@pytest.mark.asyncio
async def test_optimal_session_default(client):
    """With no sessions, optimal session defaults to 25 minutes."""
    response = await client.get("/insights")
    data = response.json()
    assert data["optimal_session"]["recommended_minutes"] == 25
    assert data["optimal_session"]["sample_size"] == 0


@pytest.mark.asyncio
async def test_optimal_session_with_data(client):
    """Optimal session picks the bucket with highest focus ratio."""
    # Create 4 sessions in the 25-min bucket (20-35 min range): high focus ratio
    for i in range(4):
        await _create_completed_session(
            client,
            days_ago=i,
            duration_seconds=25 * 60,  # 1500s
            focused_seconds=24 * 60,   # 1440s -> ratio ~0.96
        )

    # Create 4 sessions in the 60-min bucket (52-75 min range): lower focus ratio
    for i in range(4, 8):
        await _create_completed_session(
            client,
            days_ago=i,
            duration_seconds=60 * 60,  # 3600s
            focused_seconds=30 * 60,   # 1800s -> ratio 0.50
        )

    response = await client.get("/insights")
    data = response.json()
    optimal = data["optimal_session"]

    # 25-min bucket has higher ratio, should be recommended
    assert optimal["recommended_minutes"] == 25
    assert optimal["avg_focus_ratio"] > 0.9
    assert optimal["sample_size"] >= 4


# --- Trend endpoint (via full insights) ---


@pytest.mark.asyncio
async def test_trend_daily_data(client):
    """Trends return one entry per day with sessions."""
    await _create_completed_session(
        client, days_ago=0, focused_seconds=1800, distraction_count=2
    )
    await _create_completed_session(
        client, days_ago=1, focused_seconds=900, distraction_count=1
    )
    await _create_completed_session(
        client, days_ago=1, focused_seconds=600, distraction_count=0
    )

    response = await client.get("/insights?days=7")
    data = response.json()
    trends = data["trends"]

    assert len(trends) == 2  # 2 distinct days

    # Verify sorted by date ascending
    assert trends[0]["date"] < trends[1]["date"]

    # Day with 2 sessions should have combined data
    day_with_two = next(t for t in trends if t["session_count"] == 2)
    assert day_with_two["focused_minutes"] == 25.0  # (900+600)/60
    assert day_with_two["distraction_count"] == 1  # 1+0
