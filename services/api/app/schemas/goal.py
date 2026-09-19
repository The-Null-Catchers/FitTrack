"""Goal schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field, model_validator

from app.models.enums import GoalStatus, GoalType, MeasurementType
from app.schemas.common import APIModel


class GoalCreate(APIModel):
    goal_type: GoalType = GoalType.CUSTOM
    title: str = Field(..., min_length=1, max_length=160)
    description: str | None = Field(None, max_length=2000)
    exercise_id: str | None = None
    measurement_type: MeasurementType | None = None
    start_value: float | None = None
    target_value: float
    unit: str = Field("kg", max_length=16)
    is_decreasing: bool = False
    start_date: date | None = None
    target_date: date | None = None

    @model_validator(mode="after")
    def _check_subject(self) -> GoalCreate:
        if self.goal_type == GoalType.EXERCISE_1RM and not self.exercise_id:
            raise ValueError("A strength goal needs an exercise.")
        if self.goal_type == GoalType.BODY_MEASUREMENT and not self.measurement_type:
            raise ValueError("A measurement goal needs a measurement type.")
        if self.target_date and self.start_date and self.target_date < self.start_date:
            raise ValueError("The target date must be on or after the start date.")
        return self


class GoalUpdate(APIModel):
    title: str | None = Field(None, min_length=1, max_length=160)
    description: str | None = Field(None, max_length=2000)
    target_value: float | None = None
    target_date: date | None = None
    status: GoalStatus | None = None
    current_value: float | None = None


class GoalRead(APIModel):
    id: str
    goal_type: GoalType
    title: str
    description: str | None
    exercise_id: str | None
    exercise_name: str | None = None
    measurement_type: str | None
    start_value: float | None
    current_value: float | None
    target_value: float
    unit: str
    is_decreasing: bool
    start_date: date
    target_date: date | None
    status: GoalStatus
    achieved_at: datetime | None
    progress_percent: float
    days_remaining: int | None = None
    created_at: datetime
