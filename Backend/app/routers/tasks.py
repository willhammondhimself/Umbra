import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.task import TaskCreate, TaskResponse, TaskUpdate
from app.services import task_service

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskResponse])
async def list_tasks(
    project_id: uuid.UUID | None = Query(default=None),
    task_status: int | None = Query(default=None, alias="status", ge=0, le=2),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await task_service.get_tasks(
        db, user.id, project_id=project_id, status=task_status
    )


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(
    data: TaskCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await task_service.create_task(db, user.id, data.model_dump())


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: uuid.UUID,
    data: TaskUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    task = await task_service.update_task(
        db, user.id, task_id, data.model_dump(exclude_unset=True)
    )
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task
