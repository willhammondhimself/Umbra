import uuid
from datetime import datetime

from pydantic import BaseModel


class SubscriptionVerifyRequest(BaseModel):
    original_transaction_id: str
    product_id: str


class SubscriptionStatusResponse(BaseModel):
    is_pro: bool
    product_id: str | None = None
    status: str | None = None
    expiration_date: datetime | None = None
    is_trial: bool = False
    trial_end_date: datetime | None = None

    model_config = {"from_attributes": True}


class SubscriptionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    product_id: str
    status: str
    original_transaction_id: str | None
    expiration_date: datetime | None
    trial_start_date: datetime | None
    trial_end_date: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}
