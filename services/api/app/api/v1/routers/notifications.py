"""Notification endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter

from app.core.deps import CurrentUser, DbSession, Pagination
from app.schemas.common import MessageResponse, Page
from app.schemas.notification import (
    NotificationPreferenceRead,
    NotificationPreferenceUpdate,
    NotificationRead,
    PushTokenRegister,
    UnreadCount,
)
from app.services import notification_service

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=Page[NotificationRead], summary="Your notifications")
async def list_notifications(
    db: DbSession, user: CurrentUser, pagination: Pagination, unread_only: bool = False
) -> Page[NotificationRead]:
    rows, total = await notification_service.list_for_user(
        db, user, pagination=pagination, unread_only=unread_only
    )
    return Page.build(
        [NotificationRead(**notification_service.serialize(row)) for row in rows],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.get("/unread-count", response_model=UnreadCount, summary="Unread count")
async def unread_count(db: DbSession, user: CurrentUser) -> UnreadCount:
    return UnreadCount(unread=await notification_service.unread_count(db, user))


@router.post("/{notification_id}/read", response_model=NotificationRead, summary="Mark as read")
async def mark_read(
    notification_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> NotificationRead:
    notification = await notification_service.mark_read(db, user, notification_id)
    return NotificationRead(**notification_service.serialize(notification))


@router.post("/read-all", response_model=MessageResponse, summary="Mark all as read")
async def mark_all_read(db: DbSession, user: CurrentUser) -> MessageResponse:
    count = await notification_service.mark_all_read(db, user)
    return MessageResponse(message=f"Marked {count} notifications as read.")


@router.get(
    "/preferences",
    response_model=NotificationPreferenceRead,
    summary="Notification preferences",
)
async def get_preferences(db: DbSession, user: CurrentUser) -> NotificationPreferenceRead:
    preference = await notification_service.get_preferences(db, user)
    return NotificationPreferenceRead.model_validate(preference)


@router.patch(
    "/preferences",
    response_model=NotificationPreferenceRead,
    summary="Update notification preferences",
)
async def update_preferences(
    payload: NotificationPreferenceUpdate, db: DbSession, user: CurrentUser
) -> NotificationPreferenceRead:
    preference = await notification_service.update_preferences(db, user, payload)
    return NotificationPreferenceRead.model_validate(preference)


@router.post("/push-token", response_model=MessageResponse, summary="Register a device push token")
async def register_push_token(
    payload: PushTokenRegister, db: DbSession, user: CurrentUser
) -> MessageResponse:
    await notification_service.register_push_token(
        db, user, push_token=payload.push_token, platform=payload.platform
    )
    return MessageResponse(message="Push notifications are enabled on this device.")
