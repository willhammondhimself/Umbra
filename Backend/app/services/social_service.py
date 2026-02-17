import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.friendship import Friendship
from app.models.group import Group
from app.models.group_member import GroupMember
from app.models.session import Session
from app.models.social_event import SocialEvent
from app.models.user import User
from app.services.notification_service import (
    notify_encourage,
    notify_friend_request,
    notify_ping,
)


async def get_friends(db: AsyncSession, user_id: uuid.UUID) -> list[dict]:
    """Get all friends (accepted) and pending invites for a user."""
    result = await db.execute(
        select(Friendship).where(
            or_(
                Friendship.user_id_1 == user_id,
                Friendship.user_id_2 == user_id,
            )
        )
    )
    friendships = result.scalars().all()

    friends = []
    for f in friendships:
        friend_id = f.user_id_2 if f.user_id_1 == user_id else f.user_id_1
        user_result = await db.execute(select(User).where(User.id == friend_id))
        friend = user_result.scalar_one_or_none()
        if friend:
            friends.append({
                "id": f.id,
                "user_id": friend.id,
                "display_name": friend.display_name,
                "email": friend.email,
                "status": f.status,
                "since": f.created_at,
            })
    return friends


async def send_invite(
    db: AsyncSession, user_id: uuid.UUID, email: str, redis_client, apns_client=None
) -> dict:
    """Send friend invite. Rate limited to 20/day."""
    # Check rate limit
    today_key = f"invites:{user_id}:{datetime.now(timezone.utc).date()}"
    count = await redis_client.get(today_key)
    if count and int(count) >= 20:
        raise ValueError("Daily invite limit reached (20/day)")

    # Find target user
    result = await db.execute(select(User).where(User.email == email))
    target = result.scalar_one_or_none()
    if target is None:
        raise ValueError("User not found")

    if target.id == user_id:
        raise ValueError("Cannot invite yourself")

    # Canonical ordering
    uid1, uid2 = (min(user_id, target.id), max(user_id, target.id))

    # Check existing
    existing = await db.execute(
        select(Friendship).where(
            Friendship.user_id_1 == uid1,
            Friendship.user_id_2 == uid2,
        )
    )
    if existing.scalar_one_or_none():
        raise ValueError("Friendship already exists or pending")

    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="pending",
        initiated_by=user_id,
    )
    db.add(friendship)
    await db.flush()

    # Increment rate limit
    await redis_client.incr(today_key)
    await redis_client.expire(today_key, 86400)

    # Send push notification to invited user
    await notify_friend_request(db, user_id, target.id, apns_client)

    return {"id": str(friendship.id), "status": "pending"}


async def accept_invite(
    db: AsyncSession, user_id: uuid.UUID, friendship_id: uuid.UUID
) -> bool:
    """Accept a pending friend invite."""
    result = await db.execute(
        select(Friendship).where(Friendship.id == friendship_id)
    )
    friendship = result.scalar_one_or_none()
    if friendship is None:
        return False

    # Only the non-initiator can accept
    if friendship.initiated_by == user_id:
        return False

    # Must be involved
    if user_id not in (friendship.user_id_1, friendship.user_id_2):
        return False

    friendship.status = "accepted"
    await db.flush()
    return True


async def get_groups(db: AsyncSession, user_id: uuid.UUID) -> list[dict]:
    """Get all groups the user belongs to."""
    result = await db.execute(
        select(Group, func.count(GroupMember.id).label("member_count"))
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(
            Group.id.in_(
                select(GroupMember.group_id).where(GroupMember.user_id == user_id)
            )
        )
        .group_by(Group.id)
    )
    groups = []
    for row in result.all():
        group = row[0]
        groups.append({
            "id": group.id,
            "name": group.name,
            "created_by": group.created_by,
            "created_at": group.created_at,
            "member_count": row[1],
        })
    return groups


async def get_leaderboard(
    db: AsyncSession, group_id: uuid.UUID, user_id: uuid.UUID
) -> list[dict]:
    """Get weekly leaderboard for a group, respecting privacy settings."""
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)

    # Get group members
    members_result = await db.execute(
        select(GroupMember.user_id).where(GroupMember.group_id == group_id)
    )
    member_ids = [row[0] for row in members_result.all()]

    if user_id not in member_ids:
        raise ValueError("Not a member of this group")

    # Get stats per member, respecting visibility
    entries = []
    for mid in member_ids:
        user_result = await db.execute(select(User).where(User.id == mid))
        member = user_result.scalar_one_or_none()
        if not member:
            continue

        # Respect privacy
        visibility = (member.settings_json or {}).get("visibility", "private")
        if visibility == "private" and mid != user_id:
            continue

        stats_result = await db.execute(
            select(
                func.coalesce(func.sum(Session.focused_seconds), 0),
                func.count(Session.id),
            ).where(
                Session.user_id == mid,
                Session.is_complete == True,  # noqa: E712
                Session.start_time >= week_ago,
            )
        )
        row = stats_result.one()
        entries.append({
            "user_id": mid,
            "display_name": member.display_name,
            "focused_seconds": row[0],
            "session_count": row[1],
        })

    # Sort by focused_seconds descending and assign ranks
    entries.sort(key=lambda e: e["focused_seconds"], reverse=True)
    for i, entry in enumerate(entries):
        entry["rank"] = i + 1

    return entries


async def send_encourage(
    db: AsyncSession, from_user_id: uuid.UUID, to_user_id: uuid.UUID, message: str,
    apns_client=None,
) -> None:
    """Send encouragement to a friend."""
    # Verify friendship
    if not await are_friends(db, from_user_id, to_user_id):
        raise ValueError("Can only encourage friends")

    event = SocialEvent(
        from_user_id=from_user_id,
        to_user_id=to_user_id,
        event_type="encourage",
        message=message,
    )
    db.add(event)
    await db.flush()

    await notify_encourage(db, from_user_id, to_user_id, message, apns_client)


async def send_ping(
    db: AsyncSession, from_user_id: uuid.UUID, to_user_id: uuid.UUID, redis_client,
    apns_client=None,
) -> None:
    """Send accountability ping. Rate limited to 5/friend/day."""
    if not await are_friends(db, from_user_id, to_user_id):
        raise ValueError("Can only ping friends")

    today_key = f"pings:{from_user_id}:{to_user_id}:{datetime.now(timezone.utc).date()}"
    count = await redis_client.get(today_key)
    if count and int(count) >= 5:
        raise ValueError("Daily ping limit reached (5/friend/day)")

    event = SocialEvent(
        from_user_id=from_user_id,
        to_user_id=to_user_id,
        event_type="ping",
    )
    db.add(event)
    await db.flush()

    await redis_client.incr(today_key)
    await redis_client.expire(today_key, 86400)

    await notify_ping(db, from_user_id, to_user_id, apns_client)


async def are_friends(db: AsyncSession, user_a: uuid.UUID, user_b: uuid.UUID) -> bool:
    """Check if two users are accepted friends."""
    uid1, uid2 = (min(user_a, user_b), max(user_a, user_b))
    result = await db.execute(
        select(Friendship).where(
            Friendship.user_id_1 == uid1,
            Friendship.user_id_2 == uid2,
            Friendship.status == "accepted",
        )
    )
    return result.scalar_one_or_none() is not None
