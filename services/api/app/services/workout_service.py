"""Workout sessions: start, log, resume and finish."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import ConflictError, NotFoundError, PermissionError_, ValidationError
from app.models.enums import SessionStatus, SetType, TrackingType
from app.models.program import WorkoutDay, WorkoutDayExercise
from app.models.user import User
from app.models.workout import (
    PersonalRecord,
    WorkoutSession,
    WorkoutSessionExercise,
    WorkoutSet,
)
from app.schemas.common import PaginationParams
from app.schemas.workout import (
    SessionExerciseWrite,
    SessionFinishRequest,
    SessionStartRequest,
    SessionUpdateRequest,
    SetWrite,
)
from app.services import exercise_service, progression, records_service
from app.services.metrics import estimate_session_calories

_LOADED = selectinload(WorkoutSession.exercises).options(
    selectinload(WorkoutSessionExercise.sets),
    selectinload(WorkoutSessionExercise.exercise),
)


async def _load(db: AsyncSession, session_id: uuid.UUID) -> WorkoutSession | None:
    # ``populate_existing`` matters here: sessions are mutated and re-read
    # within one request, and without it SQLAlchemy would hand back the
    # collections it loaded before the mutation.
    return await db.scalar(
        select(WorkoutSession)
        .options(_LOADED)
        .where(WorkoutSession.id == session_id)
        .execution_options(populate_existing=True)
    )


async def get_for_user(db: AsyncSession, session_id: uuid.UUID, user: User) -> WorkoutSession:
    session = await _load(db, session_id)
    if session is None or session.is_deleted:
        raise NotFoundError("We couldn't find that workout.")
    if session.user_id != user.id:
        raise PermissionError_("That workout belongs to someone else.")
    return session


async def get_active(db: AsyncSession, user: User) -> WorkoutSession | None:
    """The in-progress workout, if any — what "resume" restores."""
    return await db.scalar(
        select(WorkoutSession)
        .options(_LOADED)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.IN_PROGRESS,
            WorkoutSession.is_deleted.is_(False),
        )
        .order_by(WorkoutSession.started_at.desc())
    )


def _target_snapshot(item: WorkoutDayExercise) -> dict[str, Any]:
    return {
        "sets": item.target_sets,
        "reps_min": item.target_reps_min,
        "reps_max": item.target_reps_max,
        "weight_kg": item.target_weight_kg,
        "duration_seconds": item.target_duration_seconds,
        "distance_m": item.target_distance_m,
        "rpe": item.target_rpe,
        "rir": item.target_rir,
    }


async def start(
    db: AsyncSession, user: User, data: SessionStartRequest
) -> tuple[WorkoutSession, bool]:
    """Start a workout. Returns ``(session, created)``.

    Replaying the same ``client_uuid`` returns the existing session instead of
    creating a duplicate, which is what makes offline start/retry safe.
    """
    if data.client_uuid:
        existing = await db.scalar(
            select(WorkoutSession)
            .options(_LOADED)
            .where(
                WorkoutSession.user_id == user.id,
                WorkoutSession.client_uuid == data.client_uuid,
            )
        )
        if existing is not None:
            return existing, False

    active = await get_active(db, user)
    if active is not None:
        raise ConflictError(
            "You already have a workout in progress. Finish or discard it first.",
            code="workout_in_progress",
            details={"session_id": str(active.id)},
        )

    day: WorkoutDay | None = None
    if data.day_id:
        day = await db.scalar(
            select(WorkoutDay)
            .options(
                selectinload(WorkoutDay.program),
                selectinload(WorkoutDay.exercises).selectinload(WorkoutDayExercise.exercise),
            )
            .where(WorkoutDay.id == uuid.UUID(data.day_id))
        )
        if day is None:
            raise NotFoundError("We couldn't find that workout day.")
        if day.program.user_id not in (user.id, None) and not day.program.is_template:
            raise PermissionError_("That program belongs to someone else.")

    session = WorkoutSession(
        user_id=user.id,
        program_id=uuid.UUID(data.program_id)
        if data.program_id
        else (day.program_id if day else None),
        day_id=day.id if day else None,
        name=data.name or (day.name if day else "Quick workout"),
        status=SessionStatus.IN_PROGRESS,
        started_at=data.started_at or datetime.now(UTC),
        client_uuid=data.client_uuid,
    )
    db.add(session)
    await db.flush()

    if day is not None:
        for item in sorted(day.exercises, key=lambda e: e.position):
            db.add(
                WorkoutSessionExercise(
                    session_id=session.id,
                    exercise_id=item.exercise_id,
                    position=item.position,
                    tracking_type=item.tracking_type,
                    rest_seconds=item.rest_seconds,
                    notes=item.notes,
                    superset_group=item.superset_group,
                    target_snapshot=_target_snapshot(item),
                )
            )
    elif data.exercises:
        await _replace_exercises(db, session, data.exercises, user=user)

    await db.commit()
    return await get_for_user(db, session.id, user), True


async def _replace_exercises(
    db: AsyncSession,
    session: WorkoutSession,
    payload: list[SessionExerciseWrite],
    *,
    user: User,
) -> None:
    """Overwrite a session's exercises/sets from a client-supplied snapshot."""
    ids = [uuid.UUID(item.exercise_id) for item in payload]
    known = await exercise_service.get_many(db, ids, user=user)
    missing = [str(i) for i in ids if i not in known]
    if missing:
        raise ValidationError(
            "Some of those exercises aren't available.", details={"exercise_ids": missing}
        )

    existing = {item.id: item for item in session.exercises}
    for item in existing.values():
        await db.delete(item)
    await db.flush()

    for position, entry in enumerate(payload):
        exercise = known[uuid.UUID(entry.exercise_id)]
        session_exercise = WorkoutSessionExercise(
            session_id=session.id,
            exercise_id=exercise.id,
            position=entry.position if entry.position is not None else position,
            tracking_type=entry.tracking_type or exercise.default_tracking_type,
            rest_seconds=entry.rest_seconds,
            notes=entry.notes,
            superset_group=entry.superset_group,
            target_snapshot=entry.target_snapshot,
        )
        db.add(session_exercise)
        await db.flush()
        for set_payload in entry.sets:
            db.add(_build_set(session_exercise, set_payload))
    await db.flush()


