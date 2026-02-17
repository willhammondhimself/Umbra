import pytest


@pytest.mark.asyncio
async def test_create_project(client):
    response = await client.post("/projects", json={"name": "My Project"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "My Project"
    assert data["user_id"] is not None


@pytest.mark.asyncio
async def test_list_projects(client):
    await client.post("/projects", json={"name": "Project A"})
    await client.post("/projects", json={"name": "Project B"})

    response = await client.get("/projects")
    assert response.status_code == 200
    assert len(response.json()) >= 2


@pytest.mark.asyncio
async def test_create_project_validation(client):
    # Empty name
    response = await client.post("/projects", json={"name": ""})
    assert response.status_code == 422
