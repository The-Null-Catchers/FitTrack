"""HTTP middleware: request ids, access logs, security headers."""

from __future__ import annotations

import time
import uuid

import structlog
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("api.access")

#: Paths whose access logs add nothing but noise.
_QUIET_PATHS = {"/health", "/ready", "/metrics"}


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assign a request id, bind it to the log context, and time the request."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        request.state.request_id = request_id
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        started = time.perf_counter()
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - started) * 1000, 2)

        response.headers["X-Request-ID"] = request_id
        response.headers["X-Response-Time-ms"] = str(duration_ms)

        if request.url.path not in _QUIET_PATHS:
            logger.info(
                "http.request",
                method=request.method,
                path=request.url.path,
                status=response.status_code,
                duration_ms=duration_ms,
                user_id=getattr(request.state, "user_id", None),
            )
        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy", "geolocation=(), microphone=(), camera=()"
        )
        response.headers.setdefault("Cross-Origin-Resource-Policy", "same-site")
        if settings.is_production:
            response.headers.setdefault(
                "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
            )
        return response
