import uuid
from datetime import datetime

from pydantic import BaseModel


class DeviceRegister(BaseModel):
    token: str
    platform: str  # "ios" or "macos"


class DeviceResponse(BaseModel):
    id: uuid.UUID
    token: str
    platform: str
    created_at: datetime

    model_config = {"from_attributes": True}
