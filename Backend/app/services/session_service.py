import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session
from app.models.session_event import SessionEvent


async def get_sessions(
    db: AsyncSession,
    user_id: uuid.UUID,
    limit: int = 50,
    offset: int = 0,
    start_date: datetime | None = None,
    end_date: datetime | None = None,
) -> list[Session]:
    query = select(Session).where(Session.user_id == user_id)
    if start_date:
        query = query.where(Session.start_time >= start_date)
    if end_date:
        query = query.where(Session.start_time <= end_date)
    query = query.order_by(Session.start_time.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    return list(result.scalars().all())


async def create_session(db: AsyncSession, user_id: uuid.UUID, data: dict) -> Session:
    session = Session(user_id=user_id, **data)
    db.add(session)
    await db.flush()
    await db.refresh(session)
    return session


async def update_session(
    db: AsyncSession, user_id: uuid.UUID, session_id: uuid.UUID, data: dict
) -> Session | None:
    result = await db.execute(
        select(Session).where(Session.id == session_id, Session.user_id == user_id)
    )
    session = result.scalar_one_or_none()
    if session is None:
        return None

    for key, value in data.items():
        if value is not None:
            setattr(session, key, value)
    session.updated_at = datetime.now(timezone.utc)

    await db.flush()
    await db.refresh(session)
    return session


async def append_events_batch(
    db: AsyncSession,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
    events: list[dict],
) -> list[SessionEvent]:
    # Verify session belongs to user
    result = await db.execute(
        select(Session).where(Session.id == session_id, Session.user_id == user_id)
    )
    session = result.scalar_one_or_none()
    if session is None:
        return []

    created = []
    for event_data in events:
        # Check for duplicate (session_id + event_type + timestamp)
        existing = await db.execute(
            select(SessionEvent).where(
                SessionEvent.session_id == session_id,
                SessionEvent.event_type == event_data["event_type"],
                SessionEvent.timestamp == event_data["timestamp"],
            )
        )
        if existing.scalar_one_or_none() is not None:
            continue  # Skip duplicate

        event = SessionEvent(session_id=session_id, **event_data)
        db.add(event)
        created.append(event)

    if created:
        await db.flush()
        for event in created:
            await db.refresh(event)

    return created


async def get_events_since(
    db: AsyncSession,
    session_id: uuid.UUID,
    since: datetime | None = None,
) -> list[SessionEvent]:
    query = select(SessionEvent).where(SessionEvent.session_id == session_id)
    if since:
        query = query.where(SessionEvent.timestamp > since)
    query = query.order_by(SessionEvent.timestamp.asc())
    result = await db.execute(query)
    return list(result.scalars().all())
