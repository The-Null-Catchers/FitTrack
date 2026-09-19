"""Exercise library: search, filtering and administration."""

from __future__ import annotations

import uuid
from typing import Any

from slugify import slugify
from sqlalchemy import Select, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import ConflictError, NotFoundError, PermissionError_
from app.models.enums import Difficulty, Equipment, ExerciseType, MuscleGroup, TrackingType
from app.models.exercise import Exercise, ExerciseMedia
from app.models.user import User
from app.schemas.common import PaginationParams
from app.schemas.exercise import ExerciseCreate, ExerciseUpdate
from app.storage import get_storage


def _visible_to(user: User | None) -> Any:
    """Public library entries plus the caller's own private exercises."""
    if user is None:
        return Exercise.is_public.is_(True)
    return or_(Exercise.is_public.is_(True), Exercise.created_by_id == user.id)


def _apply_filters(
    stmt: Select,
    *,
    query: str | None,
    muscle_group: str | None,
    equipment: str | None,
    difficulty: str | None,
    exercise_type: str | None,
) -> Select:
    if query:
        needle = f"%{query.strip().lower()}%"
        stmt = stmt.where(
            or_(Exercise.search_text.like(needle), func.lower(Exercise.name).like(needle))
        )
    if muscle_group:
        stmt = stmt.where(Exercise.muscle_group == muscle_group)
    if equipment:
        stmt = stmt.where(Exercise.equipment == equipment)
    if difficulty:
        stmt = stmt.where(Exercise.difficulty == difficulty)
    if exercise_type:
        stmt = stmt.where(Exercise.exercise_type == exercise_type)
    return stmt


async def search(
    db: AsyncSession,
    *,
    user: User | None,
    pagination: PaginationParams,
    query: str | None = None,
    muscle_group: str | None = None,
    equipment: str | None = None,
    difficulty: str | None = None,
    exercise_type: str | None = None,
    sort: str = "popular",
) -> tuple[list[Exercise], int]:
    base = select(Exercise).where(Exercise.is_deleted.is_(False), _visible_to(user))
    base = _apply_filters(
        base,
        query=query,
        muscle_group=muscle_group,
        equipment=equipment,
        difficulty=difficulty,
        exercise_type=exercise_type,
    )

    total = int(
        await db.scalar(select(func.count()).select_from(base.subquery())) or 0
    )

    order = {
        "name": (Exercise.name.asc(),),
        "newest": (Exercise.created_at.desc(),),
        "popular": (Exercise.popularity.desc(), Exercise.name.asc()),
    }.get(sort, (Exercise.popularity.desc(), Exercise.name.asc()))

    rows = await db.scalars(
        base.order_by(*order).offset(pagination.offset).limit(pagination.per_page)
    )
    return list(rows), total


async def get(db: AsyncSession, exercise_id: uuid.UUID, *, user: User | None) -> Exercise:
    exercise = await db.scalar(
        select(Exercise).where(
            Exercise.id == exercise_id, Exercise.is_deleted.is_(False), _visible_to(user)
        )
    )
    if exercise is None:
        raise NotFoundError("We couldn't find that exercise.")
    return exercise


async def get_many(
    db: AsyncSession, exercise_ids: list[uuid.UUID], *, user: User | None
) -> dict[uuid.UUID, Exercise]:
    """Bulk fetch used when building programs/sessions, avoiding an N+1."""
    if not exercise_ids:
        return {}
    rows = await db.scalars(
        select(Exercise).where(
            Exercise.id.in_(exercise_ids), Exercise.is_deleted.is_(False), _visible_to(user)
        )
    )
    return {row.id: row for row in rows}


async def _unique_slug(db: AsyncSession, name: str) -> str:
    base = slugify(name)[:140] or "exercise"
    slug = base
    suffix = 2
    while await db.scalar(select(Exercise.id).where(Exercise.slug == slug)) is not None:
        slug = f"{base}-{suffix}"
        suffix += 1
    return slug


async def create(
    db: AsyncSession, data: ExerciseCreate, *, user: User, as_public: bool = False
) -> Exercise:
    if as_public and not user.is_admin:
        raise PermissionError_("Only administrators can publish library exercises.")

    exercise = Exercise(
        slug=await _unique_slug(db, data.name),
        name=data.name,
        name_ar=data.name_ar,
        description=data.description,
        instructions=data.instructions,
        muscle_group=data.muscle_group,
        secondary_muscles=[m.value for m in data.secondary_muscles],
        equipment=data.equipment,
        difficulty=data.difficulty,
        exercise_type=data.exercise_type,
        default_tracking_type=data.default_tracking_type,
        default_rest_seconds=data.default_rest_seconds,
        is_unilateral=data.is_unilateral,
        video_url=data.video_url,
        aliases=data.aliases,
        is_public=as_public,
        created_by_id=user.id,
    )
    exercise.search_text = exercise.build_search_text()
    db.add(exercise)
    await db.commit()
    await db.refresh(exercise)
    return exercise


