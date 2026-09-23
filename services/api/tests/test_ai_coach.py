"""FitCoach plan generation, substitutions and summaries."""

from __future__ import annotations

import pytest

from tests.test_onboarding import ONBOARDING

PLAN_REQUEST = {
    "goal": "gain_muscle",
    "experience": "intermediate",
    "days_per_week": 4,
    "session_minutes": 60,
    "equipment": ["dumbbell"],
    "location": "home",
}


@pytest.fixture
async def onboarded(client, auth_headers, seeded_library):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)
    return auth_headers


async def test_generated_plan_respects_the_requested_shape(client, onboarded):
    response = await client.post("/api/v1/ai/plans/generate", json=PLAN_REQUEST, headers=onboarded)
    assert response.status_code == 200, response.text

    body = response.json()
    plan = body["plan"]
    assert plan["days_per_week"] == 4
    assert len(plan["days"]) == 4
    assert plan["goal"] == "gain_muscle"
    assert plan["coaching_notes"]
    assert "not medical" in body["disclaimer"]
    assert body["generation_id"]

    for day in plan["days"]:
        assert day["exercises"], f"{day['name']} has no exercises"
        for entry in day["exercises"]:
            assert entry["prescription"]["sets"] >= 1


async def test_generated_plan_only_uses_available_equipment(client, onboarded):
    response = await client.post(
        "/api/v1/ai/plans/generate",
        json={**PLAN_REQUEST, "equipment": [], "location": "home"},
        headers=onboarded,
    )
    plan = response.json()["plan"]
    # Home with no equipment declared still yields a trainable week.
    assert all(day["exercises"] for day in plan["days"])
    assert set(plan["equipment_needed"]) <= {"bodyweight", "dumbbell", "resistance_band"}


async def test_excluded_exercises_are_not_prescribed(client, onboarded):
    listing = await client.get("/api/v1/exercises?q=goblet squat", headers=onboarded)
    excluded_id = listing.json()["items"][0]["id"]

    response = await client.post(
        "/api/v1/ai/plans/generate",
        json={**PLAN_REQUEST, "excluded_exercise_ids": [excluded_id]},
        headers=onboarded,
    )
    used = {
        entry["exercise_id"]
        for day in response.json()["plan"]["days"]
        for entry in day["exercises"]
    }
    assert excluded_id not in used


async def test_strength_goal_prescribes_lower_reps_than_endurance(client, onboarded):
    strength = await client.post(
        "/api/v1/ai/plans/generate",
        json={**PLAN_REQUEST, "goal": "improve_strength"},
        headers=onboarded,
    )
    endurance = await client.post(
        "/api/v1/ai/plans/generate",
        json={**PLAN_REQUEST, "goal": "improve_endurance"},
        headers=onboarded,
    )

    def first_reps(response) -> int:
        day = response.json()["plan"]["days"][0]
        return day["exercises"][0]["prescription"]["reps_max"]

    assert first_reps(strength) < first_reps(endurance)


async def test_saving_a_plan_creates_a_new_program_without_touching_existing_ones(
    client, onboarded
):
    templates = await client.get("/api/v1/programs/templates")
    existing = await client.post(
        f"/api/v1/programs/{templates.json()[0]['id']}/duplicate",
        json={"name": "My existing plan"},
        headers=onboarded,
    )
    await client.post(f"/api/v1/programs/{existing.json()['id']}/activate", headers=onboarded)

    generated = await client.post("/api/v1/ai/plans/generate", json=PLAN_REQUEST, headers=onboarded)
    saved = await client.post(
        "/api/v1/ai/plans/save",
        json={"generation_id": generated.json()["generation_id"], "name": "Coach plan"},
        headers=onboarded,
    )
    assert saved.status_code == 201

    body = saved.json()
    assert body["name"] == "Coach plan"
    assert body["generated_by_ai"] is True
    assert body["status"] == "draft"
    assert body["day_count"] == 4

    # The previously active program is untouched.
    active = await client.get("/api/v1/programs/active", headers=onboarded)
    assert active.json()["id"] == existing.json()["id"]


async def test_saving_with_activate_switches_the_active_program(client, onboarded):
    generated = await client.post("/api/v1/ai/plans/generate", json=PLAN_REQUEST, headers=onboarded)
    saved = await client.post(
        "/api/v1/ai/plans/save",
        json={"generation_id": generated.json()["generation_id"], "activate": True},
        headers=onboarded,
    )
    active = await client.get("/api/v1/programs/active", headers=onboarded)
    assert active.json()["id"] == saved.json()["id"]


async def test_one_user_cannot_save_anothers_generated_plan(client, db, onboarded):
    generated = await client.post("/api/v1/ai/plans/generate", json=PLAN_REQUEST, headers=onboarded)

    from tests.conftest import _make_user

    other = await _make_user(db, email="plan-thief@example.com", full_name="Thief")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]

    response = await client.post(
        "/api/v1/ai/plans/save",
        json={"generation_id": generated.json()["generation_id"]},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


async def test_substitutions_match_the_muscle_group_and_equipment(client, onboarded):
    bench = (await client.get("/api/v1/exercises?q=barbell bench press", headers=onboarded)).json()[
        "items"
    ][0]

    response = await client.post(
        "/api/v1/ai/substitutions",
        json={"exercise_id": bench["id"], "available_equipment": ["dumbbell"], "limit": 3},
        headers=onboarded,
    )
    assert response.status_code == 200

    options = response.json()["options"]
    assert options
    assert bench["id"] not in [option["exercise_id"] for option in options]
    for option in options:
        assert option["equipment"] in {"dumbbell", "bodyweight"}
        assert option["rationale"]


async def test_conversation_history_is_kept_per_user(client, onboarded):
    first = await client.post(
        "/api/v1/ai/chat",
        json={"message": "How do I structure a push day?"},
        headers=onboarded,
    )
    conversation_id = first.json()["conversation_id"]

    await client.post(
        "/api/v1/ai/chat",
        json={"message": "And how much rest between sets?", "conversation_id": conversation_id},
        headers=onboarded,
    )

    detail = await client.get(f"/api/v1/ai/conversations/{conversation_id}", headers=onboarded)
    messages = detail.json()["messages"]
    assert len(messages) == 4
    assert [m["role"] for m in messages] == ["user", "assistant", "user", "assistant"]

    listing = await client.get("/api/v1/ai/conversations", headers=onboarded)
    assert len(listing.json()) == 1


async def test_progress_summary_reports_only_what_was_logged(client, onboarded):
    response = await client.get("/api/v1/ai/progress-summary?range=30d", headers=onboarded)
    assert response.status_code == 200

    body = response.json()
    assert "No training logged" in body["headline"]
    assert body["bullets"]
    assert "not medical" in body["disclaimer"]


async def test_usage_is_metered(client, onboarded):
    await client.post(
        "/api/v1/ai/chat", json={"message": "Give me a dumbbell plan"}, headers=onboarded
    )
    response = await client.get("/api/v1/ai/usage", headers=onboarded)

    body = response.json()
    assert body["messages_used"] == 1
    assert body["messages_limit"] > 0
