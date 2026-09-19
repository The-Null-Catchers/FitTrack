"""Exercise library endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.core.deps import CurrentUser, DbSession, OptionalUser, Pagination
from app.models.enums import Difficulty, Equipment, ExerciseType, MuscleGroup
from app.schemas.common import Page
from app.schemas.exercise import (
    ExerciseCreate,
    ExerciseFilterOptions,
    ExerciseRead,
    ExerciseSummary,
    ExerciseUpdate,
)
from app.services import exercise_service

router = APIRouter(prefix="/exercises", tags=["exercises"])


@router.get("", response_model=Page[ExerciseSummary], summary="Search the exercise library")
async def list_exercises(
    db: DbSession,
    pagination: Pagination,
    user: OptionalUser,
    q: Annotated[str | None, Query(description="Free-text search", max_length=120)] = None,
    muscle_group: MuscleGroup | None = None,
    equipment: Equipment | None = None,
    difficulty: Difficulty | None = None,
    exercise_type: ExerciseType | None = None,
    sort: Annotated[str, Query(pattern="^(popular|name|newest)$")] = "popular",
) -> Page[ExerciseSummary]:
    rows, total = await exercise_service.search(
        db,
        user=user,
        pagination=pagination,
        query=q,
        muscle_group=muscle_group.value if muscle_group else None,
        equipment=equipment.value if equipment else None,
        difficulty=difficulty.value if difficulty else None,
        exercise_type=exercise_type.value if exercise_type else None,
        sort=sort,
    )
    return Page.build(
        [ExerciseSummary(**exercise_service.serialize(row)) for row in rows],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.get("/filters", response_model=ExerciseFilterOptions, summary="Available filters")
async def filters() -> ExerciseFilterOptions:
    return ExerciseFilterOptions(**exercise_service.filter_options())


@router.get("/{exercise_id}", response_model=ExerciseRead, summary="Exercise detail")
async def get_exercise(exercise_id: uuid.UUID, db: DbSession, user: OptionalUser) -> ExerciseRead:
    exercise = await exercise_service.get(db, exercise_id, user=user)
    return ExerciseRead(**exercise_service.serialize(exercise, detail=True))


@router.post(
    "",
    response_model=ExerciseRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a custom exercise",
)
async def create_exercise(
    payload: ExerciseCreate, db: DbSession, user: CurrentUser
) -> ExerciseRead:
    exercise = await exercise_service.create(db, payload, user=user)
    return ExerciseRead(**exercise_service.serialize(exercise, detail=True))


@router.patch("/{exercise_id}", response_model=ExerciseRead, summary="Edit an exercise")
async def update_exercise(
    exercise_id: uuid.UUID, payload: ExerciseUpdate, db: DbSession, user: CurrentUser
) -> ExerciseRead:
    exercise = await exercise_service.update(db, exercise_id, payload, user=user)
    return ExerciseRead(**exercise_service.serialize(exercise, detail=True))


@router.delete(
    "/{exercise_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete an exercise"
)
async def delete_exercise(exercise_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await exercise_service.delete(db, exercise_id, user=user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
