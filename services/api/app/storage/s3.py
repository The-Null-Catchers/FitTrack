"""S3-compatible storage (AWS S3, MinIO, Cloudflare R2, …)."""

from __future__ import annotations

import asyncio
import contextlib
from functools import cached_property
from typing import Any

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

from app.core.config import settings
from app.core.errors import NotFoundError, ServiceUnavailableError
from app.storage.base import PRIVATE, PUBLIC, StorageProvider, StoredObject


class S3StorageProvider(StorageProvider):
    name = "s3"

    def __init__(self, bucket: str | None = None) -> None:
        self.bucket = bucket or settings.S3_BUCKET

    def _client_for(self, endpoint: str) -> Any:
        return boto3.client(
            "s3",
            endpoint_url=endpoint or None,
            region_name=settings.S3_REGION,
            aws_access_key_id=settings.S3_ACCESS_KEY or None,
            aws_secret_access_key=settings.S3_SECRET_KEY or None,
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path" if settings.S3_USE_PATH_STYLE else "auto"},
                retries={"max_attempts": 3, "mode": "standard"},
            ),
        )

    @cached_property
    def client(self) -> Any:
        """Client for operations the API performs itself, over the internal address."""
        return self._client_for(settings.S3_ENDPOINT)

    @cached_property
    def url_client(self) -> Any:
        """Client used only to mint URLs for clients outside the network.

        A SigV4 presigned URL carries `X-Amz-SignedHeaders=host`, so the host is
        part of what gets signed: rewriting the origin of an already-signed URL
        invalidates it. The public address therefore has to be the endpoint the
        URL is signed *against*, which means a second client. Presigning is
        computed locally and opens no connection, so this one never dials out.
        """
        if not settings.S3_PUBLIC_ENDPOINT:
            return self.client
        return self._client_for(settings.S3_PUBLIC_ENDPOINT)

    async def put(
        self, key: str, data: bytes, content_type: str, *, visibility: str = PRIVATE
    ) -> StoredObject:
        extra: dict[str, Any] = {"ContentType": content_type}
        if visibility == PUBLIC:
            extra["ACL"] = "public-read"
            extra["CacheControl"] = "public, max-age=31536000, immutable"
        else:
            extra["CacheControl"] = "private, no-store"
        try:
            await asyncio.to_thread(
                self.client.put_object, Bucket=self.bucket, Key=key, Body=data, **extra
            )
        except ClientError as exc:  # pragma: no cover - network failure path
            raise ServiceUnavailableError("We couldn't store that file right now.") from exc
        return StoredObject(key=key, size_bytes=len(data), content_type=content_type)

    async def get(self, key: str) -> bytes:
        try:
            response = await asyncio.to_thread(self.client.get_object, Bucket=self.bucket, Key=key)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in {"NoSuchKey", "404"}:
                raise NotFoundError("That file could not be found.") from exc
            raise ServiceUnavailableError("We couldn't read that file right now.") from exc
        return await asyncio.to_thread(response["Body"].read)

    async def delete(self, key: str) -> None:
        # Deleting is best-effort: a missing object is already the desired state.
        with contextlib.suppress(ClientError):
            await asyncio.to_thread(self.client.delete_object, Bucket=self.bucket, Key=key)

    async def exists(self, key: str) -> bool:
        try:
            await asyncio.to_thread(self.client.head_object, Bucket=self.bucket, Key=key)
        except ClientError:
            return False
        return True

    def signed_url(self, key: str, *, expires_in: int | None = None) -> str:
        return self.url_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=expires_in or settings.SIGNED_URL_TTL_SECONDS,
        )

    def public_url(self, key: str) -> str:
        endpoint = (settings.S3_PUBLIC_ENDPOINT or settings.S3_ENDPOINT).rstrip("/")
        return f"{endpoint}/{self.bucket}/{key}"

    async def health(self) -> str:
        try:
            await asyncio.to_thread(self.client.head_bucket, Bucket=self.bucket)
        except Exception:  # pragma: no cover - health probe
            return "unavailable"
        return "ok"
