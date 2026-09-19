"""Workout programs: plan -> day -> prescribed exercise."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import Boolean, Date, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import ProgramStatus, TrackingType


class WorkoutProgram(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "workout_programs"

    # Templates (user_id IS NULL) are the curated starter plans users can clone.
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), default=None, index=True
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, default=None)
    status: Mapped[str] = mapped_column(
        String(16), default=ProgramStatus.DRAFT, nullable=False, index=True
    )
    is_template: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    source_template_id: Mapped[uuid.UUID | None] = mapped_column(GUID(), default=None)

    goal: Mapped[str | None] = mapped_column(String(32), default=None)
    difficulty: Mapped[str | None] = mapped_column(String(16), default=None)
    location: Mapped[str | None] = mapped_column(String(16), default=None)
    days_per_week: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    estimated_minutes: Mapped[int | None] = mapped_column(Integer, default=None)
    equipment_needed: Mapped[list[str]] = mapped_column(JSONDict, default=list, nullable=False)

    started_at: Mapped[date | None] = mapped_column(Date, default=None)
    ended_at: Mapped[date | None] = mapped_column(Date, default=None)
    generated_by_ai: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    days: Mapped[list[WorkoutDay]] = relationship(
        back_populates="program",
        cascade="all, delete-orphan",
        order_by="WorkoutDay.position",
        lazy="selectin",
    )

    __table_args__ = (Index("ix_workout_programs_user_status", "user_id", "status"),)


class WorkoutDay(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "workout_days"

    program_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("workout_programs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    #: 0 = Monday … 6 = Sunday. NULL means "any day of the week".
    weekday: Mapped[int | None] = mapped_column(Integer, default=None)
    notes: Mapped[str | None] = mapped_column(Text, default=None)
    is_rest_day: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    program: Mapped[WorkoutProgram] = relationship(back_populates="days")
    exercises: Mapped[list[WorkoutDayExercise]] = relationship(
        back_populates="day",
        cascade="all, delete-orphan",
        order_by="WorkoutDayExercise.position",
        lazy="selectin",
    )


class WorkoutDayExercise(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """A prescribed exercise inside a program day."""

    __tablename__ = "workout_day_exercises"

    day_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("workout_days.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("exercises.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    target_sets: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    target_reps_min: Mapped[int | None] = mapped_column(Integer, default=None)
    target_reps_max: Mapped[int | None] = mapped_column(Integer, default=None)
    target_weight_kg: Mapped[float | None] = mapped_column(Float, default=None)
    target_duration_seconds: Mapped[int | None] = mapped_column(Integer, default=None)
    target_distance_m: Mapped[float | None] = mapped_column(Float, default=None)
    target_rpe: Mapped[float | None] = mapped_column(Float, default=None)
    target_rir: Mapped[int | None] = mapped_column(Integer, default=None)
    rest_seconds: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    tracking_type: Mapped[str] = mapped_column(
        String(24), default=TrackingType.WEIGHT_REPS, nullable=False
    )
    #: Exercises sharing a superset group are performed back-to-back.
    superset_group: Mapped[int | None] = mapped_column(Integer, default=None)
    notes: Mapped[str | None] = mapped_column(Text, default=None)

    day: Mapped[WorkoutDay] = relationship(back_populates="exercises")
    exercise: Mapped[object] = relationship("Exercise", lazy="selectin")
