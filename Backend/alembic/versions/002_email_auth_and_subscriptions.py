"""Add email auth fields and subscriptions table

Revision ID: 002
Revises: 001
Create Date: 2026-02-18
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add email auth fields to users
    op.add_column("users", sa.Column("password_hash", sa.String(255), nullable=True))
    op.add_column("users", sa.Column("email_verified", sa.Boolean(), server_default="false", nullable=False))

    # Subscriptions table
    op.create_table(
        "subscriptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.String(255), nullable=False),
        sa.Column("status", sa.String(50), nullable=False, server_default="active"),
        sa.Column("original_transaction_id", sa.String(255), nullable=True),
        sa.Column("expiration_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("trial_start_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("trial_end_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id", name="pk_subscriptions"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"],
            name="fk_subscriptions_user_id_users",
            ondelete="CASCADE",
        ),
    )
    op.create_index("ix_subscriptions_user_id", "subscriptions", ["user_id"])
    op.create_index("ix_subscriptions_original_transaction_id", "subscriptions", ["original_transaction_id"])


def downgrade() -> None:
    op.drop_table("subscriptions")
    op.drop_column("users", "email_verified")
    op.drop_column("users", "password_hash")
