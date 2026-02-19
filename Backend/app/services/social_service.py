import json
import secrets
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


async def create_group(db: AsyncSession, user_id: uuid.UUID, name: str) -> dict:
    """Create a new accountability group (2-10 people). Creator is auto-added as member."""
    name = name.strip()
    if not name:
        raise ValueError("Group name cannot be empty")

    group = Group(
        name=name,
        created_by=user_id,
    )
    db.add(group)
    await db.flush()

    # Add creator as first member
    member = GroupMember(
        group_id=group.id,
        user_id=user_id,
    )
    db.add(member)
    await db.flush()

    return {
        "id": group.id,
        "name": group.name,
        "created_by": group.created_by,
        "created_at": group.created_at,
        "member_count": 1,
    }


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


async def generate_invite_link(
    db: AsyncSession, user_id: uuid.UUID, redis_client
) -> dict:
    """Generate a shareable invite link. Rate limited to 20/day (shared with email invites)."""
    # Check rate limit (shares counter with email invites)
    today_key = f"invites:{user_id}:{datetime.now(timezone.utc).date()}"
    count = await redis_client.get(today_key)
    if count and int(count) >= 20:
        raise ValueError("Daily invite limit reached (20/day)")

    # Generate unique 8-char alphanumeric code
    code = secrets.token_urlsafe(6)[:8]

    # Store in Redis with 7-day TTL
    redis_key = f"invite_link:{code}"
    await redis_client.set(redis_key, str(user_id), ex=604800)

    # Increment shared rate limit counter
    await redis_client.incr(today_key)
    await redis_client.expire(today_key, 86400)

    invite_url = f"https://tether.app/invite/{code}"
    return {"invite_code": code, "invite_url": invite_url}


async def accept_invite_link(
    db: AsyncSession, user_id: uuid.UUID, invite_code: str, redis_client
) -> bool:
    """Accept a shareable invite link and create a friendship."""
    # Look up the invite code in Redis
    redis_key = f"invite_link:{invite_code}"
    inviter_id_str = await redis_client.get(redis_key)
    if inviter_id_str is None:
        raise ValueError("Invalid or expired invite link")

    inviter_id = uuid.UUID(inviter_id_str)

    if inviter_id == user_id:
        raise ValueError("Cannot accept your own invite link")

    # Canonical ordering
    uid1, uid2 = (min(user_id, inviter_id), max(user_id, inviter_id))

    # Check existing friendship
    existing = await db.execute(
        select(Friendship).where(
            Friendship.user_id_1 == uid1,
            Friendship.user_id_2 == uid2,
        )
    )
    if existing.scalar_one_or_none():
        raise ValueError("Friendship already exists or pending")

    # Create accepted friendship directly (no pending state needed for link invites)
    friendship = Friendship(
        user_id_1=uid1,
        user_id_2=uid2,
        status="accepted",
        initiated_by=inviter_id,
    )
    db.add(friendship)
    await db.flush()

    # Delete the invite code from Redis (single-use)
    await redis_client.delete(redis_key)

    return True


async def react_to_session(
    db: AsyncSession,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
    reaction_type: str,
) -> dict:
    """React to a friend's completed session (thumbs_up or fire)."""
    # Verify the session exists and is complete
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if session is None:
        raise ValueError("Session not found")
    if not session.is_complete:
        raise ValueError("Can only react to completed sessions")

    # Cannot react to own sessions
    if session.user_id == user_id:
        raise ValueError("Cannot react to your own session")

    # Verify friendship
    if not await are_friends(db, user_id, session.user_id):
        raise ValueError("Can only react to friends' sessions")

    # Prevent duplicate reactions (same user + session + type)
    metadata_like = f'"session_id": "{session_id}"'
    existing_result = await db.execute(
        select(SocialEvent).where(
            SocialEvent.from_user_id == user_id,
            SocialEvent.to_user_id == session.user_id,
            SocialEvent.event_type == "reaction",
            SocialEvent.message.contains(str(session_id)),
            SocialEvent.message.contains(reaction_type),
        )
    )
    if existing_result.scalar_one_or_none() is not None:
        raise ValueError("Already reacted with this type")

    # Create social event for the reaction
    message_json = json.dumps({
        "session_id": str(session_id),
        "reaction_type": reaction_type,
    })
    event = SocialEvent(
        from_user_id=user_id,
        to_user_id=session.user_id,
        event_type="reaction",
        message=message_json,
    )
    db.add(event)
    await db.flush()

    # Get reactor display name
    reactor = await db.get(User, user_id)
    return {
        "id": event.id,
        "user_id": user_id,
        "display_name": reactor.display_name if reactor else None,
        "reaction_type": reaction_type,
        "created_at": event.timestamp,
    }


