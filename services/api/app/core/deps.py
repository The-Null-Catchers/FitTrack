"""Shared FastAPI dependencies."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AuthenticationError, PermissionError_
from app.core.security import decode_token
from app.db.session import get_db
from app.models.enums import UserStatus
from app.models.user import User
from app.schemas.common import PaginationParams

bearer_scheme = HTTPBearer(auto_error=False, description="Access token")

DbSession = Annotated[AsyncSession, Depends(get_db)]


async def get_current_user(
    request: Request,
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)] = None,
) -> User:
    if credentials is None or not credentials.credentials:
        raise AuthenticationError()

    payload = decode_token(credentials.credentials, expected_type="access")
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError) as exc:
        raise AuthenticationError("That sign-in token isn't valid.") from exc

    user = await db.scalar(select(User).where(User.id == user_id, User.is_deleted.is_(False)))
    if user is None:
        raise AuthenticationError("That account is no longer available.")
    if user.status == UserStatus.SUSPENDED:
        raise PermissionError_(
            "This account has been suspended. Contact support if you think this is a mistake.",
            code="account_suspended",
        )

    request.state.user_id = str(user.id)
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_current_admin(user: CurrentUser) -> User:
    if not user.is_admin:
        raise PermissionError_("This area is restricted to administrators.")
    return user


AdminUser = Annotated[User, Depends(get_current_admin)]


async def get_optional_user(
    request: Request,
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)] = None,
) -> User | None:
    """For endpoints that personalise results but also serve anonymous callers."""
    if credentials is None or not credentials.credentials:
        return None
    try:
        return await get_current_user(request, db, credentials)
    except (AuthenticationError, PermissionError_):
        return None


OptionalUser = Annotated[User | None, Depends(get_optional_user)]


def pagination(
    page: Annotated[int, Query(ge=1, description="1-based page number")] = 1,
    per_page: Annotated[int, Query(ge=1, le=100, description="Items per page")] = 20,
) -> PaginationParams:
    return PaginationParams(page=page, per_page=per_page)


Pagination = Annotated[PaginationParams, Depends(pagination)]


def client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else None
