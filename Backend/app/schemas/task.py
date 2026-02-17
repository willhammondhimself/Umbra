import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    project_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=500)
    estimate_minutes: int | None = Field(default=None, ge=1, le=1440)
    priority: int = Field(default=1, ge=0, le=3)
    status: int = Field(default=0, ge=0, le=2)
    due_date: datetime | None = None
    sort_order: int = 0


class TaskUpdate(BaseModel):
    project_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=500)
    estimate_minutes: int | None = Field(default=None, ge=1, le=1440)
    priority: int | None = Field(default=None, ge=0, le=3)
    status: int | None = Field(default=None, ge=0, le=2)
    due_date: datetime | None = None
    sort_order: int | None = None


class TaskResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    project_id: uuid.UUID | None
    title: str
    estimate_minutes: int | None
    priority: int
    status: int
    due_date: datetime | None
    sort_order: int
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
