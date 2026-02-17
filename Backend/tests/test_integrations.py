import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.integration import Integration
from app.services.slack_service import set_focus_status
from app.services.task_import_service import NotionImporter, TodoistImporter


# ── Integration CRUD endpoint tests ─────────────────────────────────


@pytest.mark.asyncio
async def test_create_integration(client):
    response = await client.post("/integrations", json={
        "provider": "slack",
        "access_token": "xoxb-fake-token",
    })
    assert response.status_code == 201
    data = response.json()
    assert data["provider"] == "slack"
    assert data["is_active"] is True
    assert data["user_id"] is not None
    # access_token should not be in response (IntegrationResponse excludes it)
    assert "access_token" not in data


@pytest.mark.asyncio
async def test_create_integration_invalid_provider(client):
    response = await client.post("/integrations", json={
        "provider": "invalid",
        "access_token": "token",
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_create_integration_upserts(client):
    """Creating same provider twice updates the existing integration."""
    resp1 = await client.post("/integrations", json={
        "provider": "todoist",
        "access_token": "token-1",
    })
    assert resp1.status_code == 201
    id1 = resp1.json()["id"]

    resp2 = await client.post("/integrations", json={
        "provider": "todoist",
        "access_token": "token-2",
    })
    assert resp2.status_code == 201
    id2 = resp2.json()["id"]
    assert id1 == id2  # Same integration, updated


@pytest.mark.asyncio
async def test_list_integrations(client):
    await client.post("/integrations", json={
        "provider": "slack",
        "access_token": "token-slack",
    })
    await client.post("/integrations", json={
        "provider": "todoist",
        "access_token": "token-todoist",
    })

    response = await client.get("/integrations")
    assert response.status_code == 200
    integrations = response.json()
    assert len(integrations) >= 2


@pytest.mark.asyncio
async def test_delete_integration(client):
    create_resp = await client.post("/integrations", json={
        "provider": "notion",
        "access_token": "token-notion",
    })
    integration_id = create_resp.json()["id"]

    delete_resp = await client.delete(f"/integrations/{integration_id}")
    assert delete_resp.status_code == 204

    # Verify it's no longer listed (soft delete = is_active=False)
    list_resp = await client.get("/integrations")
    integration_ids = [i["id"] for i in list_resp.json()]
    assert integration_id not in integration_ids


@pytest.mark.asyncio
async def test_delete_nonexistent_integration(client):
    fake_id = str(uuid.uuid4())
    response = await client.delete(f"/integrations/{fake_id}")
    assert response.status_code == 404


# ── Todoist import endpoint tests ────────────────────────────────────


@pytest.mark.asyncio
async def test_todoist_import_no_integration(client):
    """Import fails when no Todoist integration exists."""
    response = await client.post("/integrations/todoist/import", json={})
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_todoist_import_with_integration(client):
    """Import succeeds with mocked Todoist API response."""
    # Create Todoist integration
    await client.post("/integrations", json={
        "provider": "todoist",
        "access_token": "fake-todoist-token",
    })

    todoist_response = [
        {"content": "Buy groceries", "priority": 3, "due": {"date": "2026-03-01"}},
        {"content": "Call dentist", "priority": 1, "due": None},
    ]

    with patch.object(
        TodoistImporter,
        "import_tasks",
        new_callable=AsyncMock,
        return_value=[
            {"title": "Buy groceries", "priority": 2, "due_date": "2026-03-01"},
            {"title": "Call dentist", "priority": 0, "due_date": None},
        ],
    ):
        response = await client.post("/integrations/todoist/import", json={})

    assert response.status_code == 200
    data = response.json()
    assert data["imported_count"] == 2
    assert len(data["tasks"]) == 2
    assert data["tasks"][0]["title"] == "Buy groceries"


# ── Notion import endpoint tests ─────────────────────────────────────


@pytest.mark.asyncio
async def test_notion_import_no_integration(client):
    """Import fails when no Notion integration exists."""
    response = await client.post("/integrations/notion/import", json={
        "project_id": "fake-db-id",
    })
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_notion_import_missing_database_id(client):
    """Import fails when database_id not provided."""
    await client.post("/integrations", json={
        "provider": "notion",
        "access_token": "fake-notion-token",
    })

    response = await client.post("/integrations/notion/import", json={})
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_notion_import_with_integration(client):
    """Import succeeds with mocked Notion API response."""
    await client.post("/integrations", json={
        "provider": "notion",
        "access_token": "fake-notion-token",
    })

    with patch.object(
        NotionImporter,
        "import_tasks",
        new_callable=AsyncMock,
        return_value=[
            {"title": "Design mockups", "priority": 2, "due_date": "2026-03-15"},
        ],
    ):
        response = await client.post("/integrations/notion/import", json={
            "project_id": "notion-db-123",
        })

    assert response.status_code == 200
    data = response.json()
    assert data["imported_count"] == 1
    assert data["tasks"][0]["title"] == "Design mockups"


# ── Todoist importer service tests ───────────────────────────────────


@pytest.mark.asyncio
async def test_todoist_importer_normalize():
    """Test Todoist task normalization."""
    importer = TodoistImporter()

    todoist_tasks = [
        {"content": "Task 1", "priority": 4, "due": {"date": "2026-02-20"}},
        {"content": "Task 2", "priority": 1, "due": None},
        {"content": "Task 3", "priority": 2, "due": {"date": "2026-03-01"}},
    ]

    mock_response = httpx.Response(200, json=todoist_tasks)
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)

    tasks = await importer.import_tasks("fake-token", http_client=mock_client)

    assert len(tasks) == 3
    assert tasks[0] == {"title": "Task 1", "priority": 3, "due_date": "2026-02-20"}
    assert tasks[1] == {"title": "Task 2", "priority": 0, "due_date": None}
    assert tasks[2] == {"title": "Task 3", "priority": 1, "due_date": "2026-03-01"}


@pytest.mark.asyncio
async def test_todoist_importer_with_project_filter():
    """Test Todoist import with project filter."""
    importer = TodoistImporter()

    mock_response = httpx.Response(200, json=[])
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(return_value=mock_response)

    await importer.import_tasks("fake-token", project_id="proj-123", http_client=mock_client)

    call_args = mock_client.get.call_args
    assert call_args.kwargs["params"]["project_id"] == "proj-123"


@pytest.mark.asyncio
async def test_todoist_importer_api_error():
    """Test Todoist import handles API errors gracefully."""
    importer = TodoistImporter()

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.get = AsyncMock(side_effect=httpx.ConnectError("Connection refused"))

    tasks = await importer.import_tasks("fake-token", http_client=mock_client)
    assert tasks == []


# ── Notion importer service tests ────────────────────────────────────


@pytest.mark.asyncio
async def test_notion_importer_normalize():
    """Test Notion page normalization."""
    importer = NotionImporter()

    notion_response = {
        "results": [
            {
                "properties": {
                    "Name": {
                        "type": "title",
                        "title": [{"plain_text": "Design landing page"}],
                    },
                    "Priority": {
                        "type": "select",
                        "select": {"name": "High"},
                    },
                    "Due": {
                        "type": "date",
                        "date": {"start": "2026-04-01"},
                    },
                },
            },
            {
                "properties": {
                    "Task": {
                        "type": "title",
                        "title": [{"plain_text": "Write tests"}],
                    },
                },
            },
        ]
    }

    mock_response = httpx.Response(200, json=notion_response)
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(return_value=mock_response)

    tasks = await importer.import_tasks("fake-token", "db-123", http_client=mock_client)

    assert len(tasks) == 2
    assert tasks[0] == {"title": "Design landing page", "priority": 2, "due_date": "2026-04-01"}
    assert tasks[1] == {"title": "Write tests", "priority": 1, "due_date": None}


@pytest.mark.asyncio
async def test_notion_importer_api_error():
    """Test Notion import handles API errors gracefully."""
    importer = NotionImporter()

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=httpx.ConnectError("Connection refused"))

    tasks = await importer.import_tasks("fake-token", "db-123", http_client=mock_client)
    assert tasks == []


