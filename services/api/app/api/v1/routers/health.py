"""Liveness and readiness probes."""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.config import settings
from app.core.deps import DbSession
from app.core.redis import redis_health
from app.schemas.common import HealthResponse, ReadinessResponse
from app.storage import get_storage

router = APIRouter(tags=["health"])

VERSION = "1.0.0"


@router.get("/health", response_model=HealthResponse, summary="Liveness probe")
async def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        version=VERSION,
        environment=settings.ENVIRONMENT,
        time=datetime.now(UTC),
    )


@router.get("/ready", response_model=ReadinessResponse, summary="Readiness probe")
async def ready(db: DbSession, response: Response) -> ReadinessResponse:
    checks = {"database": "ok", "redis": "ok", "storage": "ok"}
    try:
        await db.execute(text("SELECT 1"))
    except Exception:
        checks["database"] = "unavailable"

    checks["redis"] = await redis_health()
    checks["storage"] = await get_storage().health()

    # Redis is a soft dependency: the API still serves without it.
    ready_state = "ok" if checks["database"] == "ok" else "degraded"
    if ready_state != "ok":
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return ReadinessResponse(status=ready_state, checks=checks)
