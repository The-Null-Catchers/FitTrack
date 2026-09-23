"""Nutrition: food catalogue, meal logging and daily rollups."""

from __future__ import annotations

from datetime import date

import pytest

from tests.test_onboarding import ONBOARDING


@pytest.fixture
async def onboarded(client, auth_headers, seeded_library):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)
    return auth_headers


@pytest.fixture
async def chicken_id(client, onboarded):
    response = await client.get("/api/v1/nutrition/foods?q=chicken breast", headers=onboarded)
    return response.json()["items"][0]["id"]


async def test_food_search_returns_per_100g_nutrients(client, onboarded):
    response = await client.get("/api/v1/nutrition/foods?q=chicken", headers=onboarded)
    assert response.status_code == 200

    items = response.json()["items"]
    assert items
    chicken = items[0]
    assert chicken["calories_per_100g"] > 0
    assert chicken["protein_per_100g"] > 20
    assert chicken["is_custom"] is False


async def test_logging_a_meal_prices_catalogue_foods_server_side(client, onboarded, chicken_id):
    response = await client.post(
        "/api/v1/nutrition/meals",
        json={
            "logged_on": str(date.today()),
            "meal_type": "lunch",
            "items": [{"food_id": chicken_id, "grams": 200}],
        },
        headers=onboarded,
    )
    assert response.status_code == 201

    meal = response.json()
    item = meal["items"][0]
    # 165 kcal and 31 g protein per 100 g → doubled for a 200 g portion.
    assert item["calories"] == pytest.approx(330, abs=0.5)
    assert item["protein_g"] == pytest.approx(62, abs=0.5)
    assert meal["total_calories"] == item["calories"]


async def test_serving_options_are_honoured(client, onboarded, seeded_library):
    banana = (await client.get("/api/v1/nutrition/foods?q=banana", headers=onboarded)).json()[
        "items"
    ][0]
    label = banana["serving_options"][0]["label"]

    response = await client.post(
        "/api/v1/nutrition/meals",
        json={
            "logged_on": str(date.today()),
            "meal_type": "snack",
            "items": [{"food_id": banana["id"], "serving_label": label, "quantity": 2}],
        },
        headers=onboarded,
    )
    item = response.json()["items"][0]
    assert item["grams"] == pytest.approx(236, abs=0.5)


async def test_ad_hoc_entries_need_their_own_calories(client, onboarded):
    response = await client.post(
        "/api/v1/nutrition/meals",
        json={
            "logged_on": str(date.today()),
            "meal_type": "dinner",
            "items": [{"food_name": "Grandma's stew"}],
        },
        headers=onboarded,
    )
    assert response.status_code == 422


async def test_day_view_reports_progress_against_targets(client, onboarded, chicken_id):
    await client.post(
        "/api/v1/nutrition/meals",
        json={
            "logged_on": str(date.today()),
            "meal_type": "lunch",
            "items": [{"food_id": chicken_id, "grams": 300}],
        },
        headers=onboarded,
    )

    response = await client.get("/api/v1/nutrition/day", headers=onboarded)
    assert response.status_code == 200

    body = response.json()
    assert body["calories"]["consumed"] == pytest.approx(495, abs=1)
    assert body["calories"]["target"] > 1200
    assert body["calories"]["remaining"] == pytest.approx(
        body["calories"]["target"] - body["calories"]["consumed"], abs=1
    )
    assert body["protein_g"]["percent"] > 0
    assert len(body["meals"]) == 1


async def test_editing_a_meal_updates_the_daily_rollup(client, onboarded, chicken_id):
    meal = (
        await client.post(
            "/api/v1/nutrition/meals",
            json={
                "logged_on": str(date.today()),
                "meal_type": "lunch",
                "items": [{"food_id": chicken_id, "grams": 100}],
            },
            headers=onboarded,
        )
    ).json()

    await client.patch(
        f"/api/v1/nutrition/meals/{meal['id']}",
        json={"items": [{"food_id": chicken_id, "grams": 400}]},
        headers=onboarded,
    )

    day = (await client.get("/api/v1/nutrition/day", headers=onboarded)).json()
    assert day["calories"]["consumed"] == pytest.approx(660, abs=1)


