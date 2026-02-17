import logging

import httpx

logger = logging.getLogger(__name__)

SLACK_API_BASE = "https://slack.com/api"


async def set_focus_status(
    access_token: str,
    is_active: bool,
    http_client: httpx.AsyncClient | None = None,
) -> bool:
    """Set or clear the Slack focus status and DND mode.

    When is_active is True:
        - Sets status emoji to target, text to "Focusing in Tether"
        - Enables DND (snooze) for 120 minutes

    When is_active is False:
        - Clears status emoji and text
        - Ends DND snooze

    Returns True if all Slack API calls succeeded.
    """
    should_close = False
    if http_client is None:
        http_client = httpx.AsyncClient(timeout=10.0)
        should_close = True

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    try:
        success = True

        if is_active:
            # Set focus status
            profile_resp = await http_client.post(
                f"{SLACK_API_BASE}/users.profile.set",
                headers=headers,
                json={
                    "profile": {
                        "status_text": "Focusing in Tether",
                        "status_emoji": ":dart:",
                        "status_expiration": 0,
                    }
                },
            )
            if not profile_resp.json().get("ok", False):
                logger.warning("Slack profile set failed: %s", profile_resp.text)
                success = False

            # Enable DND for 120 minutes
            dnd_resp = await http_client.post(
                f"{SLACK_API_BASE}/dnd.setSnooze",
                headers=headers,
                json={"num_minutes": 120},
            )
            if not dnd_resp.json().get("ok", False):
                logger.warning("Slack DND set failed: %s", dnd_resp.text)
                success = False
        else:
            # Clear status
            profile_resp = await http_client.post(
                f"{SLACK_API_BASE}/users.profile.set",
                headers=headers,
                json={
                    "profile": {
                        "status_text": "",
                        "status_emoji": "",
                        "status_expiration": 0,
                    }
                },
            )
            if not profile_resp.json().get("ok", False):
                logger.warning("Slack profile clear failed: %s", profile_resp.text)
                success = False

            # End DND
            dnd_resp = await http_client.post(
                f"{SLACK_API_BASE}/dnd.endSnooze",
                headers=headers,
            )
            if not dnd_resp.json().get("ok", False):
                # dnd.endSnooze returns not_snoozing if already off — treat as success
                error = dnd_resp.json().get("error", "")
                if error != "snooze_not_active":
                    logger.warning("Slack DND end failed: %s", dnd_resp.text)
                    success = False

        return success
    except httpx.HTTPError as exc:
        logger.error("Slack API request failed: %s", exc)
        return False
    finally:
        if should_close:
            await http_client.aclose()
