import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Group(Base):
    __tablename__ = "groups"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    members: Mapped[list["GroupMember"]] = relationship(back_populates="group", cascade="all, delete-orphan")  # noqa: F821
