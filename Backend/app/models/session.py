import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Session(Base):
    __tablename__ = "sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    focused_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    distraction_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_complete: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="sessions")  # noqa: F821
    events: Mapped[list["SessionEvent"]] = relationship(back_populates="session", cascade="all, delete-orphan")  # noqa: F821