# ── Slack service tests ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_slack_set_focus_active():
    """Test setting Slack focus status active."""
    profile_resp = httpx.Response(200, json={"ok": True})
    dnd_resp = httpx.Response(200, json={"ok": True})

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=[profile_resp, dnd_resp])

    result = await set_focus_status("xoxb-token", is_active=True, http_client=mock_client)

    assert result is True
    assert mock_client.post.call_count == 2

    # Verify profile set call
    profile_call = mock_client.post.call_args_list[0]
    assert "users.profile.set" in profile_call.args[0]
    profile_json = profile_call.kwargs["json"]
    assert profile_json["profile"]["status_emoji"] == ":dart:"
    assert "Focusing in Tether" in profile_json["profile"]["status_text"]

    # Verify DND set call
    dnd_call = mock_client.post.call_args_list[1]
    assert "dnd.setSnooze" in dnd_call.args[0]


@pytest.mark.asyncio
async def test_slack_set_focus_inactive():
    """Test clearing Slack focus status."""
    profile_resp = httpx.Response(200, json={"ok": True})
    dnd_resp = httpx.Response(200, json={"ok": True})

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=[profile_resp, dnd_resp])

    result = await set_focus_status("xoxb-token", is_active=False, http_client=mock_client)

    assert result is True
    assert mock_client.post.call_count == 2

    # Verify profile clear call
    profile_call = mock_client.post.call_args_list[0]
    profile_json = profile_call.kwargs["json"]
    assert profile_json["profile"]["status_text"] == ""
    assert profile_json["profile"]["status_emoji"] == ""


@pytest.mark.asyncio
async def test_slack_set_focus_api_failure():
    """Test Slack API failure returns False."""
    profile_resp = httpx.Response(200, json={"ok": False, "error": "invalid_auth"})
    dnd_resp = httpx.Response(200, json={"ok": True})

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=[profile_resp, dnd_resp])

    result = await set_focus_status("xoxb-token", is_active=True, http_client=mock_client)

    assert result is False


@pytest.mark.asyncio
async def test_slack_set_focus_network_error():
    """Test Slack network error returns False."""
    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=httpx.ConnectError("Timeout"))

    result = await set_focus_status("xoxb-token", is_active=True, http_client=mock_client)

    assert result is False


@pytest.mark.asyncio
async def test_slack_end_dnd_not_snoozing():
    """Test ending DND when not snoozing is treated as success."""
    profile_resp = httpx.Response(200, json={"ok": True})
    dnd_resp = httpx.Response(200, json={"ok": False, "error": "snooze_not_active"})

    mock_client = AsyncMock(spec=httpx.AsyncClient)
    mock_client.post = AsyncMock(side_effect=[profile_resp, dnd_resp])

    result = await set_focus_status("xoxb-token", is_active=False, http_client=mock_client)

    assert result is True  # snooze_not_active is not a real error
