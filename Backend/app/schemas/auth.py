import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    provider: str  # "apple" or "google"
    identity_token: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str | None
    avatar_url: str | None
    settings_json: dict | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class SettingsUpdateRequest(BaseModel):
    settings_json: dict
