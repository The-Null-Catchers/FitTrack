"""Unit tests for the pure fitness calculations."""

from __future__ import annotations

from datetime import date

import pytest

from app.models.enums import ActivityLevel, FitnessGoal, Gender
from app.services.metrics import (
    age_from,
    epley_1rm,
    estimate_session_calories,
    estimate_targets,
    kg_to_lb,
    lb_to_kg,
    mifflin_st_jeor_bmr,
    moving_average,
    percent_change,
    set_volume,
)


def test_epley_returns_the_weight_itself_for_a_single():
    assert epley_1rm(100, 1) == 100


def test_epley_grows_with_reps():
    assert epley_1rm(100, 5) == pytest.approx(116.67, abs=0.01)
    assert epley_1rm(100, 10) > epley_1rm(100, 5)


def test_epley_caps_unreliable_high_rep_sets():
    # Beyond 12 reps the formula stops being meaningful, so it plateaus.
    assert epley_1rm(60, 20) == epley_1rm(60, 12)


@pytest.mark.parametrize(("weight", "reps"), [(0, 5), (100, 0), (-10, 5), (100, -1)])
def test_epley_rejects_nonsense(weight, reps):
    assert epley_1rm(weight, reps) == 0.0


def test_set_volume():
    assert set_volume(80, 8) == 640
    assert set_volume(None, 8) == 0.0
    assert set_volume(80, None) == 0.0


def test_age_from_handles_birthday_not_yet_reached():
    assert age_from(date(1990, 12, 31), on=date(2024, 6, 1)) == 33
    assert age_from(date(1990, 1, 1), on=date(2024, 6, 1)) == 34
    assert age_from(None) is None


def test_bmr_uses_the_expected_constants():
    male = mifflin_st_jeor_bmr(weight_kg=80, height_cm=180, age_years=30, gender=Gender.MALE)
    female = mifflin_st_jeor_bmr(weight_kg=80, height_cm=180, age_years=30, gender=Gender.FEMALE)
    assert male == pytest.approx(1780.0)
    assert female == pytest.approx(1614.0)
    # An undisclosed gender still produces a usable number, between the two.
    other = mifflin_st_jeor_bmr(
        weight_kg=80, height_cm=180, age_years=30, gender=Gender.UNDISCLOSED
    )
    assert female < other < male


def test_estimate_targets_reflects_the_goal():
    common = {
        "weight_kg": 80.0,
        "height_cm": 180.0,
        "age_years": 30,
        "gender": Gender.MALE,
        "activity_level": ActivityLevel.MODERATE,
    }
    cutting = estimate_targets(**common, goal=FitnessGoal.LOSE_WEIGHT)
    bulking = estimate_targets(**common, goal=FitnessGoal.GAIN_MUSCLE)

    assert cutting["recommended_calories"] < bulking["recommended_calories"]
    # Protein is held high in a deficit to protect lean mass.
    assert cutting["recommended_protein_g"] >= bulking["recommended_protein_g"]
    assert cutting["recommended_calories"] >= 1200


def test_estimate_targets_never_recommends_below_the_floor():
    tiny = estimate_targets(
        weight_kg=42.0,
        height_cm=150.0,
        age_years=70,
        gender=Gender.FEMALE,
        activity_level=ActivityLevel.SEDENTARY,
        goal=FitnessGoal.LOSE_WEIGHT,
    )
    assert tiny["recommended_calories"] >= 1200


def test_unit_conversions_round_trip():
    assert lb_to_kg(kg_to_lb(80.0)) == pytest.approx(80.0, abs=0.01)


def test_moving_average_smooths_without_shifting_length():
    values = [80.0, 81.0, 79.0, 82.0, 78.0]
    smoothed = moving_average(values, 3)
    assert len(smoothed) == len(values)
    assert smoothed[0] == 80.0
    assert max(smoothed) < max(values)


def test_percent_change():
    assert percent_change(100, 110) == 10.0
    assert percent_change(100, 90) == -10.0
    assert percent_change(0, 10) is None


def test_session_calories_needs_a_duration():
    assert (
        estimate_session_calories(duration_seconds=None, bodyweight_kg=80, total_volume_kg=5000)
        is None
    )
    value = estimate_session_calories(duration_seconds=3600, bodyweight_kg=80, total_volume_kg=5000)
    assert 350 < value < 500