async def test_deleting_a_meal_removes_it_from_the_day(client, onboarded, chicken_id):
    meal = (
        await client.post(
            "/api/v1/nutrition/meals",
            json={
                "logged_on": str(date.today()),
                "meal_type": "lunch",
                "items": [{"food_id": chicken_id, "grams": 100}],
            },
            headers=onboarded,
        )
    ).json()

    assert (
        await client.delete(f"/api/v1/nutrition/meals/{meal['id']}", headers=onboarded)
    ).status_code == 204

    day = (await client.get("/api/v1/nutrition/day", headers=onboarded)).json()
    assert day["calories"]["consumed"] == 0
    assert day["meals"] == []


async def test_meal_logging_is_idempotent_for_offline_clients(client, onboarded, chicken_id):
    payload = {
        "logged_on": str(date.today()),
        "meal_type": "breakfast",
        "items": [{"food_id": chicken_id, "grams": 100}],
        "client_uuid": "offline-meal-0001",
    }
    first = await client.post("/api/v1/nutrition/meals", json=payload, headers=onboarded)
    second = await client.post("/api/v1/nutrition/meals", json=payload, headers=onboarded)

    assert first.json()["id"] == second.json()["id"]
    day = (await client.get("/api/v1/nutrition/day", headers=onboarded)).json()
    assert len(day["meals"]) == 1


async def test_water_logging_accumulates_and_can_be_corrected(client, onboarded):
    today = str(date.today())
    for _ in range(3):
        response = await client.post(
            "/api/v1/nutrition/water",
            json={"logged_on": today, "amount_ml": 250},
            headers=onboarded,
        )
    assert response.json()["water_ml"] == 750

    # A negative amount undoes a mis-tap.
    corrected = await client.post(
        "/api/v1/nutrition/water",
        json={"logged_on": today, "amount_ml": -250},
        headers=onboarded,
    )
    assert corrected.json()["water_ml"] == 500


async def test_custom_foods_are_private(client, db, onboarded):
    created = await client.post(
        "/api/v1/nutrition/foods",
        json={
            "name": "Mum's protein pancakes",
            "calories_per_100g": 180,
            "protein_per_100g": 14,
            "carbs_per_100g": 20,
            "fat_per_100g": 4,
        },
        headers=onboarded,
    )
    assert created.status_code == 201
    assert created.json()["is_custom"] is True

    from tests.conftest import _make_user

    other = await _make_user(db, email="hungry@example.com", full_name="Hungry Person")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]
    theirs = await client.get(
        "/api/v1/nutrition/foods?q=pancakes", headers={"Authorization": f"Bearer {token}"}
    )
    assert theirs.json()["items"] == []


async def test_favourites_can_be_toggled(client, onboarded, chicken_id):
    on = await client.post(f"/api/v1/nutrition/foods/{chicken_id}/favorite", headers=onboarded)
    assert on.json()["is_favorite"] is True

    listing = await client.get("/api/v1/nutrition/foods?favorites_only=true", headers=onboarded)
    assert [item["id"] for item in listing.json()["items"]] == [chicken_id]

    off = await client.post(f"/api/v1/nutrition/foods/{chicken_id}/favorite", headers=onboarded)
    assert off.json()["is_favorite"] is False


async def test_recent_foods_reflect_what_was_logged(client, onboarded, chicken_id):
    await client.post(
        "/api/v1/nutrition/meals",
        json={
            "logged_on": str(date.today()),
            "meal_type": "lunch",
            "items": [{"food_id": chicken_id, "grams": 150}],
        },
        headers=onboarded,
    )
    recent = await client.get("/api/v1/nutrition/foods/recent", headers=onboarded)
    assert [item["id"] for item in recent.json()] == [chicken_id]
