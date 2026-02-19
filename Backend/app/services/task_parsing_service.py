"""Task Parsing Service — LLM-powered natural language task extraction.

Accepts raw text input and returns structured task data using the same
LLM provider abstraction from ai_coaching_service. Falls back gracefully
when no provider is configured.
"""

import json
import logging

from app.config import settings
from app.services.ai_coaching_service import create_provider

logger = logging.getLogger(__name__)

TASK_EXTRACTION_SYSTEM_PROMPT = """You are a task extraction engine. Given natural language input, extract individual tasks.

Return a JSON array of objects with these fields:
- title: string (clean, actionable task title)
- estimate_minutes: integer or null (time estimate in minutes)
- priority: "urgent" | "high" | "medium" | "low" (default "medium")
- project_name: string or null (if a project is mentioned)
- due_date: string or null (ISO 8601 date if mentioned)

Examples:
Input: "Write the thesis introduction for about 2 hours, then review slides for the meeting"
Output: [{"title": "Write thesis introduction", "estimate_minutes": 120, "priority": "medium", "project_name": "Thesis", "due_date": null}, {"title": "Review slides for meeting", "estimate_minutes": null, "priority": "medium", "project_name": null, "due_date": null}]

Input: "Urgent: fix the login bug by Friday, and maybe update the README sometime"
Output: [{"title": "Fix login bug", "estimate_minutes": null, "priority": "urgent", "project_name": null, "due_date": "2026-02-20"}, {"title": "Update README", "estimate_minutes": null, "priority": "low", "project_name": null, "due_date": null}]

Return ONLY the JSON array, no other text."""


async def parse_tasks_with_llm(text: str) -> dict:
    """Parse natural language into structured tasks using LLM.

    Returns dict with:
        - tasks: list of parsed task dicts
        - used_llm: bool indicating if LLM was used (vs fallback needed)
    """
    provider = create_provider(settings)

    if provider is None:
        return {"tasks": [], "used_llm": False}

    try:
        response = await provider.generate(TASK_EXTRACTION_SYSTEM_PROMPT, text)
        tasks = _parse_tasks_json(response)
        return {"tasks": tasks, "used_llm": True}
    except Exception as e:
        logger.warning("LLM task parsing failed, client should use local fallback: %s", e)
        return {"tasks": [], "used_llm": False}


def _parse_tasks_json(raw: str) -> list[dict]:
    """Extract a JSON array of tasks from LLM response text."""
    stripped = raw.strip()

    # Try direct parse first
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, list):
            return _validate_tasks(parsed)
        if isinstance(parsed, dict):
            return _validate_tasks([parsed])
    except json.JSONDecodeError:
        pass

    # Try extracting JSON array from surrounding text / markdown code blocks
    start = stripped.find("[")
    end = stripped.rfind("]")
    if start != -1 and end != -1 and end > start:
        try:
            parsed = json.loads(stripped[start : end + 1])
            if isinstance(parsed, list):
                return _validate_tasks(parsed)
        except json.JSONDecodeError:
            pass

    return []


def _validate_tasks(tasks: list) -> list[dict]:
    """Validate and normalize parsed task dicts."""
    validated = []
    valid_priorities = {"urgent", "high", "medium", "low"}

    for t in tasks:
        if not isinstance(t, dict):
            continue
        title = t.get("title")
        if not title or not isinstance(title, str):
            continue

        priority = str(t.get("priority", "medium")).lower()
        if priority not in valid_priorities:
            priority = "medium"

        estimate = t.get("estimate_minutes")
        if estimate is not None:
            try:
                estimate = int(estimate)
                if estimate <= 0:
                    estimate = None
            except (ValueError, TypeError):
                estimate = None

        validated.append({
            "title": str(title).strip(),
            "estimate_minutes": estimate,
            "priority": priority,
            "project_name": t.get("project_name"),
            "due_date": t.get("due_date"),
        })

    return validated
