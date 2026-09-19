"""FitCoach schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.models.enums import (
    Difficulty,
    Equipment,
    FitnessGoal,
    FitnessLevel,
    WorkoutLocation,
)
from app.schemas.common import APIModel


class ChatRequest(APIModel):
    message: str = Field(..., min_length=1, max_length=4000)
    conversation_id: str | None = None
    #: Opt out per-message even when the profile allows AI context.
    include_context: bool = True


class AIMessageRead(APIModel):
    id: str
    role: str
    content: str
    payload: dict = Field(default_factory=dict)
    safety_redirect: bool = False
    created_at: datetime


class ChatResponse(APIModel):
    conversation_id: str
    message: AIMessageRead
    #: Always present so clients can render the standing fitness/medical notice.
    disclaimer: str


class ConversationSummary(APIModel):
    id: str
    title: str
    last_message_at: datetime | None
    created_at: datetime
    message_count: int = 0


class ConversationRead(ConversationSummary):
    messages: list[AIMessageRead] = Field(default_factory=list)


class PlanGenerationRequest(APIModel):
    goal: FitnessGoal
    experience: FitnessLevel = FitnessLevel.BEGINNER
    days_per_week: int = Field(3, ge=1, le=7)
    session_minutes: int = Field(60, ge=15, le=180)
    equipment: list[Equipment] = Field(default_factory=list)
    location: WorkoutLocation = WorkoutLocation.GYM
    preferred_exercise_ids: list[str] = Field(default_factory=list)
    excluded_exercise_ids: list[str] = Field(default_factory=list)
    notes: str | None = Field(None, max_length=1000)


class GeneratedSetPrescription(APIModel):
    sets: int
    reps_min: int | None = None
    reps_max: int | None = None
    duration_seconds: int | None = None
    rest_seconds: int = 90
    rpe: float | None = None
    notes: str | None = None


class GeneratedExercise(APIModel):
    exercise_id: str | None = None
    exercise_name: str
    prescription: GeneratedSetPrescription


class GeneratedDay(APIModel):
    name: str
    weekday: int | None = None
    focus: str | None = None
    exercises: list[GeneratedExercise] = Field(default_factory=list)


class GeneratedPlan(APIModel):
    """Preview payload. Nothing is written until the user saves it."""

    name: str
    description: str
    goal: FitnessGoal
    difficulty: Difficulty
    days_per_week: int
    estimated_minutes: int
    equipment_needed: list[str] = Field(default_factory=list)
    days: list[GeneratedDay] = Field(default_factory=list)
    coaching_notes: list[str] = Field(default_factory=list)


class PlanGenerationResponse(APIModel):
    generation_id: str
    plan: GeneratedPlan
    disclaimer: str


class PlanSaveRequest(APIModel):
    generation_id: str
    name: str | None = Field(None, min_length=1, max_length=160)
    #: Saving always creates a new program; an existing one is never overwritten.
    activate: bool = False


class SubstitutionRequest(APIModel):
    exercise_id: str
    available_equipment: list[Equipment] = Field(default_factory=list)
    reason: str | None = Field(None, max_length=500)
    limit: int = Field(5, ge=1, le=10)


class SubstitutionOption(APIModel):
    exercise_id: str
    exercise_name: str
    equipment: str
    rationale: str


class SubstitutionResponse(APIModel):
    source_exercise_id: str
    options: list[SubstitutionOption] = Field(default_factory=list)


class ProgressSummaryResponse(APIModel):
    range: str
    headline: str
    bullets: list[str] = Field(default_factory=list)
    disclaimer: str


class AIUsageResponse(APIModel):
    day: str
    messages_used: int
    messages_limit: int
    plans_generated: int
