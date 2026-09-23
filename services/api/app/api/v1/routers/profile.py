"""Profile, onboarding, settings and data export."""

from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, File, Response, UploadFile, status

from app.core.deps import CurrentUser, DbSession
from app.schemas.common import MessageResponse
from app.schemas.user import (
    AvatarUploadResponse,
    NutritionTargetEstimate,
    NutritionTargetUpdate,
    OnboardingRequest,
    ProfileRead,
    ProfileUpdate,
    UserRead,
    UserUpdate,
)
from app.services import user_service
from app.storage import PUBLIC, build_key, get_storage, validate_upload

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=UserRead, summary="Current user and profile")
async def me(user: CurrentUser) -> UserRead:
    return UserRead(**user_service.serialize_user(user))


@router.patch("", response_model=UserRead, summary="Update account details")
async def update_me(payload: UserUpdate, db: DbSession, user: CurrentUser) -> UserRead:
    updated = await user_service.update_user(db, user, payload)
    return UserRead(**user_service.serialize_user(updated))


@router.patch("/fitness", response_model=ProfileRead, summary="Update fitness profile")
async def update_profile(payload: ProfileUpdate, db: DbSession, user: CurrentUser) -> ProfileRead:
    profile = await user_service.update_profile(db, user, payload)
    return ProfileRead.model_validate(profile)


@router.post(
    "/onboarding",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
    summary="Complete onboarding",
)
async def complete_onboarding(
    payload: OnboardingRequest, db: DbSession, user: CurrentUser
) -> UserRead:
    await user_service.complete_onboarding(db, user, payload)
    await db.refresh(user)
    return UserRead(**user_service.serialize_user(user))


@router.get(
    "/nutrition-targets/estimate",
    response_model=NutritionTargetEstimate,
    summary="Estimate calorie and macro targets",
)
async def estimate_targets(db: DbSession, user: CurrentUser) -> NutritionTargetEstimate:
    return NutritionTargetEstimate(**await user_service.estimate_nutrition_targets(db, user))


@router.put(
    "/nutrition-targets",
    response_model=ProfileRead,
    summary="Set targets manually",
)
async def set_targets(
    payload: NutritionTargetUpdate, db: DbSession, user: CurrentUser
) -> ProfileRead:
    profile = await user_service.update_nutrition_targets(db, user, payload)
    return ProfileRead.model_validate(profile)


@router.post(
    "/nutrition-targets/use-estimate",
    response_model=ProfileRead,
    summary="Adopt the estimated targets",
)
async def use_estimate(db: DbSession, user: CurrentUser) -> ProfileRead:
    profile = await user_service.apply_estimated_targets(db, user)
    return ProfileRead.model_validate(profile)


@router.post("/avatar", response_model=AvatarUploadResponse, summary="Upload an avatar")
async def upload_avatar(
    db: DbSession,
    user: CurrentUser,
    file: Annotated[UploadFile, File(description="JPEG, PNG or WebP image")],
) -> AvatarUploadResponse:
    data = await file.read()
    content_type = file.content_type or "application/octet-stream"
    validate_upload(content_type, len(data))

    from app.services.body_service import _resize

    processed, _, _ = _resize(data, 512)
    key = build_key("avatars", str(user.id), "image/jpeg")
    await get_storage().put(key, processed, "image/jpeg", visibility=PUBLIC)
    await user_service.set_avatar(db, user, key)
    return AvatarUploadResponse(avatar_url=get_storage().public_url(key))


@router.get("/export", summary="Download a full export of your data")
async def export_data(db: DbSession, user: CurrentUser) -> Response:
    payload = await user_service.build_data_export(db, user)
    return Response(
        content=json.dumps(payload, indent=2),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="fittrack-export-{user.id}.json"'},
    )


@router.get("/statistics", summary="Counts of everything stored for this account")
async def statistics(db: DbSession, user: CurrentUser) -> dict[str, int]:
    return await user_service.account_statistics(db, user)


@router.post(
    "/privacy/acknowledge",
    response_model=MessageResponse,
    summary="Record that the privacy notice was seen",
)
async def acknowledge_privacy(user: CurrentUser) -> MessageResponse:
    return MessageResponse(message="Thanks — your preferences are saved on this device.")
