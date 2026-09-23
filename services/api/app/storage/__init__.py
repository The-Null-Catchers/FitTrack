"""Storage provider selection."""

from __future__ import annotations

from functools import lru_cache

from app.core.config import settings
from app.storage.base import (
    PRIVATE,
    PUBLIC,
    StorageProvider,
    StoredObject,
    build_key,
    safe_filename,
    validate_upload,
)
from app.storage.local import LocalStorageProvider
from app.storage.s3 import S3StorageProvider


@lru_cache
def get_storage() -> StorageProvider:
    if settings.STORAGE_BACKEND == "s3":
        return S3StorageProvider()
    return LocalStorageProvider()


__all__ = [
    "PRIVATE",
    "PUBLIC",
    "LocalStorageProvider",
    "S3StorageProvider",
    "StorageProvider",
    "StoredObject",
    "build_key",
    "get_storage",
    "safe_filename",
    "validate_upload",
]
