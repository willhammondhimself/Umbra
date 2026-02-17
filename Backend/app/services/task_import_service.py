import logging

import httpx

logger = logging.getLogger(__name__)


class TodoistImporter:
    """Import tasks from Todoist REST API v2."""

    TODOIST_API_BASE = "https://api.todoist.com/rest/v2"

    async def import_tasks(
        self,
        access_token: str,
        project_id: str | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> list[dict]:
        """Fetch tasks from Todoist and return normalized task dicts.

        Args:
            access_token: Todoist API token.
            project_id: Optional Todoist project ID to filter tasks.
            http_client: Optional httpx client for testing.

        Returns:
            List of normalized task dicts with title, priority, due_date.
        """
        should_close = False
        if http_client is None:
            http_client = httpx.AsyncClient(timeout=15.0)
            should_close = True

        headers = {"Authorization": f"Bearer {access_token}"}
        params = {}
        if project_id:
            params["project_id"] = project_id

        try:
            response = await http_client.get(
                f"{self.TODOIST_API_BASE}/tasks",
                headers=headers,
                params=params,
            )
            if response.status_code >= 400:
                logger.error("Todoist API returned %d", response.status_code)
                return []
            todoist_tasks = response.json()

            return [self._normalize_task(t) for t in todoist_tasks]
        except httpx.HTTPError as exc:
            logger.error("Todoist API request failed: %s", exc)
            return []
        finally:
            if should_close:
                await http_client.aclose()

    @staticmethod
    def _normalize_task(task: dict) -> dict:
        """Convert a Todoist task to normalized format."""
        # Todoist priority: 1 (lowest) to 4 (highest)
        # Tether priority: 0 (low) to 3 (urgent)
        todoist_priority = task.get("priority", 1)
        tether_priority = max(0, min(3, todoist_priority - 1))

        due_date = None
        due = task.get("due")
        if due and isinstance(due, dict):
            due_date = due.get("date")

        return {
            "title": task.get("content", "Untitled"),
            "priority": tether_priority,
            "due_date": due_date,
        }


class NotionImporter:
    """Import tasks from a Notion database."""

    NOTION_API_BASE = "https://api.notion.com/v1"
    NOTION_VERSION = "2022-06-28"

    async def import_tasks(
        self,
        access_token: str,
        database_id: str,
        http_client: httpx.AsyncClient | None = None,
    ) -> list[dict]:
        """Query a Notion database and return normalized task dicts.

        Args:
            access_token: Notion API integration token.
            database_id: The Notion database ID to query.
            http_client: Optional httpx client for testing.

        Returns:
            List of normalized task dicts with title, priority, due_date.
        """
        should_close = False
        if http_client is None:
            http_client = httpx.AsyncClient(timeout=15.0)
            should_close = True

        headers = {
            "Authorization": f"Bearer {access_token}",
            "Notion-Version": self.NOTION_VERSION,
            "Content-Type": "application/json",
        }

        try:
            response = await http_client.post(
                f"{self.NOTION_API_BASE}/databases/{database_id}/query",
                headers=headers,
                json={},
            )
            if response.status_code >= 400:
                logger.error("Notion API returned %d", response.status_code)
                return []
            data = response.json()

            results = data.get("results", [])
            return [self._normalize_page(page) for page in results]
        except httpx.HTTPError as exc:
            logger.error("Notion API request failed: %s", exc)
            return []
        finally:
            if should_close:
                await http_client.aclose()

    @staticmethod
    def _normalize_page(page: dict) -> dict:
        """Convert a Notion database page to normalized task format."""
        properties = page.get("properties", {})

        # Extract title from the first title property
        title = "Untitled"
        for prop in properties.values():
            if prop.get("type") == "title":
                title_parts = prop.get("title", [])
                if title_parts:
                    title = "".join(
                        part.get("plain_text", "") for part in title_parts
                    )
                break

        # Extract priority (select property named "Priority")
        priority = 1
        priority_prop = properties.get("Priority", {})
        if priority_prop.get("type") == "select" and priority_prop.get("select"):
            priority_name = priority_prop["select"].get("name", "").lower()
            priority_map = {"low": 0, "medium": 1, "high": 2, "urgent": 3}
            priority = priority_map.get(priority_name, 1)

        # Extract due date (date property named "Due" or "Due Date")
        due_date = None
        for name in ("Due", "Due Date", "due", "due_date"):
            date_prop = properties.get(name, {})
            if date_prop.get("type") == "date" and date_prop.get("date"):
                due_date = date_prop["date"].get("start")
                break

        return {
            "title": title,
            "priority": priority,
            "due_date": due_date,
        }