def _build_set(session_exercise: WorkoutSessionExercise, payload: SetWrite) -> WorkoutSet:
    item = WorkoutSet(
        session_exercise_id=session_exercise.id,
        set_number=payload.set_number,
        set_type=payload.set_type,
        weight_kg=payload.weight_kg,
        reps=payload.reps,
        duration_seconds=payload.duration_seconds,
        distance_m=payload.distance_m,
        calories=payload.calories,
        rpe=payload.rpe,
        rir=payload.rir,
        is_completed=payload.is_completed,
        notes=payload.notes,
        completed_at=datetime.now(UTC) if payload.is_completed else None,
    )
    records_service.recompute_set_derivatives(item, session_exercise.tracking_type)
    return item


async def _get_session_exercise(
    db: AsyncSession, session_exercise_id: uuid.UUID, user: User
) -> WorkoutSessionExercise:
    item = await db.scalar(
        select(WorkoutSessionExercise)
        .options(
            selectinload(WorkoutSessionExercise.session),
            selectinload(WorkoutSessionExercise.sets),
            selectinload(WorkoutSessionExercise.exercise),
        )
        .where(WorkoutSessionExercise.id == session_exercise_id)
        .execution_options(populate_existing=True)
    )
    if item is None:
        raise NotFoundError("We couldn't find that exercise in your workout.")
    if item.session.user_id != user.id:
        raise PermissionError_("That workout belongs to someone else.")
    return item


