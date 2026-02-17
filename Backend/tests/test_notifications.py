import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device import Device
from app.models.user import User
from app.services.notification_service import (
    notify_encourage,
    notify_friend_request,
    notify_ping,
    notify_streak_milestone,
    send_push_notification,
)


@pytest.fixture
async def target_user(db_session: AsyncSession) -> User:
    """A user who will receive push notifications."""
    user = User(
        id=uuid.uuid4(),
        email="target@example.com",
        display_name="Target User",
        auth_provider="apple",
        auth_provider_id="apple_target_789",
        settings_json={"visibility": "friends"},
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


@pytest.fixture
async def ios_device(db_session: AsyncSession, target_user: User) -> Device:
    """An iOS device registered to the target user."""
    device = Device(
        id=uuid.uuid4(),
        user_id=target_user.id,
        token="fake-apns-device-token-abc123",
        platform="ios",
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(device)
    await db_session.commit()
    await db_session.refresh(device)
    return device


@pytest.fixture
async def macos_device(db_session: AsyncSession, target_user: User) -> Device:
    """A macOS device registered to the target user (no APNs push)."""
    device = Device(
        id=uuid.uuid4(),
        user_id=target_user.id,
        token="fake-macos-token-xyz456",
        platform="macos",
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(device)
    await db_session.commit()
    await db_session.refresh(device)
    return device


def _make_apns_client(successful: bool = True) -> MagicMock:
    """Create a mock APNs client that returns configurable responses."""
    mock_client = MagicMock()
    mock_response = MagicMock()
    mock_response.is_successful = successful
    mock_client.send_notification = AsyncMock(return_value=mock_response)
    return mock_client


# ── send_push_notification tests ──────────────────────────────────────


@pytest.mark.asyncio
async def test_send_push_no_devices(db_session: AsyncSession, target_user: User):
    """No devices registered — should return 0 sent."""
    apns = _make_apns_client()
    sent = await send_push_notification(
        db_session, target_user.id, "Title", "Body", apns_client=apns
    )
    assert sent == 0
    apns.send_notification.assert_not_called()


@pytest.mark.asyncio
async def test_send_push_no_apns_client(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """APNs client is None — should return 0 even with devices."""
    sent = await send_push_notification(
        db_session, target_user.id, "Title", "Body", apns_client=None
    )
    assert sent == 0


@pytest.mark.asyncio
async def test_send_push_ios_device_success(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """Successful push to a single iOS device."""
    apns = _make_apns_client(successful=True)
    sent = await send_push_notification(
        db_session, target_user.id, "Hello", "World", apns_client=apns
    )
    assert sent == 1
    apns.send_notification.assert_called_once()

    # Verify the notification request payload
    call_args = apns.send_notification.call_args
    notification = call_args[0][0]
    assert notification.device_token == ios_device.token
    assert notification.message["aps"]["alert"]["title"] == "Hello"
    assert notification.message["aps"]["alert"]["body"] == "World"
    assert notification.message["aps"]["sound"] == "default"


@pytest.mark.asyncio
async def test_send_push_ios_device_failure(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """APNs returns failure — should return 0 sent."""
    apns = _make_apns_client(successful=False)
    sent = await send_push_notification(
        db_session, target_user.id, "Hello", "World", apns_client=apns
    )
    assert sent == 0
    apns.send_notification.assert_called_once()


@pytest.mark.asyncio
async def test_send_push_skips_macos_devices(
    db_session: AsyncSession, target_user: User, macos_device: Device
):
    """macOS devices should not receive APNs push notifications."""
    apns = _make_apns_client()
    sent = await send_push_notification(
        db_session, target_user.id, "Hello", "World", apns_client=apns
    )
    assert sent == 0
    apns.send_notification.assert_not_called()


@pytest.mark.asyncio
async def test_send_push_multiple_devices(
    db_session: AsyncSession, target_user: User, ios_device: Device, macos_device: Device
):
    """Mixed devices — only iOS should get push, macOS skipped."""
    # Add a second iOS device
    device2 = Device(
        id=uuid.uuid4(),
        user_id=target_user.id,
        token="second-ios-token",
        platform="ios",
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(device2)
    await db_session.commit()

    apns = _make_apns_client(successful=True)
    sent = await send_push_notification(
        db_session, target_user.id, "Hello", "World", apns_client=apns
    )
    assert sent == 2
    assert apns.send_notification.call_count == 2


@pytest.mark.asyncio
async def test_send_push_exception_handling(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """APNs client raises exception — should not propagate, return 0."""
    apns = MagicMock()
    apns.send_notification = AsyncMock(side_effect=Exception("Connection lost"))
    sent = await send_push_notification(
        db_session, target_user.id, "Hello", "World", apns_client=apns
    )
    assert sent == 0


# ── notify_encourage tests ────────────────────────────────────────────


@pytest.mark.asyncio
async def test_notify_encourage(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """Encourage notification includes sender name and message."""
    apns = _make_apns_client(successful=True)
    await notify_encourage(
        db_session, test_user.id, target_user.id, "Keep going!", apns_client=apns
    )
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert "Test User" in notification.message["aps"]["alert"]["title"]
    assert "encouragement" in notification.message["aps"]["alert"]["title"].lower()
    assert notification.message["aps"]["alert"]["body"] == "Keep going!"


@pytest.mark.asyncio
async def test_notify_encourage_truncates_message(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """Long encouragement messages are truncated to 100 chars."""
    long_message = "x" * 200
    apns = _make_apns_client(successful=True)
    await notify_encourage(
        db_session, test_user.id, target_user.id, long_message, apns_client=apns
    )
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert len(notification.message["aps"]["alert"]["body"]) == 100


@pytest.mark.asyncio
async def test_notify_encourage_no_apns_client(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """No APNs client — should not raise."""
    await notify_encourage(
        db_session, test_user.id, target_user.id, "Keep going!", apns_client=None
    )


# ── notify_ping tests ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_notify_ping(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """Ping notification includes sender name."""
    apns = _make_apns_client(successful=True)
    await notify_ping(db_session, test_user.id, target_user.id, apns_client=apns)
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert notification.message["aps"]["alert"]["title"] == "Accountability Ping"
    assert "Test User" in notification.message["aps"]["alert"]["body"]


@pytest.mark.asyncio
async def test_notify_ping_no_apns_client(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """No APNs client — should not raise."""
    await notify_ping(db_session, test_user.id, target_user.id, apns_client=None)


# ── notify_friend_request tests ──────────────────────────────────────


@pytest.mark.asyncio
async def test_notify_friend_request(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """Friend request notification includes sender name."""
    apns = _make_apns_client(successful=True)
    await notify_friend_request(db_session, test_user.id, target_user.id, apns_client=apns)
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert notification.message["aps"]["alert"]["title"] == "Friend Request"
    assert "Test User" in notification.message["aps"]["alert"]["body"]
    assert "accountability partner" in notification.message["aps"]["alert"]["body"].lower()


@pytest.mark.asyncio
async def test_notify_friend_request_no_apns_client(
    db_session: AsyncSession, test_user: User, target_user: User, ios_device: Device
):
    """No APNs client — should not raise."""
    await notify_friend_request(db_session, test_user.id, target_user.id, apns_client=None)


# ── notify_streak_milestone tests ────────────────────────────────────


@pytest.mark.asyncio
async def test_notify_streak_milestone(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """Streak milestone notification with correct day count."""
    apns = _make_apns_client(successful=True)
    await notify_streak_milestone(db_session, target_user.id, 7, apns_client=apns)
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert notification.message["aps"]["alert"]["title"] == "Streak Milestone!"
    assert "7-day" in notification.message["aps"]["alert"]["body"]
    assert "Keep it up!" in notification.message["aps"]["alert"]["body"]


@pytest.mark.asyncio
async def test_notify_streak_milestone_large_streak(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """Streak milestone works for large streak counts."""
    apns = _make_apns_client(successful=True)
    await notify_streak_milestone(db_session, target_user.id, 365, apns_client=apns)
    apns.send_notification.assert_called_once()
    notification = apns.send_notification.call_args[0][0]
    assert "365-day" in notification.message["aps"]["alert"]["body"]


@pytest.mark.asyncio
async def test_notify_streak_milestone_no_apns_client(
    db_session: AsyncSession, target_user: User, ios_device: Device
):
    """No APNs client — should not raise."""
    await notify_streak_milestone(db_session, target_user.id, 7, apns_client=None)


@pytest.mark.asyncio
async def test_notify_streak_milestone_no_devices(
    db_session: AsyncSession, target_user: User
):
    """No devices registered — should complete without error."""
    apns = _make_apns_client()
    await notify_streak_milestone(db_session, target_user.id, 7, apns_client=apns)
    apns.send_notification.assert_not_called()
