"""Initial schema - all 10 tables

Revision ID: 001
Revises:
Create Date: 2026-02-17
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Users
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("display_name", sa.String(255), nullable=True),
        sa.Column("avatar_url", sa.String(1024), nullable=True),
        sa.Column("auth_provider", sa.String(50), nullable=False),
        sa.Column("auth_provider_id", sa.String(255), nullable=False),
        sa.Column("settings_json", postgresql.JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("email", name="uq_users_email"),
        sa.UniqueConstraint("auth_provider_id", name="uq_users_auth_provider_id"),
    )

    # Projects
    op.create_table(
        "projects",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_projects"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_projects_user_id_users", ondelete="CASCADE"),
    )
    op.create_index("ix_projects_user_id", "projects", ["user_id"])

    # Tasks
    op.create_table(
        "tasks",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("project_id", sa.Uuid(), nullable=True),
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("estimate_minutes", sa.Integer(), nullable=True),
        sa.Column("priority", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("status", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("due_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_tasks"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_tasks_user_id_users", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"], name="fk_tasks_project_id_projects", ondelete="SET NULL"),
    )
    op.create_index("ix_tasks_user_id", "tasks", ["user_id"])
    op.create_index("ix_tasks_project_id", "tasks", ["project_id"])

    # Sessions
    op.create_table(
        "sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("start_time", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_time", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("focused_seconds", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("distraction_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_complete", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_sessions"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_sessions_user_id_users", ondelete="CASCADE"),
    )
    op.create_index("ix_sessions_user_id", "sessions", ["user_id"])
    op.create_index("ix_sessions_user_start", "sessions", ["user_id", "start_time"])

    # Session Events
    op.create_table(
        "session_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("app_name", sa.String(255), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("metadata_json", postgresql.JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_session_events"),
        sa.ForeignKeyConstraint(["session_id"], ["sessions.id"], name="fk_session_events_session_id_sessions", ondelete="CASCADE"),
    )
    op.create_index("ix_session_events_session_timestamp", "session_events", ["session_id", "timestamp"])
    op.create_index(
        "ix_session_events_dedup",
        "session_events",
        ["session_id", "event_type", "timestamp"],
        unique=True,
    )

    # Friendships (canonical ordering: user_id_1 < user_id_2)
    op.create_table(
        "friendships",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id_1", sa.Uuid(), nullable=False),
        sa.Column("user_id_2", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("initiated_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_friendships"),
        sa.ForeignKeyConstraint(["user_id_1"], ["users.id"], name="fk_friendships_user_id_1_users", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id_2"], ["users.id"], name="fk_friendships_user_id_2_users", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["initiated_by"], ["users.id"], name="fk_friendships_initiated_by_users", ondelete="CASCADE"),
        sa.UniqueConstraint("user_id_1", "user_id_2", name="uq_friendships_pair"),
        sa.CheckConstraint("user_id_1 < user_id_2", name="ck_friendships_canonical_order"),
    )
    op.create_index("ix_friendships_user_id_1", "friendships", ["user_id_1"])
    op.create_index("ix_friendships_user_id_2", "friendships", ["user_id_2"])

    # Groups
    op.create_table(
        "groups",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_groups"),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"], name="fk_groups_created_by_users", ondelete="CASCADE"),
    )

    # Group Members
    op.create_table(
        "group_members",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("group_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("joined_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_group_members"),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], name="fk_group_members_group_id_groups", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_group_members_user_id_users", ondelete="CASCADE"),
        sa.UniqueConstraint("group_id", "user_id", name="uq_group_members_pair"),
    )
    op.create_index("ix_group_members_group_id", "group_members", ["group_id"])
    op.create_index("ix_group_members_user_id", "group_members", ["user_id"])

    # Social Events
    op.create_table(
        "social_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("from_user_id", sa.Uuid(), nullable=False),
        sa.Column("to_user_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("message", sa.String(500), nullable=True),
        sa.Column("timestamp", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_social_events"),
        sa.ForeignKeyConstraint(["from_user_id"], ["users.id"], name="fk_social_events_from_user_id_users", ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["to_user_id"], ["users.id"], name="fk_social_events_to_user_id_users", ondelete="CASCADE"),
    )
    op.create_index("ix_social_events_from_user_id", "social_events", ["from_user_id"])
    op.create_index("ix_social_events_to_user_id", "social_events", ["to_user_id"])


def downgrade() -> None:
    op.drop_table("social_events")
    op.drop_table("group_members")
    op.drop_table("groups")
    op.drop_table("friendships")
    op.drop_table("session_events")
    op.drop_table("sessions")
    op.drop_table("tasks")
    op.drop_table("projects")
    op.drop_table("users")
