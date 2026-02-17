import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.session import (
    SessionCreate,
    SessionEventBatch,
    SessionEventResponse,
    SessionResponse,
    SessionUpdate,
)
from app.services import session_service

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.get("", response_model=list[SessionResponse])
async def list_sessions(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    start_date: datetime | None = Query(default=None),
    end_date: datetime | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await session_service.get_sessions(
        db, user.id, limit=limit, offset=offset,
        start_date=start_date, end_date=end_date,
    )


@router.post("", response_model=SessionResponse, status_code=201)
async def create_session(
    data: SessionCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await session_service.create_session(db, user.id, data.model_dump())


@router.patch("/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: uuid.UUID,
    data: SessionUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    session = await session_service.update_session(
        db, user.id, session_id, data.model_dump(exclude_unset=True)
    )
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )
    return session


@router.post("/{session_id}/events", response_model=list[SessionEventResponse], status_code=201)
async def append_events(
    session_id: uuid.UUID,
    batch: SessionEventBatch,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    events = await session_service.append_events_batch(
        db, user.id, session_id,
        [e.model_dump() for e in batch.events],
    )
    if not events and batch.events:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session not found or all events were duplicates",
        )
    return events
