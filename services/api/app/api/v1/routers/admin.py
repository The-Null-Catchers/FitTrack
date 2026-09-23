"""Admin dashboard endpoints.

Every route requires the ``admin`` role. Private user content is never exposed
here — only aggregates and counts.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query

from app.core.deps import AdminUser, DbSession, Pagination
from app.models.enums import UserRole, UserStatus
from app.schemas.admin import (
    AdminAIUsageRow,
    AdminAuditLogRow,
    AdminOverview,
    AdminStorageStats,
    AdminTemplateFeatureRequest,
    AdminUserDetail,
    AdminUserRow,
    AdminUserUpdate,
    SystemHealth,
)
from app.schemas.common import Page
from app.schemas.exercise import ExerciseCreate, ExerciseRead, ExerciseUpdate
from app.schemas.program import ProgramSummary
from app.services import admin_service, ai_service, exercise_service, program_service

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/overview", response_model=AdminOverview, summary="Dashboard metrics")
async def overview(db: DbSession, _: AdminUser) -> AdminOverview:
    return AdminOverview(**await admin_service.overview(db))


@router.get("/users", response_model=Page[AdminUserRow], summary="List users")
async def list_users(
    db: DbSession,
    _: AdminUser,
    pagination: Pagination,
    q: Annotated[str | None, Query(max_length=120)] = None,
    status: UserStatus | None = None,
    role: UserRole | None = None,
) -> Page[AdminUserRow]:
    rows, total = await admin_service.list_users(
        db,
        pagination=pagination,
        query=q,
        status=status.value if status else None,
        role=role.value if role else None,
    )
    return Page.build(
        [AdminUserRow(**row) for row in rows],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.get("/users/{user_id}", response_model=AdminUserDetail, summary="User detail")
async def get_user(user_id: uuid.UUID, db: DbSession, _: AdminUser) -> AdminUserDetail:
    return AdminUserDetail(**await admin_service.get_user(db, user_id))


@router.patch(
    "/users/{user_id}", response_model=AdminUserDetail, summary="Update a user's status/role"
)
async def update_user(
    user_id: uuid.UUID, payload: AdminUserUpdate, db: DbSession, admin: AdminUser
) -> AdminUserDetail:
    return AdminUserDetail(
        **await admin_service.update_user(db, actor=admin, user_id=user_id, data=payload)
    )


@router.post("/exercises", response_model=ExerciseRead, summary="Publish a library exercise")
async def create_exercise(payload: ExerciseCreate, db: DbSession, admin: AdminUser) -> ExerciseRead:
    exercise = await exercise_service.create(db, payload, user=admin, as_public=True)
    return ExerciseRead(**exercise_service.serialize(exercise, detail=True))


@router.patch(
    "/exercises/{exercise_id}",
    response_model=ExerciseRead,
    summary="Edit a library exercise",
)
async def update_exercise(
    exercise_id: uuid.UUID, payload: ExerciseUpdate, db: DbSession, admin: AdminUser
) -> ExerciseRead:
    exercise = await exercise_service.update(db, exercise_id, payload, user=admin)
    return ExerciseRead(**exercise_service.serialize(exercise, detail=True))


@router.get("/templates", response_model=list[ProgramSummary], summary="Workout templates")
async def list_templates(db: DbSession, _: AdminUser) -> list[ProgramSummary]:
    rows = await program_service.list_templates(db)
    return [ProgramSummary(**program_service.serialize(row)) for row in rows]


@router.post(
    "/templates/{program_id}/feature",
    response_model=ProgramSummary,
    summary="Feature or unfeature a template",
)
async def feature_template(
    program_id: uuid.UUID,
    payload: AdminTemplateFeatureRequest,
    db: DbSession,
    admin: AdminUser,
) -> ProgramSummary:
    program = await admin_service.set_template_featured(
        db, actor=admin, program_id=program_id, is_featured=payload.is_featured
    )
    full = await program_service._load(db, program.id)
    return ProgramSummary(**program_service.serialize(full))


@router.get("/ai-usage", response_model=list[AdminAIUsageRow], summary="AI usage")
async def ai_usage(
    db: DbSession, _: AdminUser, days: int = Query(14, ge=1, le=90)
) -> list[AdminAIUsageRow]:
    return [AdminAIUsageRow(**row) for row in await ai_service.admin_usage_rows(db, days=days)]


@router.get("/storage", response_model=AdminStorageStats, summary="Storage usage")
async def storage(db: DbSession, _: AdminUser) -> AdminStorageStats:
    return AdminStorageStats(**await admin_service.storage_stats(db))


@router.get("/health", response_model=SystemHealth, summary="System health")
async def health(db: DbSession, _: AdminUser) -> SystemHealth:
    return SystemHealth(**await admin_service.system_health(db))


@router.get("/audit-logs", response_model=Page[AdminAuditLogRow], summary="Audit log")
async def audit_logs(
    db: DbSession,
    _: AdminUser,
    pagination: Pagination,
    action: Annotated[str | None, Query(max_length=64)] = None,
) -> Page[AdminAuditLogRow]:
    rows, total = await admin_service.audit_logs(db, pagination=pagination, action=action)
    return Page.build(
        [AdminAuditLogRow(**row) for row in rows],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )
