"""Workout programs: authoring, cloning templates and scheduling."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy import update as sa_update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import NotFoundError, PermissionError_, ValidationError
from app.models.enums import ProgramStatus
from app.models.program import WorkoutDay, WorkoutDayExercise, WorkoutProgram
from app.models.user import User
from app.schemas.common import PaginationParams
from app.schemas.program import (
    DayExerciseCreate,
    DayExerciseUpdate,
    ProgramCreate,
    ProgramUpdate,
    WorkoutDayCreate,
    WorkoutDayUpdate,
)
from app.services import exercise_service

_LOADED = (
    selectinload(WorkoutProgram.days)
    .selectinload(WorkoutDay.exercises)
    .selectinload(WorkoutDayExercise.exercise)
)


async def _load(db: AsyncSession, program_id: uuid.UUID) -> WorkoutProgram | None:
    # ``populate_existing`` keeps re-reads within a request from returning the
    # collections that were loaded before the edit.
    return await db.scalar(
        select(WorkoutProgram)
        .options(_LOADED)
        .where(WorkoutProgram.id == program_id)
        .execution_options(populate_existing=True)
    )


async def get_for_user(
    db: AsyncSession, program_id: uuid.UUID, user: User, *, allow_template: bool = True
) -> WorkoutProgram:
    program = await _load(db, program_id)
    if program is None or program.is_deleted:
        raise NotFoundError("We couldn't find that program.")
    if program.user_id == user.id:
        return program
    if allow_template and program.is_template:
        return program
    raise PermissionError_("That program belongs to someone else.")


async def list_for_user(
    db: AsyncSession,
    user: User,
    *,
    pagination: PaginationParams,
    status: str | None = None,
    include_templates: bool = False,
) -> tuple[list[WorkoutProgram], int]:
    condition = WorkoutProgram.user_id == user.id
    if include_templates:
        condition = or_(condition, WorkoutProgram.is_template.is_(True))

    base = select(WorkoutProgram).where(WorkoutProgram.is_deleted.is_(False), condition)
    if status:
        base = base.where(WorkoutProgram.status == status)

    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    rows = await db.scalars(
        base.options(_LOADED)
        .order_by(WorkoutProgram.is_template.asc(), WorkoutProgram.updated_at.desc())
        .offset(pagination.offset)
        .limit(pagination.per_page)
    )
    return list(rows), total


async def list_templates(db: AsyncSession, *, featured_only: bool = False) -> list[WorkoutProgram]:
    stmt = select(WorkoutProgram).where(
        WorkoutProgram.is_template.is_(True), WorkoutProgram.is_deleted.is_(False)
    )
    if featured_only:
        stmt = stmt.where(WorkoutProgram.is_featured.is_(True))
    rows = await db.scalars(stmt.options(_LOADED).order_by(WorkoutProgram.name))
    return list(rows)


async def _build_day_exercises(
    db: AsyncSession, day: WorkoutDay, items: list[DayExerciseCreate], *, user: User
) -> None:
    ids = [uuid.UUID(item.exercise_id) for item in items]
    known = await exercise_service.get_many(db, ids, user=user)
    missing = [str(i) for i in ids if i not in known]
    if missing:
        raise ValidationError(
            "Some of those exercises aren't available.",
            details={"exercise_ids": missing},
        )
    for position, item in enumerate(items):
        exercise = known[uuid.UUID(item.exercise_id)]
        payload = item.model_dump(exclude={"exercise_id", "position"})
        payload["tracking_type"] = payload.get("tracking_type") or exercise.default_tracking_type
        db.add(
            WorkoutDayExercise(
                day_id=day.id,
                exercise_id=exercise.id,
                position=position,
                **payload,
            )
        )


async def create(db: AsyncSession, user: User, data: ProgramCreate) -> WorkoutProgram:
    program = WorkoutProgram(
        user_id=user.id,
        name=data.name,
        description=data.description,
        goal=data.goal,
        difficulty=data.difficulty,
        location=data.location,
        days_per_week=data.days_per_week,
        estimated_minutes=data.estimated_minutes,
        equipment_needed=data.equipment_needed,
        status=ProgramStatus.DRAFT,
    )
    db.add(program)
    await db.flush()

    for position, day_data in enumerate(data.days):
        day = WorkoutDay(
            program_id=program.id,
            name=day_data.name,
            position=position,
            weekday=day_data.weekday,
            notes=day_data.notes,
            is_rest_day=day_data.is_rest_day,
        )
        db.add(day)
        await db.flush()
        await _build_day_exercises(db, day, day_data.exercises, user=user)

    await db.commit()
    return await get_for_user(db, program.id, user)


async def update(
    db: AsyncSession, program_id: uuid.UUID, user: User, data: ProgramUpdate
) -> WorkoutProgram:
    program = await get_for_user(db, program_id, user, allow_template=False)
    values = data.model_dump(exclude_unset=True)
    new_status = values.pop("status", None)
    for field, value in values.items():
        setattr(program, field, value)
    if new_status is not None:
        await _set_status(db, program, user, new_status)
    await db.commit()
    return await get_for_user(db, program.id, user)


async def _set_status(db: AsyncSession, program: WorkoutProgram, user: User, status: str) -> None:
    if status == ProgramStatus.ACTIVE:
        # Exactly one active program per user.
        await db.execute(
            sa_update(WorkoutProgram)
            .where(
                WorkoutProgram.user_id == user.id,
                WorkoutProgram.id != program.id,
                WorkoutProgram.status == ProgramStatus.ACTIVE,
            )
            .values(status=ProgramStatus.ARCHIVED, ended_at=date.today())
        )
        program.started_at = program.started_at or date.today()
        program.ended_at = None
    elif status == ProgramStatus.ARCHIVED and program.ended_at is None:
        program.ended_at = date.today()
    program.status = status


async def activate(db: AsyncSession, program_id: uuid.UUID, user: User) -> WorkoutProgram:
    program = await get_for_user(db, program_id, user, allow_template=False)
    await _set_status(db, program, user, ProgramStatus.ACTIVE)
    await db.commit()
    return await get_for_user(db, program.id, user)


async def archive(db: AsyncSession, program_id: uuid.UUID, user: User) -> WorkoutProgram:
    program = await get_for_user(db, program_id, user, allow_template=False)
    await _set_status(db, program, user, ProgramStatus.ARCHIVED)
    await db.commit()
    return await get_for_user(db, program.id, user)


async def delete(db: AsyncSession, program_id: uuid.UUID, user: User) -> None:
    program = await get_for_user(db, program_id, user, allow_template=False)
    program.soft_delete()
    await db.commit()


async def duplicate(
    db: AsyncSession, program_id: uuid.UUID, user: User, *, name: str | None = None
) -> WorkoutProgram:
    """Clone a program (or a public template) into the caller's library."""
    source = await get_for_user(db, program_id, user, allow_template=True)

    clone = WorkoutProgram(
        user_id=user.id,
        name=name or f"{source.name} (copy)",
        description=source.description,
        goal=source.goal,
        difficulty=source.difficulty,
        location=source.location,
        days_per_week=source.days_per_week,
        estimated_minutes=source.estimated_minutes,
        equipment_needed=list(source.equipment_needed or []),
        status=ProgramStatus.DRAFT,
        source_template_id=source.id if source.is_template else source.source_template_id,
        generated_by_ai=source.generated_by_ai,
    )
    db.add(clone)
    await db.flush()

    for day in sorted(source.days, key=lambda d: d.position):
        new_day = WorkoutDay(
            program_id=clone.id,
            name=day.name,
            position=day.position,
            weekday=day.weekday,
            notes=day.notes,
            is_rest_day=day.is_rest_day,
        )
        db.add(new_day)
        await db.flush()
        for item in sorted(day.exercises, key=lambda e: e.position):
            db.add(
                WorkoutDayExercise(
                    day_id=new_day.id,
                    exercise_id=item.exercise_id,
                    position=item.position,
                    target_sets=item.target_sets,
                    target_reps_min=item.target_reps_min,
                    target_reps_max=item.target_reps_max,
                    target_weight_kg=item.target_weight_kg,
                    target_duration_seconds=item.target_duration_seconds,
                    target_distance_m=item.target_distance_m,
                    target_rpe=item.target_rpe,
                    target_rir=item.target_rir,
                    rest_seconds=item.rest_seconds,
                    tracking_type=item.tracking_type,
                    superset_group=item.superset_group,
                    notes=item.notes,
                )
            )

    await db.commit()
    return await get_for_user(db, clone.id, user)


