"""FitTrack API application factory."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi

from app.api.v1 import api_router
from app.api.v1.routers import health, media
from app.core.config import settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging, get_logger
from app.core.middleware import RequestContextMiddleware, SecurityHeadersMiddleware
from app.core.redis import close_redis

logger = get_logger(__name__)

DESCRIPTION = """
FitTrack is a fitness and nutrition tracking platform: workouts, programs,
nutrition, body metrics, goals, habits and an AI coach.

**Authentication** — all endpoints except `/health`, `/ready` and the public
parts of the exercise library require a bearer access token obtained from
`/api/v1/auth/login`. Access tokens are short-lived; use
`/api/v1/auth/refresh` to rotate them.

**Errors** — every failure returns the same envelope:
`{"error": {"code", "message", "details", "request_id"}}`. The `message` is
written for end users and can be shown as-is.

**Pagination** — list endpoints accept `page` and `per_page` and return
`{"items": [...], "meta": {...}}`.
"""


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    configure_logging()
    logger.info(
        "api.startup",
        environment=settings.ENVIRONMENT,
        storage=settings.STORAGE_BACKEND,
        ai_provider=settings.AI_PROVIDER,
    )
    yield
    await close_redis()
    logger.info("api.shutdown")


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.PROJECT_NAME,
        description=DESCRIPTION,
        version="1.0.0",
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
        lifespan=lifespan,
        contact={"name": "FitTrack", "url": "https://github.com/Archipelago-alt/FitTrack"},
        license_info={"name": "MIT"},
    )

    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID", "Accept-Language"],
        expose_headers=["X-Request-ID"],
        max_age=600,
    )

    register_exception_handlers(app)

    app.include_router(health.router)
    app.include_router(api_router, prefix=settings.API_V1_PREFIX)
    if settings.STORAGE_BACKEND == "local":
        app.include_router(media.router)

    app.openapi = _openapi_factory(app)  # type: ignore[method-assign]
    return app


def _openapi_factory(app: FastAPI):  # noqa: ANN202 - FastAPI hook
    def custom_openapi() -> dict:
        if app.openapi_schema:
            return app.openapi_schema
        schema = get_openapi(
            title=app.title,
            version=app.version,
            description=app.description,
            routes=app.routes,
        )
        schema["components"].setdefault("securitySchemes", {})["bearerAuth"] = {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
        }
        schema["security"] = [{"bearerAuth": []}]
        app.openapi_schema = schema
        return schema

    return custom_openapi


app = create_app()
