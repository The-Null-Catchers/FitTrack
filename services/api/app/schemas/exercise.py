"""Exercise library schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.models.enums import Difficulty, Equipment, ExerciseType, MuscleGroup, TrackingType
from app.schemas.common import APIModel


class ExerciseMediaRead(APIModel):
    id: str
    kind: str
    url: str | None
    caption: str | None
    position: int


class ExerciseSummary(APIModel):
    id: str
    slug: str
    name: str
    name_ar: str | None = None
    muscle_group: MuscleGroup
    equipment: Equipment
    difficulty: Difficulty
    exercise_type: ExerciseType
    default_tracking_type: TrackingType
    image_url: str | None = None
    is_public: bool = True


class ExerciseRead(ExerciseSummary):
    description: str | None = None
    instructions: list[str] = Field(default_factory=list)
    secondary_muscles: list[str] = Field(default_factory=list)
    aliases: list[str] = Field(default_factory=list)
    default_rest_seconds: int = 90
    is_unilateral: bool = False
    video_url: str | None = None
    media: list[ExerciseMediaRead] = Field(default_factory=list)
    created_at: datetime | None = None


class ExerciseCreate(APIModel):
    name: str = Field(..., min_length=2, max_length=160)
    name_ar: str | None = Field(None, max_length=160)
    description: str | None = None
    instructions: list[str] = Field(default_factory=list)
    muscle_group: MuscleGroup
    secondary_muscles: list[MuscleGroup] = Field(default_factory=list)
    equipment: Equipment
    difficulty: Difficulty = Difficulty.BEGINNER
    exercise_type: ExerciseType = ExerciseType.STRENGTH
    default_tracking_type: TrackingType = TrackingType.WEIGHT_REPS
    default_rest_seconds: int = Field(90, ge=0, le=600)
    is_unilateral: bool = False
    video_url: str | None = Field(None, max_length=512)
    aliases: list[str] = Field(default_factory=list)


class ExerciseUpdate(APIModel):
    name: str | None = Field(None, min_length=2, max_length=160)
    name_ar: str | None = Field(None, max_length=160)
    description: str | None = None
    instructions: list[str] | None = None
    muscle_group: MuscleGroup | None = None
    secondary_muscles: list[MuscleGroup] | None = None
    equipment: Equipment | None = None
    difficulty: Difficulty | None = None
    exercise_type: ExerciseType | None = None
    default_tracking_type: TrackingType | None = None
    default_rest_seconds: int | None = Field(None, ge=0, le=600)
    is_unilateral: bool | None = None
    video_url: str | None = Field(None, max_length=512)
    aliases: list[str] | None = None
    is_public: bool | None = None


class ExerciseFilterOptions(APIModel):
    muscle_groups: list[str]
    equipment: list[str]
    difficulties: list[str]
    exercise_types: list[str]
    tracking_types: list[str]
