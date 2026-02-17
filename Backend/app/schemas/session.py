import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class SessionCreate(BaseModel):
    start_time: datetime
    end_time: datetime | None = None
    duration_seconds: int = Field(default=0, ge=0)
    focused_seconds: int = Field(default=0, ge=0)
    distraction_count: int = Field(default=0, ge=0)
    is_complete: bool = False


class SessionUpdate(BaseModel):
    end_time: datetime | None = None
    duration_seconds: int | None = Field(default=None, ge=0)
    focused_seconds: int | None = Field(default=None, ge=0)
    distraction_count: int | None = Field(default=None, ge=0)
    is_complete: bool | None = None


class SessionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    start_time: datetime
    end_time: datetime | None
    duration_seconds: int
    focused_seconds: int
    distraction_count: int
    is_complete: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class SessionEventCreate(BaseModel):
    event_type: str = Field(min_length=1, max_length=50)
    timestamp: datetime
    app_name: str | None = Field(default=None, max_length=255)
    duration_seconds: int | None = Field(default=None, ge=0)
    metadata_json: dict | None = None


class SessionEventResponse(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    event_type: str
    timestamp: datetime
    app_name: str | None
    duration_seconds: int | None
    metadata_json: dict | None
    created_at: datetime

    model_config = {"from_attributes": True}


class SessionEventBatch(BaseModel):
    events: list[SessionEventCreate] = Field(min_length=1, max_length=500)
