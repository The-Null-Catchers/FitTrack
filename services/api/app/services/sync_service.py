"""Offline sync: idempotent push of queued client mutations, and delta pull.

Every queued mutation carries a ``client_uuid`` generated on the device. That
id is the idempotency key: applying the same operation twice returns the first
result instead of creating a duplicate row, which is what makes a flaky mobile
connection safe to retry.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.logging import get_logger
from app.db.types import normalize_datetime_param
from app.models.body import BodyMeasurement, BodyWeight
from app.models.habit import HabitLog
from app.models.nutrition import Meal, WaterLog
from app.models.sync import SyncOperation
from app.models.user import User
from app.models.workout import WorkoutSession
from app.schemas.body import BodyWeightWrite, MeasurementWrite
from app.schemas.habit import HabitLogWrite
from app.schemas.nutrition import MealCreate, WaterLogWrite
from app.schemas.sync import SyncOperationIn, SyncPushRequest
from app.schemas.workout import SessionFinishRequest, SessionStartRequest
from app.services import body_service, habit_service, nutrition_service, workout_service

logger = get_logger(__name__)

#: Cap on rows returned per entity in a single pull.
PULL_LIMIT = 500


async def _already_applied(db: AsyncSession, user: User, client_uuid: str) -> SyncOperation | None:
    return await db.scalar(
        select(SyncOperation).where(
            SyncOperation.user_id == user.id, SyncOperation.client_uuid == client_uuid
        )
    )


async def _apply(
    db: AsyncSession, user: User, operation: SyncOperationIn
) -> tuple[str, str | None]:
    """Apply one operation, returning ``(status, server_id)``."""
    payload = dict(operation.payload)
    payload.setdefault("client_uuid", operation.client_uuid)

    if operation.entity == "workout_session":
        return await _apply_workout_session(db, user, payload)

    if operation.entity == "body_weight":
        entry = await body_service.record_weight(db, user, BodyWeightWrite(**payload))
        return "applied", str(entry.id)

    if operation.entity == "body_measurement":
        entry = await body_service.record_measurement(db, user, MeasurementWrite(**payload))
        return "applied", str(entry.id)

    if operation.entity == "meal":
        meal = await nutrition_service.create_meal(db, user, MealCreate(**payload))
        return "applied", str(meal.id)

    if operation.entity == "water_log":
        await nutrition_service.log_water(db, user, WaterLogWrite(**payload))
        return "applied", None

    if operation.entity == "habit_log":
        habit_id = payload.pop("habit_id", None)
        if not habit_id:
            raise AppError("A habit log needs a habit_id.", code="missing_habit_id")
        import uuid as _uuid

        _, entry = await habit_service.log(
            db, user, _uuid.UUID(str(habit_id)), HabitLogWrite(**payload)
        )
        return "applied", str(entry.id)

    raise AppError(f"Unsupported entity: {operation.entity}", code="unsupported_entity")


async def _apply_workout_session(
    db: AsyncSession, user: User, payload: dict[str, Any]
) -> tuple[str, str | None]:
    """Create-or-finish a session recorded offline.

    The device sends the full session (exercises + sets) once it is finished, so
    the server starts it and immediately applies the finish in one step.
    """
    exercises = payload.pop("exercises", None)
    finished = payload.pop("finished", True)
    completed_at = payload.pop("completed_at", None)
    duration_seconds = payload.pop("duration_seconds", None)
    notes = payload.pop("notes", None)
    perceived_effort = payload.pop("perceived_effort", None)

    start_payload = {
        key: payload[key]
        for key in ("program_id", "day_id", "name", "started_at", "client_uuid")
        if key in payload
    }
    session, created = await workout_service.start(db, user, SessionStartRequest(**start_payload))

    if not finished:
        return ("applied" if created else "duplicate"), str(session.id)

    if session.status == "completed" and not created:
        return "duplicate", str(session.id)

    session, _records = await workout_service.finish(
        db,
        session.id,
        user,
        SessionFinishRequest(
            completed_at=completed_at,
            duration_seconds=duration_seconds,
            notes=notes,
            perceived_effort=perceived_effort,
            exercises=exercises,
        ),
    )
    return ("applied" if created else "duplicate"), str(session.id)


async def push(db: AsyncSession, user: User, request: SyncPushRequest) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    applied = duplicates = failed = 0

    for operation in request.operations:
        existing = await _already_applied(db, user, operation.client_uuid)
        if existing is not None:
            duplicates += 1
            results.append(
                {
                    "client_uuid": operation.client_uuid,
                    "entity": operation.entity,
                    "status": "duplicate",
                    "server_id": existing.server_id,
                    "message": "This change was already synced.",
                }
            )
            continue

        try:
            status, server_id = await _apply(db, user, operation)
        except AppError as exc:
            failed += 1
            logger.info(
                "sync.operation_failed",
                entity=operation.entity,
                code=exc.code,
            )
            results.append(
                {
                    "client_uuid": operation.client_uuid,
                    "entity": operation.entity,
                    "status": "failed",
                    "server_id": None,
                    "message": exc.message,
                }
            )
            continue
        except Exception:
            failed += 1
            logger.exception("sync.operation_error", entity=operation.entity)
            await db.rollback()
            results.append(
                {
                    "client_uuid": operation.client_uuid,
                    "entity": operation.entity,
                    "status": "failed",
                    "server_id": None,
                    "message": "We couldn't sync this change. It will be retried.",
                }
            )
            continue

        db.add(
            SyncOperation(
                user_id=user.id,
                client_uuid=operation.client_uuid,
                entity_type=operation.entity,
                operation=operation.operation,
                status=status,
                server_id=server_id,
            )
        )
        await db.commit()

        if status == "duplicate":
            duplicates += 1
        else:
            applied += 1
        results.append(
            {
                "client_uuid": operation.client_uuid,
                "entity": operation.entity,
                "status": status,
                "server_id": server_id,
                "message": None,
            }
        )

    return {
        "results": results,
        "applied": applied,
        "duplicates": duplicates,
        "failed": failed,
        "server_time": datetime.now(UTC),
    }


def _rows(model: Any, instances: list[Any]) -> list[dict[str, Any]]:
    import datetime as _dt
    import uuid as _uuid

    def value(item: Any) -> Any:
        if isinstance(item, _uuid.UUID):
            return str(item)
        if isinstance(item, _dt.datetime | _dt.date):
            return item.isoformat()
        return item

    return [
        {column.key: value(getattr(row, column.key)) for column in model.__table__.columns}
        for row in instances
    ]


async def pull(db: AsyncSession, user: User, *, since: datetime | None) -> dict[str, Any]:
    """Everything that changed server-side since ``since``."""

    cutoff = normalize_datetime_param(db, since)

    async def changed(model: Any) -> list[Any]:
        stmt = select(model).where(model.user_id == user.id)
        if cutoff is not None:
            stmt = stmt.where(model.updated_at > cutoff)
        return list(await db.scalars(stmt.order_by(model.updated_at).limit(PULL_LIMIT)))

    sessions = await changed(WorkoutSession)
    weights = await changed(BodyWeight)
    measurements = await changed(BodyMeasurement)
    meals = await changed(Meal)
    water = await changed(WaterLog)
    habit_logs = await changed(HabitLog)

    has_more = any(
        len(rows) >= PULL_LIMIT
        for rows in (sessions, weights, measurements, meals, water, habit_logs)
    )

    return {
        "since": since,
        "server_time": datetime.now(UTC),
        "workout_sessions": _rows(WorkoutSession, sessions),
        "body_weights": _rows(BodyWeight, weights),
        "body_measurements": _rows(BodyMeasurement, measurements),
        "meals": _rows(Meal, meals),
        "water_logs": _rows(WaterLog, water),
        "habit_logs": _rows(HabitLog, habit_logs),
        "has_more": has_more,
    }
