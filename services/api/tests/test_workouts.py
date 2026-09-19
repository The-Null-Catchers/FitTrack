"""The workout logging flow: start, log, resume, finish, records."""

from __future__ import annotations

import pytest


@pytest.fixture
async def program(client, seeded_library, auth_headers):
    """A cloned, active Push/Pull/Legs plan."""
    templates = await client.get("/api/v1/programs/templates")
    template_id = next(t["id"] for t in templates.json() if t["name"] == "Push / Pull / Legs")
    clone = await client.post(
        f"/api/v1/programs/{template_id}/duplicate",
        json={"name": "PPL"},
        headers=auth_headers,
    )
    program = clone.json()
    await client.post(f"/api/v1/programs/{program['id']}/activate", headers=auth_headers)
    return program


@pytest.fixture
async def started(client, auth_headers, program):
    response = await client.post(
        "/api/v1/workout-sessions",
        json={"program_id": program["id"], "day_id": program["days"][0]["id"]},
        headers=auth_headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


async def test_starting_a_workout_copies_the_prescription(started):
    assert started["status"] == "in_progress"
    assert started["name"] == "Push"
    assert len(started["exercises"]) == 5

    first = started["exercises"][0]
    assert first["target_snapshot"]["sets"] == 4
    assert first["target_snapshot"]["reps_max"] == 8
    assert first["sets"] == []
    # Nothing has been trained before, so there is no "previous" column yet.
    assert first["previous"] is None


async def test_only_one_workout_can_be_in_progress(client, auth_headers, program, started):
    response = await client.post(
        "/api/v1/workout-sessions",
        json={"program_id": program["id"], "day_id": program["days"][0]["id"]},
        headers=auth_headers,
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "workout_in_progress"
    assert response.json()["error"]["details"]["session_id"] == started["id"]


async def test_start_is_idempotent_for_the_same_client_uuid(client, auth_headers, program):
    payload = {
        "program_id": program["id"],
        "day_id": program["days"][0]["id"],
        "client_uuid": "offline-session-0001",
    }
    first = await client.post("/api/v1/workout-sessions", json=payload, headers=auth_headers)
    second = await client.post("/api/v1/workout-sessions", json=payload, headers=auth_headers)

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


async def test_logging_sets_computes_volume_and_one_rep_max(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]

    response = await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "weight_kg": 80, "reps": 8, "is_completed": True, "rpe": 8},
        headers=auth_headers,
    )
    assert response.status_code == 201

    logged = response.json()["sets"][0]
    assert logged["volume_kg"] == 640
    assert logged["estimated_1rm_kg"] == pytest.approx(101.33, abs=0.01)
    assert logged["completed_at"] is not None


async def test_a_completed_set_needs_at_least_one_value(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]
    response = await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "is_completed": True},
        headers=auth_headers,
    )
    assert response.status_code == 422


async def test_workout_survives_being_left_and_resumed(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]
    await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "weight_kg": 80, "reps": 8, "is_completed": True},
        headers=auth_headers,
    )

    # A fresh client — as if the app was closed and reopened.
    resumed = await client.get("/api/v1/workout-sessions/active", headers=auth_headers)
    assert resumed.status_code == 200

    body = resumed.json()
    assert body["id"] == started["id"]
    assert body["exercises"][0]["sets"][0]["weight_kg"] == 80


async def test_finishing_computes_totals_and_duration(client, auth_headers, started):
    for item in started["exercises"][:2]:
        for set_number in (1, 2):
            await client.post(
                f"/api/v1/workout-sessions/exercises/{item['id']}/sets",
                json={
                    "set_number": set_number,
                    "weight_kg": 60,
                    "reps": 10,
                    "is_completed": True,
                },
                headers=auth_headers,
            )

    response = await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish",
        json={"duration_seconds": 3600, "perceived_effort": 8},
        headers=auth_headers,
    )
    assert response.status_code == 200

    body = response.json()
    assert body["status"] == "completed"
    assert body["total_sets"] == 4
    assert body["total_reps"] == 40
    assert body["total_volume_kg"] == 2400
    assert body["estimated_calories"] > 0
    active = await client.get("/api/v1/workout-sessions/active", headers=auth_headers)
    assert active.json() is None


async def test_finishing_detects_personal_records(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]
    await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "weight_kg": 100, "reps": 5, "is_completed": True},
        headers=auth_headers,
    )
    finished = await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish", json={}, headers=auth_headers
    )

    records = {r["record_type"]: r for r in finished.json()["personal_records"]}
    assert records["max_weight"]["value"] == 100
    assert records["max_reps"]["value"] == 5
    assert records["estimated_1rm"]["value"] > 100
    assert records["max_weight"]["previous_value"] is None
    assert finished.json()["pr_count"] == len(records)


