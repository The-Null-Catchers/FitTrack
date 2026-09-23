"""Audit trail helper.

Audit rows are written for authentication events, destructive user actions and
every administrative change. Payloads are scrubbed of credentials before being
persisted.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import SENSITIVE_KEYS
from app.models.user import AuditLog


def _scrub(data: dict[str, Any]) -> dict[str, Any]:
    return {
        key: ("[redacted]" if key.lower() in SENSITIVE_KEYS else value)
        for key, value in data.items()
    }


async def record(
    db: AsyncSession,
    *,
    action: str,
    actor_id: uuid.UUID | None = None,
    entity_type: str | None = None,
    entity_id: str | uuid.UUID | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
    metadata: dict[str, Any] | None = None,
    note: str | None = None,
) -> AuditLog:
    entry = AuditLog(
        actor_id=actor_id,
        action=action,
        entity_type=entity_type,
        entity_id=str(entity_id) if entity_id else None,
        ip_address=ip_address,
        user_agent=(user_agent or "")[:320] or None,
        metadata_json=_scrub(metadata or {}),
        note=note,
    )
    db.add(entry)
    return entry
