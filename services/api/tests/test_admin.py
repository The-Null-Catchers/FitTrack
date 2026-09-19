"""Admin dashboard: access control and aggregates."""

from __future__ import annotations

from datetime import date

import pytest

from tests.test_progress import _png


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/admin/overview",
        "/api/v1/admin/users",
        "/api/v1/admin/audit-logs",
        "/api/v1/admin/storage",
        "/api/v1/admin/health",
        "/api/v1/admin/ai-usage",
    ],
)
async def test_admin_routes_are_closed_to_regular_users(client, auth_headers, path):
    assert (await client.get(path, headers=auth_headers)).status_code == 403


@pytest.mark.parametrize("path", ["/api/v1/admin/overview", "/api/v1/admin/users"])
async def test_admin_routes_require_authentication(client, path):
    assert (await client.get(path)).status_code == 401


async def test_overview_reports_platform_metrics(client, admin_headers, user):
    response = await client.get("/api/v1/admin/overview", headers=admin_headers)
    assert response.status_code == 200

    body = response.json()
    assert body["total_users"] >= 2
    assert body["workouts_completed_total"] == 0
    # Series are gap-filled so charts have no holes.
    assert len(body["registrations_series"]) == 14
    assert len(body["workouts_series"]) == 14


async def test_user_list_is_searchable(client, admin_headers, user):
    response = await client.get("/api/v1/admin/users?q=rider", headers=admin_headers)
    items = response.json()["items"]
    assert [item["email"] for item in items] == [user.email]
    assert items[0]["workout_count"] == 0


async def test_admin_sees_photo_counts_but_never_the_photos(
    client, admin_headers, auth_headers, user
):
    await client.post(
        "/api/v1/progress/photos",
        files={"file": ("front.png", _png(), "image/png")},
        data={"taken_on": str(date.today()), "pose": "front"},
        headers=auth_headers,
    )

    detail = await client.get(f"/api/v1/admin/users/{user.id}", headers=admin_headers)
    assert detail.status_code == 200
    assert detail.json()["progress_photo_count"] == 1
    # No URL, key or any way to reach the image itself.
    assert "url" not in detail.text
    assert "storage_key" not in detail.text

    # And the private photo endpoints are closed to admins too.
    photos = await client.get("/api/v1/progress/photos", headers=admin_headers)
    assert photos.json() == []


async def test_suspending_a_user_revokes_their_sessions(client, admin_headers, auth_headers, user):
    response = await client.patch(
        f"/api/v1/admin/users/{user.id}",
        json={"status": "suspended", "note": "Spam reports"},
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "suspended"
    assert response.json()["session_count"] == 0

    blocked = await client.get("/api/v1/profile", headers=auth_headers)
    assert blocked.status_code == 403
    assert blocked.json()["error"]["code"] == "account_suspended"


async def test_an_admin_cannot_demote_themselves(client, admin_headers, admin_user):
    response = await client.patch(
        f"/api/v1/admin/users/{admin_user.id}",
        json={"role": "user"},
        headers=admin_headers,
    )
    assert response.status_code == 422


async def test_administrative_actions_are_audited(client, admin_headers, user):
    await client.patch(
        f"/api/v1/admin/users/{user.id}",
        json={"status": "suspended", "note": "Policy violation"},
        headers=admin_headers,
    )

    logs = await client.get(
        "/api/v1/admin/audit-logs?action=admin.user_updated", headers=admin_headers
    )
    entries = logs.json()["items"]
    assert entries
    assert entries[0]["entity_id"] == str(user.id)
    assert entries[0]["note"] == "Policy violation"
    assert entries[0]["metadata_json"]["status"] == "suspended"


async def test_login_is_audited(client, admin_headers, user):
    logs = await client.get("/api/v1/admin/audit-logs?action=auth.login", headers=admin_headers)
    assert logs.json()["meta"]["total"] >= 1


async def test_featuring_a_template(client, admin_headers, seeded_library):
    templates = await client.get("/api/v1/admin/templates", headers=admin_headers)
    target = next(t for t in templates.json() if not t["is_featured"])

    response = await client.post(
        f"/api/v1/admin/templates/{target['id']}/feature",
        json={"is_featured": True},
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert response.json()["is_featured"] is True

    featured = await client.get("/api/v1/programs/templates?featured_only=true")
    assert target["id"] in [t["id"] for t in featured.json()]


async def test_system_health_reports_each_dependency(client, admin_headers):
    response = await client.get("/api/v1/admin/health", headers=admin_headers)
    body = response.json()
    assert body["api"] == "ok"
    assert body["database"] == "ok"
    assert "storage" in body
    assert body["uptime_seconds"] >= 0


async def test_public_health_endpoints_need_no_auth(client):
    health = await client.get("/health")
    assert health.status_code == 200
    assert health.json()["status"] == "ok"

    ready = await client.get("/ready")
    assert ready.json()["checks"]["database"] == "ok"
