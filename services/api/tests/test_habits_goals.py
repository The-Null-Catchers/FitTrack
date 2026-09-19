"""Habits, streaks and goals."""

from __future__ import annotations

from datetime import date, timedelta

import pytest


@pytest.fixture
async def habit(client, auth_headers):
    response = await client.post(
        "/api/v1/habits",
        json={"name": "Drink 2L of water", "icon": "water_drop", "frequency": "daily"},
        headers=auth_headers,
    )
    assert response.status_code == 201
    return response.json()


async def test_logging_builds_a_streak(client, auth_headers, habit):
    today = date.today()
    for offset in range(4, -1, -1):
        await client.post(
            f"/api/v1/habits/{habit['id']}/log",
            json={"logged_on": str(today - timedelta(days=offset)), "count": 1},
            headers=auth_headers,
        )

    listing = await client.get("/api/v1/habits", headers=auth_headers)
    row = listing.json()[0]
    assert row["current_streak"] == 5
    assert row["longest_streak"] == 5
    assert row["today"]["is_completed"] is True


async def test_a_gap_breaks_the_streak_but_keeps_the_record(client, auth_headers, habit):
    today = date.today()
    # Five days, then a missed day, then two more.
    for offset in [10, 9, 8, 7, 6, 3, 2]:
        await client.post(
            f"/api/v1/habits/{habit['id']}/log",
            json={"logged_on": str(today - timedelta(days=offset)), "count": 1},
            headers=auth_headers,
        )

    row = (await client.get("/api/v1/habits", headers=auth_headers)).json()[0]
    assert row["current_streak"] == 0
    assert row["longest_streak"] == 5


async def test_undoing_todays_log_recalculates(client, auth_headers, habit):
    today = date.today()
    for offset in (1, 0):
        await client.post(
            f"/api/v1/habits/{habit['id']}/log",
            json={"logged_on": str(today - timedelta(days=offset)), "count": 1},
            headers=auth_headers,
        )
    assert (await client.get("/api/v1/habits", headers=auth_headers)).json()[0][
        "current_streak"
    ] == 2

    response = await client.delete(f"/api/v1/habits/{habit['id']}/log", headers=auth_headers)
    # Yesterday still counts — an unlogged today doesn't end a live streak.
    assert response.json()["current_streak"] == 1


async def test_partial_completion_is_not_a_completion(client, auth_headers):
    habit = (
        await client.post(
            "/api/v1/habits",
            json={"name": "Walk 3 times", "target_count": 3},
            headers=auth_headers,
        )
    ).json()

    response = await client.post(
        f"/api/v1/habits/{habit['id']}/log",
        json={"logged_on": str(date.today()), "count": 2},
        headers=auth_headers,
    )
    assert response.json()["today"]["is_completed"] is False
    assert response.json()["current_streak"] == 0


async def test_weekly_habits_only_apply_on_their_weekdays(client, auth_headers):
    today = date.today()
    response = await client.post(
        "/api/v1/habits",
        json={
            "name": "Long run",
            "frequency": "weekly",
            "active_weekdays": [(today.weekday() + 3) % 7],
        },
        headers=auth_headers,
    )
    assert response.status_code == 201

    dashboard = await client.get("/api/v1/progress/dashboard", headers=auth_headers)
    # Not expected today, so it isn't counted in today's habit total.
    assert dashboard.json()["habits_total_today"] == 0


async def test_goal_tracks_body_weight_automatically(client, auth_headers):
    goal = (
        await client.post(
            "/api/v1/goals",
            json={
                "goal_type": "body_weight",
                "title": "Reach 78 kg",
                "start_value": 84,
                "target_value": 78,
                "unit": "kg",
                "is_decreasing": True,
            },
            headers=auth_headers,
        )
    ).json()
    assert goal["progress_percent"] == 0

    await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": str(date.today()), "weight_kg": 81},
        headers=auth_headers,
    )

    refreshed = (await client.get(f"/api/v1/goals/{goal['id']}", headers=auth_headers)).json()
    assert refreshed["current_value"] == 81
    assert refreshed["progress_percent"] == 50.0
    assert refreshed["status"] == "active"


async def test_goal_is_marked_achieved_when_the_target_is_reached(client, auth_headers):
    goal = (
        await client.post(
            "/api/v1/goals",
            json={
                "goal_type": "body_weight",
                "title": "Reach 78 kg",
                "start_value": 84,
                "target_value": 78,
                "is_decreasing": True,
            },
            headers=auth_headers,
        )
    ).json()

    await client.post(
        "/api/v1/progress/weights",
        json={"recorded_on": str(date.today()), "weight_kg": 77.4},
        headers=auth_headers,
    )

    refreshed = (await client.get(f"/api/v1/goals/{goal['id']}", headers=auth_headers)).json()
    assert refreshed["status"] == "achieved"
    assert refreshed["achieved_at"] is not None
    assert refreshed["progress_percent"] == 100.0


async def test_strength_goal_requires_an_exercise(client, auth_headers):
    response = await client.post(
        "/api/v1/goals",
        json={"goal_type": "exercise_1rm", "title": "Bench 100 kg", "target_value": 100},
        headers=auth_headers,
    )
    assert response.status_code == 422


async def test_goal_target_date_must_follow_the_start_date(client, auth_headers):
    response = await client.post(
        "/api/v1/goals",
        json={
            "goal_type": "custom",
            "title": "Something",
            "target_value": 10,
            "start_date": str(date.today()),
            "target_date": str(date.today() - timedelta(days=1)),
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


async def test_total_workouts_goal_counts_completed_sessions(client, auth_headers, seeded_library):
    templates = await client.get("/api/v1/programs/templates")
    template_id = templates.json()[0]["id"]
    program = (
        await client.post(
            f"/api/v1/programs/{template_id}/duplicate", json={}, headers=auth_headers
        )
    ).json()

    goal = (
        await client.post(
            "/api/v1/goals",
            json={
                "goal_type": "total_workouts",
                "title": "Complete 10 workouts",
                "start_value": 0,
                "target_value": 10,
                "unit": "workouts",
            },
            headers=auth_headers,
        )
    ).json()

    started = (
        await client.post(
            "/api/v1/workout-sessions",
            json={"program_id": program["id"], "day_id": program["days"][0]["id"]},
            headers=auth_headers,
        )
    ).json()
    await client.post(
        f"/api/v1/workout-sessions/exercises/{started['exercises'][0]['id']}/sets",
        json={"set_number": 1, "weight_kg": 60, "reps": 8, "is_completed": True},
        headers=auth_headers,
    )
    await client.post(
        f"/api/v1/workout-sessions/{started['id']}/finish", json={}, headers=auth_headers
    )

    refreshed = (await client.get(f"/api/v1/goals/{goal['id']}", headers=auth_headers)).json()
    assert refreshed["current_value"] == 1
    assert refreshed["progress_percent"] == 10.0
