"""Admin dashboard queries.

Everything here is read-mostly and aggregate. Private user content — progress
photos above all — is exposed only as counts: administrators can see that a
user has 12 photos, never the photos themselves.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import NotFoundError, ValidationError
from app.core.redis import redis_health
from app.models.ai import AIGeneration, AIMessage
from app.models.body import ProgressPhoto
from app.models.enums import SessionStatus, UserRole, UserStatus
from app.models.exercise import ExerciseMedia
from app.models.program import WorkoutProgram
from app.models.user import AuditLog, User, UserSession
from app.models.workout import WorkoutSession
from app.schemas.admin import AdminUserUpdate
from app.schemas.common import PaginationParams
from app.services import audit
from app.storage import get_storage

_STARTED_AT = datetime.now(UTC)


def _day_series(rows: list[tuple[Any, int]], days: int) -> list[dict[str, Any]]:
    """Fill missing days with zero so charts don't have holes."""
    by_day = {str(day): int(count) for day, count in rows}
    today = date.today()
    return [
        {
            "day": today - timedelta(days=offset),
            "value": float(by_day.get((today - timedelta(days=offset)).isoformat(), 0)),
        }
        for offset in range(days - 1, -1, -1)
    ]


async def overview(db: AsyncSession) -> dict[str, Any]:
    now = datetime.now(UTC)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)
    day_ago = now - timedelta(days=1)

    async def count(model: Any, *conditions: Any) -> int:
        return int(
            await db.scalar(select(func.count()).select_from(model).where(*conditions)) or 0
        )

    total_users = await count(User, User.is_deleted.is_(False))
    active_7d = int(
        await db.scalar(
            select(func.count(func.distinct(UserSession.user_id))).where(
                UserSession.last_used_at >= week_ago
            )
        )
        or 0
    )
    active_30d = int(
        await db.scalar(
            select(func.count(func.distinct(UserSession.user_id))).where(
                UserSession.last_used_at >= month_ago
            )
        )
        or 0
    )

    registrations = await db.execute(
        select(func.date(User.created_at), func.count())
        .where(User.created_at >= now - timedelta(days=14))
        .group_by(func.date(User.created_at))
    )
    workouts = await db.execute(
        select(func.date(WorkoutSession.completed_at), func.count())
        .where(
            WorkoutSession.completed_at >= now - timedelta(days=14),
            WorkoutSession.status == SessionStatus.COMPLETED,
        )
        .group_by(func.date(WorkoutSession.completed_at))
    )

    storage_bytes = int(
        await db.scalar(
            select(func.coalesce(func.sum(ProgressPhoto.size_bytes), 0)).where(
                ProgressPhoto.is_deleted.is_(False)
            )
        )
        or 0
    )

    return {
        "total_users": total_users,
        "active_users_7d": active_7d,
        "active_users_30d": active_30d,
        "new_registrations_7d": await count(User, User.created_at >= week_ago),
        "workouts_completed_7d": await count(
            WorkoutSession,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.completed_at >= week_ago,
        ),
        "workouts_completed_total": await count(
            WorkoutSession, WorkoutSession.status == SessionStatus.COMPLETED
        ),
        "ai_requests_7d": await count(AIGeneration, AIGeneration.created_at >= week_ago),
        "ai_tokens_7d": int(
            await db.scalar(
                select(
                    func.coalesce(
                        func.sum(AIGeneration.input_tokens + AIGeneration.output_tokens), 0
                    )
                ).where(AIGeneration.created_at >= week_ago)
            )
            or 0
        ),
        "photos_uploaded_7d": await count(
            ProgressPhoto, ProgressPhoto.created_at >= week_ago
        ),
        "storage_bytes_used": storage_bytes,
        "api_errors_24h": await count(
            AuditLog, AuditLog.action == "api.error", AuditLog.created_at >= day_ago
        ),
        "registrations_series": _day_series(list(registrations), 14),
        "workouts_series": _day_series(list(workouts), 14),
    }


async def list_users(
    db: AsyncSession,
    *,
    pagination: PaginationParams,
    query: str | None = None,
    status: str | None = None,
    role: str | None = None,
) -> tuple[list[dict[str, Any]], int]:
    base = select(User).where(User.is_deleted.is_(False))
    if query:
        needle = f"%{query.strip().lower()}%"
        base = base.where(
            or_(func.lower(User.email).like(needle), func.lower(User.full_name).like(needle))
        )
    if status:
        base = base.where(User.status == status)
    if role:
        base = base.where(User.role == role)

    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    users = list(
        await db.scalars(
            base.order_by(User.created_at.desc())
            .offset(pagination.offset)
            .limit(pagination.per_page)
        )
    )
    if not users:
        return [], total

    counts = {
        user_id: int(count)
        for user_id, count in await db.execute(
            select(WorkoutSession.user_id, func.count())
            .where(
                WorkoutSession.user_id.in_([u.id for u in users]),
                WorkoutSession.status == SessionStatus.COMPLETED,
            )
            .group_by(WorkoutSession.user_id)
        )
    }
    return [_user_row(user, counts.get(user.id, 0)) for user in users], total


def _user_row(user: User, workout_count: int) -> dict[str, Any]:
    return {
        "id": str(user.id),
        "email": user.email,
        "full_name": user.full_name,
        "role": user.role,
        "status": user.status,
        "email_verified": user.email_verified,
        "onboarding_completed": user.onboarding_completed,
        "subscription_tier": user.subscription_tier,
        "workout_count": workout_count,
        "last_login_at": user.last_login_at,
        "created_at": user.created_at,
    }


