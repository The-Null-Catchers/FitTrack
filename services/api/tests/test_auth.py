"""Registration, sign-in, token rotation and account lifecycle."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.models.user import User, UserSession
from tests.conftest import TEST_PASSWORD

REGISTER_PAYLOAD = {
    "email": "newcomer@example.com",
    "password": "StrongPass123!",
    "full_name": "New Comer",
}


async def test_register_creates_user_and_returns_tokens(client):
    response = await client.post("/api/v1/auth/register", json=REGISTER_PAYLOAD)
    assert response.status_code == 201, response.text

    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["email"] == "newcomer@example.com"
    assert body["user"]["onboarding_completed"] is False
    # A profile row is created up front so onboarding can just fill it in.
    assert body["user"]["profile"] is not None


async def test_register_rejects_duplicate_email(client, user):
    response = await client.post(
        "/api/v1/auth/register",
        json={**REGISTER_PAYLOAD, "email": user.email},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "email_taken"


@pytest.mark.parametrize("password", ["short", "alllowercase", "12345678"])
async def test_register_rejects_weak_passwords(client, password):
    response = await client.post(
        "/api/v1/auth/register", json={**REGISTER_PAYLOAD, "password": password}
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


async def test_login_succeeds_and_is_case_insensitive(client, user):
    response = await client.post(
        "/api/v1/auth/login",
        json={"email": user.email.upper(), "password": TEST_PASSWORD},
    )
    assert response.status_code == 200
    assert response.json()["user"]["id"] == str(user.id)


async def test_login_with_wrong_password_is_generic(client, user):
    response = await client.post(
        "/api/v1/auth/login", json={"email": user.email, "password": "WrongPass123!"}
    )
    assert response.status_code == 401
    body = response.json()["error"]
    assert body["code"] == "invalid_credentials"
    # The same message is returned for an unknown address — no enumeration.
    unknown = await client.post(
        "/api/v1/auth/login",
        json={"email": "nobody@example.com", "password": "WrongPass123!"},
    )
    assert unknown.json()["error"]["message"] == body["message"]


async def test_protected_route_requires_token(client):
    assert (await client.get("/api/v1/profile")).status_code == 401


async def test_refresh_rotates_tokens(client, user):
    login = await client.post(
        "/api/v1/auth/login", json={"email": user.email, "password": TEST_PASSWORD}
    )
    original = login.json()["refresh_token"]

    refreshed = await client.post("/api/v1/auth/refresh", json={"refresh_token": original})
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != original


async def test_replaying_a_rotated_refresh_token_revokes_every_session(
    client, db, user
):
    login = await client.post(
        "/api/v1/auth/login", json={"email": user.email, "password": TEST_PASSWORD}
    )
    original = login.json()["refresh_token"]
    await client.post("/api/v1/auth/refresh", json={"refresh_token": original})

    replay = await client.post("/api/v1/auth/refresh", json={"refresh_token": original})
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == "token_reused"

    live = await db.scalars(
        select(UserSession).where(
            UserSession.user_id == user.id, UserSession.revoked_at.is_(None)
        )
    )
    assert list(live) == []


async def test_logout_revokes_the_session(client, db, user, auth_headers):
    response = await client.post(
        "/api/v1/auth/logout", json={"all_devices": True}, headers=auth_headers
    )
    assert response.status_code == 200
    live = await db.scalars(
        select(UserSession).where(
            UserSession.user_id == user.id, UserSession.revoked_at.is_(None)
        )
    )
    assert list(live) == []


async def test_forgot_password_never_reveals_whether_the_account_exists(client, user):
    known = await client.post("/api/v1/auth/forgot-password", json={"email": user.email})
    unknown = await client.post(
        "/api/v1/auth/forgot-password", json={"email": "ghost@example.com"}
    )
    assert known.status_code == unknown.status_code == 200
    assert known.json() == unknown.json()


async def test_password_reset_flow_end_to_end(client, db, user):
    from app.core.security import fingerprint, generate_opaque_token
    from datetime import UTC, datetime, timedelta

    from app.models.user import VerificationToken
    from app.services.auth_service import PURPOSE_PASSWORD_RESET

    token = generate_opaque_token()
    db.add(
        VerificationToken(
            user_id=user.id,
            purpose=PURPOSE_PASSWORD_RESET,
            token_hash=fingerprint(token),
            expires_at=datetime.now(UTC) + timedelta(minutes=30),
        )
    )
    await db.commit()

    response = await client.post(
        "/api/v1/auth/reset-password",
        json={"token": token, "new_password": "BrandNewPass9!"},
    )
    assert response.status_code == 200

    # The old password no longer works; the new one does.
    assert (
        await client.post(
            "/api/v1/auth/login", json={"email": user.email, "password": TEST_PASSWORD}
        )
    ).status_code == 401
    assert (
        await client.post(
            "/api/v1/auth/login",
            json={"email": user.email, "password": "BrandNewPass9!"},
        )
    ).status_code == 200

    # A reset link is single-use.
    reused = await client.post(
        "/api/v1/auth/reset-password",
        json={"token": token, "new_password": "AnotherPass9!"},
    )
    assert reused.status_code == 422


async def test_delete_account_soft_deletes_and_frees_the_email(client, db, user, auth_headers):
    response = await client.post(
        "/api/v1/auth/delete-account",
        json={"password": TEST_PASSWORD, "confirmation": "DELETE"},
        headers=auth_headers,
    )
    assert response.status_code == 200

    refreshed = await db.get(User, user.id)
    await db.refresh(refreshed)
    assert refreshed.is_deleted is True
    assert refreshed.email != "rider@example.com"

    # The address can be registered again.
    again = await client.post(
        "/api/v1/auth/register",
        json={**REGISTER_PAYLOAD, "email": "rider@example.com"},
    )
    assert again.status_code == 201
