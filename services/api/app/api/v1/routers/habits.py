"""Habit endpoints."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Response, status

from app.core.deps import CurrentUser, DbSession
from app.schemas.habit import (
    HabitCreate,
    HabitLogRead,
    HabitLogWrite,
    HabitRead,
    HabitUpdate,
)
from app.services import habit_service

router = APIRouter(prefix="/habits", tags=["habits"])


@router.get("", response_model=list[HabitRead], summary="Your habits")
async def list_habits(
    db: DbSession,
    user: CurrentUser,
    include_archived: bool = False,
    on: date | None = None,
) -> list[HabitRead]:
    rows = await habit_service.list_habits(db, user, include_archived=include_archived, on=on)
    return [HabitRead(**row) for row in rows]


@router.post(
    "",
    response_model=HabitRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a habit",
)
async def create_habit(payload: HabitCreate, db: DbSession, user: CurrentUser) -> HabitRead:
    habit = await habit_service.create(db, user, payload)
    return HabitRead(**habit_service.serialize(habit))


@router.patch("/{habit_id}", response_model=HabitRead, summary="Edit a habit")
async def update_habit(
    habit_id: uuid.UUID, payload: HabitUpdate, db: DbSession, user: CurrentUser
) -> HabitRead:
    habit = await habit_service.update(db, user, habit_id, payload)
    return HabitRead(**habit_service.serialize(habit))


@router.delete("/{habit_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a habit")
async def delete_habit(habit_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await habit_service.delete(db, user, habit_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{habit_id}/log", response_model=HabitRead, summary="Log a completion")
async def log_habit(
    habit_id: uuid.UUID, payload: HabitLogWrite, db: DbSession, user: CurrentUser
) -> HabitRead:
    habit, entry = await habit_service.log(db, user, habit_id, payload)
    return HabitRead(**habit_service.serialize(habit, today=entry))


@router.delete("/{habit_id}/log", response_model=HabitRead, summary="Undo a completion")
async def unlog_habit(
    habit_id: uuid.UUID, db: DbSession, user: CurrentUser, on: date | None = None
) -> HabitRead:
    habit = await habit_service.unlog(db, user, habit_id, on or date.today())
    return HabitRead(**habit_service.serialize(habit))


@router.get("/{habit_id}/history", response_model=list[HabitLogRead], summary="Completion history")
async def habit_history(
    habit_id: uuid.UUID,
    db: DbSession,
    user: CurrentUser,
    start_date: date | None = None,
    end_date: date | None = None,
) -> list[HabitLogRead]:
    end = end_date or date.today()
    start = start_date or (end - timedelta(days=89))
    rows = await habit_service.history(db, user, habit_id, start=start, end=end)
    return [
        HabitLogRead(
            id=str(row.id),
            habit_id=str(row.habit_id),
            logged_on=row.logged_on,
            count=row.count,
            value=row.value,
            is_completed=row.is_completed,
        )
        for row in rows
    ]
