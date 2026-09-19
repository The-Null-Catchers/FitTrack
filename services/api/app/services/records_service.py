"""Personal-record detection.

Records are evaluated per (user, exercise, record type) against the current
best, so a PR is recorded exactly once per genuine improvement.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import PersonalRecordType, TrackingType
from app.models.workout import PersonalRecord, WorkoutSession, WorkoutSessionExercise, WorkoutSet
from app.services.metrics import epley_1rm

#: A new value must beat the previous best by this margin to count, which keeps
#: floating-point noise from producing phantom records.
EPSILON = 1e-6


def _candidates(tracking_type: str, sets: list[WorkoutSet]) -> dict[str, tuple[float, WorkoutSet]]:
    """Best value per record type across a session's sets for one exercise."""
    working = [s for s in sets if s.counts_toward_records]
    if not working:
        return {}

    best: dict[str, tuple[float, WorkoutSet]] = {}

    def offer(kind: str, value: float | None, source: WorkoutSet) -> None:
        if value is None or value <= 0:
            return
        current = best.get(kind)
        if current is None or value > current[0]:
            best[kind] = (value, source)

    if tracking_type in {TrackingType.WEIGHT_REPS, TrackingType.ASSISTED_WEIGHT}:
        for item in working:
            offer(PersonalRecordType.MAX_WEIGHT, item.weight_kg, item)
            offer(PersonalRecordType.MAX_REPS, float(item.reps or 0), item)
            offer(PersonalRecordType.ESTIMATED_1RM, item.estimated_1rm_kg, item)
            offer(PersonalRecordType.MAX_VOLUME, item.volume_kg, item)
    elif tracking_type == TrackingType.REPS_ONLY:
        for item in working:
            offer(PersonalRecordType.MAX_REPS, float(item.reps or 0), item)
    elif tracking_type == TrackingType.DURATION:
        for item in working:
            offer(PersonalRecordType.BEST_TIME, float(item.duration_seconds or 0), item)
    elif tracking_type == TrackingType.DISTANCE:
        for item in working:
            offer(PersonalRecordType.MAX_DISTANCE, item.distance_m, item)

    return best


_UNITS = {
    PersonalRecordType.MAX_WEIGHT: "kg",
    PersonalRecordType.ESTIMATED_1RM: "kg",
    PersonalRecordType.MAX_VOLUME: "kg",
    PersonalRecordType.MAX_REPS: "reps",
    PersonalRecordType.BEST_TIME: "s",
    PersonalRecordType.MAX_DISTANCE: "m",
}


async def current_best(
    db: AsyncSession, user_id: uuid.UUID, exercise_id: uuid.UUID
) -> dict[str, float]:
    rows = await db.execute(
        select(PersonalRecord.record_type, func.max(PersonalRecord.value))
        .where(
            PersonalRecord.user_id == user_id,
            PersonalRecord.exercise_id == exercise_id,
        )
        .group_by(PersonalRecord.record_type)
    )
    return {record_type: float(value) for record_type, value in rows}


async def evaluate_session(db: AsyncSession, session: WorkoutSession) -> list[PersonalRecord]:
    """Detect and persist every PR set during ``session``.

    Called when a workout is finished (and again if it is later edited).
    """
    achieved_at = session.completed_at or datetime.now(UTC)
    new_records: list[PersonalRecord] = []

    for session_exercise in session.exercises:
        candidates = _candidates(session_exercise.tracking_type, list(session_exercise.sets))
        if not candidates:
            continue

        # Exclude records already logged for this session so re-finishing an
        # edited workout doesn't duplicate them.
        existing_here = await db.scalars(
            select(PersonalRecord).where(
                PersonalRecord.session_id == session.id,
                PersonalRecord.exercise_id == session_exercise.exercise_id,
            )
        )
        already = {record.record_type: record for record in existing_here}

        best = await current_best(db, session.user_id, session_exercise.exercise_id)

        for record_type, (value, source_set) in candidates.items():
            previous = best.get(record_type)
            if previous is not None and value <= previous + EPSILON:
                continue

            if record_type in already:
                record = already[record_type]
                record.value = value
                record.reps = source_set.reps
                record.weight_kg = source_set.weight_kg
                continue

            record = PersonalRecord(
                user_id=session.user_id,
                exercise_id=session_exercise.exercise_id,
                record_type=record_type,
                value=round(value, 2),
                unit=_UNITS.get(PersonalRecordType(record_type), ""),
                reps=source_set.reps,
                weight_kg=source_set.weight_kg,
                previous_value=previous,
                achieved_at=achieved_at,
                session_id=session.id,
                set_id=source_set.id,
            )
            db.add(record)
            new_records.append(record)

    if new_records:
        await db.flush()
    return new_records


