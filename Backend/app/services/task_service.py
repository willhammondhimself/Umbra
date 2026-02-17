import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.task import Task


async def get_tasks(
    db: AsyncSession,
    user_id: uuid.UUID,
    project_id: uuid.UUID | None = None,
    status: int | None = None,
) -> list[Task]:
    query = select(Task).where(Task.user_id == user_id)
    if project_id is not None:
        query = query.where(Task.project_id == project_id)
    if status is not None:
        query = query.where(Task.status == status)
    query = query.order_by(Task.status.asc(), Task.priority.desc(), Task.sort_order.asc())
    result = await db.execute(query)
    return list(result.scalars().all())


async def create_task(db: AsyncSession, user_id: uuid.UUID, data: dict) -> Task:
    task = Task(user_id=user_id, **data)
    db.add(task)
    await db.flush()
    await db.refresh(task)
    return task


async def update_task(
    db: AsyncSession, user_id: uuid.UUID, task_id: uuid.UUID, data: dict
) -> Task | None:
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == user_id)
    )
    task = result.scalar_one_or_none()
    if task is None:
        return None

    for key, value in data.items():
        if value is not None:
            setattr(task, key, value)
    task.updated_at = datetime.now(timezone.utc)

    await db.flush()
    await db.refresh(task)
    return task
