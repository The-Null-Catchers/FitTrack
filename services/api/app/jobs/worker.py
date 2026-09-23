"""arq worker definition.

Run with::

    arq app.jobs.worker.WorkerSettings
"""

from __future__ import annotations

from typing import Any

from arq import cron

from app.core.logging import configure_logging, get_logger
from app.jobs.queue import redis_settings
from app.jobs.tasks import (
    cleanup_expired_records,
    close_stale_sessions,
    process_progress_photo,
    purge_deleted_accounts,
    refresh_goal_progress,
    send_habit_reminders,
    send_weekly_summaries,
    send_workout_reminders,
)

logger = get_logger(__name__)


async def startup(_ctx: dict[str, Any]) -> None:
    configure_logging()
    logger.info("worker.startup")


async def shutdown(_ctx: dict[str, Any]) -> None:
    logger.info("worker.shutdown")


class WorkerSettings:
    redis_settings = redis_settings()
    on_startup = startup
    on_shutdown = shutdown

    functions = [
        send_workout_reminders,
        send_habit_reminders,
        send_weekly_summaries,
        refresh_goal_progress,
        close_stale_sessions,
        cleanup_expired_records,
        purge_deleted_accounts,
        process_progress_photo,
    ]

    cron_jobs = [
        # Reminder jobs run hourly and filter to the users whose configured
        # time falls in the current hour.
        cron(send_workout_reminders, minute=0),
        cron(send_habit_reminders, minute=5),
        cron(send_weekly_summaries, weekday=0, hour=8, minute=0),
        cron(refresh_goal_progress, hour={3, 15}, minute=0),
        cron(close_stale_sessions, hour=4, minute=0),
        cron(cleanup_expired_records, hour=4, minute=30),
        cron(purge_deleted_accounts, hour=5, minute=0),
    ]

    max_jobs = 10
    job_timeout = 300
    keep_result = 3600
