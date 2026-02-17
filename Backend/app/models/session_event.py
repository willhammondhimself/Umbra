import uuid
from datetime import datetime

from sqlalchemy import JSON, DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class SessionEvent(Base):
    __tablename__ = "session_events"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False
    )
    event_type: Mapped[str] = mapped_column(
        String(50), nullable=False
    )  # START, PAUSE, RESUME, STOP, TASK_COMPLETE, DISTRACTION, IDLE
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    app_name: Mapped[str | None] = mapped_column(String(255))
    duration_seconds: Mapped[int | None] = mapped_column(Integer)
    metadata_json: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    # Relationships
    session: Mapped["Session"] = relationship(back_populates="events")  # noqa: F821

    __table_args__ = (
        Index("ix_session_events_session_timestamp", "session_id", "timestamp"),
        Index("ix_session_events_dedup", "session_id", "event_type", "timestamp", unique=True),
    )
