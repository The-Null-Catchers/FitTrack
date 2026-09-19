"""Background job implementations.

Each task takes the arq context as its first argument and opens its own
database session — jobs must never share a session with a web request.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from sqlalchemy import delete, func, select

from app.core.logging import get_logger
from app.db.session import session_scope
from app.models.ai import AIGeneration
from app.models.body import ProgressPhoto
from app.models.enums import GoalStatus, NotificationType, SessionStatus
from app.models.goal import UserGoal
from app.models.habit import Habit, HabitLog
from app.models.notification import Notification, NotificationPreference
from app.models.program import WorkoutDay, WorkoutProgram
from app.models.sync import SyncOperation
from app.models.user import User, UserSession, VerificationToken
from app.models.workout import WorkoutSession
from app.services import analytics_service, notification_service
from app.storage import get_storage

logger = get_logger(__name__)

#: In-progress workouts older than this are assumed abandoned.
STALE_SESSION_HOURS = 36


async def send_workout_reminders(_ctx: dict[str, Any]) -> int:
    """Remind users whose reminder time has just passed and who haven't trained."""
    now = datetime.now(UTC)
    today = now.date()
    sent = 0

    async with session_scope() as db:
        rows = await db.execute(
            select(User, NotificationPreference)
            .join(NotificationPreference, NotificationPreference.user_id == User.id)
            .where(
                User.is_deleted.is_(False),
                NotificationPreference.workout_reminders.is_(True),
            )
        )
        for user, preference in rows:
            if not _is_due(preference.workout_reminder_time, now):
                continue

            trained = await db.scalar(
                select(func.count())
                .select_from(WorkoutSession)
                .where(
                    WorkoutSession.user_id == user.id,
                    WorkoutSession.started_at >= datetime.combine(today, time.min, tzinfo=UTC),
                    WorkoutSession.is_deleted.is_(False),
                )
            )
            if trained:
                continue

            plan = await _todays_plan_name(db, user)
            await notification_service.create(
                db,
                user.id,
                notification_type=NotificationType.WORKOUT_REMINDER,
                title="Ready to train?",
                body=(
                    f"{plan} is on your plan today."
                    if plan
                    else "You haven't logged a workout today."
                ),
                deep_link="/workout",
            )
            sent += 1

    logger.info("jobs.workout_reminders", sent=sent)
    return sent


def _is_due(reminder_time: str | None, now: datetime) -> bool:
    """True when ``reminder_time`` falls inside the hour this job is running."""
    if not reminder_time:
        return False
    hour, _, _minute = reminder_time.partition(":")
    try:
        return int(hour) == now.hour
    except ValueError:
        return False


async def _todays_plan_name(db: Any, user: User) -> str | None:
    program = await db.scalar(
        select(WorkoutProgram).where(
            WorkoutProgram.user_id == user.id,
            WorkoutProgram.status == "active",
            WorkoutProgram.is_deleted.is_(False),
        )
    )
    if program is None:
        return None
    day = await db.scalar(
        select(WorkoutDay)
        .where(
            WorkoutDay.program_id == program.id,
            WorkoutDay.weekday == date.today().weekday(),
        )
        .limit(1)
    )
    return day.name if day else None


async def send_habit_reminders(_ctx: dict[str, Any]) -> int:
    """Nudge users about habits they haven't ticked off today."""
    now = datetime.now(UTC)
    today = now.date()
    sent = 0

    async with session_scope() as db:
        rows = await db.execute(
            select(Habit, NotificationPreference)
            .join(NotificationPreference, NotificationPreference.user_id == Habit.user_id)
            .where(
                Habit.is_deleted.is_(False),
                Habit.is_archived.is_(False),
                Habit.reminder_time.is_not(None),
                NotificationPreference.habit_reminders.is_(True),
            )
        )
        for habit, _preference in rows:
            if not _is_due(habit.reminder_time, now):
                continue
            logged = await db.scalar(
                select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.logged_on == today)
            )
            if logged is not None and logged.is_completed:
                continue
            await notification_service.create(
                db,
                habit.user_id,
                notification_type=NotificationType.HABIT_REMINDER,
                title=habit.name,
                body=f"Don't lose your {habit.current_streak}-day streak."
                if habit.current_streak
                else "A good moment to tick this one off.",
                deep_link="/habits",
            )
            sent += 1

    logger.info("jobs.habit_reminders", sent=sent)
    return sent


async def send_weekly_summaries(_ctx: dict[str, Any]) -> int:
    """Monday digest of the previous week's training."""
    sent = 0
    async with session_scope() as db:
        rows = await db.execute(
            select(User, NotificationPreference)
            .join(NotificationPreference, NotificationPreference.user_id == User.id)
            .where(
                User.is_deleted.is_(False),
                NotificationPreference.weekly_summary.is_(True),
            )
        )
        for user, _unused in rows:
            overview = await analytics_service.training_overview(db, user, time_range="7d")
            if not overview["total_workouts"]:
                continue
            await notification_service.create(
                db,
                user.id,
                notification_type=NotificationType.WEEKLY_SUMMARY,
                title="Your week in training",
                body=(
                    f"{overview['total_workouts']} workouts, "
                    f"{round(overview['total_volume_kg']):,} kg lifted and "
                    f"{overview['personal_records']} personal records."
                ),
                deep_link="/progress",
                data={"range": "7d"},
            )
            sent += 1

    logger.info("jobs.weekly_summaries", sent=sent)
    return sent


