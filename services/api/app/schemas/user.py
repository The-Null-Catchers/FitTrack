"""User, profile and onboarding schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.models.enums import (
    ActivityLevel,
    Equipment,
    FitnessGoal,
    FitnessLevel,
    Gender,
    UnitSystem,
    UserRole,
    UserStatus,
    WorkoutLocation,
)
from app.schemas.common import APIModel


class ProfileRead(APIModel):
    date_of_birth: date | None
    gender: Gender
    height_cm: float | None
    current_weight_kg: float | None
    target_weight_kg: float | None
    unit_system: UnitSystem
    primary_goal: FitnessGoal
    fitness_level: FitnessLevel
    activity_level: ActivityLevel
    workout_location: WorkoutLocation
    available_equipment: list[str]
    training_days_per_week: int
    preferred_session_minutes: int
    daily_calorie_target: int | None
    daily_protein_target_g: int | None
    daily_carbs_target_g: int | None
    daily_fat_target_g: int | None
    daily_fiber_target_g: int | None
    daily_water_target_ml: int
    targets_are_manual: bool
    default_rest_seconds: int
    ai_context_opt_in: bool


class ProfileUpdate(APIModel):
    date_of_birth: date | None = None
    gender: Gender | None = None
    height_cm: float | None = Field(None, gt=50, lt=280)
    current_weight_kg: float | None = Field(None, gt=20, lt=500)
    target_weight_kg: float | None = Field(None, gt=20, lt=500)
    unit_system: UnitSystem | None = None
    primary_goal: FitnessGoal | None = None
    fitness_level: FitnessLevel | None = None
    activity_level: ActivityLevel | None = None
    workout_location: WorkoutLocation | None = None
    available_equipment: list[Equipment] | None = None
    training_days_per_week: int | None = Field(None, ge=1, le=7)
    preferred_session_minutes: int | None = Field(None, ge=10, le=240)
    default_rest_seconds: int | None = Field(None, ge=0, le=600)
    ai_context_opt_in: bool | None = None


class UserRead(APIModel):
    id: str
    email: str
    full_name: str
    avatar_url: str | None = None
    role: UserRole
    status: UserStatus
    locale: str
    timezone: str
    theme: str
    email_verified: bool
    onboarding_completed: bool
    subscription_tier: str
    created_at: datetime
    profile: ProfileRead | None = None


class UserUpdate(APIModel):
    full_name: str | None = Field(None, min_length=1, max_length=120)
    locale: str | None = Field(None, pattern="^(en|ar)$")
    timezone: str | None = Field(None, max_length=64)
    theme: str | None = Field(None, pattern="^(system|light|dark)$")


class OnboardingRequest(APIModel):
    """Everything the onboarding flow collects, submitted in one call."""

    full_name: str | None = Field(None, min_length=1, max_length=120)
    date_of_birth: date | None = None
    gender: Gender = Gender.UNDISCLOSED
    height_cm: float = Field(..., gt=50, lt=280)
    current_weight_kg: float = Field(..., gt=20, lt=500)
    target_weight_kg: float | None = Field(None, gt=20, lt=500)
    unit_system: UnitSystem = UnitSystem.METRIC
    primary_goal: FitnessGoal
    fitness_level: FitnessLevel = FitnessLevel.BEGINNER
    activity_level: ActivityLevel = ActivityLevel.MODERATE
    workout_location: WorkoutLocation = WorkoutLocation.GYM
    available_equipment: list[Equipment] = Field(default_factory=list)
    training_days_per_week: int = Field(3, ge=1, le=7)
    preferred_session_minutes: int = Field(60, ge=10, le=240)
    #: When true the server estimates calorie/macro targets from the inputs.
    estimate_nutrition_targets: bool = True


class NutritionTargetUpdate(APIModel):
    daily_calorie_target: int | None = Field(None, ge=800, le=10000)
    daily_protein_target_g: int | None = Field(None, ge=0, le=500)
    daily_carbs_target_g: int | None = Field(None, ge=0, le=1000)
    daily_fat_target_g: int | None = Field(None, ge=0, le=400)
    daily_fiber_target_g: int | None = Field(None, ge=0, le=200)
    daily_water_target_ml: int | None = Field(None, ge=0, le=10000)


class NutritionTargetEstimate(APIModel):
    bmr_kcal: int
    tdee_kcal: int
    recommended_calories: int
    recommended_protein_g: int
    recommended_carbs_g: int
    recommended_fat_g: int
    recommended_fiber_g: int
    recommended_water_ml: int
    disclaimer: str


class AvatarUploadResponse(APIModel):
    avatar_url: str


class DataExportResponse(APIModel):
    export_id: str
    status: str
    message: str
