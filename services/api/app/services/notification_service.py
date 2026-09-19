"""Notification creation, preferences and delivery."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, time
from typing import Any

from sqlalchemy import func, select, update as sa_update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import NotFoundError, PermissionError_
from app.models.enums import NotificationType
from app.models.notification import Notification, NotificationPreference
from app.models.user import User, UserSession
from app.providers.push import PushMessage, get_push_provider
from app.schemas.common import PaginationParams
from app.schemas.notification import NotificationPreferenceUpdate

#: Which preference flag gates each notification type.
_PREFERENCE_FLAG = {
    NotificationType.WORKOUT_REMINDER: "workout_reminders",
    NotificationType.GOAL_REMINDER: "goal_reminders",
    NotificationType.HABIT_REMINDER: "habit_reminders",
    NotificationType.PROGRESS_REMINDER: "progress_reminders",
    NotificationType.WEEKLY_SUMMARY: "weekly_summary",
    NotificationType.PERSONAL_RECORD: "personal_record_alerts",
}


async def get_preferences(db: AsyncSession, user: User) -> NotificationPreference:
    preference = user.notification_preference
    if preference is None:
        preference = NotificationPreference(user_id=user.id)
        db.add(preference)
        await db.commit()
        await db.refresh(preference)
        user.notification_preference = preference
    return preference


async def update_preferences(
    db: AsyncSession, user: User, data: NotificationPreferenceUpdate
) -> NotificationPreference:
    preference = await get_preferences(db, user)
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(preference, field, value)
    await db.commit()
    await db.refresh(preference)
    return preference


def _parse_hhmm(value: str | None) -> time | None:
    if not value:
        return None
    hour, _, minute = value.partition(":")
    try:
        return time(int(hour), int(minute))
    except ValueError:
        return None


def in_quiet_hours(preference: NotificationPreference, at: datetime) -> bool:
    """Quiet hours may wrap past midnight (e.g. 22:00 -> 07:00)."""
    start = _parse_hhmm(preference.quiet_hours_start)
    end = _parse_hhmm(preference.quiet_hours_end)
    if start is None or end is None:
        return False
    now = at.time()
    if start <= end:
        return start <= now < end
    return now >= start or now < end


def allows(preference: NotificationPreference, notification_type: str) -> bool:
    flag = _PREFERENCE_FLAG.get(NotificationType(notification_type))
    return getattr(preference, flag, True) if flag else True


async def create(
    db: AsyncSession,
    user_id: uuid.UUID,
    *,
    notification_type: str,
    title: str,
    body: str,
    deep_link: str | None = None,
    data: dict[str, Any] | None = None,
    deliver_push: bool = True,
) -> Notification | None:
    """Create an in-app notification and optionally deliver a push.

    Returns ``None`` when the user's preferences suppress this type.
    """
    preference = await db.scalar(
        select(NotificationPreference).where(NotificationPreference.user_id == user_id)
    )
    if preference is not None and not allows(preference, notification_type):
        return None

    notification = Notification(
        user_id=user_id,
        type=notification_type,
        title=title,
        body=body,
        deep_link=deep_link,
        data=data or {},
    )
    db.add(notification)
    await db.flush()

    if (
        deliver_push
        and preference is not None
        and preference.push_enabled
        and not in_quiet_hours(preference, datetime.now(UTC))
    ):
        await _deliver_push(db, user_id, notification)
        notification.sent_at = datetime.now(UTC)

    return notification


async def _deliver_push(
    db: AsyncSession, user_id: uuid.UUID, notification: Notification
) -> None:
    tokens = await db.scalars(
        select(UserSession.push_token).where(
            UserSession.user_id == user_id,
            UserSession.push_token.is_not(None),
            UserSession.revoked_at.is_(None),
        )
    )
    unique = {token for token in tokens if token}
    if not unique:
        return
    provider = get_push_provider()
    await provider.send_many(
        [
            PushMessage(
                token=token,
                title=notification.title,
                body=notification.body,
                data={"deep_link": notification.deep_link or "", "type": notification.type},
            )
            for token in unique
        ]
    )


async def list_for_user(
    db: AsyncSession, user: User, *, pagination: PaginationParams, unread_only: bool = False
) -> tuple[list[Notification], int]:
    base = select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        base = base.where(Notification.read_at.is_(None))
    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    rows = await db.scalars(
        base.order_by(Notification.created_at.desc())
        .offset(pagination.offset)
        .limit(pagination.per_page)
    )
    return list(rows), total


async def unread_count(db: AsyncSession, user: User) -> int:
    return int(
        await db.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        )
        or 0
    )


async def mark_read(db: AsyncSession, user: User, notification_id: uuid.UUID) -> Notification:
    notification = await db.get(Notification, notification_id)
    if notification is None:
        raise NotFoundError("We couldn't find that notification.")
    if notification.user_id != user.id:
        raise PermissionError_("That notification belongs to someone else.")
    if notification.read_at is None:
        notification.read_at = datetime.now(UTC)
        await db.commit()
    return notification


async def mark_all_read(db: AsyncSession, user: User) -> int:
    result = await db.execute(
        sa_update(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )
    await db.commit()
    return int(result.rowcount or 0)


async def register_push_token(
    db: AsyncSession, user: User, *, push_token: str, platform: str | None = None
) -> None:
    """Attach a device push token to the caller's most recent live session."""
    session = await db.scalar(
        select(UserSession)
        .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        .order_by(UserSession.created_at.desc())
        .limit(1)
    )
    if session is None:
        return
    session.push_token = push_token
    if platform:
        session.platform = platform
    await db.commit()


async def notify_personal_records(
    db: AsyncSession, user: User, records: list[Any]
) -> None:
    """One summary notification per workout rather than one per record."""
    if not records:
        return
    names = {record.exercise.name for record in records if record.exercise}
    headline = ", ".join(sorted(names)[:3])
    more = len(names) - 3
    if more > 0:
        headline += f" and {more} more"
    await create(
        db,
        user.id,
        notification_type=NotificationType.PERSONAL_RECORD,
        title=f"New personal record{'s' if len(records) > 1 else ''}",
        body=f"You set {len(records)} new record{'s' if len(records) > 1 else ''} on {headline}.",
        deep_link="/progress/records",
        data={"count": len(records)},
    )


def serialize(notification: Notification) -> dict[str, Any]:
    return {
        "id": str(notification.id),
        "type": notification.type,
        "title": notification.title,
        "body": notification.body,
        "deep_link": notification.deep_link,
        "data": notification.data or {},
        "read_at": notification.read_at,
        "created_at": notification.created_at,
    }
