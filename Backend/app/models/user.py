from datetime import datetime

from sqlalchemy import JSON, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class User(Base):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(String(1024))
    auth_provider: Mapped[str] = mapped_column(String(50), nullable=False)  # "apple", "google", or "email"
    auth_provider_id: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email_verified: Mapped[bool] = mapped_column(default=False, server_default="false")
    settings_json: Mapped[dict | None] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    projects: Mapped[list["Project"]] = relationship(back_populates="user", cascade="all, delete-orphan")  # noqa: F821
    tasks: Mapped[list["Task"]] = relationship(back_populates="user", cascade="all, delete-orphan")  # noqa: F821
    sessions: Mapped[list["Session"]] = relationship(back_populates="user", cascade="all, delete-orphan")  # noqa: F821