async def add_exercise(
    db: AsyncSession,
    session_id: uuid.UUID,
    user: User,
    *,
    exercise_id: uuid.UUID,
    position: int | None = None,
    tracking_type: str | None = None,
    rest_seconds: int | None = None,
) -> WorkoutSession:
    session = await get_for_user(db, session_id, user)
    exercise = await exercise_service.get(db, exercise_id, user=user)
    db.add(
        WorkoutSessionExercise(
            session_id=session.id,
            exercise_id=exercise.id,
            position=position if position is not None else len(session.exercises),
            tracking_type=tracking_type or exercise.default_tracking_type,
            rest_seconds=rest_seconds or exercise.default_rest_seconds,
        )
    )
    await db.commit()
    return await get_for_user(db, session.id, user)


async def remove_exercise(
    db: AsyncSession, session_exercise_id: uuid.UUID, user: User
) -> WorkoutSession:
    item = await _get_session_exercise(db, session_exercise_id, user)
    session_id = item.session_id
    await db.delete(item)
    await db.commit()
    return await get_for_user(db, session_id, user)


async def replace_exercise(
    db: AsyncSession, session_exercise_id: uuid.UUID, user: User, *, exercise_id: uuid.UUID
) -> WorkoutSession:
    """Swap the movement while keeping position, rest and any logged sets."""
    item = await _get_session_exercise(db, session_exercise_id, user)
    replacement = await exercise_service.get(db, exercise_id, user=user)

    item.replaced_exercise_id = item.exercise_id
    item.exercise_id = replacement.id
    item.tracking_type = replacement.default_tracking_type
    for logged in item.sets:
        records_service.recompute_set_derivatives(logged, item.tracking_type)
    await db.commit()
    return await get_for_user(db, item.session_id, user)


async def reorder_exercises(
    db: AsyncSession, session_id: uuid.UUID, user: User, ordered_ids: list[str]
) -> WorkoutSession:
    session = await get_for_user(db, session_id, user)
    known = {str(item.id): item for item in session.exercises}
    unknown = [i for i in ordered_ids if i not in known]
    if unknown:
        raise ValidationError(
            "Some of those exercises aren't in this workout.", details={"ids": unknown}
        )
    for position, item_id in enumerate(ordered_ids):
        known[item_id].position = position
    await db.commit()
    return await get_for_user(db, session_id, user)


async def add_set(
    db: AsyncSession, session_exercise_id: uuid.UUID, user: User, payload: SetWrite
) -> WorkoutSessionExercise:
    item = await _get_session_exercise(db, session_exercise_id, user)
    if any(existing.set_number == payload.set_number for existing in item.sets):
        raise ConflictError("That set number already exists.", code="duplicate_set")
    new_set = _build_set(item, payload)
    db.add(new_set)
    await db.commit()
    return await _get_session_exercise(db, session_exercise_id, user)


async def update_set(
    db: AsyncSession, set_id: uuid.UUID, user: User, payload: SetWrite
) -> WorkoutSessionExercise:
    logged = await db.scalar(
        select(WorkoutSet)
        .options(
            selectinload(WorkoutSet.session_exercise).selectinload(WorkoutSessionExercise.session)
        )
        .where(WorkoutSet.id == set_id)
    )
    if logged is None:
        raise NotFoundError("We couldn't find that set.")
    if logged.session_exercise.session.user_id != user.id:
        raise PermissionError_("That workout belongs to someone else.")

    was_completed = logged.is_completed
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(logged, field, value)
    if logged.is_completed and not was_completed:
        logged.completed_at = datetime.now(UTC)
    elif not logged.is_completed:
        logged.completed_at = None
    records_service.recompute_set_derivatives(logged, logged.session_exercise.tracking_type)
    await db.commit()
    return await _get_session_exercise(db, logged.session_exercise_id, user)


async def delete_set(db: AsyncSession, set_id: uuid.UUID, user: User) -> WorkoutSessionExercise:
    logged = await db.scalar(
        select(WorkoutSet)
        .options(
            selectinload(WorkoutSet.session_exercise).selectinload(WorkoutSessionExercise.session)
        )
        .where(WorkoutSet.id == set_id)
    )
    if logged is None:
        raise NotFoundError("We couldn't find that set.")
    if logged.session_exercise.session.user_id != user.id:
        raise PermissionError_("That workout belongs to someone else.")
    session_exercise_id = logged.session_exercise_id
    await db.delete(logged)
    await db.commit()
    return await _get_session_exercise(db, session_exercise_id, user)


