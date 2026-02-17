import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class IntegrationCreate(BaseModel):
    provider: str = Field(
        min_length=1,
        max_length=50,
        description="Integration provider: slack, todoist, notion",
    )
    access_token: str | None = None
    settings_json: dict = Field(default_factory=dict)


class IntegrationResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    provider: str
    is_active: bool
    settings_json: dict
    created_at: datetime

    model_config = {"from_attributes": True}


class TaskImportRequest(BaseModel):
    project_id: str | None = Field(
        default=None,
        description="Provider-specific project/database ID to import from",
    )


class TaskImportResult(BaseModel):
    title: str
    priority: int = 1
    due_date: str | None = None


class TaskImportResponse(BaseModel):
    imported_count: int
    tasks: list[TaskImportResult]
