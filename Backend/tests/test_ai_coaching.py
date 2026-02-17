"""Tests for AI Coaching Service — provider-agnostic LLM integration.

All tests use mocked LLM providers and the in-memory FakeRedis from conftest.
No real API calls are made.
"""

import json
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.session import Session
from app.models.session_event import SessionEvent
from app.models.task import Task
from app.services.ai_coaching_service import (
    AnthropicProvider,
    LLMProvider,
    OpenAIProvider,
    _check_rate_limit,
    _fallback_goals,
    _fallback_nudge,
    _fallback_session_summary,
    _parse_goals_json,
    create_provider,
    generate_coaching_nudge,
    generate_goal_suggestions,
    generate_session_summary,
)
from tests.conftest import FakeRedis

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


class MockLLMProvider(LLMProvider):
    """Mock provider that returns a preset response."""

    def __init__(self, response: str = "Great session!"):
        self.response = response
        self.calls: list[tuple[str, str]] = []

    async def generate(self, system_prompt: str, user_prompt: str) -> str:
        self.calls.append((system_prompt, user_prompt))
        return self.response


class FailingProvider(LLMProvider):
    """Provider that always raises an exception."""

    async def generate(self, system_prompt: str, user_prompt: str) -> str:
        raise RuntimeError("LLM API error")