async def update_session(
    db: AsyncSession, session_id: uuid.UUID, user: User, data: SessionUpdateRequest
) -> WorkoutSession:
    session = await get_for_user(db, session_id, user)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(session, field, value)
    await db.commit()
    return await get_for_user(db, session_id, user)


def _recompute_totals(session: WorkoutSession) -> None:
    total_volume = 0.0
    total_sets = 0
    total_reps = 0
    for item in session.exercises:
        for logged in item.sets:
            if not logged.is_completed:
                continue
            total_sets += 1
            total_reps += logged.reps or 0
            total_volume += logged.volume_kg or 0.0
    session.total_volume_kg = round(total_volume, 2)
    session.total_sets = total_sets
    session.total_reps = total_reps


async def finish(
    db: AsyncSession, session_id: uuid.UUID, user: User, data: SessionFinishRequest
) -> tuple[WorkoutSession, list[PersonalRecord]]:
    session = await get_for_user(db, session_id, user)

    if data.exercises is not None:
        await _replace_exercises(db, session, data.exercises, user=user)
        session = await get_for_user(db, session_id, user)

    completed_at = data.completed_at or datetime.now(UTC)
    started_at = session.started_at
    if started_at.tzinfo is None:
        started_at = started_at.replace(tzinfo=UTC)

    session.status = SessionStatus.COMPLETED
    session.completed_at = completed_at
    session.duration_seconds = data.duration_seconds or max(
        0, int((completed_at - started_at).total_seconds())
    )
    if data.notes is not None:
        session.notes = data.notes
    if data.perceived_effort is not None:
        session.perceived_effort = data.perceived_effort

    _recompute_totals(session)
    session.estimated_calories = estimate_session_calories(
        duration_seconds=session.duration_seconds,
        bodyweight_kg=session.bodyweight_kg,
        total_volume_kg=session.total_volume_kg,
    )

    records = await records_service.evaluate_session(db, session)
    await exercise_service.bump_popularity(db, [item.exercise_id for item in session.exercises])
    await db.commit()
    return await get_for_user(db, session_id, user), records


async def discard(db: AsyncSession, session_id: uuid.UUID, user: User) -> None:
    session = await get_for_user(db, session_id, user)
    if session.status == SessionStatus.COMPLETED:
        raise ConflictError("That workout is already finished.")
    session.status = SessionStatus.ABANDONED
    session.soft_delete()
    await db.commit()


async def delete_session(db: AsyncSession, session_id: uuid.UUID, user: User) -> None:
    session = await get_for_user(db, session_id, user)
    session.soft_delete()
    await db.commit()


async def duplicate(db: AsyncSession, session_id: uuid.UUID, user: User) -> WorkoutSession:
    """Start a fresh workout with the same exercises (sets left empty)."""
    source = await get_for_user(db, session_id, user)
    active = await get_active(db, user)
    if active is not None:
        raise ConflictError(
            "You already have a workout in progress.",
            code="workout_in_progress",
            details={"session_id": str(active.id)},
        )

    session = WorkoutSession(
        user_id=user.id,
        program_id=source.program_id,
        day_id=source.day_id,
        name=source.name,
        status=SessionStatus.IN_PROGRESS,
        started_at=datetime.now(UTC),
    )
    db.add(session)
    await db.flush()
    for item in sorted(source.exercises, key=lambda e: e.position):
        db.add(
            WorkoutSessionExercise(
                session_id=session.id,
                exercise_id=item.exercise_id,
                position=item.position,
                tracking_type=item.tracking_type,
                rest_seconds=item.rest_seconds,
                superset_group=item.superset_group,
                target_snapshot=item.target_snapshot,
            )
        )
    await db.commit()
    return await get_for_user(db, session.id, user)