async def update(
    db: AsyncSession, exercise_id: uuid.UUID, data: ExerciseUpdate, *, user: User
) -> Exercise:
    exercise = await get(db, exercise_id, user=user)
    if not user.is_admin and exercise.created_by_id != user.id:
        raise PermissionError_("You can only edit exercises you created.")

    values = data.model_dump(exclude_unset=True)
    if "is_public" in values and not user.is_admin:
        values.pop("is_public")
    if "secondary_muscles" in values and values["secondary_muscles"] is not None:
        values["secondary_muscles"] = [
            m.value if hasattr(m, "value") else m for m in values["secondary_muscles"]
        ]
    for field, value in values.items():
        setattr(exercise, field, value)
    exercise.search_text = exercise.build_search_text()
    await db.commit()
    await db.refresh(exercise)
    return exercise


async def delete(db: AsyncSession, exercise_id: uuid.UUID, *, user: User) -> None:
    exercise = await get(db, exercise_id, user=user)
    if not user.is_admin and exercise.created_by_id != user.id:
        raise PermissionError_("You can only delete exercises you created.")
    # Soft delete keeps historical sessions that reference this movement intact.
    exercise.soft_delete()
    await db.commit()


async def attach_media(
    db: AsyncSession,
    exercise_id: uuid.UUID,
    *,
    user: User,
    storage_key: str,
    kind: str,
    caption: str | None = None,
) -> ExerciseMedia:
    exercise = await get(db, exercise_id, user=user)
    if not user.is_admin:
        raise PermissionError_("Only administrators can manage exercise media.")
    if exercise.image_key is None:
        exercise.image_key = storage_key
    media = ExerciseMedia(
        exercise_id=exercise.id, kind=kind, storage_key=storage_key, caption=caption
    )
    db.add(media)
    await db.commit()
    await db.refresh(media)
    return media


async def bump_popularity(db: AsyncSession, exercise_ids: list[uuid.UUID]) -> None:
    """Nudge ranking whenever an exercise is actually trained."""
    if not exercise_ids:
        return
    from sqlalchemy import update as sa_update

    await db.execute(
        sa_update(Exercise)
        .where(Exercise.id.in_(exercise_ids))
        .values(popularity=Exercise.popularity + 1)
    )


def media_url(media: ExerciseMedia) -> str | None:
    if media.external_url:
        return media.external_url
    if media.storage_key:
        # Exercise media is public content and can be cached by the client.
        return get_storage().public_url(media.storage_key)
    return None


def image_url(exercise: Exercise) -> str | None:
    if not exercise.image_key:
        return None
    return get_storage().public_url(exercise.image_key)


def serialize(exercise: Exercise, *, detail: bool = False) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": str(exercise.id),
        "slug": exercise.slug,
        "name": exercise.name,
        "name_ar": exercise.name_ar,
        "muscle_group": exercise.muscle_group,
        "equipment": exercise.equipment,
        "difficulty": exercise.difficulty,
        "exercise_type": exercise.exercise_type,
        "default_tracking_type": exercise.default_tracking_type,
        "image_url": image_url(exercise),
        "is_public": exercise.is_public,
    }
    if detail:
        payload.update(
            {
                "description": exercise.description,
                "instructions": exercise.instructions,
                "secondary_muscles": exercise.secondary_muscles,
                "aliases": exercise.aliases,
                "default_rest_seconds": exercise.default_rest_seconds,
                "is_unilateral": exercise.is_unilateral,
                "video_url": exercise.video_url,
                "created_at": exercise.created_at,
                "media": [
                    {
                        "id": str(m.id),
                        "kind": m.kind,
                        "url": media_url(m),
                        "caption": m.caption,
                        "position": m.position,
                    }
                    for m in sorted(exercise.media, key=lambda m: m.position)
                ],
            }
        )
    return payload


def filter_options() -> dict[str, list[str]]:
    return {
        "muscle_groups": [m.value for m in MuscleGroup],
        "equipment": [e.value for e in Equipment],
        "difficulties": [d.value for d in Difficulty],
        "exercise_types": [t.value for t in ExerciseType],
        "tracking_types": [t.value for t in TrackingType],
    }


async def ensure_unique_name(db: AsyncSession, name: str) -> None:
    existing = await db.scalar(
        select(Exercise.id).where(func.lower(Exercise.name) == name.strip().lower())
    )
    if existing is not None:
        raise ConflictError("An exercise with that name already exists.")