async def add_day(
    db: AsyncSession, program_id: uuid.UUID, user: User, data: WorkoutDayCreate
) -> WorkoutProgram:
    program = await get_for_user(db, program_id, user, allow_template=False)
    position = data.position or len(program.days)
    day = WorkoutDay(
        program_id=program.id,
        name=data.name,
        position=position,
        weekday=data.weekday,
        notes=data.notes,
        is_rest_day=data.is_rest_day,
    )
    db.add(day)
    await db.flush()
    await _build_day_exercises(db, day, data.exercises, user=user)
    await db.commit()
    return await get_for_user(db, program.id, user)


async def _get_day(db: AsyncSession, day_id: uuid.UUID, user: User) -> WorkoutDay:
    day = await db.scalar(
        select(WorkoutDay)
        .options(selectinload(WorkoutDay.program), selectinload(WorkoutDay.exercises))
        .where(WorkoutDay.id == day_id)
    )
    if day is None or day.program.is_deleted:
        raise NotFoundError("We couldn't find that workout day.")
    if day.program.user_id != user.id:
        raise PermissionError_("That program belongs to someone else.")
    return day


async def update_day(
    db: AsyncSession, day_id: uuid.UUID, user: User, data: WorkoutDayUpdate
) -> WorkoutProgram:
    day = await _get_day(db, day_id, user)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(day, field, value)
    await db.commit()
    return await get_for_user(db, day.program_id, user)