async def get_session_reactions(
    db: AsyncSession,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
) -> list[dict]:
    """Get all reactions for a session."""
    # Verify the session exists
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if session is None:
        raise ValueError("Session not found")

    # Verify the user is the session owner or a friend
    if session.user_id != user_id:
        if not await are_friends(db, user_id, session.user_id):
            raise ValueError("Not authorized to view reactions")

    # Get all reaction events for this session
    result = await db.execute(
        select(SocialEvent).where(
            SocialEvent.event_type == "reaction",
            SocialEvent.message.contains(str(session_id)),
        )
    )
    events = result.scalars().all()

    reactions = []
    for event in events:
        try:
            meta = json.loads(event.message)
        except (json.JSONDecodeError, TypeError):
            continue
        # Verify this reaction is actually for the requested session
        if meta.get("session_id") != str(session_id):
            continue
        reactor = await db.get(User, event.from_user_id)
        reactions.append({
            "id": event.id,
            "user_id": event.from_user_id,
            "display_name": reactor.display_name if reactor else None,
            "reaction_type": meta.get("reaction_type", ""),
            "created_at": event.timestamp,
        })

    return reactions


async def get_friend_activity(
    db: AsyncSession,
    user_id: uuid.UUID,
) -> list[dict]:
    """Get recent completed sessions from all friends (last 7 days) with reactions."""
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)

    # Get all accepted friend IDs
    friend_ids = await _get_friend_ids(db, user_id)
    if not friend_ids:
        return []

    # Get completed sessions from friends in last 7 days
    result = await db.execute(
        select(Session)
        .where(
            Session.user_id.in_(friend_ids),
            Session.is_complete == True,  # noqa: E712
            Session.start_time >= week_ago,
        )
        .order_by(Session.start_time.desc())
        .limit(50)
    )
    sessions = result.scalars().all()

    activities = []
    for sess in sessions:
        # Get friend display name
        friend = await db.get(User, sess.user_id)

        # Check privacy: respect visibility settings
        visibility = (friend.settings_json or {}).get("visibility", "private") if friend else "private"
        if visibility == "private":
            continue

        # Get reactions for this session
        reaction_result = await db.execute(
            select(SocialEvent).where(
                SocialEvent.event_type == "reaction",
                SocialEvent.message.contains(str(sess.id)),
            )
        )
        reaction_events = reaction_result.scalars().all()

        reactions = []
        for event in reaction_events:
            try:
                meta = json.loads(event.message)
            except (json.JSONDecodeError, TypeError):
                continue
            if meta.get("session_id") != str(sess.id):
                continue
            reactor = await db.get(User, event.from_user_id)
            reactions.append({
                "id": event.id,
                "user_id": event.from_user_id,
                "display_name": reactor.display_name if reactor else None,
                "reaction_type": meta.get("reaction_type", ""),
            })

        activities.append({
            "id": sess.id,
            "user_id": sess.user_id,
            "display_name": friend.display_name if friend else None,
            "start_time": sess.start_time,
            "duration_seconds": sess.duration_seconds,
            "focused_seconds": sess.focused_seconds,
            "reactions": reactions,
        })

    return activities


async def _get_friend_ids(db: AsyncSession, user_id: uuid.UUID) -> list[uuid.UUID]:
    """Get all accepted friend user IDs for a user."""
    result = await db.execute(
        select(Friendship).where(
            or_(
                Friendship.user_id_1 == user_id,
                Friendship.user_id_2 == user_id,
            ),
            Friendship.status == "accepted",
        )
    )
    friendships = result.scalars().all()
    friend_ids = []
    for f in friendships:
        friend_id = f.user_id_2 if f.user_id_1 == user_id else f.user_id_1
        friend_ids.append(friend_id)
    return friend_ids
