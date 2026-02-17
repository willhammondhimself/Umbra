import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.device import Device
from app.models.user import User
from app.schemas.device import DeviceRegister, DeviceResponse

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post("/register", response_model=DeviceResponse, status_code=201)
async def register_device(
    data: DeviceRegister,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Register a device for push notifications. Upserts by token."""
    result = await db.execute(
        select(Device).where(Device.token == data.token)
    )
    existing = result.scalar_one_or_none()

    if existing:
        existing.user_id = user.id
        existing.platform = data.platform
        await db.flush()
        await db.refresh(existing)
        return existing

    device = Device(
        user_id=user.id,
        token=data.token,
        platform=data.platform,
    )
    db.add(device)
    await db.flush()
    await db.refresh(device)
    return device


@router.delete("/{device_id}", status_code=204)
async def unregister_device(
    device_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove a device registration."""
    result = await db.execute(
        select(Device).where(Device.id == device_id, Device.user_id == user.id)
    )
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Device not found"
        )
    await db.delete(device)