async def get_user(db: AsyncSession, user_id: uuid.UUID) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None or user.is_deleted:
        raise NotFoundError("We couldn't find that user.")

    async def count(model: Any, *conditions: Any) -> int:
        return int(
            await db.scalar(select(func.count()).select_from(model).where(*conditions)) or 0
        )

    row = _user_row(
        user,
        await count(
            WorkoutSession,
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
        ),
    )
    row.update(
        {
            "locale": user.locale,
            "timezone": user.timezone,
            # Counts only: an admin must never be able to browse these.
            "progress_photo_count": await count(
                ProgressPhoto,
                ProgressPhoto.user_id == user.id,
                ProgressPhoto.is_deleted.is_(False),
            ),
            "ai_message_count": int(
                await db.scalar(
                    select(func.count())
                    .select_from(AIMessage)
                    .join(
                        AIGeneration,
                        AIGeneration.user_id == user.id,
                        isouter=True,
                    )
                    .where(AIMessage.role == "user")
                )
                or 0
            ),
            "session_count": await count(
                UserSession,
                UserSession.user_id == user.id,
                UserSession.revoked_at.is_(None),
            ),
        }
    )
    return row


async def update_user(
    db: AsyncSession, *, actor: User, user_id: uuid.UUID, data: AdminUserUpdate
) -> dict[str, Any]:
    user = await db.get(User, user_id)
    if user is None or user.is_deleted:
        raise NotFoundError("We couldn't find that user.")
    if user.id == actor.id and data.role and data.role != UserRole.ADMIN:
        raise ValidationError("You can't remove your own administrator access.")

    changes = data.model_dump(exclude_unset=True, exclude={"note"})
    for field, value in changes.items():
        setattr(user, field, value)

    if data.status == UserStatus.SUSPENDED:
        from sqlalchemy import update as sa_update

        await db.execute(
            sa_update(UserSession)
            .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
            .values(revoked_at=datetime.now(UTC))
        )

    await audit.record(
        db,
        action="admin.user_updated",
        actor_id=actor.id,
        entity_type="user",
        entity_id=user.id,
        metadata=changes,
        note=data.note,
    )
    await db.commit()
    return await get_user(db, user.id)


async def audit_logs(
    db: AsyncSession, *, pagination: PaginationParams, action: str | None = None
) -> tuple[list[dict[str, Any]], int]:
    base = select(AuditLog)
    if action:
        base = base.where(AuditLog.action == action)
    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    rows = list(
        await db.scalars(
            base.order_by(AuditLog.created_at.desc())
            .offset(pagination.offset)
            .limit(pagination.per_page)
        )
    )
    actor_ids = [row.actor_id for row in rows if row.actor_id]
    emails: dict[uuid.UUID, str] = {}
    if actor_ids:
        emails = dict(
            await db.execute(select(User.id, User.email).where(User.id.in_(actor_ids)))
        )
    return (
        [
            {
                "id": str(row.id),
                "actor_id": str(row.actor_id) if row.actor_id else None,
                "actor_email": emails.get(row.actor_id) if row.actor_id else None,
                "action": row.action,
                "entity_type": row.entity_type,
                "entity_id": row.entity_id,
                "ip_address": row.ip_address,
                "metadata_json": row.metadata_json or {},
                "note": row.note,
                "created_at": row.created_at,
            }
            for row in rows
        ],
        total,
    )


async def storage_stats(db: AsyncSession) -> dict[str, Any]:
    photo_count = int(
        await db.scalar(
            select(func.count())
            .select_from(ProgressPhoto)
            .where(ProgressPhoto.is_deleted.is_(False))
        )
        or 0
    )
    photo_bytes = int(
        await db.scalar(
            select(func.coalesce(func.sum(ProgressPhoto.size_bytes), 0)).where(
                ProgressPhoto.is_deleted.is_(False)
            )
        )
        or 0
    )
    media_count = int(
        await db.scalar(select(func.count()).select_from(ExerciseMedia)) or 0
    )
    avatars = int(
        await db.scalar(
            select(func.count()).select_from(User).where(User.avatar_key.is_not(None))
        )
        or 0
    )
    return {
        "backend": get_storage().name,
        "progress_photos": photo_count,
        "progress_photo_bytes": photo_bytes,
        "exercise_media": media_count,
        "avatars": avatars,
        "total_bytes": photo_bytes,
    }


async def system_health(db: AsyncSession) -> dict[str, Any]:
    database = "ok"
    try:
        await db.execute(select(1))
    except Exception:
        database = "unavailable"

    storage = await get_storage().health()
    redis_state = await redis_health()
    return {
        "api": "ok",
        "database": database,
        "redis": redis_state,
        "storage": storage,
        # The worker shares the Redis instance; a live queue means it can run.
        "worker": "ok" if redis_state == "ok" else "unknown",
        "version": settings.PROJECT_NAME,
        "environment": settings.ENVIRONMENT,
        "uptime_seconds": round((datetime.now(UTC) - _STARTED_AT).total_seconds(), 1),
        "checked_at": datetime.now(UTC),
    }


async def set_template_featured(
    db: AsyncSession, *, actor: User, program_id: uuid.UUID, is_featured: bool
) -> WorkoutProgram:
    program = await db.get(WorkoutProgram, program_id)
    if program is None or not program.is_template:
        raise NotFoundError("We couldn't find that template.")
    program.is_featured = is_featured
    await audit.record(
        db,
        action="admin.template_featured",
        actor_id=actor.id,
        entity_type="workout_program",
        entity_id=program.id,
        metadata={"is_featured": is_featured},
    )
    await db.commit()
    return program
