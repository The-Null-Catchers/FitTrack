"""Body tracking, progress photos and analytics."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile, status

from app.core.deps import CurrentUser, DbSession
from app.core.rate_limit import upload_rate_limit
from app.models.enums import MeasurementType, PhotoPose
from app.schemas.analytics import (
    ChartResponse,
    DashboardResponse,
    ExerciseProgressResponse,
    TrainingOverview,
)
from app.schemas.body import (
    BodySummary,
    BodyWeightRead,
    BodyWeightWrite,
    MeasurementRead,
    MeasurementWrite,
    PhotoComparison,
    ProgressPhotoRead,
    ProgressPhotoUpdate,
)
from app.schemas.common import TimeRange
from app.schemas.exercise import ExerciseSummary
from app.services import analytics_service, body_service, goal_service

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("/dashboard", response_model=DashboardResponse, summary="Home dashboard")
async def dashboard(db: DbSession, user: CurrentUser) -> DashboardResponse:
    return DashboardResponse(**await analytics_service.dashboard(db, user))


@router.get("/summary", response_model=BodySummary, summary="Body tracking summary")
async def body_summary(db: DbSession, user: CurrentUser) -> BodySummary:
    return BodySummary(**await body_service.summary(db, user))


# --- body weight -------------------------------------------------------


@router.get("/weights", response_model=list[BodyWeightRead], summary="Weight history")
async def list_weights(
    db: DbSession,
    user: CurrentUser,
    start_date: date | None = None,
    end_date: date | None = None,
) -> list[BodyWeightRead]:
    rows = await body_service.list_weights(db, user, start_date=start_date, end_date=end_date)
    return [BodyWeightRead(id=str(r.id), **_columns(r, BodyWeightWrite)) for r in rows]


def _columns(row, schema) -> dict:
    payload = {field: getattr(row, field) for field in schema.model_fields if hasattr(row, field)}
    payload["created_at"] = row.created_at
    return payload


@router.post(
    "/weights",
    response_model=BodyWeightRead,
    status_code=status.HTTP_201_CREATED,
    summary="Log body weight",
)
async def log_weight(payload: BodyWeightWrite, db: DbSession, user: CurrentUser) -> BodyWeightRead:
    entry = await body_service.record_weight(db, user, payload)
    await goal_service.refresh_all(db, user)
    await db.commit()
    return BodyWeightRead(id=str(entry.id), **_columns(entry, BodyWeightWrite))


@router.delete(
    "/weights/{entry_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a weight entry",
)
async def delete_weight(entry_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await body_service.delete_weight(db, user, entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- measurements ------------------------------------------------------


@router.get("/measurements", response_model=list[MeasurementRead], summary="Measurement history")
async def list_measurements(
    db: DbSession,
    user: CurrentUser,
    measurement_type: MeasurementType | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> list[MeasurementRead]:
    rows = await body_service.list_measurements(
        db,
        user,
        measurement_type=measurement_type.value if measurement_type else None,
        start_date=start_date,
        end_date=end_date,
    )
    return [MeasurementRead(id=str(r.id), **_columns(r, MeasurementWrite)) for r in rows]


@router.post(
    "/measurements",
    response_model=MeasurementRead,
    status_code=status.HTTP_201_CREATED,
    summary="Log a measurement",
)
async def log_measurement(
    payload: MeasurementWrite, db: DbSession, user: CurrentUser
) -> MeasurementRead:
    entry = await body_service.record_measurement(db, user, payload)
    await goal_service.refresh_all(db, user)
    await db.commit()
    return MeasurementRead(id=str(entry.id), **_columns(entry, MeasurementWrite))


@router.delete(
    "/measurements/{entry_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a measurement",
)
async def delete_measurement(entry_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await body_service.delete_measurement(db, user, entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- progress photos ---------------------------------------------------


@router.get("/photos", response_model=list[ProgressPhotoRead], summary="Progress photos")
async def list_photos(
    db: DbSession,
    user: CurrentUser,
    pose: PhotoPose | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
) -> list[ProgressPhotoRead]:
    rows = await body_service.list_photos(
        db, user, pose=pose.value if pose else None, start_date=start_date, end_date=end_date
    )
    return [ProgressPhotoRead(**body_service.serialize_photo(row)) for row in rows]


@router.post(
    "/photos",
    response_model=ProgressPhotoRead,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a private progress photo",
    dependencies=[Depends(upload_rate_limit)],
)
async def upload_photo(
    db: DbSession,
    user: CurrentUser,
    file: Annotated[UploadFile, File(description="JPEG, PNG or WebP image")],
    taken_on: Annotated[date, Form()],
    pose: Annotated[PhotoPose, Form()] = PhotoPose.FRONT,
    weight_kg: Annotated[float | None, Form()] = None,
    note: Annotated[str | None, Form()] = None,
) -> ProgressPhotoRead:
    data = await file.read()
    photo = await body_service.upload_photo(
        db,
        user,
        data=data,
        content_type=file.content_type or "application/octet-stream",
        taken_on=taken_on,
        pose=pose.value,
        weight_kg=weight_kg,
        note=note,
    )
    return ProgressPhotoRead(**body_service.serialize_photo(photo))


@router.get("/photos/compare", response_model=PhotoComparison, summary="Compare two photos")
async def compare_photos(
    before_id: uuid.UUID, after_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> PhotoComparison:
    return PhotoComparison(**await body_service.compare_photos(db, user, before_id, after_id))


@router.patch("/photos/{photo_id}", response_model=ProgressPhotoRead, summary="Edit photo details")
async def update_photo(
    photo_id: uuid.UUID,
    payload: ProgressPhotoUpdate,
    db: DbSession,
    user: CurrentUser,
) -> ProgressPhotoRead:
    photo = await body_service.update_photo(db, user, photo_id, payload)
    return ProgressPhotoRead(**body_service.serialize_photo(photo))


@router.delete(
    "/photos/{photo_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a progress photo",
)
async def delete_photo(photo_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await body_service.delete_photo(db, user, photo_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- charts ------------------------------------------------------------


@router.get("/charts/weight", response_model=ChartResponse, summary="Body weight chart")
async def weight_chart(db: DbSession, user: CurrentUser, range: TimeRange = "30d") -> ChartResponse:
    return ChartResponse(**await analytics_service.body_weight_chart(db, user, time_range=range))


@router.get("/charts/measurements", response_model=ChartResponse, summary="Measurement chart")
async def measurement_chart(
    db: DbSession,
    user: CurrentUser,
    measurement_type: MeasurementType,
    range: TimeRange = "6m",
) -> ChartResponse:
    return ChartResponse(
        **await analytics_service.measurement_chart(
            db, user, measurement_type=measurement_type.value, time_range=range
        )
    )


@router.get("/charts/volume", response_model=ChartResponse, summary="Volume and frequency chart")
async def volume_chart(db: DbSession, user: CurrentUser, range: TimeRange = "30d") -> ChartResponse:
    return ChartResponse(**await analytics_service.volume_chart(db, user, time_range=range))


@router.get("/charts/nutrition", response_model=ChartResponse, summary="Calories and protein chart")
async def nutrition_chart(
    db: DbSession, user: CurrentUser, range: TimeRange = "30d"
) -> ChartResponse:
    return ChartResponse(**await analytics_service.nutrition_chart(db, user, time_range=range))


@router.get("/exercises", response_model=list[ExerciseSummary], summary="Exercises you've trained")
async def trained_exercises(
    db: DbSession, user: CurrentUser, limit: int = Query(40, ge=1, le=100)
) -> list[ExerciseSummary]:
    rows = await analytics_service.trained_exercises(db, user, limit=limit)
    return [ExerciseSummary(**row) for row in rows]


@router.get(
    "/exercises/{exercise_id}",
    response_model=ExerciseProgressResponse,
    summary="Progression for one exercise",
)
async def exercise_progress(
    exercise_id: uuid.UUID,
    db: DbSession,
    user: CurrentUser,
    range: TimeRange = "6m",
) -> ExerciseProgressResponse:
    return ExerciseProgressResponse(
        **await analytics_service.exercise_progress(db, user, exercise_id, time_range=range)
    )


@router.get("/overview", response_model=TrainingOverview, summary="Training overview and totals")
async def overview(db: DbSession, user: CurrentUser, range: TimeRange = "30d") -> TrainingOverview:
    return TrainingOverview(**await analytics_service.training_overview(db, user, time_range=range))
