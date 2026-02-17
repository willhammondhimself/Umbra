import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.friendship import Friendship
from app.models.social_event import SocialEvent
from app.models.user import User


@pytest.mark.asyncio
async def test_list_friends_empty(client):
    response = await client.get("/friends")
    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.asyncio
async def test_invite_friend(client, second_user):
    response = await client.post(
        "/friends/invite", json={"email": "friend@example.com"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "pending"
    assert "id" in data


@pytest.mark.asyncio
async def test_invite_nonexistent_user(client):
    response = await client.post(
        "/friends/invite", json={"email": "nobody@example.com"}
    )
    assert response.status_code == 400
    assert "not found" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_invite_self(client, test_user):
    response = await client.post(
        "/friends/invite", json={"email": test_user.email}
    )
    assert response.status_code == 400
    assert "yourself" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_invite_duplicate(client, second_user):
    await client.post("/friends/invite", json={"email": "friend@example.com"})
    response = await client.post(
        "/friends/invite", json={"email": "friend@example.com"}
    )
    assert response.status_code == 400
    assert "exists" in response.json()["detail"].lower() or "pending" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_accept_invite(client, db_session, test_user, second_user):
    # Create pending friendship where test_user initiated
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="pending",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()
    await db_session.refresh(friendship)

    # Now switch to second_user perspective by overriding
    from app.dependencies import get_current_user
    from app.main import app

    app.dependency_overrides[get_current_user] = lambda: second_user

    response = await client.post(f"/friends/{friendship.id}/accept")
    assert response.status_code == 200
    assert response.json()["status"] == "accepted"

    # Restore original user
    app.dependency_overrides[get_current_user] = lambda: test_user


@pytest.mark.asyncio
async def test_accept_own_invite_fails(client, db_session, test_user, second_user):
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="pending",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()
    await db_session.refresh(friendship)

    # test_user (initiator) tries to accept — should fail
    response = await client.post(f"/friends/{friendship.id}/accept")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_accept_nonexistent_invite(client):
    fake_id = uuid.uuid4()
    response = await client.post(f"/friends/{fake_id}/accept")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_list_friends_after_accept(client, db_session, test_user, second_user):
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="accepted",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()

    response = await client.get("/friends")
    assert response.status_code == 200
    friends = response.json()
    assert len(friends) == 1
    assert friends[0]["status"] == "accepted"


@pytest.mark.asyncio
async def test_encourage_friend(client, db_session, test_user, second_user):
    # Create accepted friendship
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="accepted",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()

    response = await client.post(
        "/social/encourage",
        json={"to_user_id": str(second_user.id), "message": "Keep going!"},
    )
    assert response.status_code == 201
    assert response.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_encourage_non_friend_fails(client, second_user):
    response = await client.post(
        "/social/encourage",
        json={"to_user_id": str(second_user.id), "message": "Keep going!"},
    )
    assert response.status_code == 400
    assert "friends" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_ping_friend(client, db_session, test_user, second_user):
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="accepted",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()

    response = await client.post(
        "/social/ping",
        json={"to_user_id": str(second_user.id)},
    )
    assert response.status_code == 201
    assert response.json()["status"] == "sent"


@pytest.mark.asyncio
async def test_ping_non_friend_fails(client, second_user):
    response = await client.post(
        "/social/ping",
        json={"to_user_id": str(second_user.id)},
    )
    assert response.status_code == 400
    assert "friends" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_ping_rate_limit(client, db_session, test_user, second_user):
    uid1, uid2 = (min(test_user.id, second_user.id), max(test_user.id, second_user.id))
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="accepted",
        initiated_by=test_user.id,
    )
    db_session.add(friendship)
    await db_session.commit()

    # Send 5 pings (at the limit)
    for _ in range(5):
        response = await client.post(
            "/social/ping",
            json={"to_user_id": str(second_user.id)},
        )
        assert response.status_code == 201

    # 6th should be rate limited
    response = await client.post(
        "/social/ping",
        json={"to_user_id": str(second_user.id)},
    )
    assert response.status_code == 429
    assert "limit" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_create_group(client):
    response = await client.post("/groups", json={"name": "Study Buddies"})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Study Buddies"
    assert data["member_count"] == 1  # Creator is auto-added
    assert "id" in data


@pytest.mark.asyncio
async def test_create_group_missing_name(client):
    response = await client.post("/groups", json={})
    assert response.status_code == 422  # Pydantic validation error


@pytest.mark.asyncio
async def test_list_groups_after_create(client):
    # Create a group
    create_response = await client.post("/groups", json={"name": "My Group"})
    assert create_response.status_code == 201

    # List groups
    list_response = await client.get("/groups")
    assert list_response.status_code == 200
    groups = list_response.json()
    assert len(groups) == 1
    assert groups[0]["name"] == "My Group"


@pytest.mark.asyncio
async def test_add_group_member(client, db_session, test_user, second_user):
    # Create a group as test_user
    create_response = await client.post("/groups", json={"name": "Team"})
    assert create_response.status_code == 201
    group_id = create_response.json()["id"]

    # Add second_user to the group
    add_response = await client.post(
        f"/groups/{group_id}/members",
        json={"user_id": str(second_user.id)},
    )
    assert add_response.status_code == 201
    assert add_response.json()["status"] == "member_added"


@pytest.mark.asyncio
async def test_add_group_member_duplicate(client, db_session, test_user, second_user):
    from app.models.group_member import GroupMember
    from app.models.group import Group

    # Create a group with second_user already added
    group = Group(name="Test Group", created_by=test_user.id)
    db_session.add(group)
    await db_session.flush()

    member = GroupMember(group_id=group.id, user_id=second_user.id)
    db_session.add(member)
    await db_session.commit()

    # Try to add second_user again
    response = await client.post(
        f"/groups/{group.id}/members",
        json={"user_id": str(second_user.id)},
    )
    assert response.status_code == 400
    assert "already" in response.json()["detail"].lower()


