import pytest


@pytest.mark.asyncio
async def test_parse_tasks_endpoint(client):
    """Test task parsing endpoint returns structured response."""
    response = await client.post(
        "/tasks/parse",
        json={"text": "Write a report for 2 hours"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "tasks" in data
    assert "used_llm" in data
    assert isinstance(data["tasks"], list)


@pytest.mark.asyncio
async def test_parse_tasks_empty_text_rejected(client):
    """Test that empty text is rejected with 422."""
    response = await client.post(
        "/tasks/parse",
        json={"text": ""},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_parse_tasks_missing_text_rejected(client):
    """Test that missing text field is rejected with 422."""
    response = await client.post(
        "/tasks/parse",
        json={},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_parse_tasks_requires_auth(db_engine, test_user):
    """Test that endpoint requires authentication."""
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    # Clear all dependency overrides to require real auth
    app.dependency_overrides.clear()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        response = await ac.post(
            "/tasks/parse",
            json={"text": "Write a report"},
        )
    assert response.status_code in (401, 403)