async def delete_day(db: AsyncSession, day_id: uuid.UUID, user: User) -> WorkoutProgram:
    day = await _get_day(db, day_id, user)
    program_id = day.program_id
    await db.delete(day)
    await db.commit()
    return await get_for_user(db, program_id, user)


async def add_day_exercise(
    db: AsyncSession, day_id: uuid.UUID, user: User, data: DayExerciseCreate
) -> WorkoutProgram:
    day = await _get_day(db, day_id, user)
    data = data.model_copy(update={"position": data.position or len(day.exercises)})
    await _build_day_exercises(db, day, [data], user=user)
    await db.commit()
    return await get_for_user(db, day.program_id, user)


async def _get_day_exercise(db: AsyncSession, item_id: uuid.UUID, user: User) -> WorkoutDayExercise:
    item = await db.scalar(
        select(WorkoutDayExercise)
        .options(selectinload(WorkoutDayExercise.day).selectinload(WorkoutDay.program))
        .where(WorkoutDayExercise.id == item_id)
    )
    if item is None:
        raise NotFoundError("We couldn't find that exercise in the program.")
    if item.day.program.user_id != user.id:
        raise PermissionError_("That program belongs to someone else.")
    return item


async def update_day_exercise(
    db: AsyncSession, item_id: uuid.UUID, user: User, data: DayExerciseUpdate
) -> WorkoutProgram:
    item = await _get_day_exercise(db, item_id, user)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    await db.commit()
    return await get_for_user(db, item.day.program_id, user)


async def remove_day_exercise(db: AsyncSession, item_id: uuid.UUID, user: User) -> WorkoutProgram:
    item = await _get_day_exercise(db, item_id, user)
    program_id = item.day.program_id
    await db.delete(item)
    await db.commit()
    return await get_for_user(db, program_id, user)


async def reorder_day_exercises(
    db: AsyncSession, day_id: uuid.UUID, user: User, ordered_ids: list[str]
) -> WorkoutProgram:
    day = await _get_day(db, day_id, user)
    known = {str(item.id): item for item in day.exercises}
    unknown = [i for i in ordered_ids if i not in known]
    if unknown:
        raise ValidationError(
            "Some of those exercises aren't part of this day.", details={"ids": unknown}
        )
    for position, item_id in enumerate(ordered_ids):
        known[item_id].position = position
    await db.commit()
    return await get_for_user(db, day.program_id, user)


