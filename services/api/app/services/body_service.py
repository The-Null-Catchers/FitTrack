"""Body weight, measurements and progress photos."""

from __future__ import annotations

import io
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError, PermissionError_, ValidationError
from app.core.logging import get_logger
from app.models.body import BodyMeasurement, BodyWeight, ProgressPhoto
from app.models.user import User
from app.schemas.body import BodyWeightWrite, MeasurementWrite, ProgressPhotoUpdate
from app.storage import PRIVATE, build_key, get_storage, validate_upload

logger = get_logger(__name__)

#: Longest edge of a stored progress photo; keeps uploads small without
#: destroying detail on a modern phone screen.
MAX_PHOTO_EDGE = 1600
THUMBNAIL_EDGE = 400
JPEG_QUALITY = 85


async def record_weight(db: AsyncSession, user: User, data: BodyWeightWrite) -> BodyWeight:
    """Upsert the weigh-in for a day (one entry per day, per user)."""
    entry = await db.scalar(
        select(BodyWeight).where(
            BodyWeight.user_id == user.id, BodyWeight.recorded_on == data.recorded_on
        )
    )
    if entry is None:
        entry = BodyWeight(user_id=user.id, recorded_on=data.recorded_on, weight_kg=data.weight_kg)
        db.add(entry)

    entry.weight_kg = data.weight_kg
    entry.body_fat_percent = data.body_fat_percent
    entry.muscle_mass_kg = data.muscle_mass_kg
    entry.note = data.note
    if data.client_uuid:
        entry.client_uuid = data.client_uuid

    # Keep the profile's "current weight" in step with the newest weigh-in.
    latest_on = await db.scalar(
        select(func.max(BodyWeight.recorded_on)).where(BodyWeight.user_id == user.id)
    )
    if user.profile and (latest_on is None or data.recorded_on >= latest_on):
        user.profile.current_weight_kg = data.weight_kg

    await db.commit()
    await db.refresh(entry)
    return entry


async def list_weights(
    db: AsyncSession,
    user: User,
    *,
    start_date: date | None = None,
    end_date: date | None = None,
    limit: int = 400,
) -> list[BodyWeight]:
    stmt = select(BodyWeight).where(BodyWeight.user_id == user.id)
    if start_date:
        stmt = stmt.where(BodyWeight.recorded_on >= start_date)
    if end_date:
        stmt = stmt.where(BodyWeight.recorded_on <= end_date)
    rows = await db.scalars(stmt.order_by(BodyWeight.recorded_on.desc()).limit(limit))
    return sorted(rows, key=lambda r: r.recorded_on)


async def delete_weight(db: AsyncSession, user: User, entry_id: uuid.UUID) -> None:
    entry = await db.get(BodyWeight, entry_id)
    if entry is None:
        raise NotFoundError("We couldn't find that weight entry.")
    if entry.user_id != user.id:
        raise PermissionError_("That entry belongs to someone else.")
    await db.delete(entry)
    await db.commit()


async def record_measurement(
    db: AsyncSession, user: User, data: MeasurementWrite
) -> BodyMeasurement:
    entry = await db.scalar(
        select(BodyMeasurement).where(
            BodyMeasurement.user_id == user.id,
            BodyMeasurement.recorded_on == data.recorded_on,
            BodyMeasurement.measurement_type == data.measurement_type,
            BodyMeasurement.custom_label == data.custom_label,
        )
    )
    if entry is None:
        entry = BodyMeasurement(
            user_id=user.id,
            recorded_on=data.recorded_on,
            measurement_type=data.measurement_type,
            custom_label=data.custom_label,
            value_cm=data.value_cm,
        )
        db.add(entry)
    entry.value_cm = data.value_cm
    entry.note = data.note
    if data.client_uuid:
        entry.client_uuid = data.client_uuid
    await db.commit()
    await db.refresh(entry)
    return entry


