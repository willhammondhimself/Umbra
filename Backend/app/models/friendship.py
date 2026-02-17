import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Friendship(Base):
    __tablename__ = "friendships"

    # Canonical ordering: user_id_1 < user_id_2 to prevent duplicates
    user_id_1: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id_2: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending"
    )  # pending, accepted, declined
    initiated_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        UniqueConstraint("user_id_1", "user_id_2", name="uq_friendships_pair"),
        CheckConstraint("user_id_1 < user_id_2", name="ck_friendships_canonical_order"),
    )
