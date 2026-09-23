"""Exercise library: search, filters and ownership rules."""

from __future__ import annotations

CUSTOM = {
    "name": "Landmine Press",
    "muscle_group": "shoulders",
    "equipment": "barbell",
    "difficulty": "intermediate",
    "exercise_type": "strength",
    "default_tracking_type": "weight_reps",
    "instructions": ["Wedge one end of the bar into a corner."],
}


async def test_library_is_readable_and_paginated(client, seeded_library):
    response = await client.get("/api/v1/exercises?per_page=10")
    assert response.status_code == 200

    body = response.json()
    assert len(body["items"]) == 10
    assert body["meta"]["total"] > 50
    assert body["meta"]["has_next"] is True


async def test_search_matches_name_and_muscle_group(client, seeded_library):
    by_name = await client.get("/api/v1/exercises?q=bench")
    names = [item["name"].lower() for item in by_name.json()["items"]]
    assert any("bench" in name for name in names)

    by_group = await client.get("/api/v1/exercises?muscle_group=legs&per_page=50")
    assert by_group.json()["items"]
    assert all(item["muscle_group"] == "legs" for item in by_group.json()["items"])


async def test_filters_combine(client, seeded_library):
    response = await client.get(
        "/api/v1/exercises?muscle_group=chest&equipment=bodyweight&per_page=50"
    )
    items = response.json()["items"]
    assert items
    for item in items:
        assert item["muscle_group"] == "chest"
        assert item["equipment"] == "bodyweight"


async def test_filter_options_are_exposed(client):
    response = await client.get("/api/v1/exercises/filters")
    body = response.json()
    assert "chest" in body["muscle_groups"]
    assert "kettlebell" in body["equipment"]
    assert "weight_reps" in body["tracking_types"]


async def test_detail_includes_instructions(client, seeded_library, auth_headers):
    listing = await client.get("/api/v1/exercises?q=bench press")
    exercise_id = listing.json()["items"][0]["id"]

    detail = await client.get(f"/api/v1/exercises/{exercise_id}", headers=auth_headers)
    assert detail.status_code == 200
    assert isinstance(detail.json()["instructions"], list)
    assert detail.json()["media"] == []


async def test_custom_exercise_is_private_to_its_creator(client, db, auth_headers, seeded_library):
    created = await client.post("/api/v1/exercises", json=CUSTOM, headers=auth_headers)
    assert created.status_code == 201
    assert created.json()["is_public"] is False
    exercise_id = created.json()["id"]

    # Visible to the owner…
    mine = await client.get("/api/v1/exercises?q=landmine", headers=auth_headers)
    assert [item["id"] for item in mine.json()["items"]] == [exercise_id]

    # …and invisible to everyone else.
    from tests.conftest import _make_user

    other = await _make_user(db, email="other@example.com", full_name="Other Person")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]
    theirs = await client.get(
        "/api/v1/exercises?q=landmine", headers={"Authorization": f"Bearer {token}"}
    )
    assert theirs.json()["items"] == []

    denied = await client.get(
        f"/api/v1/exercises/{exercise_id}", headers={"Authorization": f"Bearer {token}"}
    )
    assert denied.status_code == 404


async def test_a_user_cannot_publish_to_the_shared_library(client, auth_headers):
    created = await client.post("/api/v1/exercises", json=CUSTOM, headers=auth_headers)
    exercise_id = created.json()["id"]

    response = await client.patch(
        f"/api/v1/exercises/{exercise_id}", json={"is_public": True}, headers=auth_headers
    )
    assert response.status_code == 200
    assert response.json()["is_public"] is False


async def test_a_user_cannot_edit_a_library_exercise(client, seeded_library, auth_headers):
    listing = await client.get("/api/v1/exercises?per_page=1")
    exercise_id = listing.json()["items"][0]["id"]

    response = await client.patch(
        f"/api/v1/exercises/{exercise_id}", json={"name": "Hijacked"}, headers=auth_headers
    )
    assert response.status_code == 403


async def test_admin_can_publish_a_library_exercise(client, admin_headers):
    response = await client.post("/api/v1/admin/exercises", json=CUSTOM, headers=admin_headers)
    assert response.status_code == 200
    assert response.json()["is_public"] is True


async def test_admin_routes_reject_normal_users(client, auth_headers):
    response = await client.post("/api/v1/admin/exercises", json=CUSTOM, headers=auth_headers)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"