async def history(
    db: AsyncSession,
    user: User,
    *,
    pagination: PaginationParams,
    start_date: date | None = None,
    end_date: date | None = None,
    exercise_id: uuid.UUID | None = None,
    status: str | None = SessionStatus.COMPLETED,
) -> tuple[list[WorkoutSession], int, dict[uuid.UUID, int]]:
    base = select(WorkoutSession).where(
        WorkoutSession.user_id == user.id, WorkoutSession.is_deleted.is_(False)
    )
    if status:
        base = base.where(WorkoutSession.status == status)
    if start_date:
        base = base.where(
            WorkoutSession.started_at >= datetime.combine(start_date, datetime.min.time())
        )
    if end_date:
        base = base.where(
            WorkoutSession.started_at
            < datetime.combine(end_date + timedelta(days=1), datetime.min.time())
        )
    if exercise_id:
        base = base.where(
            WorkoutSession.id.in_(
                select(WorkoutSessionExercise.session_id).where(
                    WorkoutSessionExercise.exercise_id == exercise_id
                )
            )
        )

    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    rows = list(
        await db.scalars(
            base.options(_LOADED)
            .order_by(WorkoutSession.started_at.desc())
            .offset(pagination.offset)
            .limit(pagination.per_page)
        )
    )
    pr_counts = await records_service.session_record_count(db, [row.id for row in rows])
    return rows, total, pr_counts


async def previous_performance(
    db: AsyncSession, user: User, exercise_id: uuid.UUID, *, exclude_session_id: uuid.UUID | None
) -> dict[str, Any] | None:
    """Last completed performance of an exercise, for the "Previous" column."""
    previous = await records_service.last_session_for_exercise(
        db, user.id, exercise_id, before_session_id=exclude_session_id
    )
    if previous is None:
        return None
    session = await db.get(WorkoutSession, previous.session_id)
    if session is None:
        return None

    completed = [s for s in previous.sets if s.is_completed]
    if not completed:
        return None
    best = max(completed, key=lambda s: (s.estimated_1rm_kg or 0, s.volume_kg or 0))
    return {
        "performed_at": session.completed_at or session.started_at,
        "session_id": str(session.id),
        "best_set": serialize_set(best),
        "sets": [serialize_set(s) for s in sorted(completed, key=lambda s: s.set_number)],
        "total_volume_kg": round(sum(s.volume_kg or 0 for s in completed), 2),
    }


async def progression_hint(
    db: AsyncSession, user: User, session_exercise: WorkoutSessionExercise
) -> str | None:
    """Ask the rules engine whether to suggest a change for this exercise."""
    from app.models.enums import SessionStatus as _Status

    rows = await db.scalars(
        select(WorkoutSessionExercise)
        .options(selectinload(WorkoutSessionExercise.sets))
        .join(WorkoutSession, WorkoutSession.id == WorkoutSessionExercise.session_id)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == _Status.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
            WorkoutSessionExercise.exercise_id == session_exercise.exercise_id,
            WorkoutSessionExercise.id != session_exercise.id,
        )
        .order_by(WorkoutSession.started_at.desc())
        .limit(progression.SESSIONS_REQUIRED)
    )

    recent = [
        progression.SessionOutcome(
            sets=[
                progression.SetOutcome(
                    weight_kg=s.weight_kg,
                    reps=s.reps,
                    duration_seconds=s.duration_seconds,
                    rpe=s.rpe,
                    set_type=s.set_type,
                )
                for s in item.sets
                if s.is_completed
            ]
        )
        for item in rows
    ]
    if not recent:
        return None

    target = session_exercise.target_snapshot or {}
    suggestion = progression.suggest(
        recent_sessions=recent,
        target_sets=int(target.get("sets") or 3),
        target_reps_min=target.get("reps_min"),
        target_reps_max=target.get("reps_max"),
        tracking_type=session_exercise.tracking_type,
        equipment=session_exercise.exercise.equipment,
    )
    return suggestion.message if suggestion else None


