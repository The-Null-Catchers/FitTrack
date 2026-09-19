"""Habits, completion logging and streak maintenance."""

from __future__ import annotations

import uuid
from datetime import date, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError, PermissionError_
from app.models.enums import HabitFrequency
from app.models.habit import Habit, HabitLog
from app.models.user import User
from app.schemas.habit import HabitCreate, HabitLogWrite, HabitUpdate


async def list_habits(
    db: AsyncSession, user: User, *, include_archived: bool = False, on: date | None = None
) -> list[dict[str, Any]]:
    on = on or date.today()
    stmt = select(Habit).where(Habit.user_id == user.id, Habit.is_deleted.is_(False))
    if not include_archived:
        stmt = stmt.where(Habit.is_archived.is_(False))
    habits = list(await db.scalars(stmt.order_by(Habit.position, Habit.created_at)))
    if not habits:
        return []

    habit_ids = [habit.id for habit in habits]
    # One query for today's logs and one for the 30-day rates: no N+1.
    today_logs = {
        log.habit_id: log
        for log in await db.scalars(
            select(HabitLog).where(HabitLog.habit_id.in_(habit_ids), HabitLog.logged_on == on)
        )
    }
    since = on - timedelta(days=29)
    rates = {
        habit_id: int(count)
        for habit_id, count in await db.execute(
            select(HabitLog.habit_id, func.count())
            .where(
                HabitLog.habit_id.in_(habit_ids),
                HabitLog.logged_on >= since,
                HabitLog.logged_on <= on,
                HabitLog.is_completed.is_(True),
            )
            .group_by(HabitLog.habit_id)
        )
    }
    return [serialize(h, today=today_logs.get(h.id), completed_30d=rates.get(h.id, 0))
            for h in habits]


async def get_habit(db: AsyncSession, user: User, habit_id: uuid.UUID) -> Habit:
    habit = await db.get(Habit, habit_id)
    if habit is None or habit.is_deleted:
        raise NotFoundError("We couldn't find that habit.")
    if habit.user_id != user.id:
        raise PermissionError_("That habit belongs to someone else.")
    return habit


async def create(db: AsyncSession, user: User, data: HabitCreate) -> Habit:
    position = int(
        await db.scalar(
            select(func.count())
            .select_from(Habit)
            .where(Habit.user_id == user.id, Habit.is_deleted.is_(False))
        )
        or 0
    )
    habit = Habit(user_id=user.id, position=position, **data.model_dump())
    db.add(habit)
    await db.commit()
    await db.refresh(habit)
    return habit


