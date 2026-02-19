from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.subscription import (
    SubscriptionResponse,
    SubscriptionStatusResponse,
    SubscriptionVerifyRequest,
)
from app.services import subscription_service

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current subscription status for the authenticated user."""
    status = await subscription_service.get_subscription_status(db, user.id)
    return SubscriptionStatusResponse(**status)


@router.post("/verify", response_model=SubscriptionResponse)
async def verify_subscription(
    request: SubscriptionVerifyRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Verify and register an App Store subscription transaction."""
    sub = await subscription_service.verify_and_upsert_subscription(
        db=db,
        user_id=user.id,
        original_transaction_id=request.original_transaction_id,
        product_id=request.product_id,
    )
    return sub


@router.post("/webhook")
async def app_store_webhook():
    """Handle App Store Server Notifications V2."""
    # TODO: Implement App Store Server Notification V2 handling
    # This requires App Store Server API keys (blocker: Apple Developer enrollment)
    return {"status": "received"}
