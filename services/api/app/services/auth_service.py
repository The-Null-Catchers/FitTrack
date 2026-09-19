"""Registration, sign-in, token rotation and account lifecycle."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.errors import AuthenticationError, ConflictError, NotFoundError, ValidationError
from app.core.logging import get_logger
from app.core.security import (
    create_token,
    fingerprint,
    generate_opaque_token,
    hash_password,
    verify_password,
)
from app.models.enums import UserStatus
from app.models.notification import NotificationPreference
from app.models.user import User, UserProfile, UserSession, VerificationToken
from app.providers.email import get_email_provider
from app.schemas.auth import DeviceInfo, TokenPair
from app.services import audit

logger = get_logger(__name__)

PURPOSE_EMAIL_VERIFICATION = "email_verification"
PURPOSE_PASSWORD_RESET = "password_reset"

#: Returned for both "unknown email" and "wrong password" so the endpoint
#: cannot be used to enumerate registered addresses.
_INVALID_CREDENTIALS = "That email and password combination doesn't match an account."

#: A real hash, verified against when the email is unknown, so a miss costs
#: the same time as a wrong password.
_TIMING_EQUALIZER_HASH = "$2b$12$qFgm53L7t7yUaziCoJC5B.1kAOHYp/X8zZcipsjLW4.3j1SfHYT.i"


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def _issue_token_pair(
    db: AsyncSession,
    user: User,
    device: DeviceInfo | None,
    *,
    ip: str | None,
    user_agent: str | None,
    replaces: UserSession | None = None,
) -> TokenPair:
    """Create a session row and the matching access/refresh pair."""
    refresh_token = generate_opaque_token(48)
    expires_at = datetime.now(UTC) + timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS)

    session = UserSession(
        user_id=user.id,
        refresh_token_hash=fingerprint(refresh_token),
        device_name=device.device_name if device else None,
        device_id=device.device_id if device else None,
        platform=device.platform if device else None,
        push_token=device.push_token if device else None,
        ip_address=ip,
        user_agent=(user_agent or "")[:320] or None,
        expires_at=expires_at,
        last_used_at=datetime.now(UTC),
    )
    db.add(session)
    await db.flush()

    if replaces is not None:
        replaces.replaced_by_id = session.id

    access_token, access_expiry = create_token(
        str(user.id), "access", extra_claims={"role": user.role, "sid": str(session.id)}
    )
    return TokenPair(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=int((access_expiry - datetime.now(UTC)).total_seconds()),
        refresh_expires_at=expires_at,
    )


async def _create_verification_token(db: AsyncSession, user: User, purpose: str) -> str:
    token = generate_opaque_token()
    ttl = (
        timedelta(hours=settings.EMAIL_VERIFICATION_TTL_HOURS)
        if purpose == PURPOSE_EMAIL_VERIFICATION
        else timedelta(minutes=settings.PASSWORD_RESET_TTL_MINUTES)
    )
    db.add(
        VerificationToken(
            user_id=user.id,
            purpose=purpose,
            token_hash=fingerprint(token),
            expires_at=datetime.now(UTC) + ttl,
        )
    )
    return token


async def register(
    db: AsyncSession,
    *,
    email: str,
    password: str,
    full_name: str,
    locale: str = "en",
    timezone: str = "UTC",
    device: DeviceInfo | None = None,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[User, TokenPair]:
    email = _normalize_email(email)
    existing = await db.scalar(select(User).where(func.lower(User.email) == email))
    if existing is not None:
        raise ConflictError("An account with that email already exists.", code="email_taken")

    user = User(
        email=email,
        password_hash=hash_password(password),
        full_name=full_name.strip(),
        locale=locale,
        timezone=timezone,
    )
    user.profile = UserProfile(user_id=user.id)
    user.notification_preference = NotificationPreference(user_id=user.id)
    db.add(user)
    await db.flush()

    verification_token = await _create_verification_token(db, user, PURPOSE_EMAIL_VERIFICATION)
    tokens = await _issue_token_pair(db, user, device, ip=ip, user_agent=user_agent)
    await audit.record(
        db,
        action="auth.register",
        actor_id=user.id,
        entity_type="user",
        entity_id=user.id,
        ip_address=ip,
        user_agent=user_agent,
    )
    await db.commit()

    link = f"{settings.APP_PUBLIC_URL}/verify-email?token={verification_token}"
    await get_email_provider().send(
        to=user.email,
        subject="Confirm your FitTrack email",
        body=(
            f"Welcome to FitTrack, {user.full_name}.\n\n"
            f"Confirm your email address to unlock everything:\n{link}\n\n"
            f"This link expires in {settings.EMAIL_VERIFICATION_TTL_HOURS} hours."
        ),
    )
    return user, tokens


async def login(
    db: AsyncSession,
    *,
    email: str,
    password: str,
    device: DeviceInfo | None = None,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[User, TokenPair]:
    email = _normalize_email(email)
    user = await db.scalar(
        select(User).where(func.lower(User.email) == email, User.is_deleted.is_(False))
    )
    if user is None or not user.password_hash:
        # Spend comparable time on the miss so timing doesn't leak existence.
        verify_password(password, _TIMING_EQUALIZER_HASH)
        raise AuthenticationError(_INVALID_CREDENTIALS, code="invalid_credentials")
    if not verify_password(password, user.password_hash):
        await audit.record(
            db,
            action="auth.login_failed",
            actor_id=user.id,
            ip_address=ip,
            user_agent=user_agent,
        )
        await db.commit()
        raise AuthenticationError(_INVALID_CREDENTIALS, code="invalid_credentials")
    if user.status == UserStatus.SUSPENDED:
        raise AuthenticationError(
            "This account has been suspended. Contact support for help.", code="account_suspended"
        )

    user.last_login_at = datetime.now(UTC)
    if user.status == UserStatus.PENDING_DELETION:
        # Signing back in cancels a pending deletion.
        user.status = UserStatus.ACTIVE

    tokens = await _issue_token_pair(db, user, device, ip=ip, user_agent=user_agent)
    await audit.record(
        db, action="auth.login", actor_id=user.id, ip_address=ip, user_agent=user_agent
    )
    await db.commit()
    return user, tokens


async def refresh(
    db: AsyncSession,
    *,
    refresh_token: str,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[User, TokenPair]:
    """Rotate a refresh token.

    Presenting a token that was already rotated is treated as a possible theft:
    every session for that user is revoked.
    """
    token_hash = fingerprint(refresh_token)
    session = await db.scalar(
        select(UserSession).where(UserSession.refresh_token_hash == token_hash)
    )
    if session is None:
        raise AuthenticationError("Please sign in again.", code="invalid_refresh_token")

    now = datetime.now(UTC)
    expires_at = session.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=UTC)

    if session.revoked_at is not None or session.replaced_by_id is not None:
        await db.execute(
            update(UserSession)
            .where(UserSession.user_id == session.user_id, UserSession.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await audit.record(
            db,
            action="auth.refresh_reuse_detected",
            actor_id=session.user_id,
            ip_address=ip,
            note="A rotated refresh token was replayed; all sessions were revoked.",
        )
        await db.commit()
        raise AuthenticationError(
            "For your security we signed you out. Please sign in again.", code="token_reused"
        )
    if expires_at <= now:
        raise AuthenticationError(
            "Your session has expired. Please sign in again.", code="refresh_expired"
        )

    user = await db.scalar(
        select(User).where(User.id == session.user_id, User.is_deleted.is_(False))
    )
    if user is None:
        raise AuthenticationError("That account is no longer available.")

    session.revoked_at = now
    session.last_used_at = now
    device = DeviceInfo(
        device_id=session.device_id,
        device_name=session.device_name,
        platform=session.platform,
        push_token=session.push_token,
    )
    tokens = await _issue_token_pair(
        db, user, device, ip=ip, user_agent=user_agent, replaces=session
    )
    await db.commit()
    return user, tokens


async def logout(
    db: AsyncSession, *, user: User, refresh_token: str | None, all_devices: bool = False
) -> None:
    now = datetime.now(UTC)
    if all_devices or refresh_token is None:
        await db.execute(
            update(UserSession)
            .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
            .values(revoked_at=now)
        )
    else:
        await db.execute(
            update(UserSession)
            .where(
                UserSession.user_id == user.id,
                UserSession.refresh_token_hash == fingerprint(refresh_token),
            )
            .values(revoked_at=now)
        )
    await audit.record(
        db, action="auth.logout", actor_id=user.id, metadata={"all_devices": all_devices}
    )
    await db.commit()


async def list_sessions(db: AsyncSession, user: User) -> list[UserSession]:
    result = await db.scalars(
        select(UserSession)
        .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        .order_by(UserSession.created_at.desc())
    )
    return list(result)


async def revoke_session(db: AsyncSession, user: User, session_id: uuid.UUID) -> None:
    session = await db.scalar(
        select(UserSession).where(UserSession.id == session_id, UserSession.user_id == user.id)
    )
    if session is None:
        raise NotFoundError("We couldn't find that device session.")
    session.revoked_at = datetime.now(UTC)
    await audit.record(
        db,
        action="auth.session_revoked",
        actor_id=user.id,
        entity_type="user_session",
        entity_id=session_id,
    )
    await db.commit()


async def request_password_reset(db: AsyncSession, *, email: str) -> None:
    """Always succeeds from the caller's point of view — no account enumeration."""
    user = await db.scalar(
        select(User).where(
            func.lower(User.email) == _normalize_email(email), User.is_deleted.is_(False)
        )
    )
    if user is None:
        logger.info("auth.password_reset_unknown_email")
        return

    token = await _create_verification_token(db, user, PURPOSE_PASSWORD_RESET)
    await db.commit()

    link = f"{settings.APP_PUBLIC_URL}/reset-password?token={token}"
    await get_email_provider().send(
        to=user.email,
        subject="Reset your FitTrack password",
        body=(
            "We received a request to reset your FitTrack password.\n\n"
            f"Reset it here: {link}\n\n"
            f"The link expires in {settings.PASSWORD_RESET_TTL_MINUTES} minutes. "
            "If you didn't ask for this you can safely ignore this email."
        ),
    )


