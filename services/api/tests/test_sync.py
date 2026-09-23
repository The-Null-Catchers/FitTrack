"""Offline sync: idempotent push and delta pull."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from urllib.parse import quote

import pytest

from tests.test_onboarding import ONBOARDING


@pytest.fixture
async def program(client, seeded_library, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)
    templates = await client.get("/api/v1/programs/templates")
    template_id = next(t["id"] for t in templates.json() if t["name"] == "Full Body 3 Days")
    clone = await client.post(
        f"/api/v1/programs/{template_id}/duplicate", json={}, headers=auth_headers
    )
    program = clone.json()
    await client.post(f"/api/v1/programs/{program['id']}/activate", headers=auth_headers)
    return program


async def test_pushing_offline_records_applies_them_once(client, auth_headers):
    today = str(date.today())
    operations = [
        {
            "client_uuid": "offline-weight-0001",
            "entity": "body_weight",
            "payload": {"recorded_on": today, "weight_kg": 82.4},
        },
        {
            "client_uuid": "offline-measure-0001",
            "entity": "body_measurement",
            "payload": {
                "recorded_on": today,
                "measurement_type": "waist",
                "value_cm": 87.5,
            },
        },
        {
            "client_uuid": "offline-water-0001",
            "entity": "water_log",
            "payload": {"logged_on": today, "amount_ml": 500},
        },
    ]

    first = await client.post(
        "/api/v1/sync/push", json={"operations": operations}, headers=auth_headers
    )
    assert first.status_code == 200
    body = first.json()
    assert body["applied"] == 3
    assert body["failed"] == 0
    assert all(result["status"] == "applied" for result in body["results"])

    # The same batch replayed after a flaky connection must not duplicate.
    second = await client.post(
        "/api/v1/sync/push", json={"operations": operations}, headers=auth_headers
    )
    assert second.json()["duplicates"] == 3
    assert second.json()["applied"] == 0

    weights = await client.get("/api/v1/progress/weights", headers=auth_headers)
    assert len([w for w in weights.json() if w["weight_kg"] == 82.4]) == 1


async def test_a_workout_recorded_offline_syncs_complete(client, auth_headers, program):
    day = program["days"][0]
    exercise_ids = [item["exercise_id"] for item in day["exercises"][:2]]
    started_at = datetime.now(UTC) - timedelta(hours=2)

    operation = {
        "client_uuid": "offline-workout-0001",
        "entity": "workout_session",
        "payload": {
            "program_id": program["id"],
            "day_id": day["id"],
            "name": day["name"],
            "started_at": started_at.isoformat(),
            "duration_seconds": 3300,
            "finished": True,
            "exercises": [
                {
                    "exercise_id": exercise_id,
                    "position": position,
                    "tracking_type": "weight_reps",
                    "rest_seconds": 120,
                    "sets": [
                        {
                            "set_number": 1,
                            "weight_kg": 70,
                            "reps": 8,
                            "is_completed": True,
                        },
                        {
                            "set_number": 2,
                            "weight_kg": 70,
                            "reps": 7,
                            "is_completed": True,
                        },
                    ],
                }
                for position, exercise_id in enumerate(exercise_ids)
            ],
        },
    }

    response = await client.post(
        "/api/v1/sync/push", json={"operations": [operation]}, headers=auth_headers
    )
    assert response.status_code == 200, response.text
    result = response.json()["results"][0]
    assert result["status"] == "applied"

    session = await client.get(
        f"/api/v1/workout-sessions/{result['server_id']}", headers=auth_headers
    )
    body = session.json()
    assert body["status"] == "completed"
    assert body["total_sets"] == 4
    assert body["total_volume_kg"] == 70 * 8 * 2 + 70 * 7 * 2
    # Records are detected for synced workouts exactly as for live ones.
    assert body["pr_count"] > 0

    replay = await client.post(
        "/api/v1/sync/push", json={"operations": [operation]}, headers=auth_headers
    )
    assert replay.json()["duplicates"] == 1

    history = await client.get("/api/v1/workout-sessions", headers=auth_headers)
    assert history.json()["meta"]["total"] == 1


async def test_a_failing_operation_does_not_abort_the_batch(client, auth_headers):
    today = str(date.today())
    response = await client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "client_uuid": "offline-good-0001",
                    "entity": "body_weight",
                    "payload": {"recorded_on": today, "weight_kg": 80.0},
                },
                {
                    "client_uuid": "offline-bad-0001",
                    "entity": "habit_log",
                    "payload": {"logged_on": today, "count": 1},
                },
            ]
        },
        headers=auth_headers,
    )
    assert response.status_code == 200

    body = response.json()
    assert body["applied"] == 1
    assert body["failed"] == 1
    failure = next(r for r in body["results"] if r["status"] == "failed")
    assert failure["client_uuid"] == "offline-bad-0001"
    assert failure["message"]


async def test_pull_returns_changes_since_a_timestamp(client, auth_headers):
    before = datetime.now(UTC)
    await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": str(date.today()), "weight_kg": 79.9},
        headers=auth_headers,
    )

    response = await client.get(
        f"/api/v1/sync/pull?since={quote(before.isoformat())}", headers=auth_headers
    )
    assert response.status_code == 200

    body = response.json()
    assert len(body["body_weights"]) == 1
    assert body["body_weights"][0]["weight_kg"] == 79.9
    assert body["has_more"] is False
    assert body["server_time"]

    # Nothing has changed since now, so a follow-up pull is empty.
    latest = await client.get(
        f"/api/v1/sync/pull?since={quote(body['server_time'])}", headers=auth_headers
    )
    assert latest.json()["body_weights"] == []


async def test_sync_only_ever_touches_the_callers_own_data(client, db, auth_headers):
    from tests.conftest import _make_user

    other = await _make_user(db, email="sync-other@example.com", full_name="Other")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]

    await client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "client_uuid": "shared-uuid-0001",
                    "entity": "body_weight",
                    "payload": {"recorded_on": str(date.today()), "weight_kg": 70.0},
                }
            ]
        },
        headers=auth_headers,
    )

    # The same client_uuid from a different account is a different operation.
    response = await client.post(
        "/api/v1/sync/push",
        json={
            "operations": [
                {
                    "client_uuid": "shared-uuid-0001",
                    "entity": "body_weight",
                    "payload": {"recorded_on": str(date.today()), "weight_kg": 95.0},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.json()["applied"] == 1

    mine = await client.get("/api/v1/progress/weights", headers=auth_headers)
    assert [w["weight_kg"] for w in mine.json()] == [70.0]
