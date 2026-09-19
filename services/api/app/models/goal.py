"""User goals and their progress snapshots."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID
from app.models.enums import GoalStatus, GoalType


class UserGoal(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "user_goals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    goal_type: Mapped[str] = mapped_column(String(32), default=GoalType.CUSTOM, nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, default=None)

    #: Optional subject, e.g. the exercise for an "exercise_1rm" goal.
    exercise_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("exercises.id", ondelete="SET NULL"), default=None
    )
    measurement_type: Mapped[str | None] = mapped_column(String(24), default=None)

    start_value: Mapped[float | None] = mapped_column(Float, default=None)
    current_value: Mapped[float | None] = mapped_column(Float, default=None)
    target_value: Mapped[float] = mapped_column(Float, nullable=False)
    unit: Mapped[str] = mapped_column(String(16), default="kg", nullable=False)
    #: True when success means going *down* (e.g. body weight, waist).
    is_decreasing: Mapped[bool] = mapped_column(default=False, nullable=False)

    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    target_date: Mapped[date | None] = mapped_column(Date, default=None)
    status: Mapped[str] = mapped_column(
        String(16), default=GoalStatus.ACTIVE, nullable=False, index=True
    )
    achieved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    __table_args__ = (Index("ix_user_goals_user_status", "user_id", "status"),)

    @property
    def progress_percent(self) -> float:
        """0-100 progress from ``start_value`` toward ``target_value``."""
        if self.current_value is None:
            return 0.0
        start = self.start_value if self.start_value is not None else self.current_value
        span = self.target_value - start
        if abs(span) < 1e-9:
            return 100.0
        pct = ((self.current_value - start) / span) * 100
        return max(0.0, min(100.0, round(pct, 1)))
