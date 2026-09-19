"""Object-storage abstraction.

Two interchangeable backends are shipped: a local filesystem provider for
development and tests, and an S3-compatible provider for everything else. All
private objects (progress photos above all) are served through short-lived
signed URLs; a raw storage path is never returned to a client.
"""

from __future__ import annotations

import re
import secrets
import unicodedata
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date

from app.core.config import settings
from app.core.errors import ValidationError

_SAFE_NAME = re.compile(r"[^a-zA-Z0-9._-]+")
_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
}

#: Visibility of a stored object. Private objects always need a signed URL.
PUBLIC = "public"
PRIVATE = "private"


@dataclass(slots=True)
class StoredObject:
    key: str
    size_bytes: int
    content_type: str
    width: int | None = None
    height: int | None = None


def safe_filename(original: str) -> str:
    """Strip anything that could escape the storage prefix."""
    normalized = unicodedata.normalize("NFKD", original).encode("ascii", "ignore").decode()
    cleaned = _SAFE_NAME.sub("-", normalized).strip("-._")
    return cleaned[:80] or "file"


def extension_for(content_type: str) -> str:
    return _EXTENSIONS.get(content_type, ".bin")


def build_key(prefix: str, owner_id: str, content_type: str, *, on: date | None = None) -> str:
    """Namespaced, unguessable key: ``prefix/owner/YYYY/MM/<random>.ext``."""
    stamp = (on or date.today()).strftime("%Y/%m")
    return f"{prefix}/{owner_id}/{stamp}/{secrets.token_hex(16)}{extension_for(content_type)}"


def validate_upload(content_type: str, size_bytes: int) -> None:
    if content_type not in settings.ALLOWED_IMAGE_TYPES:
        raise ValidationError(
            "That file type isn't supported. Please upload a JPEG, PNG or WebP image.",
            code="unsupported_media_type",
        )
    if size_bytes <= 0:
        raise ValidationError("The file you uploaded is empty.", code="empty_file")
    if size_bytes > settings.MAX_UPLOAD_BYTES:
        limit_mb = settings.MAX_UPLOAD_BYTES // (1024 * 1024)
        raise ValidationError(
            f"That image is too large. Please choose one under {limit_mb} MB.",
            code="file_too_large",
        )


class StorageProvider(ABC):
    """Interface implemented by every storage backend."""

    name: str = "base"

    @abstractmethod
    async def put(
        self, key: str, data: bytes, content_type: str, *, visibility: str = PRIVATE
    ) -> StoredObject: ...

    @abstractmethod
    async def get(self, key: str) -> bytes: ...

    @abstractmethod
    async def delete(self, key: str) -> None: ...

    @abstractmethod
    async def exists(self, key: str) -> bool: ...

    @abstractmethod
    def signed_url(self, key: str, *, expires_in: int | None = None) -> str: ...

    @abstractmethod
    def public_url(self, key: str) -> str: ...

    async def health(self) -> str:
        return "ok"