async def update(
    db: AsyncSession, user: User, habit_id: uuid.UUID, data: HabitUpdate
) -> Habit:
    habit = await get_habit(db, user, habit_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(habit, field, value)
    await db.commit()
    await db.refresh(habit)
    return habit


async def delete(db: AsyncSession, user: User, habit_id: uuid.UUID) -> None:
    habit = await get_habit(db, user, habit_id)
    habit.soft_delete()
    await db.commit()


def _applies_on(habit: Habit, day: date) -> bool:
    """Whether a habit is expected on a given day."""
    if habit.frequency == HabitFrequency.WEEKLY and habit.active_weekdays:
        return day.weekday() in habit.active_weekdays
    return True


async def _recompute_streak(db: AsyncSession, habit: Habit, *, today: date) -> None:
    """Walk backwards from today counting consecutive completed days.

    Days the habit doesn't apply to are skipped rather than breaking the
    streak, and today being unlogged doesn't end a streak that ran to yesterday.
    """
    logs = {
        log.logged_on: log
        for log in await db.scalars(
            select(HabitLog)
            .where(
                HabitLog.habit_id == habit.id,
                HabitLog.logged_on >= today - timedelta(days=400),
                HabitLog.is_completed.is_(True),
            )
        )
    }

    streak = 0
    cursor = today
    if cursor not in logs and _applies_on(habit, cursor):
        cursor -= timedelta(days=1)

    for _ in range(400):
        if not _applies_on(habit, cursor):
            cursor -= timedelta(days=1)
            continue
        if cursor in logs:
            streak += 1
            cursor -= timedelta(days=1)
            continue
        break

    habit.current_streak = streak
    habit.longest_streak = max(habit.longest_streak, streak)


async def log(
    db: AsyncSession, user: User, habit_id: uuid.UUID, data: HabitLogWrite
) -> tuple[Habit, HabitLog]:
    habit = await get_habit(db, user, habit_id)
    entry = await db.scalar(
        select(HabitLog).where(
            HabitLog.habit_id == habit.id, HabitLog.logged_on == data.logged_on
        )
    )
    if entry is None:
        entry = HabitLog(
            habit_id=habit.id,
            user_id=user.id,
            logged_on=data.logged_on,
            count=data.count,
            client_uuid=data.client_uuid,
        )
        db.add(entry)
    entry.count = data.count
    entry.value = data.value
    entry.is_completed = data.count >= habit.target_count
    if data.client_uuid:
        entry.client_uuid = data.client_uuid

    await db.flush()
    await _recompute_streak(db, habit, today=max(data.logged_on, date.today()))
    await db.commit()
    await db.refresh(habit)
    await db.refresh(entry)
    return habit, entry


async def unlog(
    db: AsyncSession, user: User, habit_id: uuid.UUID, on: date
) -> Habit:
    habit = await get_habit(db, user, habit_id)
    entry = await db.scalar(
        select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.logged_on == on)
    )
    if entry is not None:
        await db.delete(entry)
        await db.flush()
    await _recompute_streak(db, habit, today=date.today())
    await db.commit()
    await db.refresh(habit)
    return habit


async def history(
    db: AsyncSession, user: User, habit_id: uuid.UUID, *, start: date, end: date
) -> list[HabitLog]:
    habit = await get_habit(db, user, habit_id)
    rows = await db.scalars(
        select(HabitLog)
        .where(
            HabitLog.habit_id == habit.id,
            HabitLog.logged_on >= start,
            HabitLog.logged_on <= end,
        )
        .order_by(HabitLog.logged_on)
    )
    return list(rows)


async def today_counts(db: AsyncSession, user: User, *, on: date) -> tuple[int, int]:
    """(completed, expected) for the dashboard."""
    habits = list(
        await db.scalars(
            select(Habit).where(
                Habit.user_id == user.id,
                Habit.is_deleted.is_(False),
                Habit.is_archived.is_(False),
            )
        )
    )
    expected = [h for h in habits if _applies_on(h, on)]
    if not expected:
        return 0, 0
    completed = int(
        await db.scalar(
            select(func.count())
            .select_from(HabitLog)
            .where(
                HabitLog.habit_id.in_([h.id for h in expected]),
                HabitLog.logged_on == on,
                HabitLog.is_completed.is_(True),
            )
        )
        or 0
    )
    return completed, len(expected)


def serialize(
    habit: Habit, *, today: HabitLog | None = None, completed_30d: int = 0
) -> dict[str, Any]:
    return {
        "id": str(habit.id),
        "name": habit.name,
        "icon": habit.icon,
        "color": habit.color,
        "frequency": habit.frequency,
        "target_count": habit.target_count,
        "target_value": habit.target_value,
        "unit": habit.unit,
        "active_weekdays": habit.active_weekdays or [],
        "reminder_time": habit.reminder_time,
        "is_archived": habit.is_archived,
        "position": habit.position,
        "current_streak": habit.current_streak,
        "longest_streak": habit.longest_streak,
        "created_at": habit.created_at,
        "today": (
            {
                "id": str(today.id),
                "habit_id": str(today.habit_id),
                "logged_on": today.logged_on,
                "count": today.count,
                "value": today.value,
                "is_completed": today.is_completed,
            }
            if today
            else None
        ),
        "completion_rate_30d": round(completed_30d / 30 * 100, 1),
    }
