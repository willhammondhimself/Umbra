from datetime import date

from pydantic import BaseModel


class DailyBreakdown(BaseModel):
    date: date
    focused_seconds: int
    session_count: int


class StatsResponse(BaseModel):
    period: str  # daily, weekly, monthly
    focused_seconds: int
    total_seconds: int
    session_count: int
    distraction_count: int
    current_streak: int
    daily_breakdown: list[DailyBreakdown]
