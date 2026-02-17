from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models.task import Task
from app.models.user import User

router = APIRouter(prefix="/blocklist", tags=["blocklist"])


@router.get("")
async def get_blocklist(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return active blocklist items for the authenticated user.

    The Chrome extension polls this endpoint to sync blocking rules.
    Returns items in the format expected by declarativeNetRequest rule generation.
    """
    # BlocklistItem is stored client-side in SQLite. For the Chrome extension,
    # we use the backend as a relay. Blocklist items are synced via the tasks
    # sync mechanism. For now, return the user's blocklist from a dedicated table
    # if it exists, or an empty list.
    #
    # Since the blocklist model doesn't exist on the backend yet, we return
    # an empty list. The full sync implementation will come in a future phase.
    # The Chrome extension handles this gracefully.
    return []