async def _create_session(
    db: AsyncSession,
    user_id: uuid.UUID,
    days_ago: int = 0,
    hour: int = 10,
    duration_seconds: int = 1500,
    focused_seconds: int = 1200,
    distraction_count: int = 1,
    is_complete: bool = True,
) -> Session:
    """Create a session directly in the database."""
    start = datetime.now(UTC) - timedelta(days=days_ago)
    start = start.replace(hour=hour, minute=0, second=0, microsecond=0)
    end = start + timedelta(seconds=duration_seconds)

    session = Session(
        id=uuid.uuid4(),
        user_id=user_id,
        start_time=start,
        end_time=end,
        duration_seconds=duration_seconds,
        focused_seconds=focused_seconds,
        distraction_count=distraction_count,
        is_complete=is_complete,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session


async def _add_distraction(
    db: AsyncSession,
    session_id: uuid.UUID,
    app_name: str,
    duration_seconds: int = 30,
) -> None:
    """Add a DISTRACTION event to a session."""
    event = SessionEvent(
        id=uuid.uuid4(),
        session_id=session_id,
        event_type="DISTRACTION",
        timestamp=datetime.now(UTC),
        app_name=app_name,
        duration_seconds=duration_seconds,
    )
    db.add(event)
    await db.commit()


# ---------------------------------------------------------------------------
# Provider Factory Tests
# ---------------------------------------------------------------------------


class TestCreateProvider:
    def test_openai_provider(self):
        class FakeSettings:
            AI_PROVIDER = "openai"
            OPENAI_API_KEY = "sk-test-key"
            ANTHROPIC_API_KEY = ""
            AI_MODEL = ""

        provider = create_provider(FakeSettings())
        assert isinstance(provider, OpenAIProvider)
        assert provider.model == "gpt-4o-mini"

    def test_openai_custom_model(self):
        class FakeSettings:
            AI_PROVIDER = "openai"
            OPENAI_API_KEY = "sk-test-key"
            ANTHROPIC_API_KEY = ""
            AI_MODEL = "gpt-4o"

        provider = create_provider(FakeSettings())
        assert isinstance(provider, OpenAIProvider)
        assert provider.model == "gpt-4o"

    def test_anthropic_provider(self):
        class FakeSettings:
            AI_PROVIDER = "anthropic"
            OPENAI_API_KEY = ""
            ANTHROPIC_API_KEY = "sk-ant-test"
            AI_MODEL = ""

        provider = create_provider(FakeSettings())
        assert isinstance(provider, AnthropicProvider)
        assert provider.model == "claude-sonnet-4-6"

    def test_no_provider_configured(self):
        class FakeSettings:
            AI_PROVIDER = ""
            OPENAI_API_KEY = ""
            ANTHROPIC_API_KEY = ""
            AI_MODEL = ""

        provider = create_provider(FakeSettings())
        assert provider is None

    def test_provider_without_key(self):
        class FakeSettings:
            AI_PROVIDER = "openai"
            OPENAI_API_KEY = ""
            ANTHROPIC_API_KEY = ""
            AI_MODEL = ""

        provider = create_provider(FakeSettings())
        assert provider is None


# ---------------------------------------------------------------------------
# Rate Limiting Tests
# ---------------------------------------------------------------------------


class TestRateLimiting:
    @pytest.mark.asyncio
    async def test_rate_limit_allows_within_limit(self):
        redis = FakeRedis()
        user_id = uuid.uuid4()

        for i in range(20):
            result = await _check_rate_limit(redis, user_id, limit=20)
            assert result is True, f"Call {i+1} should be allowed"

    @pytest.mark.asyncio
    async def test_rate_limit_blocks_over_limit(self):
        redis = FakeRedis()
        user_id = uuid.uuid4()

        # Use up all 20 calls
        for _ in range(20):
            await _check_rate_limit(redis, user_id, limit=20)

        # 21st call should be blocked
        result = await _check_rate_limit(redis, user_id, limit=20)
        assert result is False

    @pytest.mark.asyncio
    async def test_rate_limit_per_user(self):
        redis = FakeRedis()
        user_a = uuid.uuid4()
        user_b = uuid.uuid4()

        # Exhaust user A's limit
        for _ in range(20):
            await _check_rate_limit(redis, user_a, limit=20)

        # User B should still be allowed
        result = await _check_rate_limit(redis, user_b, limit=20)
        assert result is True

    @pytest.mark.asyncio
    async def test_rate_limit_sets_ttl(self):
        redis = FakeRedis()
        user_id = uuid.uuid4()
        await _check_rate_limit(redis, user_id)

        # Verify TTL was set on the key
        from datetime import date as date_type

        key = f"ai_rate:{user_id}:{date_type.today().isoformat()}"
        assert key in redis._ttls
        assert redis._ttls[key] == 86400


# ---------------------------------------------------------------------------
# Session Summary Tests
# ---------------------------------------------------------------------------


class TestSessionSummary:
    @pytest.mark.asyncio
    async def test_summary_with_provider(self, db_session, test_user):
        session = await _create_session(
            db_session,
            test_user.id,
            duration_seconds=1500,
            focused_seconds=1350,
            distraction_count=2,
        )
        provider = MockLLMProvider("You nailed your 25-minute session with 90% focus!")
        redis = FakeRedis()

        result = await generate_session_summary(
            db_session, test_user.id, session.id, provider, redis
        )

        assert result["is_ai_generated"] is True
        assert "nailed" in result["summary"]
        assert len(provider.calls) == 1

        # Verify prompt includes session data
        _, user_prompt = provider.calls[0]
        assert "25.0 minutes" in user_prompt
        assert "22.5 minutes" in user_prompt
        assert "2" in user_prompt

    @pytest.mark.asyncio
    async def test_summary_cached_in_redis(self, db_session, test_user):
        session = await _create_session(db_session, test_user.id)
        provider = MockLLMProvider("Cached response")
        redis = FakeRedis()

        await generate_session_summary(
            db_session, test_user.id, session.id, provider, redis
        )

        # Check cache was set
        cache_key = f"ai_summary:{session.id}"
        cached = await redis.get(cache_key)
        assert cached == "Cached response"

    @pytest.mark.asyncio
    async def test_summary_fallback_no_provider(self, db_session, test_user):
        session = await _create_session(
            db_session,
            test_user.id,
            duration_seconds=1500,
            focused_seconds=1400,
            distraction_count=0,
        )

        result = await generate_session_summary(
            db_session, test_user.id, session.id, None
        )

        assert result["is_ai_generated"] is False
        assert "excellent" in result["summary"]
        assert "Zero distractions" in result["summary"]

    @pytest.mark.asyncio
    async def test_summary_fallback_on_provider_error(self, db_session, test_user):
        session = await _create_session(db_session, test_user.id)
        provider = FailingProvider()

        result = await generate_session_summary(
            db_session, test_user.id, session.id, provider
        )

        assert result["is_ai_generated"] is False
        assert len(result["summary"]) > 0

    @pytest.mark.asyncio
    async def test_summary_session_not_found(self, db_session, test_user):
        fake_session_id = uuid.uuid4()

        result = await generate_session_summary(
            db_session, test_user.id, fake_session_id, None
        )

        assert result["is_ai_generated"] is False
        assert "not found" in result["summary"]

    @pytest.mark.asyncio
    async def test_summary_rate_limited(self, db_session, test_user):
        session = await _create_session(db_session, test_user.id)
        provider = MockLLMProvider("Should not see this")
        redis = FakeRedis()

        # Exhaust rate limit
        for _ in range(20):
            await _check_rate_limit(redis, test_user.id, limit=20)

        result = await generate_session_summary(
            db_session, test_user.id, session.id, provider, redis
        )

        # Should use fallback, not LLM
        assert result["is_ai_generated"] is False
        assert len(provider.calls) == 0


# ---------------------------------------------------------------------------
# Coaching Nudge Tests
# ---------------------------------------------------------------------------


class TestCoachingNudge:
    @pytest.mark.asyncio
    async def test_nudge_with_provider(self, db_session, test_user):
        await _create_session(db_session, test_user.id, days_ago=0)
        await _create_session(db_session, test_user.id, days_ago=1)

        provider = MockLLMProvider("Try a 25-minute session at 10am today!")
        redis = FakeRedis()

        result = await generate_coaching_nudge(
            db_session, test_user.id, provider, redis
        )

        assert result["is_ai_generated"] is True
        assert "25-minute" in result["nudge"]
        assert len(provider.calls) == 1

    @pytest.mark.asyncio
    async def test_nudge_cached_for_1_hour(self, db_session, test_user):
        provider = MockLLMProvider("First nudge")
        redis = FakeRedis()

        # First call — generates and caches
        result1 = await generate_coaching_nudge(
            db_session, test_user.id, provider, redis
        )
        assert result1["is_ai_generated"] is True
        assert len(provider.calls) == 1

        # Second call — should return cached value
        result2 = await generate_coaching_nudge(
            db_session, test_user.id, provider, redis
        )
        assert result2["nudge"] == "First nudge"
        assert result2["is_ai_generated"] is True
        # Provider should NOT be called again
        assert len(provider.calls) == 1

        # Verify TTL is 1 hour
        cache_key = f"ai_nudge:{test_user.id}"
        assert redis._ttls.get(cache_key) == 3600

    @pytest.mark.asyncio
    async def test_nudge_fallback_no_provider(self, db_session, test_user):
        await _create_session(db_session, test_user.id, days_ago=0)

        result = await generate_coaching_nudge(
            db_session, test_user.id, None
        )

        assert result["is_ai_generated"] is False
        assert len(result["nudge"]) > 0

    @pytest.mark.asyncio
    async def test_nudge_fallback_no_sessions(self, db_session, test_user):
        result = await generate_coaching_nudge(
            db_session, test_user.id, None
        )

        assert result["is_ai_generated"] is False
        # Should suggest scheduling a session
        assert "session" in result["nudge"].lower()

    @pytest.mark.asyncio
    async def test_nudge_rate_limited(self, db_session, test_user):
        provider = MockLLMProvider("Should not see this")
        redis = FakeRedis()

        for _ in range(20):
            await _check_rate_limit(redis, test_user.id, limit=20)

        result = await generate_coaching_nudge(
            db_session, test_user.id, provider, redis
        )

        assert result["is_ai_generated"] is False
        assert len(provider.calls) == 0


# ---------------------------------------------------------------------------
# Goal Suggestions Tests
# ---------------------------------------------------------------------------


class TestGoalSuggestions:
    MOCK_GOALS_JSON = json.dumps([
        {"goal": "Focus 60 min daily", "target": "60 min/day", "reasoning": "10% increase"},
        {"goal": "Complete 3 sessions", "target": "3 sessions/day", "reasoning": "Build habit"},
        {"goal": "Reduce distractions", "target": "< 5/day", "reasoning": "Improving trend"},
    ])

    @pytest.mark.asyncio
    async def test_goals_with_provider(self, db_session, test_user):
        await _create_session(db_session, test_user.id, days_ago=0)
        await _create_session(db_session, test_user.id, days_ago=1)

        provider = MockLLMProvider(self.MOCK_GOALS_JSON)
        redis = FakeRedis()

        result = await generate_goal_suggestions(
            db_session, test_user.id, provider, redis
        )

        assert result["is_ai_generated"] is True
        assert len(result["goals"]) == 3
        assert result["goals"][0]["goal"] == "Focus 60 min daily"
        assert result["goals"][0]["target"] == "60 min/day"

    @pytest.mark.asyncio
    async def test_goals_cached_for_24_hours(self, db_session, test_user):
        provider = MockLLMProvider(self.MOCK_GOALS_JSON)
        redis = FakeRedis()

        # First call
        result1 = await generate_goal_suggestions(
            db_session, test_user.id, provider, redis
        )
        assert result1["is_ai_generated"] is True
        assert len(provider.calls) == 1

        # Second call — should use cache
        result2 = await generate_goal_suggestions(
            db_session, test_user.id, provider, redis
        )
        assert result2["is_ai_generated"] is True
        assert len(result2["goals"]) == 3
        # Provider should NOT be called again
        assert len(provider.calls) == 1

        # Verify TTL is 24 hours
        cache_key = f"ai_goals:{test_user.id}"
        assert redis._ttls.get(cache_key) == 86400

    @pytest.mark.asyncio
    async def test_goals_fallback_no_provider(self, db_session, test_user):
        await _create_session(db_session, test_user.id, days_ago=0)

        result = await generate_goal_suggestions(
            db_session, test_user.id, None
        )

        assert result["is_ai_generated"] is False
        assert len(result["goals"]) == 3
        # Fallback goals have required structure
        for goal in result["goals"]:
            assert "goal" in goal
            assert "target" in goal
            assert "reasoning" in goal

    @pytest.mark.asyncio
    async def test_goals_handles_markdown_json(self, db_session, test_user):
        """LLM sometimes wraps JSON in markdown code blocks."""
        markdown_response = (
            "Here are your goals:\n```json\n"
            + self.MOCK_GOALS_JSON
            + "\n```\nGood luck!"
        )
        provider = MockLLMProvider(markdown_response)
        redis = FakeRedis()

        result = await generate_goal_suggestions(
            db_session, test_user.id, provider, redis
        )

        assert result["is_ai_generated"] is True
        assert len(result["goals"]) == 3

    @pytest.mark.asyncio
    async def test_goals_fallback_on_invalid_json(self, db_session, test_user):
        provider = MockLLMProvider("This is not valid JSON at all.")

        result = await generate_goal_suggestions(
            db_session, test_user.id, provider
        )

        # Should fall back to rule-based goals
        assert result["is_ai_generated"] is False
        assert len(result["goals"]) == 3

    @pytest.mark.asyncio
    async def test_goals_rate_limited(self, db_session, test_user):
        provider = MockLLMProvider(self.MOCK_GOALS_JSON)
        redis = FakeRedis()

        for _ in range(20):
            await _check_rate_limit(redis, test_user.id, limit=20)

        result = await generate_goal_suggestions(
            db_session, test_user.id, provider, redis
        )

        assert result["is_ai_generated"] is False
        assert len(provider.calls) == 0


# ---------------------------------------------------------------------------
# Fallback Function Tests
# ---------------------------------------------------------------------------


class TestFallbackFunctions:
    def test_fallback_session_summary_excellent(self):
        summary = _fallback_session_summary(25.0, 24.0, 0, 2)
        assert "excellent" in summary
        assert "Zero distractions" in summary
        assert "2 tasks" in summary

    def test_fallback_session_summary_solid(self):
        summary = _fallback_session_summary(25.0, 20.0, 1, 0)
        assert "solid" in summary
        assert "1 distraction" in summary

    def test_fallback_session_summary_challenging(self):
        summary = _fallback_session_summary(25.0, 10.0, 5, 0)
        assert "challenging" in summary
        assert "closing unnecessary" in summary

    def test_fallback_nudge_low_focus(self):
        nudge = _fallback_nudge(20.0, 10, "Slack")
        assert "25-minute" in nudge
        assert "10:00" in nudge

    def test_fallback_nudge_with_distractor(self):
        nudge = _fallback_nudge(45.0, 14, "Twitter")
        assert "Twitter" in nudge
        assert "14:00" in nudge

    def test_fallback_nudge_no_distractor(self):
        nudge = _fallback_nudge(45.0, 14, "none")
        assert "45" in nudge
        assert "10%" in nudge

    def test_fallback_goals_structure(self):
        goals = _fallback_goals(30.0, 2.0, 0.8)
        assert len(goals) == 3
        for g in goals:
            assert "goal" in g
            assert "target" in g
            assert "reasoning" in g

    def test_fallback_goals_improvement_target(self):
        goals = _fallback_goals(50.0, 3.0, 0.75)
        # First goal should target 10% increase
        assert "55" in goals[0]["goal"]  # 50 * 1.1 = 55


# ---------------------------------------------------------------------------
# JSON Parsing Tests
# ---------------------------------------------------------------------------


class TestParseGoalsJson:
    def test_parse_valid_json(self):
        raw = '[{"goal": "A", "target": "B", "reasoning": "C"}]'
        result = _parse_goals_json(raw)
        assert len(result) == 1
        assert result[0]["goal"] == "A"

    def test_parse_json_in_markdown(self):
        raw = '```json\n[{"goal": "A", "target": "B", "reasoning": "C"}]\n```'
        result = _parse_goals_json(raw)
        assert len(result) == 1

    def test_parse_json_with_surrounding_text(self):
        raw = 'Here are goals: [{"goal": "A", "target": "B", "reasoning": "C"}] enjoy!'
        result = _parse_goals_json(raw)
        assert len(result) == 1

    def test_parse_invalid_json_returns_none(self):
        result = _parse_goals_json("not json at all")
        assert result is None

    def test_parse_missing_keys_returns_none(self):
        raw = '[{"goal": "A", "target": "B"}]'  # missing "reasoning"
        result = _parse_goals_json(raw)
        assert result is None

    def test_parse_mixed_valid_invalid(self):
        raw = json.dumps([
            {"goal": "A", "target": "B", "reasoning": "C"},
            {"goal": "D"},  # invalid
        ])
        result = _parse_goals_json(raw)
        # Only one valid goal, but _validate_goals requires all to be valid
        # to return; here only 1 is valid so it returns that 1
        assert result is not None
        assert len(result) == 1


# ---------------------------------------------------------------------------
# API Endpoint Tests (via HTTP client)
# ---------------------------------------------------------------------------


class TestAPIEndpoints:
    @pytest.mark.asyncio
    async def test_session_summary_endpoint(self, client, db_session, test_user):
        """POST /insights/session-summary returns fallback when no AI configured."""
        session = await _create_session(
            db_session,
            test_user.id,
            duration_seconds=1500,
            focused_seconds=1200,
            distraction_count=2,
        )

        resp = await client.post(
            "/insights/session-summary",
            params={"session_id": str(session.id)},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "summary" in data
        assert data["is_ai_generated"] is False
        assert len(data["summary"]) > 0

    @pytest.mark.asyncio
    async def test_nudge_endpoint(self, client, db_session, test_user):
        """GET /insights/nudge returns a nudge."""
        await _create_session(db_session, test_user.id, days_ago=0)

        resp = await client.get("/insights/nudge")
        assert resp.status_code == 200
        data = resp.json()
        assert "nudge" in data
        assert isinstance(data["is_ai_generated"], bool)
        assert len(data["nudge"]) > 0

    @pytest.mark.asyncio
    async def test_ai_goals_endpoint(self, client, db_session, test_user):
        """GET /insights/goals/ai returns goal suggestions."""
        await _create_session(db_session, test_user.id, days_ago=0)
        await _create_session(db_session, test_user.id, days_ago=1)

        resp = await client.get("/insights/goals/ai")
        assert resp.status_code == 200
        data = resp.json()
        assert "goals" in data
        assert isinstance(data["goals"], list)
        assert len(data["goals"]) == 3
        for goal in data["goals"]:
            assert "goal" in goal
            assert "target" in goal
            assert "reasoning" in goal

    @pytest.mark.asyncio
    async def test_session_summary_invalid_session(self, client):
        """POST /insights/session-summary with non-existent session."""
        fake_id = str(uuid.uuid4())
        resp = await client.post(
            "/insights/session-summary",
            params={"session_id": fake_id},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "not found" in data["summary"]
        assert data["is_ai_generated"] is False


# ---------------------------------------------------------------------------
# Integration: Data Aggregation Tests
# ---------------------------------------------------------------------------


class TestDataAggregation:
    @pytest.mark.asyncio
    async def test_patterns_include_distraction_app(self, db_session, test_user):
        """User patterns should identify the top distracting app."""
        session = await _create_session(db_session, test_user.id, days_ago=0)
        await _add_distraction(db_session, session.id, "Slack", 45)
        await _add_distraction(db_session, session.id, "Twitter", 30)
        await _add_distraction(db_session, session.id, "Slack", 20)

        provider = MockLLMProvider("Focus nudge")
        result = await generate_coaching_nudge(
            db_session, test_user.id, provider
        )

        assert result["is_ai_generated"] is True
        # Verify prompt was built with Slack as top distractor
        _, user_prompt = provider.calls[0]
        assert "Slack" in user_prompt

    @pytest.mark.asyncio
    async def test_trend_data_distraction_trend(self, db_session, test_user):
        """Distraction trend should compare week-over-week."""
        # Week 1 (8-14 days ago): high distractions
        for i in range(8, 12):
            await _create_session(
                db_session, test_user.id, days_ago=i, distraction_count=10
            )

        # Week 2 (0-6 days ago): fewer distractions
        for i in range(0, 4):
            await _create_session(
                db_session, test_user.id, days_ago=i, distraction_count=2
            )

        provider = MockLLMProvider(json.dumps([
            {"goal": "Keep it up", "target": "< 2/day", "reasoning": "Improving"},
        ]))

        result = await generate_goal_suggestions(
            db_session, test_user.id, provider
        )

        assert result["is_ai_generated"] is True
        _, user_prompt = provider.calls[0]
        assert "improving" in user_prompt

    @pytest.mark.asyncio
    async def test_summary_includes_task_count(self, db_session, test_user):
        """Session summary prompt should include tasks completed during session."""
        session = await _create_session(
            db_session,
            test_user.id,
            duration_seconds=1500,
            focused_seconds=1200,
        )

        # Create a completed task within the session window
        task = Task(
            id=uuid.uuid4(),
            user_id=test_user.id,
            title="Write tests",
            status=2,  # done
            updated_at=session.start_time + timedelta(minutes=10),
        )
        db_session.add(task)
        await db_session.commit()

        provider = MockLLMProvider("Great work completing your task!")
        result = await generate_session_summary(
            db_session, test_user.id, session.id, provider
        )

        assert result["is_ai_generated"] is True
        _, user_prompt = provider.calls[0]
        assert "1" in user_prompt  # tasks_completed = 1
