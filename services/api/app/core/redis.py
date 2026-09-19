"""Shared Redis client.

Redis is used for rate limiting, short-lived caches and the job queue. It is a
soft dependency: if it is unreachable the API degrades (rate limiting opens,
caches miss) rather than failing requests.
"""

from __future__ import annotations

from typing import Any

import redis.asyncio as aioredis

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

_client: aioredis.Redis | None = None


def get_redis() -> aioredis.Redis:
    global _client
    if _client is None:
        _client = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
            health_check_interval=30,
        )
    return _client


async def close_redis() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


async def redis_health() -> str:
    try:
        await get_redis().ping()
    except Exception:
        return "unavailable"
    return "ok"


async def cache_get_json(key: str) -> Any | None:
    import json

    try:
        raw = await get_redis().get(key)
    except Exception:
        return None
    return json.loads(raw) if raw else None


async def cache_set_json(key: str, value: Any, ttl_seconds: int = 300) -> None:
    import json

    try:
        await get_redis().set(key, json.dumps(value, default=str), ex=ttl_seconds)
    except Exception:
        logger.debug("cache.set_failed", key=key)


async def cache_delete_prefix(prefix: str) -> None:
    try:
        client = get_redis()
        async for key in client.scan_iter(match=f"{prefix}*", count=200):
            await client.delete(key)
    except Exception:
        logger.debug("cache.delete_prefix_failed", prefix=prefix)
