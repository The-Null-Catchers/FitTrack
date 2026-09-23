"""Job enqueuing.

The API never does expensive work inline; it enqueues a job here. If Redis is
unavailable the enqueue is logged and skipped rather than failing the request —
these are all best-effort background tasks.
"""

from __future__ import annotations

from typing import Any

from arq.connections import RedisSettings, create_pool

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)


def redis_settings() -> RedisSettings:
    return RedisSettings.from_dsn(settings.REDIS_URL)


async def enqueue(job_name: str, *args: Any, **kwargs: Any) -> str | None:
    """Queue a job. Returns the job id, or ``None`` when the queue is down."""
    try:
        pool = await create_pool(redis_settings())
        job = await pool.enqueue_job(job_name, *args, **kwargs)
        await pool.aclose()
    except Exception:
        logger.warning("jobs.enqueue_failed", job=job_name)
        return None
    return job.job_id if job else None
