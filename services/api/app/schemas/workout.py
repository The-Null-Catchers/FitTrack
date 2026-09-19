"""Workout session, set and personal-record schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field, model_validator

from app.models.enums import PersonalRecordType, SessionStatus, SetType, TrackingType
from app.schemas.common import APIModel
from app.schemas.exercise import ExerciseSummary


class SetWrite(APIModel):
    set_number: int = Field(..., ge=1, le=50)
    set_type: SetType = SetType.NORMAL
    weight_kg: float | None = Field(None, ge=0, le=1000)
    reps: int | None = Field(None, ge=0, le=1000)
    duration_seconds: int | None = Field(None, ge=0, le=86400)
    distance_m: float | None = Field(None, ge=0, le=1_000_000)
    calories: int | None = Field(None, ge=0, le=10000)
    rpe: float | None = Field(None, ge=1, le=10)
    rir: int | None = Field(None, ge=0, le=10)
    is_completed: bool = False
    notes: str | None = Field(None, max_length=255)

    @model_validator(mode="after")
    def _require_a_value_when_completed(self) -> SetWrite:
        if self.is_completed and all(
            v is None
            for v in (
                self.weight_kg,
                self.reps,
                self.duration_seconds,
                self.distance_m,
                self.calories,
            )
        ):
            raise ValueError("A completed set needs at least one recorded value.")
        return self


class SetRead(SetWrite):
    id: str
    completed_at: datetime | None = None
    estimated_1rm_kg: float | None = None
    volume_kg: float = 0.0


class SessionExerciseWrite(APIModel):
    exercise_id: str
    position: int = Field(0, ge=0)
    tracking_type: TrackingType = TrackingType.WEIGHT_REPS
    rest_seconds: int = Field(90, ge=0, le=900)
    notes: str | None = Field(None, max_length=2000)
    superset_group: int | None = Field(None, ge=1, le=20)
    target_snapshot: dict = Field(default_factory=dict)
    sets: list[SetWrite] = Field(default_factory=list)


class PreviousPerformance(APIModel):
    """Last time the user trained this movement — shown next to "Today"."""

    performed_at: datetime
    session_id: str
    best_set: SetRead | None = None
    sets: list[SetRead] = Field(default_factory=list)
    total_volume_kg: float = 0.0


class SessionExerciseRead(APIModel):
    id: str
    position: int
    tracking_type: TrackingType
    rest_seconds: int
    notes: str | None
    superset_group: int | None
    target_snapshot: dict = Field(default_factory=dict)
    exercise: ExerciseSummary
    sets: list[SetRead] = Field(default_factory=list)
    previous: PreviousPerformance | None = None
    progression_hint: str | None = None


class SessionStartRequest(APIModel):
    program_id: str | None = None
    day_id: str | None = None
    name: str | None = Field(None, min_length=1, max_length=160)
    started_at: datetime | None = None
    #: Offline clients send their locally generated id so replays are idempotent.
    client_uuid: str | None = Field(None, max_length=64)
    #: Ad-hoc sessions may start with exercises chosen by the user.
    exercises: list[SessionExerciseWrite] = Field(default_factory=list)


class SessionUpdateRequest(APIModel):
    name: str | None = Field(None, min_length=1, max_length=160)
    notes: str | None = Field(None, max_length=4000)
    perceived_effort: int | None = Field(None, ge=1, le=10)
    bodyweight_kg: float | None = Field(None, gt=20, lt=500)
    started_at: datetime | None = None


class SessionFinishRequest(APIModel):
    completed_at: datetime | None = None
    duration_seconds: int | None = Field(None, ge=0, le=86400)
    notes: str | None = Field(None, max_length=4000)
    perceived_effort: int | None = Field(None, ge=1, le=10)
    #: Full set state from the client, so a finish also flushes offline edits.
    exercises: list[SessionExerciseWrite] | None = None


class PersonalRecordRead(APIModel):
    id: str
    record_type: PersonalRecordType
    value: float
    unit: str
    reps: int | None
    weight_kg: float | None
    previous_value: float | None
    achieved_at: datetime
    acknowledged_at: datetime | None
    exercise: ExerciseSummary


class SessionSummary(APIModel):
    id: str
    name: str
    status: SessionStatus
    started_at: datetime
    completed_at: datetime | None
    duration_seconds: int | None
    total_volume_kg: float
    total_sets: int
    total_reps: int
    estimated_calories: int | None
    exercise_count: int = 0
    pr_count: int = 0


class SessionRead(SessionSummary):
    program_id: str | None = None
    day_id: str | None = None
    notes: str | None = None
    perceived_effort: int | None = None
    bodyweight_kg: float | None = None
    client_uuid: str | None = None
    exercises: list[SessionExerciseRead] = Field(default_factory=list)
    personal_records: list[PersonalRecordRead] = Field(default_factory=list)


class ReplaceExerciseRequest(APIModel):
    exercise_id: str


class AddExerciseRequest(APIModel):
    exercise_id: str
    position: int | None = Field(None, ge=0)
    tracking_type: TrackingType | None = None
    rest_seconds: int | None = Field(None, ge=0, le=900)
