import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class FriendResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    display_name: str | None
    email: str
    status: str
    since: datetime

    model_config = {"from_attributes": True}


class InviteRequest(BaseModel):
    email: str = Field(max_length=255)


class GroupCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class GroupResponse(BaseModel):
    id: uuid.UUID
    name: str
    created_by: uuid.UUID
    created_at: datetime
    member_count: int = 0

    model_config = {"from_attributes": True}


class LeaderboardEntry(BaseModel):
    user_id: uuid.UUID
    display_name: str | None
    focused_seconds: int
    session_count: int
    rank: int


class EncourageRequest(BaseModel):
    to_user_id: uuid.UUID
    message: str = Field(max_length=500)


class PingRequest(BaseModel):
    to_user_id: uuid.UUID


class InviteLinkResponse(BaseModel):
    invite_code: str
    invite_url: str


class ReactionRequest(BaseModel):
    reaction_type: str = Field(pattern=r"^(thumbs_up|fire)$")


class ReactionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    display_name: str | None
    reaction_type: str
    created_at: datetime

    model_config = {"from_attributes": True}


class ActivityReaction(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    display_name: str | None
    reaction_type: str

    model_config = {"from_attributes": True}


class ActivityItem(BaseModel):
    id: uuid.UUID  # session id
    user_id: uuid.UUID
    display_name: str | None
    start_time: datetime
    duration_seconds: int
    focused_seconds: int
    reactions: list[ActivityReaction] = []

    model_config = {"from_attributes": True}
