import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Task(Base):
    __tablename__ = "tasks"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    project_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("projects.id", ondelete="SET NULL"), index=True)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    estimate_minutes: Mapped[int | None] = mapped_column(Integer)
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=1)  # 0=low, 1=med, 2=high, 3=urgent
    status: Mapped[int] = mapped_column(Integer, nullable=False, default=0)  # 0=todo, 1=inProgress, 2=done
    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="tasks")  # noqa: F821
    project: Mapped["Project | None"] = relationship(back_populates="tasks")  # noqa: F821
