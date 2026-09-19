"""Transactional email.

The console provider lets the whole auth flow be exercised locally without an
SMTP account — verification and reset links are printed to the log.
"""

from __future__ import annotations

import smtplib
from abc import ABC, abstractmethod
from email.message import EmailMessage
from functools import lru_cache

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)


class EmailProvider(ABC):
    name = "base"

    @abstractmethod
    async def send(self, *, to: str, subject: str, body: str, html: str | None = None) -> None: ...


class ConsoleEmailProvider(EmailProvider):
    name = "console"

    async def send(self, *, to: str, subject: str, body: str, html: str | None = None) -> None:
        logger.info("email.sent", provider="console", to=to, subject=subject, body=body)


class SMTPEmailProvider(EmailProvider):
    name = "smtp"

    async def send(self, *, to: str, subject: str, body: str, html: str | None = None) -> None:
        message = EmailMessage()
        message["From"] = settings.EMAIL_FROM
        message["To"] = to
        message["Subject"] = subject
        message.set_content(body)
        if html:
            message.add_alternative(html, subtype="html")

        import asyncio

        def _send() -> None:
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as server:
                server.starttls()
                if settings.SMTP_USER:
                    server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                server.send_message(message)

        await asyncio.to_thread(_send)
        logger.info("email.sent", provider="smtp", to=to, subject=subject)


@lru_cache
def get_email_provider() -> EmailProvider:
    if settings.EMAIL_PROVIDER == "smtp" and settings.SMTP_HOST:
        return SMTPEmailProvider()
    return ConsoleEmailProvider()
