"""Workout program schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field, model_validator

from app.models.enums import (
    Difficulty,
    FitnessGoal,
    ProgramStatus,
    TrackingType,
    WorkoutLocation,
)
from app.schemas.common import APIModel
from app.schemas.exercise import ExerciseSummary


class DayExerciseBase(APIModel):
    exercise_id: str
    target_sets: int = Field(3, ge=1, le=20)
    target_reps_min: int | None = Field(None, ge=1, le=200)
    target_reps_max: int | None = Field(None, ge=1, le=200)
    target_weight_kg: float | None = Field(None, ge=0, le=1000)
    target_duration_seconds: int | None = Field(None, ge=1, le=36000)
    target_distance_m: float | None = Field(None, ge=1, le=1_000_000)
    target_rpe: float | None = Field(None, ge=1, le=10)
    target_rir: int | None = Field(None, ge=0, le=10)
    rest_seconds: int = Field(90, ge=0, le=900)
    tracking_type: TrackingType = TrackingType.WEIGHT_REPS
    superset_group: int | None = Field(None, ge=1, le=20)
    notes: str | None = Field(None, max_length=1000)

    @model_validator(mode="after")
    def _check_rep_range(self) -> DayExerciseBase:
        if (
            self.target_reps_min is not None
            and self.target_reps_max is not None
            and self.target_reps_min > self.target_reps_max
        ):
            raise ValueError("Minimum reps cannot be greater than maximum reps.")
        return self


class DayExerciseCreate(DayExerciseBase):
    position: int = Field(0, ge=0)


class DayExerciseUpdate(APIModel):
    target_sets: int | None = Field(None, ge=1, le=20)
    target_reps_min: int | None = Field(None, ge=1, le=200)
    target_reps_max: int | None = Field(None, ge=1, le=200)
    target_weight_kg: float | None = Field(None, ge=0, le=1000)
    target_duration_seconds: int | None = Field(None, ge=1, le=36000)
    target_distance_m: float | None = Field(None, ge=1, le=1_000_000)
    target_rpe: float | None = Field(None, ge=1, le=10)
    target_rir: int | None = Field(None, ge=0, le=10)
    rest_seconds: int | None = Field(None, ge=0, le=900)
    tracking_type: TrackingType | None = None
    superset_group: int | None = Field(None, ge=1, le=20)
    notes: str | None = Field(None, max_length=1000)
    position: int | None = Field(None, ge=0)


class DayExerciseRead(DayExerciseBase):
    id: str
    position: int
    exercise: ExerciseSummary


class WorkoutDayCreate(APIModel):
    name: str = Field(..., min_length=1, max_length=120)
    position: int = Field(0, ge=0)
    weekday: int | None = Field(None, ge=0, le=6)
    notes: str | None = Field(None, max_length=2000)
    is_rest_day: bool = False
    exercises: list[DayExerciseCreate] = Field(default_factory=list)


class WorkoutDayUpdate(APIModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    position: int | None = Field(None, ge=0)
    weekday: int | None = Field(None, ge=0, le=6)
    notes: str | None = Field(None, max_length=2000)
    is_rest_day: bool | None = None


class WorkoutDayRead(APIModel):
    id: str
    name: str
    position: int
    weekday: int | None
    notes: str | None
    is_rest_day: bool
    exercises: list[DayExerciseRead] = Field(default_factory=list)


class ProgramCreate(APIModel):
    name: str = Field(..., min_length=1, max_length=160)
    description: str | None = Field(None, max_length=4000)
    goal: FitnessGoal | None = None
    difficulty: Difficulty | None = None
    location: WorkoutLocation | None = None
    days_per_week: int = Field(3, ge=1, le=7)
    estimated_minutes: int | None = Field(None, ge=10, le=300)
    equipment_needed: list[str] = Field(default_factory=list)
    days: list[WorkoutDayCreate] = Field(default_factory=list)


class ProgramUpdate(APIModel):
    name: str | None = Field(None, min_length=1, max_length=160)
    description: str | None = Field(None, max_length=4000)
    goal: FitnessGoal | None = None
    difficulty: Difficulty | None = None
    location: WorkoutLocation | None = None
    days_per_week: int | None = Field(None, ge=1, le=7)
    estimated_minutes: int | None = Field(None, ge=10, le=300)
    status: ProgramStatus | None = None


class ProgramSummary(APIModel):
    id: str
    name: str
    description: str | None
    status: ProgramStatus
    is_template: bool
    is_featured: bool
    goal: str | None
    difficulty: str | None
    location: str | None
    days_per_week: int
    estimated_minutes: int | None
    equipment_needed: list[str] = Field(default_factory=list)
    generated_by_ai: bool = False
    day_count: int = 0
    exercise_count: int = 0
    started_at: date | None = None
    created_at: datetime


class ProgramRead(ProgramSummary):
    days: list[WorkoutDayRead] = Field(default_factory=list)


class ProgramDuplicateRequest(APIModel):
    name: str | None = Field(None, min_length=1, max_length=160)


class ReorderRequest(APIModel):
    """Ordered list of ids; index in the list becomes the new position."""

    ids: list[str] = Field(..., min_length=1)
