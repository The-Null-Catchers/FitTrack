"""Habit schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.models.enums import HabitFrequency
from app.schemas.common import APIModel


class HabitCreate(APIModel):
    name: str = Field(..., min_length=1, max_length=120)
    icon: str = Field("check_circle", max_length=40)
    color: str | None = Field(None, pattern="^#[0-9A-Fa-f]{6}$")
    frequency: HabitFrequency = HabitFrequency.DAILY
    target_count: int = Field(1, ge=1, le=50)
    target_value: float | None = Field(None, gt=0, le=100000)
    unit: str | None = Field(None, max_length=24)
    active_weekdays: list[int] = Field(default_factory=list)
    reminder_time: str | None = Field(None, pattern="^([01]\\d|2[0-3]):[0-5]\\d$")


class HabitUpdate(APIModel):
    name: str | None = Field(None, min_length=1, max_length=120)
    icon: str | None = Field(None, max_length=40)
    color: str | None = Field(None, pattern="^#[0-9A-Fa-f]{6}$")
    frequency: HabitFrequency | None = None
    target_count: int | None = Field(None, ge=1, le=50)
    target_value: float | None = Field(None, gt=0, le=100000)
    unit: str | None = Field(None, max_length=24)
    active_weekdays: list[int] | None = None
    reminder_time: str | None = Field(None, pattern="^([01]\\d|2[0-3]):[0-5]\\d$")
    is_archived: bool | None = None
    position: int | None = Field(None, ge=0)


class HabitLogWrite(APIModel):
    logged_on: date
    count: int = Field(1, ge=0, le=50)
    value: float | None = Field(None, ge=0, le=100000)
    client_uuid: str | None = Field(None, max_length=64)


class HabitLogRead(APIModel):
    id: str
    habit_id: str
    logged_on: date
    count: int
    value: float | None
    is_completed: bool


class HabitRead(APIModel):
    id: str
    name: str
    icon: str
    color: str | None
    frequency: HabitFrequency
    target_count: int
    target_value: float | None
    unit: str | None
    active_weekdays: list[int] = Field(default_factory=list)
    reminder_time: str | None
    is_archived: bool
    position: int
    current_streak: int
    longest_streak: int
    created_at: datetime
    #: Today's log, when one exists — lets the list render without an N+1.
    today: HabitLogRead | None = None
    completion_rate_30d: float = 0.0
