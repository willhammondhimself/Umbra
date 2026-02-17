import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.integration import Integration
from app.models.user import User
from app.schemas.integration import (
    IntegrationCreate,
    IntegrationResponse,
    TaskImportRequest,
    TaskImportResponse,
    TaskImportResult,
)
from app.services.task_import_service import NotionImporter, TodoistImporter

router = APIRouter(prefix="/integrations", tags=["integrations"])


@router.post("", response_model=IntegrationResponse, status_code=201)
async def create_integration(
    data: IntegrationCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create or update a third-party integration."""
    valid_providers = {"slack", "todoist", "notion"}
    if data.provider not in valid_providers:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid provider. Must be one of: {', '.join(sorted(valid_providers))}",
        )

    # Check for existing integration with same provider
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.provider == data.provider,
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        # Update existing integration
        existing.access_token = data.access_token
        existing.settings_json = data.settings_json
        existing.is_active = True
        await db.flush()
        await db.refresh(existing)
        return existing

    integration = Integration(
        user_id=user.id,
        provider=data.provider,
        access_token=data.access_token,
        settings_json=data.settings_json,
        is_active=True,
    )
    db.add(integration)
    await db.flush()
    await db.refresh(integration)
    return integration


@router.get("", response_model=list[IntegrationResponse])
async def list_integrations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all active integrations for the authenticated user."""
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.is_active.is_(True),
        ).order_by(Integration.created_at.desc())
    )
    return list(result.scalars().all())


@router.delete("/{integration_id}", status_code=204)
async def delete_integration(
    integration_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove an integration (soft-delete by setting inactive)."""
    result = await db.execute(
        select(Integration).where(
            Integration.id == integration_id, Integration.user_id == user.id
        )
    )
    integration = result.scalar_one_or_none()
    if not integration:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Integration not found"
        )
    integration.is_active = False
    await db.flush()


@router.post("/todoist/import", response_model=TaskImportResponse)
async def import_todoist_tasks(
    data: TaskImportRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Import tasks from Todoist. Requires active Todoist integration."""
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.provider == "todoist",
            Integration.is_active.is_(True),
        )
    )
    integration = result.scalar_one_or_none()
    if not integration or not integration.access_token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active Todoist integration found. Connect Todoist first.",
        )

    importer = TodoistImporter()
    tasks = await importer.import_tasks(
        access_token=integration.access_token,
        project_id=data.project_id,
    )

    return TaskImportResponse(
        imported_count=len(tasks),
        tasks=[TaskImportResult(**t) for t in tasks],
    )


@router.post("/notion/import", response_model=TaskImportResponse)
async def import_notion_tasks(
    data: TaskImportRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Import tasks from a Notion database. Requires active Notion integration."""
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.provider == "notion",
            Integration.is_active.is_(True),
        )
    )
    integration = result.scalar_one_or_none()
    if not integration or not integration.access_token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active Notion integration found. Connect Notion first.",
        )

    if not data.project_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="project_id (Notion database ID) is required for Notion import.",
        )

    importer = NotionImporter()
    tasks = await importer.import_tasks(
        access_token=integration.access_token,
        database_id=data.project_id,
    )

    return TaskImportResponse(
        imported_count=len(tasks),
        tasks=[TaskImportResult(**t) for t in tasks],
    )