def serialize_set(item: WorkoutSet) -> dict[str, Any]:
    return {
        "id": str(item.id),
        "set_number": item.set_number,
        "set_type": item.set_type,
        "weight_kg": item.weight_kg,
        "reps": item.reps,
        "duration_seconds": item.duration_seconds,
        "distance_m": item.distance_m,
        "calories": item.calories,
        "rpe": item.rpe,
        "rir": item.rir,
        "is_completed": item.is_completed,
        "notes": item.notes,
        "completed_at": item.completed_at,
        "estimated_1rm_kg": item.estimated_1rm_kg,
        "volume_kg": item.volume_kg,
    }


def serialize_record(record: PersonalRecord) -> dict[str, Any]:
    return {
        "id": str(record.id),
        "record_type": record.record_type,
        "value": record.value,
        "unit": record.unit,
        "reps": record.reps,
        "weight_kg": record.weight_kg,
        "previous_value": record.previous_value,
        "achieved_at": record.achieved_at,
        "acknowledged_at": record.acknowledged_at,
        "exercise": exercise_service.serialize(record.exercise),
    }


def serialize_session(
    session: WorkoutSession,
    *,
    detail: bool = False,
    pr_count: int = 0,
    previous: dict[uuid.UUID, dict[str, Any]] | None = None,
    hints: dict[uuid.UUID, str | None] | None = None,
    records: list[PersonalRecord] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": str(session.id),
        "name": session.name,
        "status": session.status,
        "started_at": session.started_at,
        "completed_at": session.completed_at,
        "duration_seconds": session.duration_seconds,
        "total_volume_kg": session.total_volume_kg,
        "total_sets": session.total_sets,
        "total_reps": session.total_reps,
        "estimated_calories": session.estimated_calories,
        "exercise_count": len(session.exercises),
        "pr_count": pr_count,
    }
    if not detail:
        return payload

    previous = previous or {}
    hints = hints or {}
    payload.update(
        {
            "program_id": str(session.program_id) if session.program_id else None,
            "day_id": str(session.day_id) if session.day_id else None,
            "notes": session.notes,
            "perceived_effort": session.perceived_effort,
            "bodyweight_kg": session.bodyweight_kg,
            "client_uuid": session.client_uuid,
            "exercises": [
                {
                    "id": str(item.id),
                    "position": item.position,
                    "tracking_type": item.tracking_type,
                    "rest_seconds": item.rest_seconds,
                    "notes": item.notes,
                    "superset_group": item.superset_group,
                    "target_snapshot": item.target_snapshot,
                    "exercise": exercise_service.serialize(item.exercise),
                    "sets": [
                        serialize_set(s) for s in sorted(item.sets, key=lambda s: s.set_number)
                    ],
                    "previous": previous.get(item.exercise_id),
                    "progression_hint": hints.get(item.id),
                }
                for item in sorted(session.exercises, key=lambda e: e.position)
            ],
            "personal_records": [serialize_record(r) for r in (records or [])],
        }
    )
    return payload


async def build_detail(
    db: AsyncSession, session: WorkoutSession, user: User, *, with_context: bool = True
) -> dict[str, Any]:
    """Detail payload, optionally enriched with previous-performance context."""
    previous: dict[uuid.UUID, dict[str, Any]] = {}
    hints: dict[uuid.UUID, str | None] = {}
    if with_context:
        for item in session.exercises:
            data = await previous_performance(
                db, user, item.exercise_id, exclude_session_id=session.id
            )
            if data:
                previous[item.exercise_id] = data
            hints[item.id] = await progression_hint(db, user, item)

    records = list(
        await db.scalars(
            select(PersonalRecord)
            .options(selectinload(PersonalRecord.exercise))
            .where(PersonalRecord.session_id == session.id)
            .order_by(PersonalRecord.achieved_at.desc())
        )
    )
    return serialize_session(
        session,
        detail=True,
        pr_count=len(records),
        previous=previous,
        hints=hints,
        records=records,
    )


def default_set_type_for(tracking_type: str) -> str:
    """Warm-ups only make sense where load is involved."""
    if tracking_type in {TrackingType.WEIGHT_REPS, TrackingType.ASSISTED_WEIGHT}:
        return SetType.NORMAL
    return SetType.NORMAL
