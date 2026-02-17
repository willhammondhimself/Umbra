import asyncio
import hashlib
import hmac
import json
import logging
import uuid

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.webhook import Webhook

logger = logging.getLogger(__name__)

VALID_EVENTS = {"session.start", "session.end", "task.complete"}


async def deliver_webhook(
    webhook: Webhook,
    event_type: str,
    payload: dict,
    http_client: httpx.AsyncClient | None = None,
) -> bool:
    """Deliver a webhook payload with HMAC-SHA256 signature.

    Signs the payload body with the webhook's secret key and POSTs
    to the webhook URL. Retries up to 3 times with exponential backoff.

    Returns True if delivery succeeded, False otherwise.
    """
    body = json.dumps(payload, default=str, sort_keys=True)
    signature = hmac.new(
        webhook.secret.encode("utf-8"),
        body.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    headers = {
        "Content-Type": "application/json",
        "X-Tether-Event": event_type,
        "X-Tether-Signature": f"sha256={signature}",
    }

    should_close = False
    if http_client is None:
        http_client = httpx.AsyncClient(timeout=10.0)
        should_close = True

    delays = [1.0, 2.0, 4.0]
    try:
        for attempt, delay in enumerate(delays):
            try:
                response = await http_client.post(
                    webhook.url, content=body, headers=headers
                )
                if response.status_code < 400:
                    return True
                logger.warning(
                    "Webhook delivery attempt %d to %s returned %d",
                    attempt + 1,
                    webhook.url,
                    response.status_code,
                )
            except httpx.HTTPError as exc:
                logger.warning(
                    "Webhook delivery attempt %d to %s failed: %s",
                    attempt + 1,
                    webhook.url,
                    exc,
                )

            if attempt < len(delays) - 1:
                await asyncio.sleep(delay)

        return False
    finally:
        if should_close:
            await http_client.aclose()


async def fire_webhooks(
    db: AsyncSession,
    user_id: uuid.UUID,
    event_type: str,
    payload: dict,
    http_client: httpx.AsyncClient | None = None,
) -> int:
    """Fire all active webhooks for a user that match the given event type.

    Returns the number of successfully delivered webhooks.
    """
    result = await db.execute(
        select(Webhook).where(
            Webhook.user_id == user_id,
            Webhook.is_active.is_(True),
        )
    )
    webhooks = list(result.scalars().all())

    delivered = 0
    for webhook in webhooks:
        if event_type in webhook.events:
            success = await deliver_webhook(
                webhook, event_type, payload, http_client=http_client
            )
            if success:
                delivered += 1

    return delivered
