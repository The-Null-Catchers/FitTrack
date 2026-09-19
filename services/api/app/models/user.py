"""User identity, profile, auth sessions and single-use tokens."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import (
    ActivityLevel,
    FitnessGoal,
    FitnessLevel,
    Gender,
    SubscriptionTier,
    UnitSystem,
    UserRole,
    UserStatus,
    WorkoutLocation,
)

if TYPE_CHECKING:
    from app.models.notification import NotificationPreference


class User(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255), default=None)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    avatar_key: Mapped[str | None] = mapped_column(String(512), default=None)

    role: Mapped[str] = mapped_column(String(20), default=UserRole.USER, nullable=False)
    status: Mapped[str] = mapped_column(String(24), default=UserStatus.ACTIVE, nullable=False)

    email_verified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    onboarding_completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    locale: Mapped[str] = mapped_column(String(8), default="en", nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC", nullable=False)
    theme: Mapped[str] = mapped_column(String(16), default="system", nullable=False)

    oauth_provider: Mapped[str | None] = mapped_column(String(24), default=None)
    oauth_subject: Mapped[str | None] = mapped_column(String(255), default=None)

    subscription_tier: Mapped[str] = mapped_column(
        String(16), default=SubscriptionTier.FREE, nullable=False
    )

    profile: Mapped[UserProfile | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan", lazy="selectin"
    )
    notification_preference: Mapped[NotificationPreference | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan", lazy="selectin"
    )

    __table_args__ = (
        UniqueConstraint("oauth_provider", "oauth_subject", name="uq_users_oauth_identity"),
        Index("ix_users_role_status", "role", "status"),
    )

    @property
    def is_admin(self) -> bool:
        return self.role == UserRole.ADMIN

    @property
    def email_verified(self) -> bool:
        return self.email_verified_at is not None

    @property
    def onboarding_completed(self) -> bool:
        return self.onboarding_completed_at is not None


class UserProfile(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Fitness profile captured during onboarding and editable later."""

    __tablename__ = "user_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    date_of_birth: Mapped[date | None] = mapped_column(Date, default=None)
    gender: Mapped[str] = mapped_column(String(16), default=Gender.UNDISCLOSED, nullable=False)

    # Canonical storage is always metric; the unit system is a display concern.
    height_cm: Mapped[float | None] = mapped_column(Float, default=None)
    current_weight_kg: Mapped[float | None] = mapped_column(Float, default=None)
    target_weight_kg: Mapped[float | None] = mapped_column(Float, default=None)

    unit_system: Mapped[str] = mapped_column(String(16), default=UnitSystem.METRIC, nullable=False)
    primary_goal: Mapped[str] = mapped_column(
        String(32), default=FitnessGoal.GENERAL_FITNESS, nullable=False
    )
    fitness_level: Mapped[str] = mapped_column(
        String(16), default=FitnessLevel.BEGINNER, nullable=False
    )
    activity_level: Mapped[str] = mapped_column(
        String(16), default=ActivityLevel.MODERATE, nullable=False
    )
    workout_location: Mapped[str] = mapped_column(
        String(16), default=WorkoutLocation.GYM, nullable=False
    )
    available_equipment: Mapped[list[str]] = mapped_column(JSONDict, default=list, nullable=False)
    training_days_per_week: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    preferred_session_minutes: Mapped[int] = mapped_column(Integer, default=60, nullable=False)

    # Nutrition targets. ``targets_are_manual`` records that the user overrode
    # our estimate, so recalculation never silently replaces their choice.
    daily_calorie_target: Mapped[int | None] = mapped_column(Integer, default=None)
    daily_protein_target_g: Mapped[int | None] = mapped_column(Integer, default=None)
    daily_carbs_target_g: Mapped[int | None] = mapped_column(Integer, default=None)
    daily_fat_target_g: Mapped[int | None] = mapped_column(Integer, default=None)
    daily_fiber_target_g: Mapped[int | None] = mapped_column(Integer, default=None)
    daily_water_target_ml: Mapped[int] = mapped_column(Integer, default=2000, nullable=False)
    targets_are_manual: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    default_rest_seconds: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    ai_context_opt_in: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    user: Mapped[User] = relationship(back_populates="profile")


class UserSession(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """One row per signed-in device; backs refresh-token rotation."""

    __tablename__ = "user_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    refresh_token_hash: Mapped[str] = mapped_column(
        String(64), unique=True, index=True, nullable=False
    )
    device_name: Mapped[str | None] = mapped_column(String(120), default=None)
    device_id: Mapped[str | None] = mapped_column(String(128), default=None)
    platform: Mapped[str | None] = mapped_column(String(32), default=None)
    ip_address: Mapped[str | None] = mapped_column(String(64), default=None)
    user_agent: Mapped[str | None] = mapped_column(String(320), default=None)
    push_token: Mapped[str | None] = mapped_column(String(512), default=None)

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    # Set when rotation issues a successor, so replay of an old token is detectable.
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), default=None)

    __table_args__ = (Index("ix_user_sessions_user_revoked", "user_id", "revoked_at"),)


class VerificationToken(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Single-use token for email verification and password reset."""

    __tablename__ = "verification_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    purpose: Mapped[str] = mapped_column(String(32), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    __table_args__ = (Index("ix_verification_tokens_user_purpose", "user_id", "purpose"),)


class AuditLog(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Append-only record of security-relevant and administrative actions."""

    __tablename__ = "audit_logs"

    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), default=None, index=True
    )
    action: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    entity_type: Mapped[str | None] = mapped_column(String(64), default=None)
    entity_id: Mapped[str | None] = mapped_column(String(64), default=None)
    ip_address: Mapped[str | None] = mapped_column(String(64), default=None)
    user_agent: Mapped[str | None] = mapped_column(String(320), default=None)
    metadata_json: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)
    note: Mapped[str | None] = mapped_column(Text, default=None)

    __table_args__ = (Index("ix_audit_logs_action_created", "action", "created_at"),)