async def reorder_days(
    db: AsyncSession, program_id: uuid.UUID, user: User, ordered_ids: list[str]
) -> WorkoutProgram:
    program = await get_for_user(db, program_id, user, allow_template=False)
    known = {str(day.id): day for day in program.days}
    unknown = [i for i in ordered_ids if i not in known]
    if unknown:
        raise ValidationError(
            "Some of those days aren't part of this program.", details={"ids": unknown}
        )
    for position, day_id in enumerate(ordered_ids):
        known[day_id].position = position
    await db.commit()
    return await get_for_user(db, program.id, user)


async def get_active(db: AsyncSession, user: User) -> WorkoutProgram | None:
    return await db.scalar(
        select(WorkoutProgram)
        .options(_LOADED)
        .where(
            WorkoutProgram.user_id == user.id,
            WorkoutProgram.status == ProgramStatus.ACTIVE,
            WorkoutProgram.is_deleted.is_(False),
        )
        .order_by(WorkoutProgram.updated_at.desc())
    )


async def today_day(
    db: AsyncSession, user: User, *, on: date | None = None
) -> tuple[WorkoutProgram, WorkoutDay] | None:
    """Pick today's scheduled day from the active program.

    A day pinned to today's weekday wins. Otherwise we rotate through the
    program in order, starting after whichever day was trained most recently.
    """
    program = await get_active(db, user)
    if program is None or not program.days:
        return None

    today = on or datetime.now(UTC).date()
    days = sorted(program.days, key=lambda d: d.position)

    scheduled = [d for d in days if d.weekday == today.weekday()]
    if scheduled:
        return program, scheduled[0]
    if any(d.weekday is not None for d in days):
        # The program is weekday-pinned and nothing is scheduled today.
        rest = next((d for d in days if d.is_rest_day), None)
        return (program, rest) if rest else None

    from app.models.workout import WorkoutSession

    last_day_id = await db.scalar(
        select(WorkoutSession.day_id)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.program_id == program.id,
            WorkoutSession.day_id.is_not(None),
            WorkoutSession.is_deleted.is_(False),
        )
        .order_by(WorkoutSession.started_at.desc())
        .limit(1)
    )
    trainable = [d for d in days if not d.is_rest_day] or days
    if last_day_id is None:
        return program, trainable[0]
    ids = [d.id for d in trainable]
    if last_day_id in ids:
        return program, trainable[(ids.index(last_day_id) + 1) % len(trainable)]
    return program, trainable[0]


def serialize(program: WorkoutProgram, *, detail: bool = False) -> dict[str, Any]:
    days = sorted(program.days, key=lambda d: d.position)
    payload: dict[str, Any] = {
        "id": str(program.id),
        "name": program.name,
        "description": program.description,
        "status": program.status,
        "is_template": program.is_template,
        "is_featured": program.is_featured,
        "goal": program.goal,
        "difficulty": program.difficulty,
        "location": program.location,
        "days_per_week": program.days_per_week,
        "estimated_minutes": program.estimated_minutes,
        "equipment_needed": program.equipment_needed or [],
        "generated_by_ai": program.generated_by_ai,
        "day_count": len(days),
        "exercise_count": sum(len(d.exercises) for d in days),
        "started_at": program.started_at,
        "created_at": program.created_at,
    }
    if detail:
        payload["days"] = [
            {
                "id": str(day.id),
                "name": day.name,
                "position": day.position,
                "weekday": day.weekday,
                "notes": day.notes,
                "is_rest_day": day.is_rest_day,
                "exercises": [
                    {
                        "id": str(item.id),
                        "exercise_id": str(item.exercise_id),
                        "position": item.position,
                        "target_sets": item.target_sets,
                        "target_reps_min": item.target_reps_min,
                        "target_reps_max": item.target_reps_max,
                        "target_weight_kg": item.target_weight_kg,
                        "target_duration_seconds": item.target_duration_seconds,
                        "target_distance_m": item.target_distance_m,
                        "target_rpe": item.target_rpe,
                        "target_rir": item.target_rir,
                        "rest_seconds": item.rest_seconds,
                        "tracking_type": item.tracking_type,
                        "superset_group": item.superset_group,
                        "notes": item.notes,
                        "exercise": exercise_service.serialize(item.exercise),
                    }
                    for item in sorted(day.exercises, key=lambda e: e.position)
                ],
            }
            for day in days
        ]
    return payload
