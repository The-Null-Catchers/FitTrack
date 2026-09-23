"""Starter workout templates users can clone.

Each day lists exercises by name; the seeder resolves them against the library
and skips any that are missing rather than failing the whole seed.
"""

from __future__ import annotations

from app.models.enums import Difficulty as D
from app.models.enums import FitnessGoal as G
from app.models.enums import WorkoutLocation as L

#: (sets, reps_min, reps_max, rest_seconds)
Scheme = tuple[int, int, int, int]

TEMPLATES: list[dict] = [
    {
        "name": "Push / Pull / Legs",
        "description": "The classic three-way split. Each muscle group gets a dedicated "
        "day, so you can train hard and still recover between sessions.",
        "goal": G.GAIN_MUSCLE,
        "difficulty": D.INTERMEDIATE,
        "location": L.GYM,
        "days_per_week": 3,
        "estimated_minutes": 70,
        "days": [
            (
                "Push",
                0,
                [
                    ("Barbell Bench Press", (4, 6, 8, 150)),
                    ("Incline Dumbbell Press", (3, 8, 12, 120)),
                    ("Dumbbell Shoulder Press", (3, 8, 12, 120)),
                    ("Lateral Raise", (3, 12, 15, 60)),
                    ("Triceps Pushdown", (3, 10, 15, 60)),
                ],
            ),
            (
                "Pull",
                2,
                [
                    ("Barbell Row", (4, 6, 8, 150)),
                    ("Lat Pulldown", (3, 8, 12, 120)),
                    ("Seated Cable Row", (3, 10, 12, 90)),
                    ("Face Pull", (3, 12, 15, 60)),
                    ("Dumbbell Curl", (3, 10, 12, 60)),
                ],
            ),
            (
                "Legs",
                4,
                [
                    ("Back Squat", (4, 5, 8, 180)),
                    ("Romanian Deadlift", (3, 8, 10, 150)),
                    ("Leg Press", (3, 10, 12, 120)),
                    ("Leg Curl", (3, 10, 15, 75)),
                    ("Standing Calf Raise", (4, 12, 15, 60)),
                ],
            ),
        ],
    },
    {
        "name": "Upper / Lower",
        "description": "Four sessions a week, alternating upper and lower body. A strong "
        "default once three days a week stops being enough.",
        "goal": G.GAIN_MUSCLE,
        "difficulty": D.INTERMEDIATE,
        "location": L.GYM,
        "days_per_week": 4,
        "estimated_minutes": 65,
        "days": [
            (
                "Upper A",
                0,
                [
                    ("Barbell Bench Press", (4, 5, 8, 150)),
                    ("Barbell Row", (4, 6, 10, 150)),
                    ("Dumbbell Shoulder Press", (3, 8, 12, 120)),
                    ("Lat Pulldown", (3, 10, 12, 90)),
                    ("Triceps Pushdown", (3, 10, 15, 60)),
                ],
            ),
            (
                "Lower A",
                1,
                [
                    ("Back Squat", (4, 5, 8, 180)),
                    ("Romanian Deadlift", (3, 8, 10, 150)),
                    ("Walking Lunge", (3, 10, 12, 90)),
                    ("Plank", (3, 1, 1, 60)),
                ],
            ),
            (
                "Upper B",
                3,
                [
                    ("Overhead Press", (4, 5, 8, 180)),
                    ("Pull-Up", (4, 5, 10, 150)),
                    ("Incline Dumbbell Press", (3, 8, 12, 120)),
                    ("Single-Arm Dumbbell Row", (3, 10, 12, 90)),
                    ("Hammer Curl", (3, 10, 12, 60)),
                ],
            ),
            (
                "Lower B",
                4,
                [
                    ("Deadlift", (3, 3, 5, 240)),
                    ("Bulgarian Split Squat", (3, 8, 12, 120)),
                    ("Leg Extension", (3, 12, 15, 75)),
                    ("Hanging Leg Raise", (3, 8, 12, 75)),
                ],
            ),
        ],
    },
    {
        "name": "Full Body 3 Days",
        "description": "Three full-body sessions a week. The most time-efficient way to "
        "train every muscle group often.",
        "goal": G.GENERAL_FITNESS,
        "difficulty": D.BEGINNER,
        "location": L.GYM,
        "days_per_week": 3,
        "estimated_minutes": 55,
        "days": [
            (
                "Full Body A",
                0,
                [
                    ("Back Squat", (3, 6, 8, 150)),
                    ("Barbell Bench Press", (3, 6, 8, 150)),
                    ("Seated Cable Row", (3, 8, 12, 90)),
                    ("Plank", (3, 1, 1, 60)),
                ],
            ),
            (
                "Full Body B",
                2,
                [
                    ("Romanian Deadlift", (3, 8, 10, 150)),
                    ("Dumbbell Shoulder Press", (3, 8, 12, 120)),
                    ("Lat Pulldown", (3, 8, 12, 90)),
                    ("Goblet Squat", (3, 10, 12, 90)),
                ],
            ),
            (
                "Full Body C",
                4,
                [
                    ("Leg Press", (3, 10, 12, 120)),
                    ("Incline Dumbbell Press", (3, 8, 12, 120)),
                    ("Single-Arm Dumbbell Row", (3, 10, 12, 90)),
                    ("Hanging Leg Raise", (3, 8, 12, 75)),
                ],
            ),
        ],
    },
    {
        "name": "Beginner Gym",
        "description": "A gentle introduction to the gym: machines and simple free-weight "
        "movements, three days a week, focused on learning the patterns.",
        "goal": G.GENERAL_FITNESS,
        "difficulty": D.BEGINNER,
        "location": L.GYM,
        "days_per_week": 3,
        "estimated_minutes": 45,
        "days": [
            (
                "Day 1",
                0,
                [
                    ("Leg Press", (3, 10, 12, 90)),
                    ("Chest Press Machine", (3, 10, 12, 90)),
                    ("Lat Pulldown", (3, 10, 12, 90)),
                    ("Plank", (3, 1, 1, 60)),
                ],
            ),
            (
                "Day 2",
                2,
                [
                    ("Goblet Squat", (3, 10, 12, 90)),
                    ("Dumbbell Bench Press", (3, 10, 12, 90)),
                    ("Seated Cable Row", (3, 10, 12, 90)),
                    ("Dead Bug", (3, 8, 10, 45)),
                ],
            ),
            (
                "Day 3",
                4,
                [
                    ("Leg Curl", (3, 12, 15, 75)),
                    ("Dumbbell Shoulder Press", (3, 10, 12, 90)),
                    ("Inverted Row", (3, 8, 12, 90)),
                    ("Side Plank", (3, 1, 1, 45)),
                ],
            ),
        ],
    },
    {
        "name": "Dumbbells Only",
        "description": "Everything here needs a single pair of adjustable dumbbells — "
        "built for a home setup with limited space.",
        "goal": G.GAIN_MUSCLE,
        "difficulty": D.BEGINNER,
        "location": L.HOME,
        "days_per_week": 4,
        "estimated_minutes": 45,
        "days": [
            (
                "Upper",
                0,
                [
                    ("Dumbbell Bench Press", (4, 8, 12, 90)),
                    ("Single-Arm Dumbbell Row", (4, 8, 12, 90)),
                    ("Dumbbell Shoulder Press", (3, 8, 12, 90)),
                    ("Hammer Curl", (3, 10, 12, 60)),
                    ("Overhead Triceps Extension", (3, 10, 12, 60)),
                ],
            ),
            (
                "Lower",
                1,
                [
                    ("Goblet Squat", (4, 10, 12, 90)),
                    ("Bulgarian Split Squat", (3, 8, 12, 90)),
                    ("Romanian Deadlift", (3, 10, 12, 120)),
                    ("Step-Up", (3, 10, 12, 75)),
                ],
            ),
            (
                "Push & Core",
                3,
                [
                    ("Incline Dumbbell Press", (4, 8, 12, 90)),
                    ("Lateral Raise", (3, 12, 15, 60)),
                    ("Push-Up", (3, 10, 20, 60)),
                    ("Plank", (3, 1, 1, 60)),
                ],
            ),
            (
                "Pull & Carry",
                4,
                [
                    ("Single-Arm Dumbbell Row", (4, 8, 12, 90)),
                    ("Rear Delt Fly", (3, 12, 15, 60)),
                    ("Dumbbell Curl", (3, 10, 12, 60)),
                    ("Farmer's Carry", (3, 1, 1, 90)),
                ],
            ),
        ],
    },
    {
        "name": "Home Bodyweight",
        "description": "No equipment at all. Progress by adding reps and slowing the "
        "lowering phase before you look for extra load.",
        "goal": G.GENERAL_FITNESS,
        "difficulty": D.BEGINNER,
        "location": L.HOME,
        "days_per_week": 3,
        "estimated_minutes": 35,
        "days": [
            (
                "Push Day",
                0,
                [
                    ("Push-Up", (4, 8, 20, 60)),
                    ("Pike Push-Up", (3, 6, 12, 75)),
                    ("Bench Dip", (3, 8, 15, 60)),
                    ("Plank", (3, 1, 1, 60)),
                ],
            ),
            (
                "Legs Day",
                2,
                [
                    ("Air Squat", (4, 15, 25, 60)),
                    ("Walking Lunge", (3, 10, 16, 75)),
                    ("Glute Bridge", (3, 12, 20, 60)),
                    ("Mountain Climber", (3, 1, 1, 45)),
                ],
            ),
            (
                "Pull & Core",
                4,
                [
                    ("Inverted Row", (4, 8, 15, 90)),
                    ("Superman Hold", (3, 1, 1, 45)),
                    ("Russian Twist", (3, 12, 20, 45)),
                    ("Side Plank", (3, 1, 1, 45)),
                ],
            ),
        ],
    },
]
