import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.subscription import Subscription

# Free tier limits
FREE_HISTORY_DAYS = 30
FREE_MAX_FRIENDS = 3


async def get_subscription_status(db: AsyncSession, user_id: uuid.UUID) -> dict:
    """Get the current subscription status for a user."""
    result = await db.execute(
        select(Subscription)
        .where(Subscription.user_id == user_id)
        .where(Subscription.status.in_(["active", "trial"]))
        .order_by(Subscription.created_at.desc())
        .limit(1)
    )
    sub = result.scalar_one_or_none()

    if sub is None:
        return {
            "is_pro": False,
            "product_id": None,
            "status": None,
            "expiration_date": None,
            "is_trial": False,
            "trial_end_date": None,
        }

    now = datetime.now(timezone.utc)
    is_expired = sub.expiration_date and sub.expiration_date < now
    is_trial = sub.status == "trial"
    trial_expired = sub.trial_end_date and sub.trial_end_date < now

    if is_expired or (is_trial and trial_expired):
        sub.status = "expired"
        await db.flush()
        return {
            "is_pro": False,
            "product_id": sub.product_id,
            "status": "expired",
            "expiration_date": sub.expiration_date,
            "is_trial": is_trial,
            "trial_end_date": sub.trial_end_date,
        }

    return {
        "is_pro": True,
        "product_id": sub.product_id,
        "status": sub.status,
        "expiration_date": sub.expiration_date,
        "is_trial": is_trial,
        "trial_end_date": sub.trial_end_date,
    }


async def verify_and_upsert_subscription(
    db: AsyncSession,
    user_id: uuid.UUID,
    original_transaction_id: str,
    product_id: str,
) -> Subscription:
    """Create or update subscription from App Store transaction."""
    result = await db.execute(
        select(Subscription).where(
            Subscription.original_transaction_id == original_transaction_id
        )
    )
    sub = result.scalar_one_or_none()

    now = datetime.now(timezone.utc)

    if sub is None:
        sub = Subscription(
            id=uuid.uuid4(),
            user_id=user_id,
            product_id=product_id,
            status="active",
            original_transaction_id=original_transaction_id,
            created_at=now,
            updated_at=now,
        )
        db.add(sub)
    else:
        sub.product_id = product_id
        sub.status = "active"
        sub.updated_at = now

    await db.flush()
    await db.refresh(sub)
    return sub


async def is_user_pro(db: AsyncSession, user_id: uuid.UUID) -> bool:
    """Quick check if user has active pro subscription."""
    status = await get_subscription_status(db, user_id)
    return status["is_pro"]
