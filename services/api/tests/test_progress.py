"""Body tracking, progress photos and analytics."""

from __future__ import annotations

import io
from datetime import date, timedelta

import pytest

from tests.test_onboarding import ONBOARDING


def _png(size: tuple[int, int] = (900, 1200), color: str = "#3f6f9f") -> bytes:
    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture
async def onboarded(client, auth_headers):
    await client.post("/api/v1/profile/onboarding", json=ONBOARDING, headers=auth_headers)
    return auth_headers


async def test_weight_is_one_entry_per_day(client, onboarded):
    today = str(date.today())
    first = await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": today, "weight_kg": 83.5},
        headers=onboarded,
    )
    second = await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": today, "weight_kg": 83.1},
        headers=onboarded,
    )
    assert first.json()["id"] == second.json()["id"]

    listing = await client.get("/api/v1/progress/weights", headers=onboarded)
    today_entries = [e for e in listing.json() if e["recorded_on"] == today]
    assert len(today_entries) == 1
    assert today_entries[0]["weight_kg"] == 83.1


async def test_logging_weight_updates_the_profile(client, onboarded):
    await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": str(date.today()), "weight_kg": 81.2},
        headers=onboarded,
    )
    profile = (await client.get("/api/v1/profile", headers=onboarded)).json()["profile"]
    assert profile["current_weight_kg"] == 81.2


async def test_weight_chart_summarises_the_trend(client, onboarded):
    base = date.today() - timedelta(days=20)
    for offset in range(0, 21, 2):
        await client.post(
            "/api/v1/progress/weights",
            json={
                "recorded_on": str(base + timedelta(days=offset)),
                "weight_kg": 85 - offset * 0.2,
            },
            headers=onboarded,
        )

    chart = await client.get("/api/v1/progress/charts/weight?range=30d", headers=onboarded)
    assert chart.status_code == 200

    body = chart.json()
    series = body["series"][0]
    assert len(series["points"]) >= 10
    # A smoothed trend line is returned alongside the noisy daily values.
    assert len(series["trend"]) == len(series["points"])
    assert body["change_absolute"] < 0
    assert "down" in body["summary"]


async def test_measurements_are_upserted_per_type_and_day(client, onboarded):
    payload = {
        "recorded_on": str(date.today()),
        "measurement_type": "waist",
        "value_cm": 88.0,
    }
    await client.post("/api/v1/progress/measurements", json=payload, headers=onboarded)
    await client.post(
        "/api/v1/progress/measurements",
        json={**payload, "value_cm": 87.2},
        headers=onboarded,
    )
    await client.post(
        "/api/v1/progress/measurements",
        json={**payload, "measurement_type": "chest", "value_cm": 103.0},
        headers=onboarded,
    )

    waist = await client.get(
        "/api/v1/progress/measurements?measurement_type=waist", headers=onboarded
    )
    assert len(waist.json()) == 1
    assert waist.json()[0]["value_cm"] == 87.2

    everything = await client.get("/api/v1/progress/measurements", headers=onboarded)
    assert len(everything.json()) == 2


async def test_progress_photo_is_private_and_served_through_a_signed_url(client, onboarded):
    response = await client.post(
        "/api/v1/progress/photos",
        files={"file": ("front.png", _png(), "image/png")},
        data={"taken_on": str(date.today()), "pose": "front", "weight_kg": "83.5"},
        headers=onboarded,
    )
    assert response.status_code == 201, response.text

    photo = response.json()
    assert photo["url"].startswith("http")
    assert "signature=" in photo["url"]
    assert photo["thumbnail_url"]
    # The raw storage key is never exposed to the client.
    assert "progress-photos/" not in response.text.split("?")[0].split("/media/")[0]
    # Images are downscaled on the way in.
    assert photo["width"] <= 1600


async def test_a_signed_url_is_required_to_fetch_a_photo(client, onboarded):
    photo = (
        await client.post(
            "/api/v1/progress/photos",
            files={"file": ("front.png", _png(), "image/png")},
            data={"taken_on": str(date.today()), "pose": "front"},
            headers=onboarded,
        )
    ).json()

    path = photo["url"].split("://", 1)[1].split("/", 1)[1]
    signed_path = "/" + path
    unsigned_path = signed_path.split("?")[0]

    assert (await client.get(signed_path)).status_code == 200
    denied = await client.get(unsigned_path)
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "invalid_signature"


async def test_uploads_reject_the_wrong_file_type(client, onboarded):
    response = await client.post(
        "/api/v1/progress/photos",
        files={"file": ("notes.txt", b"not an image", "text/plain")},
        data={"taken_on": str(date.today()), "pose": "front"},
        headers=onboarded,
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "unsupported_media_type"


async def test_photo_comparison_orders_by_date(client, onboarded):
    earlier = (
        await client.post(
            "/api/v1/progress/photos",
            files={"file": ("a.png", _png(), "image/png")},
            data={
                "taken_on": str(date.today() - timedelta(days=60)),
                "pose": "front",
                "weight_kg": "88",
            },
            headers=onboarded,
        )
    ).json()
    later = (
        await client.post(
            "/api/v1/progress/photos",
            files={"file": ("b.png", _png(), "image/png")},
            data={"taken_on": str(date.today()), "pose": "front", "weight_kg": "83"},
            headers=onboarded,
        )
    ).json()

    # Deliberately passed the wrong way round; the API sorts them.
    comparison = await client.get(
        f"/api/v1/progress/photos/compare?before_id={later['id']}&after_id={earlier['id']}",
        headers=onboarded,
    )
    body = comparison.json()
    assert body["before"]["id"] == earlier["id"]
    assert body["after"]["id"] == later["id"]
    assert body["days_between"] == 60
    assert body["weight_change_kg"] == -5.0


async def test_one_user_cannot_read_another_users_photo(client, db, onboarded):
    photo = (
        await client.post(
            "/api/v1/progress/photos",
            files={"file": ("front.png", _png(), "image/png")},
            data={"taken_on": str(date.today()), "pose": "front"},
            headers=onboarded,
        )
    ).json()

    from tests.conftest import _make_user

    other = await _make_user(db, email="creep@example.com", full_name="Creep")
    token = (
        await client.post(
            "/api/v1/auth/login",
            json={"email": other.email, "password": "TestPass123!"},
        )
    ).json()["access_token"]

    response = await client.patch(
        f"/api/v1/progress/photos/{photo['id']}",
        json={"note": "mine now"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


async def test_dashboard_is_usable_on_a_brand_new_account(client, onboarded):
    response = await client.get("/api/v1/progress/dashboard", headers=onboarded)
    assert response.status_code == 200

    body = response.json()
    assert body["greeting_name"] == "Alex"
    assert body["active_session"] is None
    assert body["calories"]["consumed"] == 0
    assert body["calories"]["target"] > 0
    assert body["current_streak_days"] == 0
    assert body["weekly_workouts"]["target"] == 4
    assert len(body["weekly_workouts"]["days"]) == 7
    # Onboarding seeded the first weigh-in, so the trend is already there.
    assert body["latest_weight_kg"] == 84


async def test_training_overview_is_empty_but_honest_without_workouts(client, onboarded):
    response = await client.get("/api/v1/progress/overview?range=30d", headers=onboarded)
    body = response.json()
    assert body["total_workouts"] == 0
    assert body["volume_by_muscle_group"] == []
    assert "No workouts" in body["summary"]
