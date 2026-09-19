"""Authentication request/response schemas."""

from __future__ import annotations

from datetime import datetime

from pydantic import EmailStr, Field, field_validator

from app.core.config import settings
from app.schemas.common import APIModel


def _validate_password_strength(value: str) -> str:
    if len(value) < settings.PASSWORD_MIN_LENGTH:
        raise ValueError(
            f"Password must be at least {settings.PASSWORD_MIN_LENGTH} characters long."
        )
    if len(value.encode()) > 72:
        raise ValueError("Password is too long (maximum 72 bytes).")
    if value.isalpha() or value.isdigit():
        raise ValueError("Password must mix letters with numbers or symbols.")
    return value


class DeviceInfo(APIModel):
    device_id: str | None = Field(None, max_length=128)
    device_name: str | None = Field(None, max_length=120)
    platform: str | None = Field(None, max_length=32)
    push_token: str | None = Field(None, max_length=512)


class RegisterRequest(APIModel):
    email: EmailStr
    password: str
    full_name: str = Field(..., min_length=1, max_length=120)
    locale: str = Field("en", max_length=8)
    timezone: str = Field("UTC", max_length=64)
    device: DeviceInfo | None = None

    _check_password = field_validator("password")(_validate_password_strength)


class LoginRequest(APIModel):
    email: EmailStr
    password: str
    device: DeviceInfo | None = None


class RefreshRequest(APIModel):
    refresh_token: str


class LogoutRequest(APIModel):
    refresh_token: str | None = None
    all_devices: bool = False


class ForgotPasswordRequest(APIModel):
    email: EmailStr


class ResetPasswordRequest(APIModel):
    token: str
    new_password: str

    _check_password = field_validator("new_password")(_validate_password_strength)


class ChangePasswordRequest(APIModel):
    current_password: str
    new_password: str

    _check_password = field_validator("new_password")(_validate_password_strength)


class VerifyEmailRequest(APIModel):
    token: str


class OAuthLoginRequest(APIModel):
    provider: str = Field(..., pattern="^(google|apple)$")
    id_token: str
    device: DeviceInfo | None = None


class TokenPair(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    refresh_expires_at: datetime


class SessionSummary(APIModel):
    id: str
    device_name: str | None
    platform: str | None
    ip_address: str | None
    created_at: datetime
    last_used_at: datetime | None
    expires_at: datetime
    is_current: bool = False


class DeleteAccountRequest(APIModel):
    password: str | None = None
    confirmation: str = Field(..., pattern="^DELETE$")
