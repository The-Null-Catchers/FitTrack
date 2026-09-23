"""Offline sync endpoints."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter

from app.core.deps import CurrentUser, DbSession
from app.schemas.sync import SyncPullResponse, SyncPushRequest, SyncPushResponse
from app.services import sync_service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post(
    "/push",
    response_model=SyncPushResponse,
    summary="Push queued offline changes",
    description=(
        "Each operation carries a client-generated `client_uuid` that acts as an "
        "idempotency key, so a retried batch never creates duplicate records."
    ),
)
async def push(payload: SyncPushRequest, db: DbSession, user: CurrentUser) -> SyncPushResponse:
    return SyncPushResponse(**await sync_service.push(db, user, payload))


@router.get(
    "/pull",
    response_model=SyncPullResponse,
    summary="Pull server-side changes since a timestamp",
)
async def pull(db: DbSession, user: CurrentUser, since: datetime | None = None) -> SyncPullResponse:
    return SyncPullResponse(**await sync_service.pull(db, user, since=since))
