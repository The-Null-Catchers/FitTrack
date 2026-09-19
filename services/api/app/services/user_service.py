"""Profile, onboarding, nutrition targets and account data export."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError
from app.models.body import BodyMeasurement, BodyWeight, ProgressPhoto
from app.models.goal import UserGoal
from app.models.habit import Habit, HabitLog
from app.models.notification import NotificationPreference
from app.models.nutrition import Meal, WaterLog
from app.models.user import User, UserProfile
from app.models.workout import PersonalRecord, WorkoutSession
from app.schemas.user import NutritionTargetUpdate, OnboardingRequest, ProfileUpdate, UserUpdate
from app.services import audit
from app.services.metrics import ESTIMATE_DISCLAIMER, age_from, estimate_targets
from app.storage import get_storage


async def get_profile(db: AsyncSession, user: User) -> UserProfile:
    profile = user.profile
    if profile is None:
        profile = UserProfile(user_id=user.id)
        db.add(profile)
        await db.flush()
        user.profile = profile
    return profile


def avatar_url(user: User) -> str | None:
    if not user.avatar_key:
        return None
    return get_storage().signed_url(user.avatar_key)


def serialize_user(user: User) -> dict[str, Any]:
    """Shape a ``User`` for :class:`~app.schemas.user.UserRead`."""
    payload: dict[str, Any] = {
        "id": str(user.id),
        "email": user.email,
        "full_name": user.full_name,
        "avatar_url": avatar_url(user),
        "role": user.role,
        "status": user.status,
        "locale": user.locale,
        "timezone": user.timezone,
        "theme": user.theme,
        "email_verified": user.email_verified,
        "onboarding_completed": user.onboarding_completed,
        "subscription_tier": user.subscription_tier,
        "created_at": user.created_at,
        "profile": user.profile,
    }
    return payload


async def update_user(db: AsyncSession, user: User, data: UserUpdate) -> User:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    await db.commit()
    await db.refresh(user)
    return user


async def update_profile(db: AsyncSession, user: User, data: ProfileUpdate) -> UserProfile:
    profile = await get_profile(db, user)
    values = data.model_dump(exclude_unset=True)
    for field, value in values.items():
        setattr(profile, field, value)

    # Keep estimated targets aligned with the inputs unless the user pinned them.
    if not profile.targets_are_manual and {
        "current_weight_kg", "height_cm", "activity_level", "primary_goal", "date_of_birth"
    } & values.keys():
        _apply_estimated_targets(profile)

    await db.commit()
    await db.refresh(profile)
    return profile


def _apply_estimated_targets(profile: UserProfile) -> dict[str, int] | None:
    if not profile.current_weight_kg or not profile.height_cm:
        return None
    estimate = estimate_targets(
        weight_kg=profile.current_weight_kg,
        height_cm=profile.height_cm,
        age_years=age_from(profile.date_of_birth),
        gender=profile.gender,
        activity_level=profile.activity_level,
        goal=profile.primary_goal,
    )
    profile.daily_calorie_target = estimate["recommended_calories"]
    profile.daily_protein_target_g = estimate["recommended_protein_g"]
    profile.daily_carbs_target_g = estimate["recommended_carbs_g"]
    profile.daily_fat_target_g = estimate["recommended_fat_g"]
    profile.daily_fiber_target_g = estimate["recommended_fiber_g"]
    profile.daily_water_target_ml = estimate["recommended_water_ml"]
    return estimate


async def complete_onboarding(
    db: AsyncSession, user: User, data: OnboardingRequest
) -> UserProfile:
    profile = await get_profile(db, user)

    if data.full_name:
        user.full_name = data.full_name

    profile.date_of_birth = data.date_of_birth
    profile.gender = data.gender
    profile.height_cm = data.height_cm
    profile.current_weight_kg = data.current_weight_kg
    profile.target_weight_kg = data.target_weight_kg
    profile.unit_system = data.unit_system
    profile.primary_goal = data.primary_goal
    profile.fitness_level = data.fitness_level
    profile.activity_level = data.activity_level
    profile.workout_location = data.workout_location
    profile.available_equipment = [e.value for e in data.available_equipment]
    profile.training_days_per_week = data.training_days_per_week
    profile.preferred_session_minutes = data.preferred_session_minutes

    if data.estimate_nutrition_targets:
        _apply_estimated_targets(profile)
        profile.targets_are_manual = False

    # Seed the weight chart with the starting weight so day one isn't empty.
    today = datetime.now(UTC).date()
    existing = await db.scalar(
        select(BodyWeight).where(BodyWeight.user_id == user.id, BodyWeight.recorded_on == today)
    )
    if existing is None:
        db.add(
            BodyWeight(user_id=user.id, recorded_on=today, weight_kg=data.current_weight_kg)
        )
    else:
        existing.weight_kg = data.current_weight_kg

    if user.notification_preference is None:
        db.add(NotificationPreference(user_id=user.id))

    user.onboarding_completed_at = datetime.now(UTC)
    await audit.record(db, action="user.onboarding_completed", actor_id=user.id)
    await db.commit()
    await db.refresh(profile)
    return profile


async def estimate_nutrition_targets(db: AsyncSession, user: User) -> dict[str, Any]:
    profile = await get_profile(db, user)
    if not profile.current_weight_kg or not profile.height_cm:
        raise NotFoundError(
            "Add your height and weight first so we can estimate your targets.",
            code="profile_incomplete",
        )
    estimate = estimate_targets(
        weight_kg=profile.current_weight_kg,
        height_cm=profile.height_cm,
        age_years=age_from(profile.date_of_birth),
        gender=profile.gender,
        activity_level=profile.activity_level,
        goal=profile.primary_goal,
    )
    return {**estimate, "disclaimer": ESTIMATE_DISCLAIMER}


async def update_nutrition_targets(
    db: AsyncSession, user: User, data: NutritionTargetUpdate
) -> UserProfile:
    profile = await get_profile(db, user)
    values = data.model_dump(exclude_unset=True)
    for field, value in values.items():
        setattr(profile, field, value)
    if values:
        # Any manual edit pins the targets against future recalculation.
        profile.targets_are_manual = True
    await db.commit()
    await db.refresh(profile)
    return profile


async def apply_estimated_targets(db: AsyncSession, user: User) -> UserProfile:
    """Explicitly re-adopt the estimate, clearing the manual override."""
    profile = await get_profile(db, user)
    _apply_estimated_targets(profile)
    profile.targets_are_manual = False
    await db.commit()
    await db.refresh(profile)
    return profile


async def set_avatar(db: AsyncSession, user: User, key: str) -> User:
    previous = user.avatar_key
    user.avatar_key = key
    await db.commit()
    if previous and previous != key:
        await get_storage().delete(previous)
    return user


async def build_data_export(db: AsyncSession, user: User) -> dict[str, Any]:
    """Assemble a complete JSON export of the user's own data.

    Progress photos are listed as metadata with signed URLs rather than being
    inlined, so the export stays small and the links stay access-controlled.
    """

    async def rows(model: Any, order: Any) -> list[dict[str, Any]]:
        result = await db.scalars(select(model).where(model.user_id == user.id).order_by(order))
        out = []
        for row in result:
            out.append(
                {
                    column.key: _jsonable(getattr(row, column.key))
                    for column in row.__table__.columns
                    if column.key not in {"storage_key", "thumbnail_key"}
                }
            )
        return out

    storage = get_storage()
    photos = await db.scalars(
        select(ProgressPhoto)
        .where(ProgressPhoto.user_id == user.id, ProgressPhoto.is_deleted.is_(False))
        .order_by(ProgressPhoto.taken_on)
    )

    return {
        "exported_at": datetime.now(UTC).isoformat(),
        "account": {
            "id": str(user.id),
            "email": user.email,
            "full_name": user.full_name,
            "locale": user.locale,
            "timezone": user.timezone,
            "created_at": user.created_at.isoformat(),
        },
        "profile": (
            {
                column.key: _jsonable(getattr(user.profile, column.key))
                for column in user.profile.__table__.columns
            }
            if user.profile
            else None
        ),
        "workout_sessions": await rows(WorkoutSession, WorkoutSession.started_at),
        "personal_records": await rows(PersonalRecord, PersonalRecord.achieved_at),
        "body_weights": await rows(BodyWeight, BodyWeight.recorded_on),
        "body_measurements": await rows(BodyMeasurement, BodyMeasurement.recorded_on),
        "meals": await rows(Meal, Meal.logged_on),
        "water_logs": await rows(WaterLog, WaterLog.logged_on),
        "habits": await rows(Habit, Habit.created_at),
        "habit_logs": await rows(HabitLog, HabitLog.logged_on),
        "goals": await rows(UserGoal, UserGoal.start_date),
        "progress_photos": [
            {
                "id": str(photo.id),
                "taken_on": photo.taken_on.isoformat(),
                "pose": photo.pose,
                "note": photo.note,
                "download_url": storage.signed_url(photo.storage_key, expires_in=3600),
            }
            for photo in photos
        ],
    }


def _jsonable(value: Any) -> Any:
    import datetime as _dt
    import uuid as _uuid

    if isinstance(value, _uuid.UUID):
        return str(value)
    if isinstance(value, _dt.datetime | _dt.date):
        return value.isoformat()
    return value


async def account_statistics(db: AsyncSession, user: User) -> dict[str, int]:
    async def count(model: Any) -> int:
        return int(
            await db.scalar(
                select(func.count()).select_from(model).where(model.user_id == user.id)
            )
            or 0
        )

    return {
        "workout_sessions": await count(WorkoutSession),
        "body_weights": await count(BodyWeight),
        "body_measurements": await count(BodyMeasurement),
        "progress_photos": await count(ProgressPhoto),
        "meals": await count(Meal),
        "habits": await count(Habit),
        "goals": await count(UserGoal),
    }
