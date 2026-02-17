import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class GroupMember(Base):
    __tablename__ = "group_members"

    group_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("groups.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    group: Mapped["Group"] = relationship(back_populates="members")  # noqa: F821

    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_members_pair"),
    )
