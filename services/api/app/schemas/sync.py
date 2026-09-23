"""Offline sync schemas.

The client pushes a batch of queued mutations; the server applies each one
idempotently (keyed by ``client_uuid``) and returns a per-operation result so
the client can retire or retry individual entries.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import Field

from app.schemas.common import APIModel

SyncEntity = Literal[
    "workout_session",
    "body_weight",
    "body_measurement",
    "meal",
    "water_log",
    "habit_log",
]


class SyncOperationIn(APIModel):
    client_uuid: str = Field(..., min_length=8, max_length=64)
    entity: SyncEntity
    operation: Literal["create", "update", "delete"] = "create"
    #: Client clock; used only for conflict reporting, never for authorization.
    client_updated_at: datetime | None = None
    payload: dict[str, Any] = Field(default_factory=dict)


class SyncPushRequest(APIModel):
    operations: list[SyncOperationIn] = Field(..., max_length=200)
    device_id: str | None = Field(None, max_length=128)


class SyncOperationResult(APIModel):
    client_uuid: str
    entity: str
    status: Literal["applied", "duplicate", "conflict", "failed"]
    server_id: str | None = None
    message: str | None = None


class SyncPushResponse(APIModel):
    results: list[SyncOperationResult] = Field(default_factory=list)
    applied: int = 0
    duplicates: int = 0
    failed: int = 0
    server_time: datetime


class SyncPullResponse(APIModel):
    """Everything changed since ``since``, for the client to merge locally."""

    since: datetime | None
    server_time: datetime
    workout_sessions: list[dict] = Field(default_factory=list)
    body_weights: list[dict] = Field(default_factory=list)
    body_measurements: list[dict] = Field(default_factory=list)
    meals: list[dict] = Field(default_factory=list)
    water_logs: list[dict] = Field(default_factory=list)
    habit_logs: list[dict] = Field(default_factory=list)
    has_more: bool = False
