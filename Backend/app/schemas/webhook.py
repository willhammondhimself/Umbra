import uuid
from datetime import datetime

from pydantic import BaseModel, Field, HttpUrl


class WebhookCreate(BaseModel):
    url: str = Field(min_length=1, max_length=2048)
    events: list[str] = Field(
        min_length=1,
        description="Event types to subscribe to: session.start, session.end, task.complete",
    )


class WebhookResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    url: str
    events: list[str]
    secret: str
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class WebhookList(BaseModel):
    webhooks: list[WebhookResponse]
    count: int
