"""Goal endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Query, Response, status

from app.core.deps import CurrentUser, DbSession
from app.models.enums import GoalStatus
from app.schemas.goal import GoalCreate, GoalRead, GoalUpdate
from app.services import goal_service

router = APIRouter(prefix="/goals", tags=["goals"])


@router.get("", response_model=list[GoalRead], summary="Your goals")
async def list_goals(
    db: DbSession,
    user: CurrentUser,
    status_filter: GoalStatus | None = Query(None, alias="status"),
) -> list[GoalRead]:
    goals = await goal_service.list_goals(
        db, user, status=status_filter.value if status_filter else None
    )
    return [GoalRead(**row) for row in await goal_service.serialize_many(db, goals)]


@router.post(
    "", response_model=GoalRead, status_code=status.HTTP_201_CREATED, summary="Create a goal"
)
async def create_goal(payload: GoalCreate, db: DbSession, user: CurrentUser) -> GoalRead:
    goal = await goal_service.create(db, user, payload)
    return GoalRead(**(await goal_service.serialize_many(db, [goal]))[0])


@router.get("/{goal_id}", response_model=GoalRead, summary="Goal detail")
async def get_goal(goal_id: uuid.UUID, db: DbSession, user: CurrentUser) -> GoalRead:
    goal = await goal_service.get(db, user, goal_id)
    await goal_service.refresh_progress(db, user, goal)
    await db.commit()
    return GoalRead(**(await goal_service.serialize_many(db, [goal]))[0])


@router.patch("/{goal_id}", response_model=GoalRead, summary="Edit a goal")
async def update_goal(
    goal_id: uuid.UUID, payload: GoalUpdate, db: DbSession, user: CurrentUser
) -> GoalRead:
    goal = await goal_service.update(db, user, goal_id, payload)
    return GoalRead(**(await goal_service.serialize_many(db, [goal]))[0])


@router.delete(
    "/{goal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a goal"
)
async def delete_goal(goal_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await goal_service.delete(db, user, goal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