async def list_measurements(
    db: AsyncSession,
    user: User,
    *,
    measurement_type: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
    limit: int = 500,
) -> list[BodyMeasurement]:
    stmt = select(BodyMeasurement).where(BodyMeasurement.user_id == user.id)
    if measurement_type:
        stmt = stmt.where(BodyMeasurement.measurement_type == measurement_type)
    if start_date:
        stmt = stmt.where(BodyMeasurement.recorded_on >= start_date)
    if end_date:
        stmt = stmt.where(BodyMeasurement.recorded_on <= end_date)
    rows = await db.scalars(stmt.order_by(BodyMeasurement.recorded_on.desc()).limit(limit))
    return sorted(rows, key=lambda r: r.recorded_on)


async def delete_measurement(db: AsyncSession, user: User, entry_id: uuid.UUID) -> None:
    entry = await db.get(BodyMeasurement, entry_id)
    if entry is None:
        raise NotFoundError("We couldn't find that measurement.")
    if entry.user_id != user.id:
        raise PermissionError_("That entry belongs to someone else.")
    await db.delete(entry)
    await db.commit()


def _resize(data: bytes, max_edge: int) -> tuple[bytes, int, int]:
    """Downscale and re-encode as JPEG, dropping EXIF (including GPS)."""
    from PIL import Image, ImageOps

    with Image.open(io.BytesIO(data)) as image:
        image = ImageOps.exif_transpose(image)
        image = image.convert("RGB")
        image.thumbnail((max_edge, max_edge), Image.LANCZOS)
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        return buffer.getvalue(), image.width, image.height


async def upload_photo(
    db: AsyncSession,
    user: User,
    *,
    data: bytes,
    content_type: str,
    taken_on: date,
    pose: str,
    weight_kg: float | None = None,
    note: str | None = None,
) -> ProgressPhoto:
    validate_upload(content_type, len(data))

    try:
        processed, width, height = _resize(data, MAX_PHOTO_EDGE)
        thumbnail, _, _ = _resize(data, THUMBNAIL_EDGE)
    except Exception as exc:
        raise ValidationError(
            "We couldn't read that image. Try a different photo.", code="invalid_image"
        ) from exc

    storage = get_storage()
    key = build_key("progress-photos", str(user.id), "image/jpeg", on=taken_on)
    thumb_key = key.replace(".jpg", "_thumb.jpg")

    await storage.put(key, processed, "image/jpeg", visibility=PRIVATE)
    await storage.put(thumb_key, thumbnail, "image/jpeg", visibility=PRIVATE)

    photo = ProgressPhoto(
        user_id=user.id,
        taken_on=taken_on,
        pose=pose,
        storage_key=key,
        thumbnail_key=thumb_key,
        content_type="image/jpeg",
        size_bytes=len(processed),
        width=width,
        height=height,
        weight_kg=weight_kg,
        note=note,
        processed_at=datetime.now(UTC),
    )
    db.add(photo)
    await db.commit()
    await db.refresh(photo)
    return photo


async def list_photos(
    db: AsyncSession,
    user: User,
    *,
    pose: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
    limit: int = 200,
) -> list[ProgressPhoto]:
    stmt = select(ProgressPhoto).where(
        ProgressPhoto.user_id == user.id, ProgressPhoto.is_deleted.is_(False)
    )
    if pose:
        stmt = stmt.where(ProgressPhoto.pose == pose)
    if start_date:
        stmt = stmt.where(ProgressPhoto.taken_on >= start_date)
    if end_date:
        stmt = stmt.where(ProgressPhoto.taken_on <= end_date)
    rows = await db.scalars(stmt.order_by(ProgressPhoto.taken_on.desc()).limit(limit))
    return list(rows)


