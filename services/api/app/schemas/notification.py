"""Notification schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.models.enums import NotificationType
from app.schemas.common import APIModel


class NotificationRead(APIModel):
    id: str
    type: NotificationType
    title: str
    body: str
    deep_link: str | None
    data: dict = Field(default_factory=dict)
    read_at: datetime | None
    created_at: datetime


class NotificationPreferenceRead(APIModel):
    push_enabled: bool
    email_enabled: bool
    workout_reminders: bool
    workout_reminder_time: str
    goal_reminders: bool
    habit_reminders: bool
    progress_reminders: bool
    weekly_summary: bool
    personal_record_alerts: bool
    rest_timer_alerts: bool
    quiet_hours_start: str | None
    quiet_hours_end: str | None


class NotificationPreferenceUpdate(APIModel):
    push_enabled: bool | None = None
    email_enabled: bool | None = None
    workout_reminders: bool | None = None
    workout_reminder_time: str | None = Field(None, pattern="^([01]\\d|2[0-3]):[0-5]\\d$")
    goal_reminders: bool | None = None
    habit_reminders: bool | None = None
    progress_reminders: bool | None = None
    weekly_summary: bool | None = None
    personal_record_alerts: bool | None = None
    rest_timer_alerts: bool | None = None
    quiet_hours_start: str | None = Field(None, pattern="^([01]\\d|2[0-3]):[0-5]\\d$")
    quiet_hours_end: str | None = Field(None, pattern="^([01]\\d|2[0-3]):[0-5]\\d$")


class PushTokenRegister(APIModel):
    push_token: str = Field(..., min_length=8, max_length=512)
    platform: str | None = Field(None, max_length=32)


class UnreadCount(APIModel):
    unread: int
