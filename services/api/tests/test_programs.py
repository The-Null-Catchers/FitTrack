"""Workout programs and templates."""

from __future__ import annotations

import pytest


@pytest.fixture
async def exercise_ids(client, seeded_library):
    listing = await client.get("/api/v1/exercises?muscle_group=chest&per_page=3")
    return [item["id"] for item in listing.json()["items"]]


def _program_payload(exercise_ids: list[str]) -> dict:
    return {
        "name": "My Push Plan",
        "description": "Chest-focused push day",
        "goal": "gain_muscle",
        "difficulty": "intermediate",
        "location": "gym",
        "days_per_week": 3,
        "estimated_minutes": 60,
        "days": [
            {
                "name": "Push",
                "weekday": 0,
                "exercises": [
                    {
                        "exercise_id": exercise_id,
                        "target_sets": 4,
                        "target_reps_min": 6,
                        "target_reps_max": 10,
                        "rest_seconds": 120,
                    }
                    for exercise_id in exercise_ids
                ],
            }
        ],
    }


async def test_create_program_with_days_and_exercises(client, auth_headers, exercise_ids):
    response = await client.post(
        "/api/v1/programs", json=_program_payload(exercise_ids), headers=auth_headers
    )
    assert response.status_code == 201, response.text

    body = response.json()
    assert body["status"] == "draft"
    assert body["day_count"] == 1
    assert body["exercise_count"] == 3
    assert body["days"][0]["exercises"][0]["exercise"]["name"]


async def test_program_rejects_unknown_exercises(client, auth_headers):
    payload = _program_payload(["00000000-0000-0000-0000-000000000000"])
    response = await client.post("/api/v1/programs", json=payload, headers=auth_headers)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


async def test_rep_range_is_validated(client, auth_headers, exercise_ids):
    payload = _program_payload(exercise_ids[:1])
    payload["days"][0]["exercises"][0].update({"target_reps_min": 12, "target_reps_max": 6})
    response = await client.post("/api/v1/programs", json=payload, headers=auth_headers)
    assert response.status_code == 422


async def test_activating_a_program_archives_the_previous_one(client, auth_headers, exercise_ids):
    first = await client.post(
        "/api/v1/programs", json=_program_payload(exercise_ids), headers=auth_headers
    )
    second = await client.post(
        "/api/v1/programs",
        json={**_program_payload(exercise_ids), "name": "Second Plan"},
        headers=auth_headers,
    )

    await client.post(f"/api/v1/programs/{first.json()['id']}/activate", headers=auth_headers)
    await client.post(f"/api/v1/programs/{second.json()['id']}/activate", headers=auth_headers)

    reread_first = await client.get(f"/api/v1/programs/{first.json()['id']}", headers=auth_headers)
    assert reread_first.json()["status"] == "archived"

    active = await client.get("/api/v1/programs/active", headers=auth_headers)
    assert active.json()["id"] == second.json()["id"]


async def test_templates_are_listed_and_cloneable(client, seeded_library, auth_headers):
    templates = await client.get("/api/v1/programs/templates")
    assert templates.status_code == 200
    names = [template["name"] for template in templates.json()]
    assert "Push / Pull / Legs" in names
    assert "Home Bodyweight" in names

    template_id = next(t["id"] for t in templates.json() if t["name"] == "Push / Pull / Legs")
    clone = await client.post(
        f"/api/v1/programs/{template_id}/duplicate",
        json={"name": "My PPL"},
        headers=auth_headers,
    )
    assert clone.status_code == 201
    body = clone.json()
    assert body["name"] == "My PPL"
    assert body["is_template"] is False
    assert body["day_count"] == 3
    assert body["exercise_count"] == 15


async def test_cloning_copies_prescriptions(client, seeded_library, auth_headers):
    templates = await client.get("/api/v1/programs/templates")
    template_id = templates.json()[0]["id"]
    original = (await client.get(f"/api/v1/programs/{template_id}", headers=auth_headers)).json()

    clone = await client.post(
        f"/api/v1/programs/{template_id}/duplicate", json={}, headers=auth_headers
    )
    cloned_day = clone.json()["days"][0]
    original_day = original["days"][0]
    assert [e["target_sets"] for e in cloned_day["exercises"]] == [
        e["target_sets"] for e in original_day["exercises"]
    ]
    assert clone.json()["name"].endswith("(copy)")


async def test_reordering_exercises_within_a_day(client, auth_headers, exercise_ids):
    created = await client.post(
        "/api/v1/programs", json=_program_payload(exercise_ids), headers=auth_headers
    )
    day = created.json()["days"][0]
    ids = [item["id"] for item in day["exercises"]]

    response = await client.post(
        f"/api/v1/programs/days/{day['id']}/exercises/reorder",
        json={"ids": list(reversed(ids))},
        headers=auth_headers,
    )
    assert response.status_code == 200
    reordered = [item["id"] for item in response.json()["days"][0]["exercises"]]
    assert reordered == list(reversed(ids))


async def test_another_user_cannot_read_your_program(client, db, auth_headers, exercise_ids):
    created = await client.post(
        "/api/v1/programs", json=_program_payload(exercise_ids), headers=auth_headers
    )
    from tests.conftest import _make_user

    other = await _make_user(db, email="nosy@example.com", full_name="Nosy Person")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]

    response = await client.get(
        f"/api/v1/programs/{created.json()['id']}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


async def test_deleted_program_disappears_from_the_list(client, auth_headers, exercise_ids):
    created = await client.post(
        "/api/v1/programs", json=_program_payload(exercise_ids), headers=auth_headers
    )
    program_id = created.json()["id"]

    assert (
        await client.delete(f"/api/v1/programs/{program_id}", headers=auth_headers)
    ).status_code == 204

    listing = await client.get("/api/v1/programs", headers=auth_headers)
    assert [p["id"] for p in listing.json()["items"]] == []
