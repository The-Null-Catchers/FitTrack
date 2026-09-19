"""Goals and their automatic progress tracking."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError, PermissionError_
from app.models.body import BodyMeasurement, BodyWeight
from app.models.enums import GoalStatus, GoalType, PersonalRecordType, SessionStatus
from app.models.exercise import Exercise
from app.models.goal import UserGoal
from app.models.user import User
from app.models.workout import PersonalRecord, WorkoutSession
from app.schemas.goal import GoalCreate, GoalUpdate


async def create(db: AsyncSession, user: User, data: GoalCreate) -> UserGoal:
    goal = UserGoal(
        user_id=user.id,
        goal_type=data.goal_type,
        title=data.title,
        description=data.description,
        exercise_id=uuid.UUID(data.exercise_id) if data.exercise_id else None,
        measurement_type=data.measurement_type,
        start_value=data.start_value,
        current_value=data.start_value,
        target_value=data.target_value,
        unit=data.unit,
        is_decreasing=data.is_decreasing,
        start_date=data.start_date or date.today(),
        target_date=data.target_date,
    )
    db.add(goal)
    await db.flush()
    await refresh_progress(db, user, goal)
    await db.commit()
    await db.refresh(goal)
    return goal


async def get(db: AsyncSession, user: User, goal_id: uuid.UUID) -> UserGoal:
    goal = await db.get(UserGoal, goal_id)
    if goal is None or goal.is_deleted:
        raise NotFoundError("We couldn't find that goal.")
    if goal.user_id != user.id:
        raise PermissionError_("That goal belongs to someone else.")
    return goal


async def list_goals(
    db: AsyncSession, user: User, *, status: str | None = None, refresh: bool = True
) -> list[UserGoal]:
    stmt = select(UserGoal).where(UserGoal.user_id == user.id, UserGoal.is_deleted.is_(False))
    if status:
        stmt = stmt.where(UserGoal.status == status)
    goals = list(await db.scalars(stmt.order_by(UserGoal.status, UserGoal.target_date)))
    if refresh:
        for goal in goals:
            if goal.status == GoalStatus.ACTIVE:
                await refresh_progress(db, user, goal)
        await db.commit()
    return goals


async def update(db: AsyncSession, user: User, goal_id: uuid.UUID, data: GoalUpdate) -> UserGoal:
    goal = await get(db, user, goal_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(goal, field, value)
    _evaluate_status(goal)
    await db.commit()
    await db.refresh(goal)
    return goal


async def delete(db: AsyncSession, user: User, goal_id: uuid.UUID) -> None:
    goal = await get(db, user, goal_id)
    goal.soft_delete()
    await db.commit()


def _evaluate_status(goal: UserGoal) -> None:
    """Mark a goal achieved/missed based on its current value and date."""
    if goal.status not in {GoalStatus.ACTIVE, GoalStatus.ACHIEVED}:
        return
    if goal.current_value is None:
        return

    reached = (
        goal.current_value <= goal.target_value
        if goal.is_decreasing
        else goal.current_value >= goal.target_value
    )
    if reached:
        if goal.status != GoalStatus.ACHIEVED:
            goal.status = GoalStatus.ACHIEVED
            goal.achieved_at = datetime.now(UTC)
        return

    goal.status = GoalStatus.ACTIVE
    goal.achieved_at = None
    if goal.target_date and goal.target_date < date.today():
        goal.status = GoalStatus.MISSED


async def refresh_progress(db: AsyncSession, user: User, goal: UserGoal) -> UserGoal:
    """Pull the goal's current value from whichever domain owns it."""
    value: float | None = goal.current_value

    if goal.goal_type == GoalType.BODY_WEIGHT:
        latest = await db.scalar(
            select(BodyWeight.weight_kg)
            .where(BodyWeight.user_id == user.id)
            .order_by(BodyWeight.recorded_on.desc())
            .limit(1)
        )
        value = float(latest) if latest is not None else value

    elif goal.goal_type == GoalType.EXERCISE_1RM and goal.exercise_id:
        best = await db.scalar(
            select(func.max(PersonalRecord.value)).where(
                PersonalRecord.user_id == user.id,
                PersonalRecord.exercise_id == goal.exercise_id,
                PersonalRecord.record_type == PersonalRecordType.ESTIMATED_1RM,
            )
        )
        value = float(best) if best is not None else value

    elif goal.goal_type == GoalType.TOTAL_WORKOUTS:
        count = await db.scalar(
            select(func.count())
            .select_from(WorkoutSession)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.status == SessionStatus.COMPLETED,
                WorkoutSession.is_deleted.is_(False),
                WorkoutSession.started_at >= datetime.combine(goal.start_date, datetime.min.time()),
            )
        )
        value = float(count or 0)

    elif goal.goal_type == GoalType.WORKOUTS_PER_WEEK:
        week_start = date.today() - timedelta(days=date.today().weekday())
        count = await db.scalar(
            select(func.count())
            .select_from(WorkoutSession)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.status == SessionStatus.COMPLETED,
                WorkoutSession.is_deleted.is_(False),
                WorkoutSession.started_at >= datetime.combine(week_start, datetime.min.time()),
            )
        )
        value = float(count or 0)

    elif goal.goal_type == GoalType.BODY_MEASUREMENT and goal.measurement_type:
        latest = await db.scalar(
            select(BodyMeasurement.value_cm)
            .where(
                BodyMeasurement.user_id == user.id,
                BodyMeasurement.measurement_type == goal.measurement_type,
            )
            .order_by(BodyMeasurement.recorded_on.desc())
            .limit(1)
        )
        value = float(latest) if latest is not None else value

    if value is not None:
        goal.current_value = round(value, 2)
        if goal.start_value is None:
            goal.start_value = goal.current_value
    _evaluate_status(goal)
    return goal


async def refresh_all(db: AsyncSession, user: User) -> None:
    """Called after workouts/weigh-ins so goals stay current without polling."""
    goals = list(
        await db.scalars(
            select(UserGoal).where(
                UserGoal.user_id == user.id,
                UserGoal.is_deleted.is_(False),
                UserGoal.status == GoalStatus.ACTIVE,
            )
        )
    )
    for goal in goals:
        await refresh_progress(db, user, goal)


async def serialize_many(db: AsyncSession, goals: list[UserGoal]) -> list[dict[str, Any]]:
    exercise_ids = [g.exercise_id for g in goals if g.exercise_id]
    names: dict[uuid.UUID, str] = {}
    if exercise_ids:
        rows = await db.execute(
            select(Exercise.id, Exercise.name).where(Exercise.id.in_(exercise_ids))
        )
        names = dict(rows.all())
    return [serialize(goal, exercise_name=names.get(goal.exercise_id)) for goal in goals]


def serialize(goal: UserGoal, *, exercise_name: str | None = None) -> dict[str, Any]:
    days_remaining = (goal.target_date - date.today()).days if goal.target_date else None
    return {
        "id": str(goal.id),
        "goal_type": goal.goal_type,
        "title": goal.title,
        "description": goal.description,
        "exercise_id": str(goal.exercise_id) if goal.exercise_id else None,
        "exercise_name": exercise_name,
        "measurement_type": goal.measurement_type,
        "start_value": goal.start_value,
        "current_value": goal.current_value,
        "target_value": goal.target_value,
        "unit": goal.unit,
        "is_decreasing": goal.is_decreasing,
        "start_date": goal.start_date,
        "target_date": goal.target_date,
        "status": goal.status,
        "achieved_at": goal.achieved_at,
        "progress_percent": goal.progress_percent,
        "days_remaining": days_remaining,
        "created_at": goal.created_at,
    }
