"""Workout program endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Query, Response, status

from app.core.deps import CurrentUser, DbSession, Pagination
from app.models.enums import ProgramStatus
from app.schemas.common import Page
from app.schemas.program import (
    DayExerciseCreate,
    DayExerciseUpdate,
    ProgramCreate,
    ProgramDuplicateRequest,
    ProgramRead,
    ProgramSummary,
    ProgramUpdate,
    ReorderRequest,
    WorkoutDayCreate,
    WorkoutDayUpdate,
)
from app.services import program_service

router = APIRouter(prefix="/programs", tags=["programs"])


def _detail(program) -> ProgramRead:  # noqa: ANN001 - SQLAlchemy model
    return ProgramRead(**program_service.serialize(program, detail=True))


@router.get("", response_model=Page[ProgramSummary], summary="List your programs")
async def list_programs(
    db: DbSession,
    user: CurrentUser,
    pagination: Pagination,
    status_filter: ProgramStatus | None = Query(None, alias="status"),
    include_templates: bool = False,
) -> Page[ProgramSummary]:
    rows, total = await program_service.list_for_user(
        db,
        user,
        pagination=pagination,
        status=status_filter.value if status_filter else None,
        include_templates=include_templates,
    )
    return Page.build(
        [ProgramSummary(**program_service.serialize(row)) for row in rows],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.get(
    "/templates", response_model=list[ProgramSummary], summary="Starter templates"
)
async def list_templates(db: DbSession, featured_only: bool = False) -> list[ProgramSummary]:
    rows = await program_service.list_templates(db, featured_only=featured_only)
    return [ProgramSummary(**program_service.serialize(row)) for row in rows]


@router.get("/active", response_model=ProgramRead | None, summary="Your active program")
async def active_program(db: DbSession, user: CurrentUser) -> ProgramRead | None:
    program = await program_service.get_active(db, user)
    return _detail(program) if program else None


@router.get("/{program_id}", response_model=ProgramRead, summary="Program detail")
async def get_program(
    program_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.get_for_user(db, program_id, user))


@router.post(
    "", response_model=ProgramRead, status_code=status.HTTP_201_CREATED,
    summary="Create a program",
)
async def create_program(
    payload: ProgramCreate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.create(db, user, payload))


@router.patch("/{program_id}", response_model=ProgramRead, summary="Edit a program")
async def update_program(
    program_id: uuid.UUID, payload: ProgramUpdate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.update(db, program_id, user, payload))


@router.post(
    "/{program_id}/duplicate",
    response_model=ProgramRead,
    status_code=status.HTTP_201_CREATED,
    summary="Clone a program or template",
)
async def duplicate_program(
    program_id: uuid.UUID,
    payload: ProgramDuplicateRequest,
    db: DbSession,
    user: CurrentUser,
) -> ProgramRead:
    return _detail(await program_service.duplicate(db, program_id, user, name=payload.name))


@router.post("/{program_id}/activate", response_model=ProgramRead, summary="Make active")
async def activate_program(
    program_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.activate(db, program_id, user))


@router.post("/{program_id}/archive", response_model=ProgramRead, summary="Archive")
async def archive_program(
    program_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.archive(db, program_id, user))


@router.delete(
    "/{program_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a program"
)
async def delete_program(
    program_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> Response:
    await program_service.delete(db, program_id, user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{program_id}/days",
    response_model=ProgramRead,
    status_code=status.HTTP_201_CREATED,
    summary="Add a workout day",
)
async def add_day(
    program_id: uuid.UUID, payload: WorkoutDayCreate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.add_day(db, program_id, user, payload))


@router.post(
    "/{program_id}/days/reorder", response_model=ProgramRead, summary="Reorder days"
)
async def reorder_days(
    program_id: uuid.UUID, payload: ReorderRequest, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.reorder_days(db, program_id, user, payload.ids))


@router.patch("/days/{day_id}", response_model=ProgramRead, summary="Edit a day")
async def update_day(
    day_id: uuid.UUID, payload: WorkoutDayUpdate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.update_day(db, day_id, user, payload))


@router.delete("/days/{day_id}", response_model=ProgramRead, summary="Remove a day")
async def delete_day(day_id: uuid.UUID, db: DbSession, user: CurrentUser) -> ProgramRead:
    return _detail(await program_service.delete_day(db, day_id, user))


@router.post(
    "/days/{day_id}/exercises",
    response_model=ProgramRead,
    status_code=status.HTTP_201_CREATED,
    summary="Add an exercise to a day",
)
async def add_day_exercise(
    day_id: uuid.UUID, payload: DayExerciseCreate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.add_day_exercise(db, day_id, user, payload))


@router.post(
    "/days/{day_id}/exercises/reorder",
    response_model=ProgramRead,
    summary="Reorder a day's exercises",
)
async def reorder_day_exercises(
    day_id: uuid.UUID, payload: ReorderRequest, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(
        await program_service.reorder_day_exercises(db, day_id, user, payload.ids)
    )


@router.patch(
    "/day-exercises/{item_id}", response_model=ProgramRead, summary="Edit a prescription"
)
async def update_day_exercise(
    item_id: uuid.UUID, payload: DayExerciseUpdate, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.update_day_exercise(db, item_id, user, payload))


@router.delete(
    "/day-exercises/{item_id}", response_model=ProgramRead, summary="Remove an exercise"
)
async def remove_day_exercise(
    item_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> ProgramRead:
    return _detail(await program_service.remove_day_exercise(db, item_id, user))
