"""End-to-end integration test covering the full user workflow."""
import uuid
from datetime import datetime, timezone

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import StaticPool
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.models import Base
from app.models.user import User


@pytest.mark.asyncio
async def test_full_workflow():
    """Register -> create project + tasks -> start/stop session -> verify stats ->
    export data -> delete account."""

    # Setup
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    test_user = User(
        id=uuid.uuid4(),
        email="integration@test.com",
        display_name="Integration Tester",
        auth_provider="apple",
        auth_provider_id="integration_test_id",
        settings_json={"visibility": "private"},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    async with session_factory() as session:
        session.add(test_user)
        await session.commit()

    async def override_get_db():
        async with session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    async def override_get_current_user():
        return test_user

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Create project
        resp = await client.post("/projects", json={"name": "Integration Test Project"})
        assert resp.status_code == 201
        project_id = resp.json()["id"]

        # 2. Create tasks
        task1_resp = await client.post("/tasks", json={
            "title": "Write integration tests",
            "project_id": project_id,
            "priority": 2,
        })
        assert task1_resp.status_code == 201
        task1_id = task1_resp.json()["id"]

        task2_resp = await client.post("/tasks", json={
            "title": "Review code",
            "priority": 1,
        })
        assert task2_resp.status_code == 201

        # 3. List tasks
        tasks_resp = await client.get("/tasks")
        assert tasks_resp.status_code == 200
        assert len(tasks_resp.json()) == 2

        # 4. Update task
        update_resp = await client.patch(f"/tasks/{task1_id}", json={
            "status": 2,  # done
        })
        assert update_resp.status_code == 200
        assert update_resp.json()["status"] == 2

        # 5. Start session
        now = datetime.now(timezone.utc)
        session_resp = await client.post("/sessions", json={
            "start_time": now.isoformat(),
        })
        assert session_resp.status_code == 201
        session_id = session_resp.json()["id"]

        # 6. Append events
        events_resp = await client.post(f"/sessions/{session_id}/events", json={
            "events": [
                {"event_type": "START", "timestamp": now.isoformat()},
                {"event_type": "DISTRACTION", "timestamp": now.isoformat(), "app_name": "Slack", "duration_seconds": 30},
                {"event_type": "STOP", "timestamp": now.isoformat()},
            ]
        })
        assert events_resp.status_code == 201
        assert len(events_resp.json()) == 3

        # 7. Finalize session
        finalize_resp = await client.patch(f"/sessions/{session_id}", json={
            "end_time": now.isoformat(),
            "duration_seconds": 3600,
            "focused_seconds": 3200,
            "distraction_count": 1,
            "is_complete": True,
        })
        assert finalize_resp.status_code == 200
        assert finalize_resp.json()["is_complete"] is True

        # 8. Check stats
        stats_resp = await client.get("/stats?period=weekly")
        assert stats_resp.status_code == 200
        stats = stats_resp.json()
        assert stats["focused_seconds"] == 3200
        assert stats["session_count"] == 1
        assert stats["distraction_count"] == 1

        # 9. Export account data
        export_resp = await client.get("/auth/account/export")
        assert export_resp.status_code == 200
        export = export_resp.json()
        assert export["user"]["email"] == "integration@test.com"
        assert len(export["projects"]) == 1
        assert len(export["tasks"]) == 2
        assert len(export["sessions"]) == 1
        assert len(export["session_events"]) == 3

        # 10. Delete account
        delete_resp = await client.delete("/auth/account")
        assert delete_resp.status_code == 204

    app.dependency_overrides.clear()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()
