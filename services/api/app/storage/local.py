"""Filesystem storage for local development and tests.

Signed URLs are real HMAC signatures verified by the ``/media`` route, so the
development flow exercises the same access-control path as production.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import time
from pathlib import Path

from app.core.config import settings
from app.core.errors import NotFoundError
from app.storage.base import PRIVATE, StorageProvider, StoredObject


def _signature(key: str, expires: int) -> str:
    message = f"{key}:{expires}".encode()
    return hmac.new(settings.JWT_SECRET.encode(), message, hashlib.sha256).hexdigest()[:32]


def verify_local_signature(key: str, expires: int, signature: str) -> bool:
    if expires < int(time.time()):
        return False
    return hmac.compare_digest(_signature(key, expires), signature)


class LocalStorageProvider(StorageProvider):
    name = "local"

    def __init__(self, root: str | None = None) -> None:
        self.root = Path(root or settings.STORAGE_LOCAL_PATH).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        path = (self.root / key).resolve()
        # Defensive: a crafted key must never write outside the storage root.
        if not str(path).startswith(str(self.root)):
            raise NotFoundError("That file could not be found.")
        return path

    async def put(
        self, key: str, data: bytes, content_type: str, *, visibility: str = PRIVATE
    ) -> StoredObject:
        def _write() -> None:
            path = self._path(key)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        await asyncio.to_thread(_write)
        return StoredObject(key=key, size_bytes=len(data), content_type=content_type)

    async def get(self, key: str) -> bytes:
        path = self._path(key)
        if not path.exists():
            raise NotFoundError("That file could not be found.")
        return await asyncio.to_thread(path.read_bytes)

    async def delete(self, key: str) -> None:
        path = self._path(key)
        if path.exists():
            await asyncio.to_thread(path.unlink)

    async def exists(self, key: str) -> bool:
        return await asyncio.to_thread(self._path(key).exists)

    def signed_url(self, key: str, *, expires_in: int | None = None) -> str:
        expires = int(time.time()) + (expires_in or settings.SIGNED_URL_TTL_SECONDS)
        sig = _signature(key, expires)
        base = settings.STORAGE_PUBLIC_BASE_URL.rstrip("/")
        return f"{base}/{key}?expires={expires}&signature={sig}"

    def public_url(self, key: str) -> str:
        return f"{settings.STORAGE_PUBLIC_BASE_URL.rstrip('/')}/{key}"
