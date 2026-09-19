"""Body weight, measurements and progress photos."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID
from app.models.enums import PhotoPose


class BodyWeight(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """At most one weigh-in per user per day; a re-log updates the day's entry."""

    __tablename__ = "body_weights"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    recorded_on: Mapped[date] = mapped_column(Date, nullable=False)
    weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    body_fat_percent: Mapped[float | None] = mapped_column(Float, default=None)
    muscle_mass_kg: Mapped[float | None] = mapped_column(Float, default=None)
    note: Mapped[str | None] = mapped_column(String(255), default=None)
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    __table_args__ = (
        UniqueConstraint("user_id", "recorded_on", name="uq_body_weights_user_day"),
        Index("ix_body_weights_user_date", "user_id", "recorded_on"),
    )


class BodyMeasurement(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "body_measurements"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    recorded_on: Mapped[date] = mapped_column(Date, nullable=False)
    measurement_type: Mapped[str] = mapped_column(String(24), nullable=False)
    #: Label for ``measurement_type == "custom"``.
    custom_label: Mapped[str | None] = mapped_column(String(60), default=None)
    value_cm: Mapped[float] = mapped_column(Float, nullable=False)
    note: Mapped[str | None] = mapped_column(String(255), default=None)
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "recorded_on",
            "measurement_type",
            "custom_label",
            name="uq_body_measurements_user_day_type",
        ),
        Index("ix_body_measurements_user_type_date", "user_id", "measurement_type", "recorded_on"),
    )


class ProgressPhoto(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    """Private by default — never served from a raw storage URL."""

    __tablename__ = "progress_photos"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    taken_on: Mapped[date] = mapped_column(Date, nullable=False)
    pose: Mapped[str] = mapped_column(String(16), default=PhotoPose.FRONT, nullable=False)
    storage_key: Mapped[str] = mapped_column(String(512), nullable=False)
    thumbnail_key: Mapped[str | None] = mapped_column(String(512), default=None)
    content_type: Mapped[str] = mapped_column(String(64), default="image/jpeg", nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    width: Mapped[int | None] = mapped_column(Integer, default=None)
    height: Mapped[int | None] = mapped_column(Integer, default=None)
    weight_kg: Mapped[float | None] = mapped_column(Float, default=None)
    note: Mapped[str | None] = mapped_column(Text, default=None)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    __table_args__ = (Index("ix_progress_photos_user_taken", "user_id", "taken_on"),)
