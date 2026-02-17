import uuid

import pytest


@pytest.mark.asyncio
async def test_create_task(client):
    response = await client.post("/tasks", json={
        "title": "Write unit tests",
        "priority": 2,
        "status": 0,
    })
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Write unit tests"
    assert data["priority"] == 2
    assert data["status"] == 0
    assert data["user_id"] is not None


@pytest.mark.asyncio
async def test_create_task_with_project(client):
    # Create project first
    proj_resp = await client.post("/projects", json={"name": "Test Project"})
    project_id = proj_resp.json()["id"]

    response = await client.post("/tasks", json={
        "title": "Project task",
        "project_id": project_id,
    })
    assert response.status_code == 201
    assert response.json()["project_id"] == project_id


@pytest.mark.asyncio
async def test_list_tasks(client):
    await client.post("/tasks", json={"title": "Task 1"})
    await client.post("/tasks", json={"title": "Task 2"})

    response = await client.get("/tasks")
    assert response.status_code == 200
    tasks = response.json()
    assert len(tasks) >= 2


@pytest.mark.asyncio
async def test_list_tasks_filter_by_status(client):
    await client.post("/tasks", json={"title": "Todo task", "status": 0})
    await client.post("/tasks", json={"title": "Done task", "status": 2})

    response = await client.get("/tasks?status=0")
    assert response.status_code == 200
    for task in response.json():
        assert task["status"] == 0


@pytest.mark.asyncio
async def test_update_task(client):
    create_resp = await client.post("/tasks", json={"title": "Original"})
    task_id = create_resp.json()["id"]

    response = await client.patch(f"/tasks/{task_id}", json={
        "title": "Updated",
        "status": 1,
    })
    assert response.status_code == 200
    assert response.json()["title"] == "Updated"
    assert response.json()["status"] == 1


@pytest.mark.asyncio
async def test_update_nonexistent_task(client):
    fake_id = str(uuid.uuid4())
    response = await client.patch(f"/tasks/{fake_id}", json={"title": "Nope"})
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_create_task_validation(client):
    # Empty title
    response = await client.post("/tasks", json={"title": ""})
    assert response.status_code == 422

    # Invalid priority
    response = await client.post("/tasks", json={"title": "Test", "priority": 5})
    assert response.status_code == 422

    # Invalid status
    response = await client.post("/tasks", json={"title": "Test", "status": 9})
    assert response.status_code == 422
