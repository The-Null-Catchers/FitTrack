"""Habits and their completion history."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import (
    Boolean,
    Date,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import HabitFrequency


class Habit(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "habits"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    icon: Mapped[str] = mapped_column(String(40), default="check_circle", nullable=False)
    color: Mapped[str | None] = mapped_column(String(16), default=None)
    frequency: Mapped[str] = mapped_column(String(16), default=HabitFrequency.DAILY, nullable=False)
    #: How many completions count as "done" for one period.
    target_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    target_value: Mapped[float | None] = mapped_column(Float, default=None)
    unit: Mapped[str | None] = mapped_column(String(24), default=None)
    #: For weekly habits: which weekdays it applies to (0 = Monday).
    active_weekdays: Mapped[list[int]] = mapped_column(JSONDict, default=list, nullable=False)
    reminder_time: Mapped[str | None] = mapped_column(String(5), default=None)
    is_archived: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    current_streak: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    longest_streak: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class HabitLog(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "habit_logs"

    habit_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("habits.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logged_on: Mapped[date] = mapped_column(Date, nullable=False)
    count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    value: Mapped[float | None] = mapped_column(Float, default=None)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    __table_args__ = (
        UniqueConstraint("habit_id", "logged_on", name="uq_habit_logs_habit_day"),
        Index("ix_habit_logs_user_date", "user_id", "logged_on"),
    )
