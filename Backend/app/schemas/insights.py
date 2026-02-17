from pydantic import BaseModel


class HeatmapEntry(BaseModel):
    hour: int  # 0-23
    day_of_week: int  # 0=Monday, 6=Sunday
    focused_minutes: float


class FocusTrend(BaseModel):
    date: str  # ISO date string
    focused_minutes: float
    session_count: int
    distraction_count: int


class DistractionPattern(BaseModel):
    app_name: str
    count: int
    total_duration_seconds: int


class OptimalSessionLength(BaseModel):
    recommended_minutes: int
    avg_focus_ratio: float
    sample_size: int


class SmartGoal(BaseModel):
    goal_type: str  # "daily_focus", "session_count", "distraction_reduction", "streak"
    target_value: float
    current_value: float
    description: str


class InsightsResponse(BaseModel):
    heatmap: list[HeatmapEntry]
    trends: list[FocusTrend]
    top_distractors: list[DistractionPattern]
    optimal_session: OptimalSessionLength
    goals: list[SmartGoal]


# --- AI Coaching Schemas ---


class AISessionSummary(BaseModel):
    summary: str
    is_ai_generated: bool = True


class AICoachingNudge(BaseModel):
    nudge: str
    is_ai_generated: bool = True


class AIGoalSuggestion(BaseModel):
    goal: str
    target: str
    reasoning: str


class AIGoalsResponse(BaseModel):
    goals: list[AIGoalSuggestion]
    is_ai_generated: bool = True