async def get_photo(db: AsyncSession, user: User, photo_id: uuid.UUID) -> ProgressPhoto:
    photo = await db.get(ProgressPhoto, photo_id)
    if photo is None or photo.is_deleted:
        raise NotFoundError("We couldn't find that photo.")
    if photo.user_id != user.id:
        # Progress photos are private, including from administrators.
        raise PermissionError_("That photo is private.")
    return photo


async def update_photo(
    db: AsyncSession, user: User, photo_id: uuid.UUID, data: ProgressPhotoUpdate
) -> ProgressPhoto:
    photo = await get_photo(db, user, photo_id)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(photo, field, value)
    await db.commit()
    await db.refresh(photo)
    return photo


async def delete_photo(db: AsyncSession, user: User, photo_id: uuid.UUID) -> None:
    photo = await get_photo(db, user, photo_id)
    photo.soft_delete()
    await db.commit()
    storage = get_storage()
    await storage.delete(photo.storage_key)
    if photo.thumbnail_key:
        await storage.delete(photo.thumbnail_key)


async def compare_photos(
    db: AsyncSession, user: User, before_id: uuid.UUID, after_id: uuid.UUID
) -> dict[str, Any]:
    before = await get_photo(db, user, before_id)
    after = await get_photo(db, user, after_id)
    if before.taken_on > after.taken_on:
        before, after = after, before

    weight_change = (
        round(after.weight_kg - before.weight_kg, 2)
        if before.weight_kg and after.weight_kg
        else None
    )
    return {
        "before": serialize_photo(before),
        "after": serialize_photo(after),
        "days_between": (after.taken_on - before.taken_on).days,
        "weight_change_kg": weight_change,
    }


def serialize_photo(photo: ProgressPhoto) -> dict[str, Any]:
    storage = get_storage()
    return {
        "id": str(photo.id),
        "taken_on": photo.taken_on,
        "pose": photo.pose,
        "url": storage.signed_url(photo.storage_key),
        "thumbnail_url": (
            storage.signed_url(photo.thumbnail_key) if photo.thumbnail_key else None
        ),
        "weight_kg": photo.weight_kg,
        "note": photo.note,
        "width": photo.width,
        "height": photo.height,
        "created_at": photo.created_at,
    }


async def summary(db: AsyncSession, user: User, *, window_days: int = 30) -> dict[str, Any]:
    latest = await db.scalar(
        select(BodyWeight)
        .where(BodyWeight.user_id == user.id)
        .order_by(BodyWeight.recorded_on.desc())
        .limit(1)
    )
    change = None
    if latest is not None:
        since = latest.recorded_on - timedelta(days=window_days)
        baseline = await db.scalar(
            select(BodyWeight)
            .where(BodyWeight.user_id == user.id, BodyWeight.recorded_on <= since)
            .order_by(BodyWeight.recorded_on.desc())
            .limit(1)
        )
        if baseline is None:
            baseline = await db.scalar(
                select(BodyWeight)
                .where(BodyWeight.user_id == user.id)
                .order_by(BodyWeight.recorded_on.asc())
                .limit(1)
            )
        if baseline is not None and baseline.id != latest.id:
            change = round(latest.weight_kg - baseline.weight_kg, 2)

    measurement_count = int(
        await db.scalar(
            select(func.count())
            .select_from(BodyMeasurement)
            .where(BodyMeasurement.user_id == user.id)
        )
        or 0
    )
    photo_count = int(
        await db.scalar(
            select(func.count())
            .select_from(ProgressPhoto)
            .where(ProgressPhoto.user_id == user.id, ProgressPhoto.is_deleted.is_(False))
        )
        or 0
    )

    return {
        "latest_weight_kg": latest.weight_kg if latest else None,
        "latest_weight_on": latest.recorded_on if latest else None,
        "weight_change_kg": change,
        "weight_change_period_days": window_days,
        "target_weight_kg": user.profile.target_weight_kg if user.profile else None,
        "latest_body_fat_percent": latest.body_fat_percent if latest else None,
        "measurement_count": measurement_count,
        "photo_count": photo_count,
    }
