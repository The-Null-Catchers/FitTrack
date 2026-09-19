"""Workout session endpoints — the heart of the logging experience."""

from __future__ import annotations

import uuid
from datetime import date

from fastapi import APIRouter, Query, Response, status

from app.core.deps import CurrentUser, DbSession, Pagination
from app.models.enums import SessionStatus
from app.schemas.common import Page
from app.schemas.program import ReorderRequest
from app.schemas.workout import (
    AddExerciseRequest,
    PersonalRecordRead,
    ReplaceExerciseRequest,
    SessionExerciseRead,
    SessionFinishRequest,
    SessionRead,
    SessionStartRequest,
    SessionSummary,
    SessionUpdateRequest,
    SetWrite,
)
from app.services import goal_service, notification_service, records_service, workout_service

router = APIRouter(prefix="/workout-sessions", tags=["workouts"])


@router.get(
    "/active",
    response_model=SessionRead | None,
    summary="Resume an unfinished workout",
)
async def active_session(db: DbSession, user: CurrentUser) -> SessionRead | None:
    session = await workout_service.get_active(db, user)
    if session is None:
        return None
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.get("", response_model=Page[SessionSummary], summary="Workout history")
async def history(
    db: DbSession,
    user: CurrentUser,
    pagination: Pagination,
    start_date: date | None = None,
    end_date: date | None = None,
    exercise_id: uuid.UUID | None = None,
    status_filter: SessionStatus | None = Query(SessionStatus.COMPLETED, alias="status"),
) -> Page[SessionSummary]:
    rows, total, pr_counts = await workout_service.history(
        db,
        user,
        pagination=pagination,
        start_date=start_date,
        end_date=end_date,
        exercise_id=exercise_id,
        status=status_filter.value if status_filter else None,
    )
    return Page.build(
        [
            SessionSummary(
                **workout_service.serialize_session(row, pr_count=pr_counts.get(row.id, 0))
            )
            for row in rows
        ],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.post(
    "",
    response_model=SessionRead,
    status_code=status.HTTP_201_CREATED,
    summary="Start a workout",
)
async def start_session(
    payload: SessionStartRequest, db: DbSession, user: CurrentUser
) -> SessionRead:
    session, _created = await workout_service.start(db, user, payload)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.get("/{session_id}", response_model=SessionRead, summary="Workout detail")
async def get_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> SessionRead:
    session = await workout_service.get_for_user(db, session_id, user)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.patch("/{session_id}", response_model=SessionRead, summary="Edit a workout")
async def update_session(
    session_id: uuid.UUID,
    payload: SessionUpdateRequest,
    db: DbSession,
    user: CurrentUser,
) -> SessionRead:
    session = await workout_service.update_session(db, session_id, user, payload)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.post("/{session_id}/finish", response_model=SessionRead, summary="Finish a workout")
async def finish_session(
    session_id: uuid.UUID,
    payload: SessionFinishRequest,
    db: DbSession,
    user: CurrentUser,
) -> SessionRead:
    session, records = await workout_service.finish(db, session_id, user, payload)
    # Records and goals are cheap to refresh here and keep the UI truthful.
    await notification_service.notify_personal_records(db, user, records)
    await goal_service.refresh_all(db, user)
    await db.commit()
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.post(
    "/{session_id}/discard",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Abandon a workout in progress",
)
async def discard_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await workout_service.discard(db, session_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{session_id}/duplicate",
    response_model=SessionRead,
    status_code=status.HTTP_201_CREATED,
    summary="Repeat a past workout",
)
async def duplicate_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> SessionRead:
    session = await workout_service.duplicate(db, session_id, user)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a workout")
async def delete_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await workout_service.delete_session(db, session_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{session_id}/exercises",
    response_model=SessionRead,
    status_code=status.HTTP_201_CREATED,
    summary="Add an exercise mid-workout",
)
async def add_exercise(
    session_id: uuid.UUID,
    payload: AddExerciseRequest,
    db: DbSession,
    user: CurrentUser,
) -> SessionRead:
    session = await workout_service.add_exercise(
        db,
        session_id,
        user,
        exercise_id=uuid.UUID(payload.exercise_id),
        position=payload.position,
        tracking_type=payload.tracking_type.value if payload.tracking_type else None,
        rest_seconds=payload.rest_seconds,
    )
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.post(
    "/{session_id}/exercises/reorder",
    response_model=SessionRead,
    summary="Reorder exercises",
)
async def reorder_exercises(
    session_id: uuid.UUID, payload: ReorderRequest, db: DbSession, user: CurrentUser
) -> SessionRead:
    session = await workout_service.reorder_exercises(db, session_id, user, payload.ids)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.delete(
    "/exercises/{session_exercise_id}",
    response_model=SessionRead,
    summary="Remove an exercise from a workout",
)
async def remove_exercise(
    session_exercise_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> SessionRead:
    session = await workout_service.remove_exercise(db, session_exercise_id, user)
    return SessionRead(**await workout_service.build_detail(db, session, user))


@router.post(
    "/exercises/{session_exercise_id}/replace",
    response_model=SessionRead,
    summary="Swap an exercise",
)
async def replace_exercise(
    session_exercise_id: uuid.UUID,
    payload: ReplaceExerciseRequest,
    db: DbSession,
    user: CurrentUser,
) -> SessionRead:
    session = await workout_service.replace_exercise(
        db, session_exercise_id, user, exercise_id=uuid.UUID(payload.exercise_id)
    )
    return SessionRead(**await workout_service.build_detail(db, session, user))


def _exercise_payload(item) -> SessionExerciseRead:
    from app.services import exercise_service

    return SessionExerciseRead(
        id=str(item.id),
        position=item.position,
        tracking_type=item.tracking_type,
        rest_seconds=item.rest_seconds,
        notes=item.notes,
        superset_group=item.superset_group,
        target_snapshot=item.target_snapshot or {},
        exercise=exercise_service.serialize(item.exercise),
        sets=[
            workout_service.serialize_set(s) for s in sorted(item.sets, key=lambda s: s.set_number)
        ],
    )


@router.post(
    "/exercises/{session_exercise_id}/sets",
    response_model=SessionExerciseRead,
    status_code=status.HTTP_201_CREATED,
    summary="Log a set",
)
async def add_set(
    session_exercise_id: uuid.UUID, payload: SetWrite, db: DbSession, user: CurrentUser
) -> SessionExerciseRead:
    item = await workout_service.add_set(db, session_exercise_id, user, payload)
    return _exercise_payload(item)


@router.put("/sets/{set_id}", response_model=SessionExerciseRead, summary="Update a set")
async def update_set(
    set_id: uuid.UUID, payload: SetWrite, db: DbSession, user: CurrentUser
) -> SessionExerciseRead:
    item = await workout_service.update_set(db, set_id, user, payload)
    return _exercise_payload(item)


@router.delete("/sets/{set_id}", response_model=SessionExerciseRead, summary="Delete a set")
async def delete_set(set_id: uuid.UUID, db: DbSession, user: CurrentUser) -> SessionExerciseRead:
    item = await workout_service.delete_set(db, set_id, user)
    return _exercise_payload(item)


records_router = APIRouter(prefix="/personal-records", tags=["workouts"])


@router.get(
    "/exercises/{exercise_id}/previous",
    summary="Your last performance of an exercise",
)
async def previous_performance(
    exercise_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> dict | None:
    return await workout_service.previous_performance(
        db, user, exercise_id, exclude_session_id=None
    )


@records_router.get("", response_model=list[PersonalRecordRead], summary="Your personal records")
async def list_records(
    db: DbSession,
    user: CurrentUser,
    exercise_id: uuid.UUID | None = None,
    limit: int = Query(50, ge=1, le=200),
    current_only: bool = True,
) -> list[PersonalRecordRead]:
    records = await records_service.list_for_user(
        db, user.id, exercise_id=exercise_id, limit=limit, current_only=current_only
    )
    for record in records:
        await db.refresh(record, ["exercise"])
    return [PersonalRecordRead(**workout_service.serialize_record(record)) for record in records]


@records_router.post("/acknowledge", summary="Mark record celebrations as seen")
async def acknowledge_records(
    payload: ReorderRequest, db: DbSession, user: CurrentUser
) -> dict[str, int]:
    count = await records_service.acknowledge(db, user.id, [uuid.UUID(i) for i in payload.ids])
    return {"acknowledged": count}
