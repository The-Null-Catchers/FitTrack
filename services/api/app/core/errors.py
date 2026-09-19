"""Uniform API error handling.

Every error the API returns has the same envelope::

    {"error": {"code": "not_found", "message": "...", "details": {...},
               "request_id": "..."}}

Human-facing ``message`` values are written to be shown directly to users —
clients should never have to translate "Error 500" into something meaningful.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import get_logger

logger = get_logger(__name__)

#: Starlette renamed this constant; the numeric code is stable either way.
HTTP_422_UNPROCESSABLE = 422


class AppError(Exception):
    """Base class for all errors the application raises deliberately."""

    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "bad_request"
    message: str = "The request could not be completed."

    def __init__(
        self,
        message: str | None = None,
        *,
        code: str | None = None,
        details: dict[str, Any] | None = None,
        status_code: int | None = None,
    ) -> None:
        self.message = message or self.message
        self.code = code or self.code
        self.details = details or {}
        self.status_code = status_code or self.status_code
        super().__init__(self.message)


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "not_found"
    message = "We couldn't find what you were looking for."


class ValidationError(AppError):
    status_code = HTTP_422_UNPROCESSABLE
    code = "validation_error"
    message = "Some of the information you entered isn't valid."


class ConflictError(AppError):
    status_code = status.HTTP_409_CONFLICT
    code = "conflict"
    message = "That action conflicts with data that already exists."


class AuthenticationError(AppError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = "unauthenticated"
    message = "Please sign in to continue."


class PermissionError_(AppError):
    status_code = status.HTTP_403_FORBIDDEN
    code = "forbidden"
    message = "You don't have access to this resource."


class RateLimitError(AppError):
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    code = "rate_limited"
    message = "You're doing that a little too often. Please try again shortly."


class ServiceUnavailableError(AppError):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    code = "service_unavailable"
    message = "That service is temporarily unavailable. Please try again."


def error_payload(
    code: str, message: str, details: dict[str, Any] | None, request_id: str | None
) -> dict[str, Any]:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
            "request_id": request_id,
        }
    }


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=error_payload(
                exc.code, exc.message, exc.details, getattr(request.state, "request_id", None)
            ),
            headers=({"Retry-After": "60"} if isinstance(exc, RateLimitError) else None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError) -> JSONResponse:
        fields: dict[str, str] = {}
        for err in exc.errors():
            location = ".".join(str(part) for part in err["loc"][1:]) or "body"
            fields[location] = err["msg"]
        return JSONResponse(
            status_code=HTTP_422_UNPROCESSABLE,
            content=error_payload(
                "validation_error",
                "Some of the information you entered isn't valid.",
                {"fields": fields},
                getattr(request.state, "request_id", None),
            ),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        codes = {
            401: "unauthenticated",
            403: "forbidden",
            404: "not_found",
            405: "method_not_allowed",
            429: "rate_limited",
        }
        return JSONResponse(
            status_code=exc.status_code,
            content=error_payload(
                codes.get(exc.status_code, "http_error"),
                str(exc.detail),
                None,
                getattr(request.state, "request_id", None),
            ),
            headers=exc.headers,
        )

    @app.exception_handler(IntegrityError)
    async def _integrity(request: Request, exc: IntegrityError) -> JSONResponse:
        logger.warning("db.integrity_error", error=str(exc.orig))
        return JSONResponse(
            status_code=status.HTTP_409_CONFLICT,
            content=error_payload(
                "conflict",
                "That action conflicts with data that already exists.",
                None,
                getattr(request.state, "request_id", None),
            ),
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("api.unhandled_error", path=request.url.path)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=error_payload(
                "internal_error",
                "Something went wrong on our end. Please try again.",
                None,
                getattr(request.state, "request_id", None),
            ),
        )
