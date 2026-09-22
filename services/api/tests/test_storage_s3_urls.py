"""URLs the s3 backend hands to clients.

`S3_ENDPOINT` is the address the API dials; `S3_PUBLIC_ENDPOINT` is the one
baked into URLs handed out. They differ whenever storage sits behind a name
that only resolves inside the network, which is the case for the compose
stack (`minio:9000`).
"""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest

from app.core.config import settings
from app.storage.s3 import S3StorageProvider

INTERNAL = "http://minio:9000"
PUBLIC = "http://localhost:9000"


@pytest.fixture
def s3_settings(monkeypatch: pytest.MonkeyPatch):
    """Point the settings at a split-horizon MinIO, with credentials to sign with."""

    def _apply(public_endpoint: str) -> None:
        monkeypatch.setattr(settings, "S3_ENDPOINT", INTERNAL)
        monkeypatch.setattr(settings, "S3_PUBLIC_ENDPOINT", public_endpoint)
        monkeypatch.setattr(settings, "S3_BUCKET", "fittrack")
        monkeypatch.setattr(settings, "S3_ACCESS_KEY", "fittrack")
        monkeypatch.setattr(settings, "S3_SECRET_KEY", "fittrack-dev-secret")
        monkeypatch.setattr(settings, "S3_REGION", "us-east-1")
        monkeypatch.setattr(settings, "S3_USE_PATH_STYLE", True)

    return _apply


def _signature(url: str) -> str:
    return parse_qs(urlparse(url).query)["X-Amz-Signature"][0]


def _origin(url: str) -> str:
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}"


def test_unset_public_endpoint_keeps_the_internal_address(s3_settings) -> None:
    """The default has to behave exactly as it did before the setting existed."""
    s3_settings("")
    provider = S3StorageProvider()

    assert _origin(provider.signed_url("progress/a.png")) == INTERNAL
    assert provider.public_url("progress/a.png") == f"{INTERNAL}/fittrack/progress/a.png"
    # No second client is built when there is nothing to point it at.
    assert provider.url_client is provider.client


def test_public_endpoint_is_used_for_urls_handed_to_clients(s3_settings) -> None:
    s3_settings(PUBLIC)
    provider = S3StorageProvider()

    assert _origin(provider.signed_url("progress/a.png")) == PUBLIC
    assert provider.public_url("progress/a.png") == f"{PUBLIC}/fittrack/progress/a.png"


def test_the_api_still_dials_the_internal_address(s3_settings) -> None:
    """Only the URLs move; the client the API operates through must not."""
    s3_settings(PUBLIC)
    provider = S3StorageProvider()

    assert provider.client.meta.endpoint_url == INTERNAL
    assert provider.url_client.meta.endpoint_url == PUBLIC


def test_the_host_is_part_of_the_signature(s3_settings) -> None:
    """Why this needs a second client rather than a string replacement.

    SigV4 presigned URLs carry `X-Amz-SignedHeaders=host`, so the host is
    signed. Swapping the origin of an already-signed URL therefore produces a
    URL whose signature no longer matches — storage rejects it. Signing
    against the public endpoint is the only thing that yields a valid URL.
    """
    s3_settings("")
    signed_for_internal = S3StorageProvider().signed_url("progress/a.png")

    s3_settings(PUBLIC)
    signed_for_public = S3StorageProvider().signed_url("progress/a.png")

    assert "host" in parse_qs(urlparse(signed_for_public).query)["X-Amz-SignedHeaders"][0]
    # Same key, same credentials, different host — and so a different signature.
    assert _signature(signed_for_internal) != _signature(signed_for_public)

    # The naive fix: rewrite the origin of the internally-signed URL. It carries
    # the wrong signature, which is precisely why it is not what we do.
    rewritten = signed_for_internal.replace(INTERNAL, PUBLIC, 1)
    assert _origin(rewritten) == _origin(signed_for_public)
    assert _signature(rewritten) != _signature(signed_for_public)


def test_a_trailing_slash_does_not_double_up(s3_settings) -> None:
    s3_settings(f"{PUBLIC}/")
    provider = S3StorageProvider()

    assert provider.public_url("progress/a.png") == f"{PUBLIC}/fittrack/progress/a.png"
