"""Logged workout sessions, their exercises and individual sets."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
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
from app.models.enums import SessionStatus, SetType, TrackingType


class WorkoutSession(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "workout_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    program_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("workout_programs.id", ondelete="SET NULL"), default=None
    )
    day_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("workout_days.id", ondelete="SET NULL"), default=None
    )

    name: Mapped[str] = mapped_column(String(160), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), default=SessionStatus.IN_PROGRESS, nullable=False, index=True
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    #: Wall-clock duration minus paused time, set when the session is finished.
    duration_seconds: Mapped[int | None] = mapped_column(Integer, default=None)

    notes: Mapped[str | None] = mapped_column(Text, default=None)
    perceived_effort: Mapped[int | None] = mapped_column(Integer, default=None)
    bodyweight_kg: Mapped[float | None] = mapped_column(Float, default=None)

    # Denormalised rollups so history and analytics avoid re-aggregating sets.
    total_volume_kg: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    total_sets: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_reps: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    estimated_calories: Mapped[int | None] = mapped_column(Integer, default=None)

    #: Idempotency key supplied by the offline client so a replayed sync never
    #: creates a duplicate session.
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    exercises: Mapped[list[WorkoutSessionExercise]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="WorkoutSessionExercise.position",
        lazy="selectin",
    )

    __table_args__ = (
        UniqueConstraint("user_id", "client_uuid", name="uq_workout_sessions_user_client_uuid"),
        Index("ix_workout_sessions_user_started", "user_id", "started_at"),
        Index("ix_workout_sessions_user_status", "user_id", "status"),
    )


class WorkoutSessionExercise(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "workout_session_exercises"

    session_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("workout_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("exercises.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    tracking_type: Mapped[str] = mapped_column(
        String(24), default=TrackingType.WEIGHT_REPS, nullable=False
    )
    rest_seconds: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, default=None)
    superset_group: Mapped[int | None] = mapped_column(Integer, default=None)
    #: Prescription copied from the program at session start, kept for "target" display.
    target_snapshot: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)
    #: Set when the user swapped the prescribed movement for another one.
    replaced_exercise_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), default=None)

    session: Mapped[WorkoutSession] = relationship(back_populates="exercises")
    exercise: Mapped["object"] = relationship("Exercise", lazy="selectin")
    sets: Mapped[list[WorkoutSet]] = relationship(
        back_populates="session_exercise",
        cascade="all, delete-orphan",
        order_by="WorkoutSet.set_number",
        lazy="selectin",
    )


class WorkoutSet(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "workout_sets"

    session_exercise_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("workout_session_exercises.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    set_number: Mapped[int] = mapped_column(Integer, nullable=False)
    set_type: Mapped[str] = mapped_column(String(16), default=SetType.NORMAL, nullable=False)

    weight_kg: Mapped[float | None] = mapped_column(Float, default=None)
    reps: Mapped[int | None] = mapped_column(Integer, default=None)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, default=None)
    distance_m: Mapped[float | None] = mapped_column(Float, default=None)
    calories: Mapped[int | None] = mapped_column(Integer, default=None)

    rpe: Mapped[float | None] = mapped_column(Float, default=None)
    rir: Mapped[int | None] = mapped_column(Integer, default=None)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    notes: Mapped[str | None] = mapped_column(String(255), default=None)

    #: Cached so leaderboards/charts don't recompute Epley on every read.
    estimated_1rm_kg: Mapped[float | None] = mapped_column(Float, default=None)
    volume_kg: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    session_exercise: Mapped[WorkoutSessionExercise] = relationship(back_populates="sets")

    __table_args__ = (
        UniqueConstraint("session_exercise_id", "set_number", name="uq_workout_sets_number"),
    )

    @property
    def counts_toward_records(self) -> bool:
        """Warm-up sets never set personal records."""
        return self.is_completed and self.set_type != SetType.WARMUP


class PersonalRecord(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """One row per PR event; the latest per (user, exercise, type) is current."""

    __tablename__ = "personal_records"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False, index=True
    )
    record_type: Mapped[str] = mapped_column(String(24), nullable=False)
    value: Mapped[float] = mapped_column(Float, nullable=False)
    unit: Mapped[str] = mapped_column(String(16), default="kg", nullable=False)
    #: Context, e.g. the reps performed at the record weight.
    reps: Mapped[int | None] = mapped_column(Integer, default=None)
    weight_kg: Mapped[float | None] = mapped_column(Float, default=None)
    previous_value: Mapped[float | None] = mapped_column(Float, default=None)

    achieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("workout_sessions.id", ondelete="SET NULL"), default=None
    )
    set_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), default=None)
    #: Cleared once the celebration has been shown on the client.
    acknowledged_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None
    )

    exercise: Mapped["object"] = relationship("Exercise", lazy="selectin")

    __table_args__ = (
        Index("ix_personal_records_lookup", "user_id", "exercise_id", "record_type"),
        Index("ix_personal_records_user_achieved", "user_id", "achieved_at"),
    )
