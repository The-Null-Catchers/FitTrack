"""Dashboard assembly and progress analytics."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import NotFoundError
from app.models.body import BodyMeasurement, BodyWeight
from app.models.enums import GoalStatus, SessionStatus
from app.models.exercise import Exercise
from app.models.notification import Notification
from app.models.nutrition import DailyNutrition
from app.models.workout import (
    PersonalRecord,
    WorkoutSession,
    WorkoutSessionExercise,
    WorkoutSet,
)
from app.models.user import User
from app.services import (
    exercise_service,
    goal_service,
    habit_service,
    nutrition_service,
    program_service,
    records_service,
    workout_service,
)
from app.services.metrics import moving_average, percent_change

#: Window length in days for each supported time range. ``None`` = all time.
RANGE_DAYS: dict[str, int | None] = {
    "7d": 7,
    "30d": 30,
    "3m": 90,
    "6m": 180,
    "1y": 365,
    "all": None,
}


def range_bounds(time_range: str, *, today: date | None = None) -> tuple[date, date]:
    end = today or date.today()
    days = RANGE_DAYS.get(time_range, 30)
    start = date(2015, 1, 1) if days is None else end - timedelta(days=days - 1)
    return start, end


def _as_datetime(day: date) -> datetime:
    return datetime.combine(day, datetime.min.time())


async def _completed_sessions(
    db: AsyncSession, user: User, *, start: date, end: date
) -> list[WorkoutSession]:
    rows = await db.scalars(
        select(WorkoutSession)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
            WorkoutSession.started_at >= _as_datetime(start),
            WorkoutSession.started_at < _as_datetime(end + timedelta(days=1)),
        )
        .order_by(WorkoutSession.started_at)
    )
    return list(rows)


async def workout_streak(db: AsyncSession, user: User, *, today: date | None = None) -> tuple[int, int]:
    """(current, longest) streak in consecutive *days with a workout*.

    Rest days don't break a streak on their own — a gap of more than one day
    does. This keeps the number motivating without being trivially gameable.
    """
    today = today or date.today()
    rows = await db.scalars(
        select(WorkoutSession.started_at)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
        )
        .order_by(WorkoutSession.started_at.desc())
    )
    days = sorted({row.date() for row in rows}, reverse=True)
    if not days:
        return 0, 0

    current = 0
    if (today - days[0]).days <= 1:
        current = 1
        for previous, following in zip(days[1:], days, strict=False):
            if (following - previous).days <= 2:
                current += 1
            else:
                break

    longest = 1
    run = 1
    for previous, following in zip(days[1:], days, strict=False):
        if (following - previous).days <= 2:
            run += 1
            longest = max(longest, run)
        else:
            run = 1
    return current, max(longest, current)


async def dashboard(db: AsyncSession, user: User, *, today: date | None = None) -> dict[str, Any]:
    today = today or datetime.now(UTC).date()

    today_plan = await program_service.today_day(db, user)
    active_session = await workout_service.get_active(db, user)

    nutrition_row = await nutrition_service.recompute_day(db, user, today)
    await db.commit()

    profile = user.profile
    calorie_target = profile.daily_calorie_target if profile else None
    protein_target = profile.daily_protein_target_g if profile else None
    water_target = profile.daily_water_target_ml if profile else None

    current_streak, longest_streak = await workout_streak(db, user, today=today)

    week_start = today - timedelta(days=today.weekday())
    week_sessions = await _completed_sessions(db, user, start=week_start, end=today)
    trained_days = {s.started_at.date() for s in week_sessions}
    weekly_target = profile.training_days_per_week if profile else 3

    weights = await db.scalars(
        select(BodyWeight)
        .where(
            BodyWeight.user_id == user.id,
            BodyWeight.recorded_on >= today - timedelta(days=89),
        )
        .order_by(BodyWeight.recorded_on)
    )
    weight_rows = list(weights)
    weight_series = None
    weight_change = None
    if weight_rows:
        values = [row.weight_kg for row in weight_rows]
        trend = moving_average(values, 7)
        weight_series = {
            "key": "body_weight",
            "label": "Body weight",
            "unit": "kg",
            "points": [
                {"x": row.recorded_on, "y": row.weight_kg} for row in weight_rows
            ],
            "trend": [
                {"x": row.recorded_on, "y": value}
                for row, value in zip(weight_rows, trend, strict=True)
            ],
        }
        cutoff = today - timedelta(days=30)
        baseline = next((r for r in weight_rows if r.recorded_on >= cutoff), weight_rows[0])
        weight_change = round(weight_rows[-1].weight_kg - baseline.weight_kg, 2)

    recent_records = await records_service.list_for_user(db, user.id, limit=5)
    for record in recent_records:
        await db.refresh(record, ["exercise"])

    goals = await goal_service.list_goals(db, user, status=GoalStatus.ACTIVE)
    habits_done, habits_total = await habit_service.today_counts(db, user, on=today)

    unread = int(
        await db.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        )
        or 0
    )

    today_workout = None
    if today_plan:
        program, day = today_plan
        today_workout = {
            "program_id": str(program.id),
            "program_name": program.name,
            "day_id": str(day.id),
            "day_name": day.name,
            "exercise_count": len(day.exercises),
            "estimated_minutes": program.estimated_minutes,
            "is_rest_day": day.is_rest_day,
        }

    active_ref = None
    if active_session:
        all_sets = [s for item in active_session.exercises for s in item.sets]
        active_ref = {
            "id": str(active_session.id),
            "name": active_session.name,
            "started_at": active_session.started_at,
            "completed_set_count": sum(1 for s in all_sets if s.is_completed),
            "total_set_count": len(all_sets),
        }

    def ring(consumed: float, target: float | None) -> dict[str, Any]:
        return {
            "consumed": round(consumed, 1),
            "target": float(target) if target else None,
            "percent": round(consumed / target * 100, 1) if target else None,
        }

    return {
        "greeting_name": user.full_name.split(" ")[0],
        "date": today,
        "today_workout": today_workout,
        "active_session": active_ref,
        "calories": ring(nutrition_row.calories, calorie_target),
        "protein_g": ring(nutrition_row.protein_g, protein_target),
        "water_ml": ring(float(nutrition_row.water_ml), water_target),
        "current_streak_days": current_streak,
        "longest_streak_days": longest_streak,
        "weekly_workouts": {
            "completed": len(trained_days),
            "target": weekly_target,
            "percent": round(min(len(trained_days) / max(weekly_target, 1), 1) * 100, 1),
            "days": [
                (week_start + timedelta(days=i)) in trained_days for i in range(7)
            ],
        },
        "weight_trend": weight_series,
        "latest_weight_kg": weight_rows[-1].weight_kg if weight_rows else None,
        "weight_change_30d_kg": weight_change,
        "recent_records": [workout_service.serialize_record(r) for r in recent_records],
        "active_goals": await goal_service.serialize_many(db, goals[:5]),
        "habits_completed_today": habits_done,
        "habits_total_today": habits_total,
        "unread_notifications": unread,
    }


async def body_weight_chart(
    db: AsyncSession, user: User, *, time_range: str = "30d"
) -> dict[str, Any]:
    start, end = range_bounds(time_range)
    rows = list(
        await db.scalars(
            select(BodyWeight)
            .where(
                BodyWeight.user_id == user.id,
                BodyWeight.recorded_on >= start,
                BodyWeight.recorded_on <= end,
            )
            .order_by(BodyWeight.recorded_on)
        )
    )

    series: list[dict[str, Any]] = []
    summary = None
    change_pct = None
    change_abs = None
    if rows:
        values = [row.weight_kg for row in rows]
        trend = moving_average(values, min(7, max(2, len(values) // 3)))
        series.append(
            {
                "key": "body_weight",
                "label": "Body weight",
                "unit": "kg",
                "points": [{"x": r.recorded_on, "y": r.weight_kg} for r in rows],
                "trend": [
                    {"x": r.recorded_on, "y": v}
                    for r, v in zip(rows, trend, strict=True)
                ],
            }
        )
        change_abs = round(values[-1] - values[0], 2)
        change_pct = percent_change(values[0], values[-1])
        if len(values) > 1:
            direction = "down" if change_abs < 0 else "up"
            summary = (
                f"Your weight is {direction} {abs(change_abs):g} kg over this period."
                if change_abs
                else "Your weight has held steady over this period."
            )

    return {
        "range": time_range,
        "start_date": rows[0].recorded_on if rows else start,
        "end_date": rows[-1].recorded_on if rows else end,
        "series": series,
        "summary": summary,
        "change_percent": change_pct,
        "change_absolute": change_abs,
    }


async def measurement_chart(
    db: AsyncSession, user: User, *, measurement_type: str, time_range: str = "6m"
) -> dict[str, Any]:
    start, end = range_bounds(time_range)
    rows = list(
        await db.scalars(
            select(BodyMeasurement)
            .where(
                BodyMeasurement.user_id == user.id,
                BodyMeasurement.measurement_type == measurement_type,
                BodyMeasurement.recorded_on >= start,
                BodyMeasurement.recorded_on <= end,
            )
            .order_by(BodyMeasurement.recorded_on)
        )
    )
    series = (
        [
            {
                "key": measurement_type,
                "label": measurement_type.replace("_", " ").title(),
                "unit": "cm",
                "points": [{"x": r.recorded_on, "y": r.value_cm} for r in rows],
                "trend": [],
            }
        ]
        if rows
        else []
    )
    change_abs = round(rows[-1].value_cm - rows[0].value_cm, 2) if len(rows) > 1 else None
    return {
        "range": time_range,
        "start_date": rows[0].recorded_on if rows else start,
        "end_date": rows[-1].recorded_on if rows else end,
        "series": series,
        "summary": None,
        "change_percent": (
            percent_change(rows[0].value_cm, rows[-1].value_cm) if len(rows) > 1 else None
        ),
        "change_absolute": change_abs,
    }


async def volume_chart(
    db: AsyncSession, user: User, *, time_range: str = "30d"
) -> dict[str, Any]:
    start, end = range_bounds(time_range)
    sessions = await _completed_sessions(db, user, start=start, end=end)

    by_day: dict[date, float] = {}
    counts: dict[date, int] = {}
    for session in sessions:
        day = session.started_at.date()
        by_day[day] = by_day.get(day, 0) + session.total_volume_kg
        counts[day] = counts.get(day, 0) + 1

    days = sorted(by_day)
    series = []
    if days:
        series.append(
            {
                "key": "volume",
                "label": "Training volume",
                "unit": "kg",
                "points": [{"x": d, "y": round(by_day[d], 1)} for d in days],
                "trend": [],
            }
        )
        series.append(
            {
                "key": "frequency",
                "label": "Workouts",
                "unit": "sessions",
                "points": [{"x": d, "y": float(counts[d])} for d in days],
                "trend": [],
            }
        )

    total = sum(by_day.values())
    return {
        "range": time_range,
        "start_date": days[0] if days else start,
        "end_date": days[-1] if days else end,
        "series": series,
        "summary": (
            f"You lifted {round(total):,} kg across {len(sessions)} workouts."
            if sessions
            else None
        ),
        "change_percent": None,
        "change_absolute": round(total, 1) if sessions else None,
    }


async def nutrition_chart(
    db: AsyncSession, user: User, *, time_range: str = "30d"
) -> dict[str, Any]:
    start, end = range_bounds(time_range)
    rows = await nutrition_service.range_summary(db, user, start=start, end=end)
    logged = [row for row in rows if row.calories > 0]

    series = []
    if logged:
        series.append(
            {
                "key": "calories",
                "label": "Calories",
                "unit": "kcal",
                "points": [{"x": r.logged_on, "y": r.calories} for r in logged],
                "trend": [
                    {"x": r.logged_on, "y": v}
                    for r, v in zip(
                        logged,
                        moving_average([r.calories for r in logged], 7),
                        strict=True,
                    )
                ],
            }
        )
        series.append(
            {
                "key": "protein",
                "label": "Protein",
                "unit": "g",
                "points": [{"x": r.logged_on, "y": r.protein_g} for r in logged],
                "trend": [],
            }
        )

    average = round(sum(r.calories for r in logged) / len(logged)) if logged else None
    return {
        "range": time_range,
        "start_date": logged[0].logged_on if logged else start,
        "end_date": logged[-1].logged_on if logged else end,
        "series": series,
        "summary": (
            f"You averaged {average:,} kcal on the {len(logged)} days you logged."
            if average
            else None
        ),
        "change_percent": None,
        "change_absolute": None,
    }


async def exercise_progress(
    db: AsyncSession, user: User, exercise_id: uuid.UUID, *, time_range: str = "6m"
) -> dict[str, Any]:
    exercise = await db.get(Exercise, exercise_id)
    if exercise is None:
        raise NotFoundError("We couldn't find that exercise.")

    start, end = range_bounds(time_range)
    rows = await db.scalars(
        select(WorkoutSessionExercise)
        .options(selectinload(WorkoutSessionExercise.sets))
        .join(WorkoutSession, WorkoutSession.id == WorkoutSessionExercise.session_id)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
            WorkoutSessionExercise.exercise_id == exercise_id,
            WorkoutSession.started_at >= _as_datetime(start),
            WorkoutSession.started_at < _as_datetime(end + timedelta(days=1)),
        )
        .order_by(WorkoutSession.started_at)
    )

    session_ids = []
    items = list(rows)
    for item in items:
        session_ids.append(item.session_id)
    dates: dict[uuid.UUID, date] = {}
    if session_ids:
        for session_id, started_at in await db.execute(
            select(WorkoutSession.id, WorkoutSession.started_at).where(
                WorkoutSession.id.in_(session_ids)
            )
        ):
            dates[session_id] = started_at.date()

    points: list[dict[str, Any]] = []
    for item in items:
        completed = [s for s in item.sets if s.counts_toward_records]
        if not completed:
            continue
        points.append(
            {
                "performed_on": dates.get(item.session_id, start),
                "best_weight_kg": max((s.weight_kg or 0) for s in completed) or None,
                "best_reps": max((s.reps or 0) for s in completed) or None,
                "estimated_1rm_kg": max((s.estimated_1rm_kg or 0) for s in completed) or None,
                "total_volume_kg": round(sum(s.volume_kg or 0 for s in completed), 1),
                "total_sets": len(completed),
            }
        )
    points.sort(key=lambda p: p["performed_on"])

    one_rms = [p["estimated_1rm_kg"] for p in points if p["estimated_1rm_kg"]]
    change = percent_change(one_rms[0], one_rms[-1]) if len(one_rms) > 1 else None
    summary = None
    if change is not None and one_rms:
        weeks = max(1, (points[-1]["performed_on"] - points[0]["performed_on"]).days // 7)
        direction = "increased" if change >= 0 else "decreased"
        summary = (
            f"Your {exercise.name} estimated 1RM {direction} by {abs(change)}% "
            f"over the last {weeks} week{'s' if weeks != 1 else ''}."
        )

    return {
        "exercise_id": str(exercise.id),
        "exercise_name": exercise.name,
        "range": time_range,
        "points": points,
        "best_1rm_kg": max(one_rms) if one_rms else None,
        "change_percent": change,
        "summary": summary,
    }


async def training_overview(
    db: AsyncSession, user: User, *, time_range: str = "30d"
) -> dict[str, Any]:
    start, end = range_bounds(time_range)
    sessions = await _completed_sessions(db, user, start=start, end=end)

    if not sessions:
        return {
            "range": time_range,
            "total_workouts": 0,
            "total_duration_minutes": 0,
            "total_volume_kg": 0.0,
            "total_sets": 0,
            "average_session_minutes": 0.0,
            "workouts_per_week": 0.0,
            "volume_by_muscle_group": [],
            "personal_records": 0,
            "summary": "No workouts logged in this period yet.",
        }

    session_ids = [s.id for s in sessions]
    rows = await db.execute(
        select(
            Exercise.muscle_group,
            func.coalesce(func.sum(WorkoutSet.volume_kg), 0),
            func.count(WorkoutSet.id),
        )
        .join(
            WorkoutSessionExercise,
            WorkoutSessionExercise.id == WorkoutSet.session_exercise_id,
        )
        .join(Exercise, Exercise.id == WorkoutSessionExercise.exercise_id)
        .where(
            WorkoutSessionExercise.session_id.in_(session_ids),
            WorkoutSet.is_completed.is_(True),
        )
        .group_by(Exercise.muscle_group)
    )
    grouped = [
        {"muscle_group": group, "volume_kg": round(float(volume), 1), "set_count": int(count)}
        for group, volume, count in rows
    ]
    total_volume = sum(g["volume_kg"] for g in grouped) or 1.0
    for group in grouped:
        group["percent"] = round(group["volume_kg"] / total_volume * 100, 1)
    grouped.sort(key=lambda g: g["volume_kg"], reverse=True)

    pr_count = int(
        await db.scalar(
            select(func.count())
            .select_from(PersonalRecord)
            .where(
                PersonalRecord.user_id == user.id,
                PersonalRecord.achieved_at >= _as_datetime(start),
            )
        )
        or 0
    )

    total_minutes = sum((s.duration_seconds or 0) for s in sessions) // 60
    span_days = max(1, (end - sessions[0].started_at.date()).days + 1)
    per_week = round(len(sessions) / (span_days / 7), 1)

    return {
        "range": time_range,
        "total_workouts": len(sessions),
        "total_duration_minutes": total_minutes,
        "total_volume_kg": round(sum(s.total_volume_kg for s in sessions), 1),
        "total_sets": sum(s.total_sets for s in sessions),
        "average_session_minutes": round(total_minutes / len(sessions), 1),
        "workouts_per_week": per_week,
        "volume_by_muscle_group": grouped,
        "personal_records": pr_count,
        "summary": (
            f"{len(sessions)} workouts, {round(sum(s.total_volume_kg for s in sessions)):,} kg "
            f"lifted and {pr_count} personal record{'s' if pr_count != 1 else ''} in this period."
        ),
    }


async def trained_exercises(db: AsyncSession, user: User, *, limit: int = 40) -> list[dict[str, Any]]:
    """Exercises the user has actually logged — the picker for progress charts."""
    rows = await db.execute(
        select(
            WorkoutSessionExercise.exercise_id,
            func.count(WorkoutSessionExercise.id).label("times"),
        )
        .join(WorkoutSession, WorkoutSession.id == WorkoutSessionExercise.session_id)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
        )
        .group_by(WorkoutSessionExercise.exercise_id)
        .order_by(func.count(WorkoutSessionExercise.id).desc())
        .limit(limit)
    )
    ids = [row[0] for row in rows]
    if not ids:
        return []
    exercises = {
        e.id: e for e in await db.scalars(select(Exercise).where(Exercise.id.in_(ids)))
    }
    return [exercise_service.serialize(exercises[i]) for i in ids if i in exercises]


async def daily_nutrition_rows(
    db: AsyncSession, user: User, *, start: date, end: date
) -> list[DailyNutrition]:
    return await nutrition_service.range_summary(db, user, start=start, end=end)
