import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class SocialEvent(Base):
    __tablename__ = "social_events"

    from_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    to_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    event_type: Mapped[str] = mapped_column(
        String(50), nullable=False
    )  # encourage, ping
    message: Mapped[str | None] = mapped_column(String(500))
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
