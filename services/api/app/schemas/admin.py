"""Admin dashboard schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.models.enums import UserRole, UserStatus
from app.schemas.common import APIModel


class AdminMetricPoint(APIModel):
    day: date
    value: float


class AdminOverview(APIModel):
    total_users: int
    active_users_7d: int
    active_users_30d: int
    new_registrations_7d: int
    workouts_completed_7d: int
    workouts_completed_total: int
    ai_requests_7d: int
    ai_tokens_7d: int
    photos_uploaded_7d: int
    storage_bytes_used: int
    api_errors_24h: int
    registrations_series: list[AdminMetricPoint] = Field(default_factory=list)
    workouts_series: list[AdminMetricPoint] = Field(default_factory=list)


class AdminUserRow(APIModel):
    id: str
    email: str
    full_name: str
    role: UserRole
    status: UserStatus
    email_verified: bool
    onboarding_completed: bool
    subscription_tier: str
    workout_count: int = 0
    last_login_at: datetime | None = None
    created_at: datetime


class AdminUserDetail(AdminUserRow):
    locale: str
    timezone: str
    #: Counts only. Admins never see a user's private photos.
    progress_photo_count: int = 0
    ai_message_count: int = 0
    session_count: int = 0


class AdminUserUpdate(APIModel):
    status: UserStatus | None = None
    role: UserRole | None = None
    note: str | None = Field(None, max_length=500)


class AdminAuditLogRow(APIModel):
    id: str
    actor_id: str | None
    actor_email: str | None = None
    action: str
    entity_type: str | None
    entity_id: str | None
    ip_address: str | None
    metadata_json: dict = Field(default_factory=dict)
    note: str | None
    created_at: datetime


class AdminAIUsageRow(APIModel):
    day: str
    kind: str
    requests: int
    input_tokens: int
    output_tokens: int
    failures: int


class AdminStorageStats(APIModel):
    backend: str
    progress_photos: int
    progress_photo_bytes: int
    exercise_media: int
    avatars: int
    total_bytes: int


class SystemHealth(APIModel):
    api: str
    database: str
    redis: str
    storage: str
    worker: str
    version: str
    environment: str
    uptime_seconds: float
    checked_at: datetime


class AdminTemplateFeatureRequest(APIModel):
    is_featured: bool
