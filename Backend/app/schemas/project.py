import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class ProjectCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class ProjectResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
