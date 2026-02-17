import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device import Device
from app.models.user import User


async def get_user_devices(db: AsyncSession, user_id: uuid.UUID) -> list[Device]:
    """Get all registered devices for a user."""
    result = await db.execute(
        select(Device).where(Device.user_id == user_id)
    )
    return list(result.scalars().all())


async def send_push_notification(
    db: AsyncSession,
    to_user_id: uuid.UUID,
    title: str,
    body: str,
    apns_client=None,
) -> int:
    """Send push notification to all devices of a user.

    Returns the number of notifications sent.
    Uses aioapns client if provided, otherwise logs intent for testing.
    """
    devices = await get_user_devices(db, to_user_id)
    sent = 0

    for device in devices:
        if device.platform == "ios" and apns_client is not None:
            try:
                from aioapns import NotificationRequest

                notification = NotificationRequest(
                    device_token=device.token,
                    message={
                        "aps": {
                            "alert": {"title": title, "body": body},
                            "sound": "default",
                            "badge": 1,
                        }
                    },
                )
                response = await apns_client.send_notification(notification)
                if response.is_successful:
                    sent += 1
            except ImportError:
                # aioapns not installed — skip silently in dev
                pass
            except Exception:
                # Individual send failures shouldn't break the loop
                pass

    return sent


async def notify_encourage(
    db: AsyncSession,
    from_user_id: uuid.UUID,
    to_user_id: uuid.UUID,
    message: str,
    apns_client=None,
):
    """Send push notification for encouragement."""
    from_user = await db.get(User, from_user_id)
    name = from_user.display_name or "A friend" if from_user else "A friend"
    await send_push_notification(
        db,
        to_user_id,
        title=f"{name} sent you encouragement!",
        body=message[:100],
        apns_client=apns_client,
    )


async def notify_ping(
    db: AsyncSession,
    from_user_id: uuid.UUID,
    to_user_id: uuid.UUID,
    apns_client=None,
):
    """Send push notification for accountability ping."""
    from_user = await db.get(User, from_user_id)
    name = from_user.display_name or "A friend" if from_user else "A friend"
    await send_push_notification(
        db,
        to_user_id,
        title="Accountability Ping",
        body=f"{name} wants to know how you're doing!",
        apns_client=apns_client,
    )


async def notify_friend_request(
    db: AsyncSession,
    from_user_id: uuid.UUID,
    to_user_id: uuid.UUID,
    apns_client=None,
):
    """Send push notification for friend request."""
    from_user = await db.get(User, from_user_id)
    name = from_user.display_name or "Someone" if from_user else "Someone"
    await send_push_notification(
        db,
        to_user_id,
        title="Friend Request",
        body=f"{name} wants to be your accountability partner!",
        apns_client=apns_client,
    )


async def notify_streak_milestone(
    db: AsyncSession,
    user_id: uuid.UUID,
    streak_days: int,
    apns_client=None,
):
    """Send push notification for streak milestone."""
    await send_push_notification(
        db,
        user_id,
        title="Streak Milestone!",
        body=f"You've maintained a {streak_days}-day focus streak! Keep it up!",
        apns_client=apns_client,
    )