async def test_warm_up_sets_never_set_records(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]
    await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={
            "set_number": 1,
            "weight_kg": 200,
            "reps": 5,
            "is_completed": True,
            "set_type": "warmup",
        },
        headers=auth_headers,
    )
    finished = await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish", json={}, headers=auth_headers
    )
    assert finished.json()["personal_records"] == []


async def test_a_second_workout_shows_previous_performance(client, auth_headers, program, started):
    session_exercise_id = started["exercises"][0]["id"]
    await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "weight_kg": 80, "reps": 8, "is_completed": True},
        headers=auth_headers,
    )
    await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish", json={}, headers=auth_headers
    )

    second = await client.post(
        "/api/v1/workout-sessions",
        json={"program_id": program["id"], "day_id": program["days"][0]["id"]},
        headers=auth_headers,
    )
    previous = second.json()["exercises"][0]["previous"]
    assert previous is not None
    assert previous["best_set"]["weight_kg"] == 80
    assert previous["best_set"]["reps"] == 8
    assert previous["total_volume_kg"] == 640


async def test_replacing_an_exercise_keeps_the_slot(client, auth_headers, seeded_library, started):
    listing = await client.get("/api/v1/exercises?q=push-up")
    replacement_id = listing.json()["items"][0]["id"]
    session_exercise_id = started["exercises"][0]["id"]

    response = await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/replace",
        json={"exercise_id": replacement_id},
        headers=auth_headers,
    )
    assert response.status_code == 200

    swapped = response.json()["exercises"][0]
    assert swapped["id"] == session_exercise_id
    assert swapped["exercise"]["id"] == replacement_id
    assert swapped["tracking_type"] == "reps_only"


async def test_history_is_filterable_and_reports_records(client, auth_headers, started):
    session_exercise_id = started["exercises"][0]["id"]
    await client.post(
        f"/api/v1/workout-sessions/exercises/{session_exercise_id}/sets",
        json={"set_number": 1, "weight_kg": 90, "reps": 6, "is_completed": True},
        headers=auth_headers,
    )
    await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish", json={}, headers=auth_headers
    )

    history = await client.get("/api/v1/workout-sessions", headers=auth_headers)
    assert history.status_code == 200
    items = history.json()["items"]
    assert len(items) == 1
    assert items[0]["pr_count"] > 0

    exercise_id = started["exercises"][0]["exercise"]["id"]
    filtered = await client.get(
        f"/api/v1/workout-sessions?exercise_id={exercise_id}", headers=auth_headers
    )
    assert len(filtered.json()["items"]) == 1

    other_exercise = (await client.get("/api/v1/exercises?q=burpee")).json()["items"][0]["id"]
    empty = await client.get(
        f"/api/v1/workout-sessions?exercise_id={other_exercise}", headers=auth_headers
    )
    assert empty.json()["items"] == []


async def test_personal_records_endpoint_returns_current_bests(client, auth_headers, program):
    """Two sessions: the second must supersede the first, not duplicate it."""
    for weight in (80, 90):
        started = (
            await client.post(
                "/api/v1/workout-sessions",
                json={"program_id": program["id"], "day_id": program["days"][0]["id"]},
                headers=auth_headers,
            )
        ).json()
        await client.post(
            f"/api/v1/workout-sessions/exercises/{started['exercises'][0]['id']}/sets",
            json={"set_number": 1, "weight_kg": weight, "reps": 5, "is_completed": True},
            headers=auth_headers,
        )
        await client.post(
            f"/api/v1/workout-sessions/{started['id']}/finish",
            json={},
            headers=auth_headers,
        )

    records = await client.get("/api/v1/personal-records", headers=auth_headers)
    by_type = {r["record_type"]: r for r in records.json()}
    assert by_type["max_weight"]["value"] == 90
    assert by_type["max_weight"]["previous_value"] == 80


async def test_discarding_a_workout_clears_the_active_session(client, auth_headers, started):
    response = await client.post(
        f"/api/v1/workout-sessions/{started['id']}/discard", headers=auth_headers
    )
    assert response.status_code == 204
    assert (
        await client.get("/api/v1/workout-sessions/active", headers=auth_headers)
    ).json() is None


async def test_one_user_cannot_touch_another_users_workout(client, db, auth_headers, started):
    from tests.conftest import _make_user

    other = await _make_user(db, email="thief@example.com", full_name="Thief")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]

    response = await client.get(
        f"/api/v1/workout-sessions/{started['id']}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403
