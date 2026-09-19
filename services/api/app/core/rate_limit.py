"""Fixed-window rate limiting backed by Redis.

Limits are expressed as ``"<count>/<window>"`` strings, e.g. ``"10/minute"``.
If Redis is unavailable the limiter fails open — availability of the product
matters more than a perfectly enforced throttle on a degraded dependency.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from fastapi import Request

from app.core.config import settings
from app.core.errors import RateLimitError
from app.core.logging import get_logger
from app.core.redis import get_redis

logger = get_logger(__name__)

_WINDOWS = {"second": 1, "minute": 60, "hour": 3600, "day": 86400}


@dataclass(frozen=True, slots=True)
class Limit:
    count: int
    seconds: int

    @classmethod
    def parse(cls, spec: str) -> Limit:
        raw_count, _, unit = spec.partition("/")
        return cls(count=int(raw_count), seconds=_WINDOWS[unit.strip().lower()])


def client_identity(request: Request) -> str:
    """Prefer the authenticated user; fall back to the caller's IP."""
    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return f"user:{user_id}"
    forwarded = request.headers.get("x-forwarded-for", "")
    ip = (
        forwarded.split(",")[0].strip()
        if forwarded
        else (request.client.host if request.client else "unknown")
    )
    return f"ip:{ip}"


async def enforce(key: str, limit: Limit) -> None:
    if not settings.RATE_LIMIT_ENABLED:
        return
    window = int(time.time()) // limit.seconds
    redis_key = f"rl:{key}:{window}"
    try:
        client = get_redis()
        current = await client.incr(redis_key)
        if current == 1:
            await client.expire(redis_key, limit.seconds)
    except Exception:
        logger.debug("ratelimit.unavailable", key=key)
        return
    if current > limit.count:
        raise RateLimitError()


class RateLimiter:
    """FastAPI dependency factory: ``Depends(RateLimiter("10/minute"))``."""

    def __init__(self, spec: str, *, scope: str = "default") -> None:
        self.limit = Limit.parse(spec)
        self.scope = scope

    async def __call__(self, request: Request) -> None:
        await enforce(f"{self.scope}:{client_identity(request)}", self.limit)


auth_rate_limit = RateLimiter(settings.RATE_LIMIT_AUTH, scope="auth")
ai_rate_limit = RateLimiter(settings.RATE_LIMIT_AI, scope="ai")
upload_rate_limit = RateLimiter("60/hour", scope="upload")
