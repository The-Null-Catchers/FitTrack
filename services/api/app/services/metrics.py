"""Pure fitness calculations.

Everything here is deliberately side-effect free so it can be unit tested and
reused from the API, the worker and the seeder.

None of these figures are medical advice; they are informational estimates.
"""

from __future__ import annotations

from datetime import date

from app.models.enums import ActivityLevel, FitnessGoal, Gender

#: Multipliers applied to BMR to approximate total daily energy expenditure.
ACTIVITY_MULTIPLIERS = {
    ActivityLevel.SEDENTARY: 1.2,
    ActivityLevel.LIGHT: 1.375,
    ActivityLevel.MODERATE: 1.55,
    ActivityLevel.ACTIVE: 1.725,
    ActivityLevel.VERY_ACTIVE: 1.9,
}

#: Calorie deltas per goal, kept modest on purpose.
GOAL_CALORIE_DELTA = {
    FitnessGoal.LOSE_WEIGHT: -450,
    FitnessGoal.GAIN_MUSCLE: 300,
    FitnessGoal.IMPROVE_STRENGTH: 200,
    FitnessGoal.IMPROVE_ENDURANCE: 0,
    FitnessGoal.GENERAL_FITNESS: 0,
    FitnessGoal.MAINTAIN_WEIGHT: 0,
}

#: Grams of protein per kg of body weight, per goal.
GOAL_PROTEIN_PER_KG = {
    FitnessGoal.LOSE_WEIGHT: 2.0,
    FitnessGoal.GAIN_MUSCLE: 1.9,
    FitnessGoal.IMPROVE_STRENGTH: 1.8,
    FitnessGoal.IMPROVE_ENDURANCE: 1.5,
    FitnessGoal.GENERAL_FITNESS: 1.5,
    FitnessGoal.MAINTAIN_WEIGHT: 1.5,
}

ESTIMATE_DISCLAIMER = (
    "These targets are general estimates based on the information you entered. "
    "They are not medical or nutritional advice and may not suit everyone — "
    "adjust them to fit you, or speak to a qualified professional."
)

KG_PER_LB = 0.45359237
CM_PER_INCH = 2.54


def epley_1rm(weight_kg: float, reps: int) -> float:
    """Estimated one-rep max (Epley).

    Reps above 12 make the estimate unreliable, so they are capped rather than
    extrapolated into fantasy numbers.
    """
    if weight_kg <= 0 or reps <= 0:
        return 0.0
    if reps == 1:
        return round(weight_kg, 2)
    effective_reps = min(reps, 12)
    return round(weight_kg * (1 + effective_reps / 30), 2)


def set_volume(weight_kg: float | None, reps: int | None) -> float:
    if not weight_kg or not reps:
        return 0.0
    return round(weight_kg * reps, 2)


def age_from(date_of_birth: date | None, *, on: date | None = None) -> int | None:
    if date_of_birth is None:
        return None
    today = on or date.today()
    years = today.year - date_of_birth.year
    if (today.month, today.day) < (date_of_birth.month, date_of_birth.day):
        years -= 1
    return max(0, years)


def mifflin_st_jeor_bmr(
    *, weight_kg: float, height_cm: float, age_years: int, gender: str
) -> float:
    """Basal metabolic rate (Mifflin-St Jeor).

    For undisclosed/other genders the male and female constants are averaged so
    the estimate degrades gracefully instead of refusing to produce a number.
    """
    base = (10 * weight_kg) + (6.25 * height_cm) - (5 * age_years)
    if gender == Gender.MALE:
        return base + 5
    if gender == Gender.FEMALE:
        return base - 161
    return base - 78


def estimate_targets(
    *,
    weight_kg: float,
    height_cm: float,
    age_years: int | None,
    gender: str,
    activity_level: str,
    goal: str,
) -> dict[str, int]:
    """Return an informational calorie/macro target set."""
    age = age_years if age_years is not None else 30
    bmr = mifflin_st_jeor_bmr(
        weight_kg=weight_kg, height_cm=height_cm, age_years=age, gender=gender
    )
    multiplier = ACTIVITY_MULTIPLIERS.get(ActivityLevel(activity_level), 1.55)
    tdee = bmr * multiplier
    calories = tdee + GOAL_CALORIE_DELTA.get(FitnessGoal(goal), 0)
    # Never recommend a target below a conservative floor.
    calories = max(calories, bmr * 1.05, 1200)

    protein_g = weight_kg * GOAL_PROTEIN_PER_KG.get(FitnessGoal(goal), 1.6)
    fat_g = (calories * 0.27) / 9
    carbs_g = max(0.0, (calories - (protein_g * 4) - (fat_g * 9)) / 4)
    fiber_g = max(20.0, calories / 1000 * 14)
    water_ml = max(1500.0, weight_kg * 33)

    return {
        "bmr_kcal": round(bmr),
        "tdee_kcal": round(tdee),
        "recommended_calories": round(calories),
        "recommended_protein_g": round(protein_g),
        "recommended_carbs_g": round(carbs_g),
        "recommended_fat_g": round(fat_g),
        "recommended_fiber_g": round(fiber_g),
        "recommended_water_ml": int(round(water_ml / 50) * 50),
    }


def estimate_session_calories(
    *, duration_seconds: int | None, bodyweight_kg: float | None, total_volume_kg: float
) -> int | None:
    """Rough energy cost of a strength session.

    Uses a resistance-training MET of ~5.0 with a small volume bonus. Returned
    as an estimate for display only.
    """
    if not duration_seconds or duration_seconds <= 0:
        return None
    weight = bodyweight_kg or 75.0
    hours = duration_seconds / 3600
    base = 5.0 * weight * hours
    volume_bonus = min(total_volume_kg / 1000, 12) * 4
    return int(round(base + volume_bonus))


def kg_to_lb(value: float) -> float:
    return round(value / KG_PER_LB, 2)


def lb_to_kg(value: float) -> float:
    return round(value * KG_PER_LB, 3)


def cm_to_in(value: float) -> float:
    return round(value / CM_PER_INCH, 2)


def in_to_cm(value: float) -> float:
    return round(value * CM_PER_INCH, 2)


def moving_average(values: list[float], window: int = 7) -> list[float]:
    """Trailing moving average, used to smooth noisy body-weight charts."""
    if window <= 1 or not values:
        return list(values)
    out: list[float] = []
    running: list[float] = []
    for value in values:
        running.append(value)
        if len(running) > window:
            running.pop(0)
        out.append(round(sum(running) / len(running), 2))
    return out


def percent_change(first: float, last: float) -> float | None:
    if first == 0:
        return None
    return round(((last - first) / abs(first)) * 100, 1)
