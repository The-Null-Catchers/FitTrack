"""Rules-based smart progression.

This is deliberately independent of the AI layer: it is deterministic,
explainable and always available offline-capable clients can rely on. It only
ever *suggests* — nothing is applied to a program automatically.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from app.models.enums import Equipment, SetType, TrackingType

#: Smallest weight jump we suggest, by equipment.
INCREMENT_KG = {
    Equipment.BARBELL: 2.5,
    Equipment.DUMBBELL: 2.0,
    Equipment.MACHINE: 5.0,
    Equipment.CABLE: 2.5,
    Equipment.KETTLEBELL: 4.0,
    Equipment.RESISTANCE_BAND: 0.0,
    Equipment.BODYWEIGHT: 0.0,
    Equipment.CARDIO_MACHINE: 0.0,
    Equipment.OTHER: 2.5,
}

#: Consecutive qualifying sessions before a suggestion is raised.
SESSIONS_REQUIRED = 2

Action = Literal["increase_weight", "increase_reps", "hold", "deload"]


@dataclass(slots=True)
class SetOutcome:
    """Flattened view of one logged set, used by the rules below."""

    weight_kg: float | None
    reps: int | None
    duration_seconds: int | None
    rpe: float | None
    set_type: str


@dataclass(slots=True)
class SessionOutcome:
    sets: list[SetOutcome]

    @property
    def working_sets(self) -> list[SetOutcome]:
        return [s for s in self.sets if s.set_type != SetType.WARMUP]


@dataclass(slots=True)
class Suggestion:
    action: Action
    message: str
    suggested_weight_kg: float | None = None
    suggested_reps: int | None = None


def _met_target(
    session: SessionOutcome,
    *,
    target_sets: int,
    target_reps_max: int | None,
    tracking_type: str,
) -> bool:
    working = session.working_sets
    if len(working) < target_sets:
        return False
    if tracking_type == TrackingType.DURATION:
        return all((s.duration_seconds or 0) > 0 for s in working[:target_sets])
    if target_reps_max is None:
        return False
    return all((s.reps or 0) >= target_reps_max for s in working[:target_sets])


def _hard_effort(session: SessionOutcome) -> bool:
    """RPE 9.5+ across working sets means the load is already near-maximal."""
    rpes = [s.rpe for s in session.working_sets if s.rpe is not None]
    return bool(rpes) and min(rpes) >= 9.5


def _top_weight(session: SessionOutcome) -> float | None:
    weights = [s.weight_kg for s in session.working_sets if s.weight_kg]
    return max(weights) if weights else None


def suggest(
    *,
    recent_sessions: list[SessionOutcome],
    target_sets: int,
    target_reps_min: int | None,
    target_reps_max: int | None,
    tracking_type: str,
    equipment: str,
) -> Suggestion | None:
    """Return a progression suggestion, or ``None`` when nothing to say.

    ``recent_sessions`` is newest-first and should contain at least
    :data:`SESSIONS_REQUIRED` entries for a load increase to be proposed.
    """
    if not recent_sessions:
        return None

    latest = recent_sessions[0]
    if not latest.working_sets:
        return None

    if tracking_type in {TrackingType.DISTANCE, TrackingType.CALORIES}:
        return None

    qualifying = [
        s
        for s in recent_sessions[:SESSIONS_REQUIRED]
        if _met_target(
            s,
            target_sets=target_sets,
            target_reps_max=target_reps_max,
            tracking_type=tracking_type,
        )
    ]

    if len(qualifying) >= SESSIONS_REQUIRED and not _hard_effort(latest):
        if tracking_type == TrackingType.DURATION:
            return Suggestion(
                action="increase_reps",
                message="You've hit your target twice in a row. Consider adding 10-15 seconds "
                "next session.",
            )
        increment = INCREMENT_KG.get(Equipment(equipment), 2.5)
        top = _top_weight(latest)
        if increment > 0 and top:
            return Suggestion(
                action="increase_weight",
                message=(
                    f"You hit every set at the top of your rep range twice in a row. "
                    f"Consider adding {increment:g} kg next session."
                ),
                suggested_weight_kg=round(top + increment, 2),
                suggested_reps=target_reps_min,
            )
        return Suggestion(
            action="increase_reps",
            message="Bodyweight target met twice in a row — try adding a rep or two per set.",
            suggested_reps=(target_reps_max or 0) + 1 or None,
        )

    # Repeatedly falling short of the bottom of the range: back the load off.
    if target_reps_min is not None and len(recent_sessions) >= SESSIONS_REQUIRED:
        short = [
            s
            for s in recent_sessions[:SESSIONS_REQUIRED]
            if s.working_sets
            and max((x.reps or 0) for x in s.working_sets) < target_reps_min
        ]
        if len(short) >= SESSIONS_REQUIRED:
            top = _top_weight(latest)
            suggested = round(top * 0.9, 1) if top else None
            return Suggestion(
                action="deload",
                message=(
                    "You've come in under your rep target twice. Consider dropping about 10% "
                    "and building back up."
                ),
                suggested_weight_kg=suggested,
            )

    return None
