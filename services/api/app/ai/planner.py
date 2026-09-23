"""Workout plan generation.

The generator is grounded in the real exercise library rather than in whatever
a model invents: it selects movements by muscle group, equipment and
difficulty, then applies goal-appropriate set/rep/rest prescriptions. The LLM
layer (when configured) contributes the coaching notes on top of this
structure, so a plan is never unusable because an external API was down.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import (
    Difficulty,
    Equipment,
    FitnessGoal,
    FitnessLevel,
    MuscleGroup,
    WorkoutLocation,
)
from app.models.exercise import Exercise


@dataclass(frozen=True, slots=True)
class Prescription:
    sets: int
    reps_min: int
    reps_max: int
    rest_seconds: int
    rpe: float | None = None


#: Set/rep/rest scheme per goal, applied to compound movements. Isolation work
#: takes the lighter variant defined in :func:`_prescription`.
GOAL_SCHEME: dict[str, Prescription] = {
    FitnessGoal.IMPROVE_STRENGTH: Prescription(5, 3, 5, 180, 8.0),
    FitnessGoal.GAIN_MUSCLE: Prescription(4, 6, 10, 120, 8.5),
    FitnessGoal.LOSE_WEIGHT: Prescription(3, 10, 15, 60, 8.0),
    FitnessGoal.IMPROVE_ENDURANCE: Prescription(3, 12, 20, 45, 7.5),
    FitnessGoal.GENERAL_FITNESS: Prescription(3, 8, 12, 90, 8.0),
    FitnessGoal.MAINTAIN_WEIGHT: Prescription(3, 8, 12, 90, 8.0),
}

#: Weekly split templates: (day name, focus, [(muscle group, slots)]).
SPLITS: dict[int, list[tuple[str, str, list[tuple[str, int]]]]] = {
    1: [
        (
            "Full Body",
            "full_body",
            [
                (MuscleGroup.LEGS, 2),
                (MuscleGroup.CHEST, 1),
                (MuscleGroup.BACK, 2),
                (MuscleGroup.SHOULDERS, 1),
                (MuscleGroup.CORE, 1),
            ],
        ),
    ],
    2: [
        (
            "Upper Body",
            "upper",
            [
                (MuscleGroup.CHEST, 2),
                (MuscleGroup.BACK, 2),
                (MuscleGroup.SHOULDERS, 1),
                (MuscleGroup.ARMS, 1),
            ],
        ),
        ("Lower Body", "lower", [(MuscleGroup.LEGS, 4), (MuscleGroup.CORE, 2)]),
    ],
    3: [
        (
            "Push",
            "push",
            [(MuscleGroup.CHEST, 2), (MuscleGroup.SHOULDERS, 2), (MuscleGroup.ARMS, 1)],
        ),
        ("Pull", "pull", [(MuscleGroup.BACK, 3), (MuscleGroup.ARMS, 1), (MuscleGroup.CORE, 1)]),
        ("Legs", "legs", [(MuscleGroup.LEGS, 4), (MuscleGroup.CORE, 1)]),
    ],
    4: [
        (
            "Upper A",
            "upper",
            [(MuscleGroup.CHEST, 2), (MuscleGroup.BACK, 2), (MuscleGroup.SHOULDERS, 1)],
        ),
        ("Lower A", "lower", [(MuscleGroup.LEGS, 4), (MuscleGroup.CORE, 1)]),
        (
            "Upper B",
            "upper",
            [(MuscleGroup.BACK, 2), (MuscleGroup.SHOULDERS, 2), (MuscleGroup.ARMS, 2)],
        ),
        ("Lower B", "lower", [(MuscleGroup.LEGS, 3), (MuscleGroup.CORE, 2)]),
    ],
    5: [
        ("Push", "push", [(MuscleGroup.CHEST, 3), (MuscleGroup.SHOULDERS, 2)]),
        ("Pull", "pull", [(MuscleGroup.BACK, 3), (MuscleGroup.ARMS, 1)]),
        ("Legs", "legs", [(MuscleGroup.LEGS, 4), (MuscleGroup.CORE, 1)]),
        ("Upper", "upper", [(MuscleGroup.CHEST, 1), (MuscleGroup.BACK, 2), (MuscleGroup.ARMS, 2)]),
        ("Lower & Core", "lower", [(MuscleGroup.LEGS, 3), (MuscleGroup.CORE, 2)]),
    ],
    6: [
        ("Push A", "push", [(MuscleGroup.CHEST, 3), (MuscleGroup.SHOULDERS, 1)]),
        ("Pull A", "pull", [(MuscleGroup.BACK, 3), (MuscleGroup.ARMS, 1)]),
        ("Legs A", "legs", [(MuscleGroup.LEGS, 4)]),
        ("Push B", "push", [(MuscleGroup.SHOULDERS, 3), (MuscleGroup.CHEST, 1)]),
        ("Pull B", "pull", [(MuscleGroup.BACK, 2), (MuscleGroup.ARMS, 2)]),
        ("Legs B & Core", "legs", [(MuscleGroup.LEGS, 3), (MuscleGroup.CORE, 2)]),
    ],
}
SPLITS[7] = SPLITS[6] + [
    ("Conditioning & Mobility", "cardio", [(MuscleGroup.CARDIO, 2), (MuscleGroup.MOBILITY, 2)])
]

#: Sensible training weekdays per frequency (0 = Monday).
WEEKDAYS: dict[int, list[int]] = {
    1: [2],
    2: [1, 4],
    3: [0, 2, 4],
    4: [0, 1, 3, 4],
    5: [0, 1, 2, 4, 5],
    6: [0, 1, 2, 3, 4, 5],
    7: [0, 1, 2, 3, 4, 5, 6],
}

_LEVEL_ALLOWED: dict[str, set[str]] = {
    FitnessLevel.BEGINNER: {Difficulty.BEGINNER},
    FitnessLevel.INTERMEDIATE: {Difficulty.BEGINNER, Difficulty.INTERMEDIATE},
    FitnessLevel.ADVANCED: {Difficulty.BEGINNER, Difficulty.INTERMEDIATE, Difficulty.ADVANCED},
}

#: Equipment implicitly available at each location, on top of the user's list.
_LOCATION_EQUIPMENT: dict[str, set[str]] = {
    WorkoutLocation.GYM: {
        Equipment.BARBELL,
        Equipment.DUMBBELL,
        Equipment.CABLE,
        Equipment.MACHINE,
        Equipment.BODYWEIGHT,
        Equipment.KETTLEBELL,
        Equipment.CARDIO_MACHINE,
    },
    WorkoutLocation.HOME: {Equipment.BODYWEIGHT, Equipment.DUMBBELL, Equipment.RESISTANCE_BAND},
    WorkoutLocation.OUTDOOR: {Equipment.BODYWEIGHT},
    WorkoutLocation.MIXED: {Equipment.BODYWEIGHT, Equipment.DUMBBELL},
}


def _prescription(goal: str, is_compound: bool) -> Prescription:
    scheme = GOAL_SCHEME.get(goal, GOAL_SCHEME[FitnessGoal.GENERAL_FITNESS])
    if is_compound:
        return scheme
    # Isolation work: one fewer set, a couple more reps, shorter rest.
    return Prescription(
        sets=max(2, scheme.sets - 1),
        reps_min=scheme.reps_min + 2,
        reps_max=scheme.reps_max + 3,
        rest_seconds=max(45, scheme.rest_seconds - 30),
        rpe=scheme.rpe,
    )


def _is_compound(exercise: Exercise) -> bool:
    return bool(exercise.secondary_muscles) and exercise.equipment in {
        Equipment.BARBELL,
        Equipment.DUMBBELL,
        Equipment.MACHINE,
        Equipment.BODYWEIGHT,
    }


async def _candidate_pool(
    db: AsyncSession,
    *,
    equipment: set[str],
    level: str,
    excluded: set[uuid.UUID],
    user_id: uuid.UUID | None,
) -> list[Exercise]:
    allowed_difficulty = _LEVEL_ALLOWED.get(level, {Difficulty.BEGINNER})
    stmt = select(Exercise).where(
        Exercise.is_deleted.is_(False),
        Exercise.difficulty.in_(list(allowed_difficulty)),
        Exercise.equipment.in_(list(equipment)),
        or_(Exercise.is_public.is_(True), Exercise.created_by_id == user_id),
    )
    rows = [e for e in await db.scalars(stmt) if e.id not in excluded]
    # Compounds first, then by popularity: the important lifts lead each day.
    rows.sort(key=lambda e: (not _is_compound(e), -e.popularity, e.name))
    return rows


def _session_slot_budget(session_minutes: int, goal: str) -> int:
    """How many exercises fit in the session length the user chose."""
    scheme = GOAL_SCHEME.get(goal, GOAL_SCHEME[FitnessGoal.GENERAL_FITNESS])
    seconds_per_exercise = scheme.sets * (scheme.rest_seconds + 45)
    budget = int((session_minutes * 60 * 0.85) // max(seconds_per_exercise, 1))
    return max(3, min(budget, 8))


async def generate(
    db: AsyncSession,
    *,
    goal: str,
    experience: str,
    days_per_week: int,
    session_minutes: int,
    equipment: list[str],
    location: str,
    preferred_exercise_ids: list[uuid.UUID],
    excluded_exercise_ids: list[uuid.UUID],
    user_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    """Build a complete weekly plan from the exercise library."""
    days_per_week = max(1, min(days_per_week, 7))
    available = set(equipment) or set()
    available |= _LOCATION_EQUIPMENT.get(location, {Equipment.BODYWEIGHT})
    available.add(Equipment.BODYWEIGHT)

    pool = await _candidate_pool(
        db,
        equipment=available,
        level=experience,
        excluded=set(excluded_exercise_ids),
        user_id=user_id,
    )
    by_group: dict[str, list[Exercise]] = {}
    for exercise in pool:
        by_group.setdefault(exercise.muscle_group, []).append(exercise)

    preferred = set(preferred_exercise_ids)
    for group_exercises in by_group.values():
        group_exercises.sort(key=lambda e: (e.id not in preferred,))

    template = SPLITS[days_per_week]
    weekdays = WEEKDAYS[days_per_week]
    budget = _session_slot_budget(session_minutes, goal)

    used_overall: set[uuid.UUID] = set()
    days: list[dict[str, Any]] = []

    for index, (name, focus, groups) in enumerate(template):
        chosen: list[Exercise] = []
        slots = [(group, count) for group, count in groups]
        total_requested = sum(count for _, count in slots)
        # Scale the day down proportionally when the time budget is tight.
        scale = min(1.0, budget / max(total_requested, 1))

        for group, count in slots:
            take = max(1, round(count * scale))
            candidates = by_group.get(group, [])
            picked = 0
            for exercise in candidates:
                if picked >= take:
                    break
                if exercise.id in used_overall and len(candidates) > take * 2:
                    continue
                if exercise in chosen:
                    continue
                chosen.append(exercise)
                used_overall.add(exercise.id)
                picked += 1
            # If the library couldn't fill the slot, fall back to repeats.
            if picked == 0 and candidates:
                chosen.append(candidates[0])

        chosen = chosen[:budget]
        days.append(
            {
                "name": name,
                "weekday": weekdays[index] if index < len(weekdays) else None,
                "focus": focus,
                "exercises": [
                    {
                        "exercise_id": str(exercise.id),
                        "exercise_name": exercise.name,
                        "prescription": _prescription_payload(
                            exercise, _prescription(goal, _is_compound(exercise))
                        ),
                    }
                    for exercise in chosen
                ],
            }
        )

    scheme = GOAL_SCHEME.get(goal, GOAL_SCHEME[FitnessGoal.GENERAL_FITNESS])
    return {
        "name": _plan_name(goal, days_per_week),
        "description": _plan_description(goal, days_per_week, session_minutes, location),
        "goal": goal,
        "difficulty": _difficulty_for(experience),
        "days_per_week": days_per_week,
        "estimated_minutes": session_minutes,
        "equipment_needed": sorted(available),
        "days": days,
        "coaching_notes": _coaching_notes(goal, experience, scheme),
    }


def _prescription_payload(exercise: Exercise, scheme: Prescription) -> dict[str, Any]:
    from app.models.enums import TrackingType

    if exercise.default_tracking_type == TrackingType.DURATION:
        return {
            "sets": scheme.sets,
            "reps_min": None,
            "reps_max": None,
            "duration_seconds": 45,
            "rest_seconds": scheme.rest_seconds,
            "rpe": scheme.rpe,
            "notes": None,
        }
    return {
        "sets": scheme.sets,
        "reps_min": scheme.reps_min,
        "reps_max": scheme.reps_max,
        "duration_seconds": None,
        "rest_seconds": scheme.rest_seconds,
        "rpe": scheme.rpe,
        "notes": None,
    }


def _difficulty_for(experience: str) -> str:
    return {
        FitnessLevel.BEGINNER: Difficulty.BEGINNER,
        FitnessLevel.INTERMEDIATE: Difficulty.INTERMEDIATE,
        FitnessLevel.ADVANCED: Difficulty.ADVANCED,
    }.get(experience, Difficulty.BEGINNER)


def _plan_name(goal: str, days: int) -> str:
    label = {
        FitnessGoal.LOSE_WEIGHT: "Lean Progress",
        FitnessGoal.GAIN_MUSCLE: "Muscle Builder",
        FitnessGoal.IMPROVE_STRENGTH: "Strength Focus",
        FitnessGoal.IMPROVE_ENDURANCE: "Conditioning",
        FitnessGoal.GENERAL_FITNESS: "Balanced Training",
        FitnessGoal.MAINTAIN_WEIGHT: "Maintenance",
    }.get(goal, "Training Plan")
    return f"{label} — {days} Day{'s' if days != 1 else ''}"


def _plan_description(goal: str, days: int, minutes: int, location: str) -> str:
    readable_goal = goal.replace("_", " ")
    return (
        f"A {days}-day week built around {readable_goal}, designed for roughly "
        f"{minutes}-minute sessions {'at home' if location == 'home' else 'in the gym'}. "
        "Exercises are drawn from your available equipment; adjust anything that "
        "doesn't fit you."
    )


def _coaching_notes(goal: str, experience: str, scheme: Prescription) -> list[str]:
    notes = [
        f"Aim for {scheme.sets} working sets of {scheme.reps_min}-{scheme.reps_max} reps on "
        f"the main lifts, resting about {scheme.rest_seconds} seconds between them.",
        "Add a small amount of weight once you hit the top of the rep range on every set "
        "for two sessions in a row — FitTrack will prompt you when that happens.",
        "Warm up with two or three progressively heavier sets before your first working "
        "set of each main movement.",
    ]
    if experience == FitnessLevel.BEGINNER:
        notes.append(
            "Leave two or three reps in reserve for the first few weeks while you learn the "
            "movements — technique first, load second."
        )
    if goal == FitnessGoal.LOSE_WEIGHT:
        notes.append(
            "Keep the lifting intensity up while you're in a calorie deficit; that's what "
            "protects the muscle you already have."
        )
    if goal == FitnessGoal.IMPROVE_STRENGTH:
        notes.append(
            "Take the full rest between heavy sets. Cutting rest short here costs you reps, "
            "not time."
        )
    notes.append(
        "This plan is general fitness information, not medical advice. If anything hurts, "
        "stop and speak with a qualified professional."
    )
    return notes
