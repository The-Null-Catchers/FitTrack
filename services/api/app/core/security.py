"""Password hashing and JWT issuing/verification."""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from passlib.context import CryptContext

from app.core.config import settings
from app.core.errors import AuthenticationError

_pwd = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)

TokenType = Literal["access", "refresh"]


def hash_password(password: str) -> str:
    # bcrypt silently truncates at 72 bytes; reject rather than hash a prefix.
    if len(password.encode()) > 72:
        raise ValueError("Password is too long (maximum 72 bytes).")
    return _pwd.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _pwd.verify(password, password_hash)
    except ValueError:
        return False


def create_token(
    subject: str,
    token_type: TokenType,
    *,
    expires_delta: timedelta | None = None,
    extra_claims: dict[str, Any] | None = None,
) -> tuple[str, datetime]:
    """Return ``(encoded_jwt, expiry)``."""
    now = datetime.now(UTC)
    if expires_delta is None:
        expires_delta = (
            timedelta(minutes=settings.ACCESS_TOKEN_TTL_MINUTES)
            if token_type == "access"
            else timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS)
        )
    expires_at = now + expires_delta
    payload: dict[str, Any] = {
        "sub": subject,
        "typ": token_type,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "jti": uuid.uuid4().hex,
    }
    if extra_claims:
        payload.update(extra_claims)
    encoded = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return encoded, expires_at


def decode_token(token: str, *, expected_type: TokenType | None = None) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationError(
            "Your session has expired. Please sign in again.", code="token_expired"
        ) from exc
    except jwt.PyJWTError as exc:
        raise AuthenticationError("That sign-in token isn't valid.", code="invalid_token") from exc

    if expected_type and payload.get("typ") != expected_type:
        raise AuthenticationError("That sign-in token isn't valid.", code="invalid_token")
    return payload


def generate_opaque_token(nbytes: int = 32) -> str:
    """A URL-safe secret for email verification / password reset links."""
    return secrets.token_urlsafe(nbytes)


def fingerprint(value: str) -> str:
    """Stable, non-reversible digest used to store token references."""
    return hashlib.sha256(value.encode()).hexdigest()
