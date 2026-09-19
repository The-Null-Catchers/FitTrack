"""Push notification delivery.

FCM credentials are optional: without them the console provider logs what
would have been delivered, so notification scheduling stays testable.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from functools import lru_cache

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)


@dataclass(slots=True)
class PushMessage:
    token: str
    title: str
    body: str
    data: dict[str, str] = field(default_factory=dict)


class PushProvider(ABC):
    name = "base"

    @abstractmethod
    async def send(self, message: PushMessage) -> bool: ...

    async def send_many(self, messages: list[PushMessage]) -> int:
        delivered = 0
        for message in messages:
            if await self.send(message):
                delivered += 1
        return delivered


class ConsolePushProvider(PushProvider):
    name = "console"

    async def send(self, message: PushMessage) -> bool:
        logger.info(
            "push.sent",
            provider="console",
            title=message.title,
            body=message.body,
            data=message.data,
        )
        return True


class FCMPushProvider(PushProvider):
    """Firebase Cloud Messaging via the HTTP v1 API.

    Kept intentionally thin; credentials are supplied through
    ``FCM_CREDENTIALS_JSON``. Falls back to a no-op when unconfigured.
    """

    name = "fcm"

    async def send(self, message: PushMessage) -> bool:  # pragma: no cover - needs credentials
        if not settings.FCM_CREDENTIALS_JSON:
            logger.warning("push.fcm_unconfigured")
            return False
        import httpx

        from app.providers.fcm_auth import get_access_token, get_project_id

        token = await get_access_token()
        project_id = get_project_id()
        url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
        payload = {
            "message": {
                "token": message.token,
                "notification": {"title": message.title, "body": message.body},
                "data": message.data,
            }
        }
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                url, json=payload, headers={"Authorization": f"Bearer {token}"}
            )
        if response.status_code >= 400:
            logger.warning("push.fcm_failed", status=response.status_code)
            return False
        return True


@lru_cache
def get_push_provider() -> PushProvider:
    if settings.PUSH_PROVIDER == "fcm" and settings.FCM_CREDENTIALS_JSON:
        return FCMPushProvider()
    return ConsolePushProvider()