async def _consume_token(db: AsyncSession, token: str, purpose: str) -> VerificationToken:
    record = await db.scalar(
        select(VerificationToken).where(
            VerificationToken.token_hash == fingerprint(token),
            VerificationToken.purpose == purpose,
        )
    )
    if record is None or record.consumed_at is not None:
        raise ValidationError(
            "That link is no longer valid. Please request a new one.", code="invalid_token"
        )
    expires_at = record.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=UTC)
    if expires_at <= datetime.now(UTC):
        raise ValidationError(
            "That link has expired. Please request a new one.", code="token_expired"
        )
    record.consumed_at = datetime.now(UTC)
    return record


async def reset_password(db: AsyncSession, *, token: str, new_password: str) -> None:
    record = await _consume_token(db, token, PURPOSE_PASSWORD_RESET)
    user = await db.get(User, record.user_id)
    if user is None:
        raise NotFoundError("That account is no longer available.")

    user.password_hash = hash_password(new_password)
    # A password reset invalidates every existing session.
    await db.execute(
        update(UserSession)
        .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    await audit.record(db, action="auth.password_reset", actor_id=user.id)
    await db.commit()


async def verify_email(db: AsyncSession, *, token: str) -> User:
    record = await _consume_token(db, token, PURPOSE_EMAIL_VERIFICATION)
    user = await db.get(User, record.user_id)
    if user is None:
        raise NotFoundError("That account is no longer available.")
    if user.email_verified_at is None:
        user.email_verified_at = datetime.now(UTC)
    await audit.record(db, action="auth.email_verified", actor_id=user.id)
    await db.commit()
    return user


async def resend_verification(db: AsyncSession, user: User) -> None:
    if user.email_verified:
        raise ConflictError("Your email address is already confirmed.", code="already_verified")
    token = await _create_verification_token(db, user, PURPOSE_EMAIL_VERIFICATION)
    await db.commit()
    link = f"{settings.APP_PUBLIC_URL}/verify-email?token={token}"
    await get_email_provider().send(
        to=user.email,
        subject="Confirm your FitTrack email",
        body=f"Confirm your email address:\n{link}",
    )


async def change_password(
    db: AsyncSession, *, user: User, current_password: str, new_password: str
) -> None:
    if not user.password_hash or not verify_password(current_password, user.password_hash):
        raise AuthenticationError(
            "Your current password isn't correct.", code="invalid_credentials"
        )
    user.password_hash = hash_password(new_password)
    await audit.record(db, action="auth.password_changed", actor_id=user.id)
    await db.commit()


async def delete_account(
    db: AsyncSession, *, user: User, password: str | None, ip: str | None = None
) -> None:
    """Soft-delete the account and revoke access immediately.

    Hard deletion of the user's data is handled by a background job so the
    request stays fast even for large accounts.
    """
    if user.password_hash and (not password or not verify_password(password, user.password_hash)):
        raise AuthenticationError(
            "Please confirm your password to delete your account.",
            code="invalid_credentials",
        )

    user.status = UserStatus.PENDING_DELETION
    user.soft_delete()
    # Free the address so the person can sign up again later.
    user.email = f"deleted+{user.id.hex}@fittrack.invalid"
    await db.execute(
        update(UserSession)
        .where(UserSession.user_id == user.id, UserSession.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    await audit.record(
        db,
        action="account.deleted",
        actor_id=user.id,
        entity_type="user",
        entity_id=user.id,
        ip_address=ip,
    )
    await db.commit()
