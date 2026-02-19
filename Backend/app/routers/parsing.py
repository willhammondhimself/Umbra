from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.dependencies import get_current_user
from app.models.user import User
from app.services.task_parsing_service import parse_tasks_with_llm

router = APIRouter(tags=["parsing"])


class ParseRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


class ParsedTaskResponse(BaseModel):
    title: str
    estimate_minutes: int | None = None
    priority: str = "medium"
    project_name: str | None = None
    due_date: str | None = None


class ParseResponse(BaseModel):
    tasks: list[ParsedTaskResponse]
    used_llm: bool


@router.post("/tasks/parse", response_model=ParseResponse)
async def parse_tasks(
    data: ParseRequest,
    user: User = Depends(get_current_user),
):
    """Parse natural language text into structured tasks using LLM."""
    result = await parse_tasks_with_llm(data.text)
    return result
