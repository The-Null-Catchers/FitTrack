"""Body weight, measurement and progress-photo schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.models.enums import MeasurementType, PhotoPose
from app.schemas.common import APIModel


class BodyWeightWrite(APIModel):
    recorded_on: date
    weight_kg: float = Field(..., gt=20, lt=500)
    body_fat_percent: float | None = Field(None, ge=1, le=70)
    muscle_mass_kg: float | None = Field(None, ge=1, le=200)
    note: str | None = Field(None, max_length=255)
    client_uuid: str | None = Field(None, max_length=64)


class BodyWeightRead(BodyWeightWrite):
    id: str
    created_at: datetime


class MeasurementWrite(APIModel):
    recorded_on: date
    measurement_type: MeasurementType
    custom_label: str | None = Field(None, max_length=60)
    value_cm: float = Field(..., gt=1, lt=400)
    note: str | None = Field(None, max_length=255)
    client_uuid: str | None = Field(None, max_length=64)


class MeasurementRead(MeasurementWrite):
    id: str
    created_at: datetime


class ProgressPhotoRead(APIModel):
    id: str
    taken_on: date
    pose: PhotoPose
    #: Short-lived signed URL. Never a raw storage path.
    url: str | None = None
    thumbnail_url: str | None = None
    weight_kg: float | None = None
    note: str | None = None
    width: int | None = None
    height: int | None = None
    created_at: datetime


class ProgressPhotoUpdate(APIModel):
    taken_on: date | None = None
    pose: PhotoPose | None = None
    weight_kg: float | None = Field(None, gt=20, lt=500)
    note: str | None = Field(None, max_length=2000)


class PhotoComparison(APIModel):
    before: ProgressPhotoRead
    after: ProgressPhotoRead
    days_between: int
    weight_change_kg: float | None = None


class BodySummary(APIModel):
    latest_weight_kg: float | None
    latest_weight_on: date | None
    weight_change_kg: float | None
    weight_change_period_days: int
    target_weight_kg: float | None
    latest_body_fat_percent: float | None
    measurement_count: int
    photo_count: int
