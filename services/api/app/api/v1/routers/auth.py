"""Authentication endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status

from app.core.deps import CurrentUser, DbSession, client_ip
from app.core.rate_limit import auth_rate_limit
from app.schemas.auth import (
    ChangePasswordRequest,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    SessionSummary,
    TokenPair,
    VerifyEmailRequest,
)
from app.schemas.common import MessageResponse
from app.schemas.user import UserRead
from app.services import auth_service, user_service

router = APIRouter(prefix="/auth", tags=["auth"])

RateLimited = Annotated[None, Depends(auth_rate_limit)]


class AuthResponse(TokenPair):
    user: UserRead


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create an account",
)
async def register(
    payload: RegisterRequest, request: Request, db: DbSession, _: RateLimited
) -> AuthResponse:
    user, tokens = await auth_service.register(
        db,
        email=payload.email,
        password=payload.password,
        full_name=payload.full_name,
        locale=payload.locale,
        timezone=payload.timezone,
        device=payload.device,
        ip=client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )
    return AuthResponse(**tokens.model_dump(), user=UserRead(**user_service.serialize_user(user)))


@router.post("/login", response_model=AuthResponse, summary="Sign in")
async def login(
    payload: LoginRequest, request: Request, db: DbSession, _: RateLimited
) -> AuthResponse:
    user, tokens = await auth_service.login(
        db,
        email=payload.email,
        password=payload.password,
        device=payload.device,
        ip=client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )
    return AuthResponse(**tokens.model_dump(), user=UserRead(**user_service.serialize_user(user)))


@router.post("/refresh", response_model=TokenPair, summary="Rotate the refresh token")
async def refresh(payload: RefreshRequest, request: Request, db: DbSession) -> TokenPair:
    _user, tokens = await auth_service.refresh(
        db,
        refresh_token=payload.refresh_token,
        ip=client_ip(request),
        user_agent=request.headers.get("user-agent"),
    )
    return tokens


@router.post("/logout", response_model=MessageResponse, summary="Sign out")
async def logout(payload: LogoutRequest, db: DbSession, user: CurrentUser) -> MessageResponse:
    await auth_service.logout(
        db, user=user, refresh_token=payload.refresh_token, all_devices=payload.all_devices
    )
    return MessageResponse(message="You've been signed out.")


@router.post("/forgot-password", response_model=MessageResponse, summary="Request a reset link")
async def forgot_password(
    payload: ForgotPasswordRequest, db: DbSession, _: RateLimited
) -> MessageResponse:
    await auth_service.request_password_reset(db, email=payload.email)
    # Deliberately identical whether or not the address exists.
    return MessageResponse(message="If that email is registered, we've sent a reset link to it.")


@router.post("/reset-password", response_model=MessageResponse, summary="Set a new password")
async def reset_password(
    payload: ResetPasswordRequest, db: DbSession, _: RateLimited
) -> MessageResponse:
    await auth_service.reset_password(db, token=payload.token, new_password=payload.new_password)
    return MessageResponse(message="Your password has been updated. Please sign in.")


@router.post("/verify-email", response_model=UserRead, summary="Confirm an email address")
async def verify_email(payload: VerifyEmailRequest, db: DbSession) -> UserRead:
    user = await auth_service.verify_email(db, token=payload.token)
    return UserRead(**user_service.serialize_user(user))


@router.post(
    "/resend-verification",
    response_model=MessageResponse,
    summary="Resend the confirmation email",
)
async def resend_verification(db: DbSession, user: CurrentUser, _: RateLimited) -> MessageResponse:
    await auth_service.resend_verification(db, user)
    return MessageResponse(message="We've sent a new confirmation link to your inbox.")


@router.post("/change-password", response_model=MessageResponse, summary="Change password")
async def change_password(
    payload: ChangePasswordRequest, db: DbSession, user: CurrentUser, _: RateLimited
) -> MessageResponse:
    await auth_service.change_password(
        db,
        user=user,
        current_password=payload.current_password,
        new_password=payload.new_password,
    )
    return MessageResponse(message="Your password has been updated.")


@router.get("/sessions", response_model=list[SessionSummary], summary="List signed-in devices")
async def list_sessions(db: DbSession, user: CurrentUser) -> list[SessionSummary]:
    sessions = await auth_service.list_sessions(db, user)
    return [
        SessionSummary(
            id=str(session.id),
            device_name=session.device_name,
            platform=session.platform,
            ip_address=session.ip_address,
            created_at=session.created_at,
            last_used_at=session.last_used_at,
            expires_at=session.expires_at,
        )
        for session in sessions
    ]


@router.delete(
    "/sessions/{session_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Sign out one device",
)
async def revoke_session(session_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await auth_service.revoke_session(db, user, session_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/delete-account", response_model=MessageResponse, summary="Delete this account")
async def delete_account(
    payload: DeleteAccountRequest, request: Request, db: DbSession, user: CurrentUser
) -> MessageResponse:
    await auth_service.delete_account(
        db, user=user, password=payload.password, ip=client_ip(request)
    )
    return MessageResponse(message="Your account has been deleted and you've been signed out.")
