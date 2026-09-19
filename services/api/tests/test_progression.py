"""The rules-based progression engine."""

from __future__ import annotations

from app.models.enums import Equipment, SetType, TrackingType
from app.services.progression import SessionOutcome, SetOutcome, suggest


def _session(*sets: tuple[float, int, float | None], set_type: str = SetType.NORMAL):
    return SessionOutcome(
        sets=[
            SetOutcome(
                weight_kg=weight,
                reps=reps,
                duration_seconds=None,
                rpe=rpe,
                set_type=set_type,
            )
            for weight, reps, rpe in sets
        ]
    )


BASE = {
    "target_sets": 3,
    "target_reps_min": 6,
    "target_reps_max": 8,
    "tracking_type": TrackingType.WEIGHT_REPS,
    "equipment": Equipment.BARBELL,
}


def test_no_suggestion_without_history():
    assert suggest(recent_sessions=[], **BASE) is None


def test_suggests_more_weight_after_two_clean_sessions():
    clean = _session((80, 8, 8.0), (80, 8, 8.0), (80, 8, 8.5))
    result = suggest(recent_sessions=[clean, clean], **BASE)

    assert result is not None
    assert result.action == "increase_weight"
    assert result.suggested_weight_kg == 82.5
    assert "2.5 kg" in result.message


def test_one_clean_session_is_not_enough():
    clean = _session((80, 8, 8.0), (80, 8, 8.0), (80, 8, 8.0))
    partial = _session((80, 7, 8.0), (80, 6, 9.0), (80, 6, 9.0))
    assert suggest(recent_sessions=[clean, partial], **BASE) is None


def test_maximal_effort_holds_the_weight():
    grinding = _session((80, 8, 10.0), (80, 8, 9.5), (80, 8, 9.5))
    assert suggest(recent_sessions=[grinding, grinding], **BASE) is None


def test_warm_up_sets_do_not_count_toward_the_target():
    warmups = SessionOutcome(
        sets=[
            SetOutcome(40, 8, None, 5.0, SetType.WARMUP),
            SetOutcome(60, 8, None, 6.0, SetType.WARMUP),
            SetOutcome(80, 8, None, 8.0, SetType.NORMAL),
        ]
    )
    # Only one working set against a target of three.
    assert suggest(recent_sessions=[warmups, warmups], **BASE) is None


def test_repeatedly_missing_the_rep_floor_suggests_a_deload():
    short = _session((90, 4, 9.0), (90, 3, 9.5), (90, 3, 9.5))
    result = suggest(recent_sessions=[short, short], **BASE)

    assert result is not None
    assert result.action == "deload"
    assert result.suggested_weight_kg == 81.0


def test_dumbbell_increment_is_smaller_than_barbell():
    clean = _session((24, 8, 8.0), (24, 8, 8.0), (24, 8, 8.0))
    result = suggest(
        recent_sessions=[clean, clean], **{**BASE, "equipment": Equipment.DUMBBELL}
    )
    assert result.suggested_weight_kg == 26.0


def test_bodyweight_work_progresses_by_reps():
    clean = SessionOutcome(
        sets=[SetOutcome(None, 12, None, 8.0, SetType.NORMAL) for _ in range(3)]
    )
    result = suggest(
        recent_sessions=[clean, clean],
        **{
            **BASE,
            "equipment": Equipment.BODYWEIGHT,
            "target_reps_min": 8,
            "target_reps_max": 12,
        },
    )
    assert result.action == "increase_reps"


def test_duration_work_suggests_more_time():
    held = SessionOutcome(
        sets=[SetOutcome(None, None, 60, 8.0, SetType.NORMAL) for _ in range(3)]
    )
    result = suggest(
        recent_sessions=[held, held],
        **{**BASE, "tracking_type": TrackingType.DURATION, "equipment": Equipment.BODYWEIGHT},
    )
    assert result.action == "increase_reps"
    assert "seconds" in result.message


def test_distance_work_is_left_alone():
    ran = SessionOutcome(sets=[SetOutcome(None, None, 1800, 7.0, SetType.NORMAL)])
    assert (
        suggest(
            recent_sessions=[ran, ran],
            **{**BASE, "tracking_type": TrackingType.DISTANCE},
        )
        is None
    )