async def list_for_user(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    exercise_id: uuid.UUID | None = None,
    limit: int = 50,
    current_only: bool = True,
) -> list[PersonalRecord]:
    """Recent records, newest first.

    With ``current_only`` the list is reduced to the standing best per
    (exercise, record type) rather than every historical PR event.
    """
    stmt = select(PersonalRecord).where(PersonalRecord.user_id == user_id)
    if exercise_id:
        stmt = stmt.where(PersonalRecord.exercise_id == exercise_id)
    rows = list(await db.scalars(stmt.order_by(PersonalRecord.achieved_at.desc()).limit(limit * 4)))
    if not current_only:
        return rows[:limit]

    seen: set[tuple[uuid.UUID, str]] = set()
    out: list[PersonalRecord] = []
    for record in rows:
        key = (record.exercise_id, record.record_type)
        if key in seen:
            continue
        seen.add(key)
        out.append(record)
        if len(out) >= limit:
            break
    return out


async def acknowledge(db: AsyncSession, user_id: uuid.UUID, record_ids: list[uuid.UUID]) -> int:
    """Mark celebration UI as shown for the given records."""
    if not record_ids:
        return 0
    from sqlalchemy import update as sa_update

    result = await db.execute(
        sa_update(PersonalRecord)
        .where(
            PersonalRecord.user_id == user_id,
            PersonalRecord.id.in_(record_ids),
            PersonalRecord.acknowledged_at.is_(None),
        )
        .values(acknowledged_at=datetime.now(UTC))
    )
    await db.commit()
    return int(result.rowcount or 0)


def recompute_set_derivatives(item: WorkoutSet, tracking_type: str) -> None:
    """Refresh the cached 1RM/volume columns for a set."""
    if tracking_type in {TrackingType.WEIGHT_REPS, TrackingType.ASSISTED_WEIGHT}:
        item.volume_kg = round((item.weight_kg or 0) * (item.reps or 0), 2)
        item.estimated_1rm_kg = (
            epley_1rm(item.weight_kg, item.reps) if item.weight_kg and item.reps else None
        )
    else:
        item.volume_kg = 0.0
        item.estimated_1rm_kg = None


async def exercise_ids_with_records(db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    rows = await db.scalars(
        select(PersonalRecord.exercise_id).where(PersonalRecord.user_id == user_id).distinct()
    )
    return set(rows)


async def session_record_count(
    db: AsyncSession, session_ids: list[uuid.UUID]
) -> dict[uuid.UUID, int]:
    """PR counts keyed by session id — one query for a whole history page."""
    if not session_ids:
        return {}
    rows = await db.execute(
        select(PersonalRecord.session_id, func.count())
        .where(PersonalRecord.session_id.in_(session_ids))
        .group_by(PersonalRecord.session_id)
    )
    return {session_id: int(count) for session_id, count in rows if session_id}


async def last_session_for_exercise(
    db: AsyncSession,
    user_id: uuid.UUID,
    exercise_id: uuid.UUID,
    *,
    before_session_id: uuid.UUID | None = None,
) -> WorkoutSessionExercise | None:
    """The most recent completed performance of an exercise."""
    from app.models.enums import SessionStatus

    stmt = (
        select(WorkoutSessionExercise)
        .join(WorkoutSession, WorkoutSession.id == WorkoutSessionExercise.session_id)
        .where(
            WorkoutSession.user_id == user_id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
            WorkoutSessionExercise.exercise_id == exercise_id,
        )
        .order_by(WorkoutSession.started_at.desc())
        .limit(1)
    )
    if before_session_id is not None:
        stmt = stmt.where(WorkoutSession.id != before_session_id)
    return await db.scalar(stmt)
