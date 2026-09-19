"""Notifications and per-user delivery preferences."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import NotificationType

if TYPE_CHECKING:
    from app.models.user import User


class Notification(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    type: Mapped[str] = mapped_column(
        String(32), default=NotificationType.SYSTEM, nullable=False
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    #: Client-side route to open when tapped, e.g. "/progress/records".
    deep_link: Mapped[str | None] = mapped_column(String(255), default=None)
    data: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)

    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    scheduled_for: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    __table_args__ = (Index("ix_notifications_user_read", "user_id", "read_at"),)


class NotificationPreference(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "notification_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )

    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    email_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    workout_reminders: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    workout_reminder_time: Mapped[str] = mapped_column(String(5), default="18:00", nullable=False)
    goal_reminders: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    habit_reminders: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    progress_reminders: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    weekly_summary: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    personal_record_alerts: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    rest_timer_alerts: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    #: 24h "HH:MM" bounds; nothing is delivered inside this window.
    quiet_hours_start: Mapped[str | None] = mapped_column(String(5), default="22:00")
    quiet_hours_end: Mapped[str | None] = mapped_column(String(5), default="07:00")

    user: Mapped[User] = relationship(back_populates="notification_preference")
