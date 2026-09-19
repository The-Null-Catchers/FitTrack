"""Minimal service-account OAuth for FCM.

Isolated here so the push provider stays readable and so the dependency on
Google credentials is confined to one module.
"""

from __future__ import annotations

import json
import time
from typing import Any

import httpx
import jwt

from app.core.config import settings

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_TOKEN_URL = "https://oauth2.googleapis.com/token"

_cached_token: tuple[str, float] | None = None


def _credentials() -> dict[str, Any]:
    return json.loads(settings.FCM_CREDENTIALS_JSON)


def get_project_id() -> str:
    return str(_credentials()["project_id"])


async def get_access_token() -> str:  # pragma: no cover - requires credentials
    global _cached_token
    now = time.time()
    if _cached_token and _cached_token[1] > now + 60:
        return _cached_token[0]

    creds = _credentials()
    assertion = jwt.encode(
        {
            "iss": creds["client_email"],
            "scope": _SCOPE,
            "aud": _TOKEN_URL,
            "iat": int(now),
            "exp": int(now) + 3600,
        },
        creds["private_key"],
        algorithm="RS256",
    )
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            _TOKEN_URL,
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            },
        )
    response.raise_for_status()
    payload = response.json()
    _cached_token = (payload["access_token"], now + payload.get("expires_in", 3600))
    return _cached_token[0]
