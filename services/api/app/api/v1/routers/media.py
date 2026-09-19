"""Local media serving.

Only used with ``STORAGE_BACKEND=local``. Signed URLs are verified here so the
development flow has the same access-control behaviour as S3 presigned URLs.
"""

from __future__ import annotations

from fastapi import APIRouter, Query, Response

from app.core.config import settings
from app.core.errors import NotFoundError, PermissionError_
from app.storage import get_storage
from app.storage.local import LocalStorageProvider, verify_local_signature

router = APIRouter(prefix="/media", tags=["media"], include_in_schema=False)

_PUBLIC_PREFIXES = ("exercise-media/", "avatars/")
_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}


@router.get("/{key:path}")
async def serve(
    key: str,
    expires: int | None = Query(None),
    signature: str | None = Query(None),
) -> Response:
    storage = get_storage()
    if not isinstance(storage, LocalStorageProvider):
        raise NotFoundError("That file could not be found.")

    is_public = key.startswith(_PUBLIC_PREFIXES)
    if not is_public:
        if not expires or not signature or not verify_local_signature(key, expires, signature):
            raise PermissionError_(
                "That link has expired. Open the photo again from the app.",
                code="invalid_signature",
            )

    data = await storage.get(key)
    suffix = "." + key.rsplit(".", 1)[-1].lower() if "." in key else ""
    cache = (
        "public, max-age=31536000, immutable"
        if is_public
        else f"private, max-age={settings.SIGNED_URL_TTL_SECONDS}"
    )
    return Response(
        content=data,
        media_type=_CONTENT_TYPES.get(suffix, "application/octet-stream"),
        headers={"Cache-Control": cache},
    )
