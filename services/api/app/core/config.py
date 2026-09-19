"""Application configuration, loaded from the environment.

All runtime configuration lives here. Nothing in the codebase should read
``os.environ`` directly — import :data:`settings` instead.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore", case_sensitive=False
    )

    # --- application ---------------------------------------------------
    ENVIRONMENT: Literal["development", "test", "staging", "production"] = "development"
    DEBUG: bool = False
    PROJECT_NAME: str = "FitTrack API"
    API_V1_PREFIX: str = "/api/v1"
    LOG_LEVEL: str = "INFO"

    # --- database ------------------------------------------------------
    DATABASE_URL: str = "postgresql+asyncpg://fittrack:fittrack@localhost:5432/fittrack"
    DB_POOL_SIZE: int = 10
    DB_MAX_OVERFLOW: int = 20
    DB_ECHO: bool = False

    # --- redis / queue -------------------------------------------------
    REDIS_URL: str = "redis://localhost:6379/0"
    QUEUE_NAME: str = "fittrack:jobs"

    # --- auth ----------------------------------------------------------
    JWT_SECRET: str = "change-me-in-production-this-is-only-a-dev-default"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_TTL_MINUTES: int = 15
    REFRESH_TOKEN_TTL_DAYS: int = 60
    EMAIL_VERIFICATION_TTL_HOURS: int = 48
    PASSWORD_RESET_TTL_MINUTES: int = 30
    PASSWORD_MIN_LENGTH: int = 8

    # --- rate limiting -------------------------------------------------
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_DEFAULT: str = "300/minute"
    RATE_LIMIT_AUTH: str = "10/minute"
    RATE_LIMIT_AI: str = "30/hour"

    # --- CORS ----------------------------------------------------------
    CORS_ORIGINS: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])

    # --- storage -------------------------------------------------------
    STORAGE_BACKEND: Literal["local", "s3"] = "local"
    STORAGE_LOCAL_PATH: str = "./var/storage"
    STORAGE_PUBLIC_BASE_URL: str = "http://localhost:8000/media"
    S3_ENDPOINT: str = "http://localhost:9000"
    S3_REGION: str = "us-east-1"
    S3_BUCKET: str = "fittrack"
    S3_ACCESS_KEY: str = ""
    S3_SECRET_KEY: str = ""
    S3_USE_PATH_STYLE: bool = True
    SIGNED_URL_TTL_SECONDS: int = 900
    MAX_UPLOAD_BYTES: int = 10 * 1024 * 1024
    ALLOWED_IMAGE_TYPES: list[str] = Field(
        default_factory=lambda: ["image/jpeg", "image/png", "image/webp", "image/heic"]
    )

    # --- AI ------------------------------------------------------------
    AI_PROVIDER: Literal["mock", "anthropic", "openai"] = "mock"
    AI_API_KEY: str = ""
    AI_MODEL: str = "claude-sonnet-5"
    AI_MAX_TOKENS: int = 2048
    AI_TIMEOUT_SECONDS: int = 60
    AI_DAILY_MESSAGE_LIMIT: int = 50

    # --- email ---------------------------------------------------------
    EMAIL_PROVIDER: Literal["console", "smtp"] = "console"
    EMAIL_FROM: str = "FitTrack <no-reply@fittrack.app>"
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    APP_PUBLIC_URL: str = "https://app.fittrack.dev"

    # --- push notifications ---------------------------------------------
    PUSH_PROVIDER: Literal["console", "fcm"] = "console"
    FCM_CREDENTIALS_JSON: str = ""

    # --- observability ---------------------------------------------------
    SENTRY_DSN: str = ""
    OTEL_EXPORTER_OTLP_ENDPOINT: str = ""

    @field_validator("CORS_ORIGINS", "ALLOWED_IMAGE_TYPES", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        """Allow comma-separated env values as well as JSON lists."""
        if isinstance(value, str) and not value.strip().startswith("["):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @property
    def is_testing(self) -> bool:
        return self.ENVIRONMENT == "test"

    @property
    def sync_database_url(self) -> str:
        """Synchronous DSN, used by Alembic."""
        return self.DATABASE_URL.replace("+asyncpg", "").replace("+aiosqlite", "")


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