async def refresh_goal_progress(_ctx: dict[str, Any]) -> int:
    """Keep goal progress and missed-deadline states current."""
    from app.services import goal_service

    updated = 0
    async with session_scope() as db:
        users = await db.scalars(
            select(User)
            .where(User.is_deleted.is_(False))
            .where(
                User.id.in_(
                    select(UserGoal.user_id).where(
                        UserGoal.status == GoalStatus.ACTIVE,
                        UserGoal.is_deleted.is_(False),
                    )
                )
            )
        )
        for user in users:
            await goal_service.refresh_all(db, user)
            updated += 1

    logger.info("jobs.goal_progress", users=updated)
    return updated


async def close_stale_sessions(_ctx: dict[str, Any]) -> int:
    """Abandon workouts left running far longer than any real session."""
    cutoff = datetime.now(UTC) - timedelta(hours=STALE_SESSION_HOURS)
    async with session_scope() as db:
        stale = list(
            await db.scalars(
                select(WorkoutSession).where(
                    WorkoutSession.status == SessionStatus.IN_PROGRESS,
                    WorkoutSession.started_at < cutoff,
                    WorkoutSession.is_deleted.is_(False),
                )
            )
        )
        for session in stale:
            session.status = SessionStatus.ABANDONED

    logger.info("jobs.stale_sessions", closed=len(stale))
    return len(stale)


async def cleanup_expired_records(_ctx: dict[str, Any]) -> dict[str, int]:
    """Remove data that has served its purpose."""
    now = datetime.now(UTC)
    async with session_scope() as db:
        tokens = await db.execute(
            delete(VerificationToken).where(VerificationToken.expires_at < now)
        )
        sessions = await db.execute(
            delete(UserSession).where(UserSession.expires_at < now - timedelta(days=7))
        )
        notifications = await db.execute(
            delete(Notification).where(
                Notification.created_at < now - timedelta(days=90),
                Notification.read_at.is_not(None),
            )
        )
        # The sync ledger only needs to cover the window a client might retry in.
        sync_rows = await db.execute(
            delete(SyncOperation).where(SyncOperation.created_at < now - timedelta(days=30))
        )
        generations = await db.execute(
            delete(AIGeneration).where(AIGeneration.created_at < now - timedelta(days=180))
        )

    counts = {
        "verification_tokens": int(tokens.rowcount or 0),
        "user_sessions": int(sessions.rowcount or 0),
        "notifications": int(notifications.rowcount or 0),
        "sync_operations": int(sync_rows.rowcount or 0),
        "ai_generations": int(generations.rowcount or 0),
    }
    logger.info("jobs.cleanup", **counts)
    return counts


async def purge_deleted_accounts(_ctx: dict[str, Any]) -> int:
    """Hard-delete accounts that have been soft-deleted for 30 days.

    Stored objects are removed first so nothing is orphaned in the bucket.
    """
    cutoff = datetime.now(UTC) - timedelta(days=30)
    storage = get_storage()
    purged = 0

    async with session_scope() as db:
        users = list(
            await db.scalars(
                select(User).where(User.is_deleted.is_(True), User.deleted_at < cutoff)
            )
        )
        for user in users:
            photos = await db.scalars(select(ProgressPhoto).where(ProgressPhoto.user_id == user.id))
            for photo in photos:
                await storage.delete(photo.storage_key)
                if photo.thumbnail_key:
                    await storage.delete(photo.thumbnail_key)
            if user.avatar_key:
                await storage.delete(user.avatar_key)
            await db.delete(user)
            purged += 1

    logger.info("jobs.purge_accounts", purged=purged)
    return purged


async def process_progress_photo(_ctx: dict[str, Any], photo_id: str) -> bool:
    """Re-derive a thumbnail for a photo that was stored without one."""
    from app.services.body_service import THUMBNAIL_EDGE, _resize

    async with session_scope() as db:
        photo = await db.get(ProgressPhoto, uuid.UUID(photo_id))
        if photo is None or photo.thumbnail_key:
            return False
        storage = get_storage()
        original = await storage.get(photo.storage_key)
        thumbnail, _, _ = _resize(original, THUMBNAIL_EDGE)
        key = photo.storage_key.replace(".jpg", "_thumb.jpg")
        await storage.put(key, thumbnail, "image/jpeg")
        photo.thumbnail_key = key
        photo.processed_at = datetime.now(UTC)

    logger.info("jobs.photo_processed", photo_id=photo_id)
    return True
