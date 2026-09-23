"""Onboarding and profile management."""

from __future__ import annotations

from datetime import date

from sqlalchemy import select

from app.models.body import BodyWeight

ONBOARDING = {
    "date_of_birth": "1995-04-12",
    "gender": "undisclosed",
    "height_cm": 178,
    "current_weight_kg": 84,
    "target_weight_kg": 78,
    "unit_system": "metric",
    "primary_goal": "lose_weight",
    "fitness_level": "intermediate",
    "activity_level": "moderate",
    "workout_location": "gym",
    "available_equipment": ["barbell", "dumbbell", "cable"],
    "training_days_per_week": 4,
    "preferred_session_minutes": 60,
}


async def test_onboarding_populates_the_profile_and_targets(client, auth_headers):
    response = await client.post(
        "/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers
    )
    assert response.status_code == 201, response.text

    body = response.json()
    assert body["onboarding_completed"] is True
    profile = body["profile"]
    assert profile["height_cm"] == 178
    assert profile["primary_goal"] == "lose_weight"
    assert profile["available_equipment"] == ["barbell", "dumbbell", "cable"]
    # Targets are estimated so the nutrition screen is useful immediately.
    assert profile["daily_calorie_target"] > 1200
    assert profile["daily_protein_target_g"] > 100
    assert profile["targets_are_manual"] is False


async def test_onboarding_seeds_the_first_weigh_in(client, db, user, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)

    entry = await db.scalar(select(BodyWeight).where(BodyWeight.user_id == user.id))
    assert entry is not None
    assert entry.weight_kg == 84
    assert entry.recorded_on == date.today()


async def test_onboarding_validates_implausible_values(client, auth_headers):
    response = await client.post(
        "/api/v1/profile/onboarding",
        json={**ONBOARDING, "height_cm": 12},
        headers=auth_headers,
    )
    assert response.status_code == 422
    assert "height_cm" in response.json()["error"]["details"]["fields"]


async def test_manual_targets_are_never_overwritten_by_an_estimate(client, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)

    manual = await client.put(
        "/api/v1/profile/nutrition-targets",
        json={"daily_calorie_target": 2100, "daily_protein_target_g": 190},
        headers=auth_headers,
    )
    assert manual.status_code == 200
    assert manual.json()["targets_are_manual"] is True

    # Changing a profile input would normally recalculate; it must not here.
    await client.patch(
        "/api/v1/profile/fitness",
        json={"current_weight_kg": 80, "activity_level": "very_active"},
        headers=auth_headers,
    )
    profile = (await client.get("/api/v1/profile", headers=auth_headers)).json()["profile"]
    assert profile["daily_calorie_target"] == 2100
    assert profile["daily_protein_target_g"] == 190


async def test_user_can_re_adopt_the_estimate(client, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)
    await client.put(
        "/api/v1/profile/nutrition-targets",
        json={"daily_calorie_target": 1500},
        headers=auth_headers,
    )

    response = await client.post(
        "/api/v1/profile/nutrition-targets/use-estimate", headers=auth_headers
    )
    assert response.status_code == 200
    assert response.json()["targets_are_manual"] is False
    assert response.json()["daily_calorie_target"] != 1500


async def test_estimate_endpoint_carries_a_disclaimer(client, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)

    response = await client.get("/api/v1/profile/nutrition-targets/estimate", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["bmr_kcal"] > 0
    assert body["tdee_kcal"] > body["bmr_kcal"]
    assert "not medical" in body["disclaimer"]


async def test_estimate_requires_height_and_weight(client, auth_headers):
    response = await client.get("/api/v1/profile/nutrition-targets/estimate", headers=auth_headers)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "profile_incomplete"


async def test_profile_locale_is_restricted_to_supported_languages(client, auth_headers):
    ok = await client.patch("/api/v1/profile", json={"locale": "ar"}, headers=auth_headers)
    assert ok.status_code == 200
    assert ok.json()["locale"] == "ar"

    bad = await client.patch("/api/v1/profile", json={"locale": "zz"}, headers=auth_headers)
    assert bad.status_code == 422


async def test_data_export_includes_every_domain(client, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)

    response = await client.get("/api/v1/profile/export", headers=auth_headers)
    assert response.status_code == 200
    assert "attachment" in response.headers["content-disposition"]

    payload = response.json()
    for key in (
        "account",
        "profile",
        "workout_sessions",
        "body_weights",
        "meals",
        "habits",
        "goals",
        "progress_photos",
    ):
        assert key in payload
    # The export must never leak raw storage paths.
    assert "storage_key" not in response.text
