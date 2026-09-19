"""Idempotent database seeding.

``seed_reference_data`` loads the exercise library, food catalogue and starter
templates; it is safe to run on every deploy. ``seed_demo_data`` additionally
creates a demo account with several months of realistic history so charts and
dashboards are populated the moment a reviewer signs in.

No real personal data is ever seeded.
"""

from __future__ import annotations

import random
from datetime import UTC, date, datetime, time, timedelta

from slugify import slugify
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.core.security import hash_password
from app.models.body import BodyMeasurement, BodyWeight
from app.models.enums import (
    ActivityLevel,
    Equipment,
    FitnessGoal,
    FitnessLevel,
    Gender,
    GoalType,
    HabitFrequency,
    MealType,
    MeasurementType,
    ProgramStatus,
    SessionStatus,
    SetType,
    TrackingType,
    UserRole,
    WorkoutLocation,
)
from app.models.exercise import Exercise
from app.models.goal import UserGoal
from app.models.habit import Habit, HabitLog
from app.models.notification import NotificationPreference
from app.models.nutrition import Food, Meal, MealItem, WaterLog
from app.models.program import WorkoutDay, WorkoutDayExercise, WorkoutProgram
from app.models.user import User, UserProfile
from app.models.workout import WorkoutSession, WorkoutSessionExercise, WorkoutSet
from app.seeds.exercise_data import EXERCISES
from app.seeds.food_data import FOODS
from app.seeds.template_data import TEMPLATES
from app.services import nutrition_service, records_service, workout_service
from app.services.metrics import epley_1rm, estimate_targets

logger = get_logger(__name__)

DEMO_EMAIL = "demo@fittrack.app"
DEMO_PASSWORD = "FitTrack2024!"
ADMIN_EMAIL = "admin@fittrack.app"
ADMIN_PASSWORD = "AdminFitTrack2024!"

#: Fixed seed so a reseed reproduces the same demo history.
RNG = random.Random(20240115)

#: Starting working weights (kg) for the demo user's main lifts.
_STARTING_LOAD = {
    "Barbell Bench Press": 60.0,
    "Back Squat": 80.0,
    "Deadlift": 100.0,
    "Overhead Press": 35.0,
    "Barbell Row": 55.0,
    "Romanian Deadlift": 70.0,
    "Incline Dumbbell Press": 22.0,
    "Dumbbell Shoulder Press": 18.0,
    "Lat Pulldown": 50.0,
    "Seated Cable Row": 50.0,
    "Leg Press": 120.0,
    "Lateral Raise": 8.0,
    "Triceps Pushdown": 25.0,
    "Dumbbell Curl": 12.0,
    "Hammer Curl": 12.0,
    "Face Pull": 20.0,
    "Leg Curl": 40.0,
    "Standing Calf Raise": 60.0,
}


async def seed_exercises(db: AsyncSession) -> int:
    existing = set(await db.scalars(select(Exercise.slug).where(Exercise.is_public.is_(True))))
    created = 0
    for (
        name,
        name_ar,
        muscle_group,
        equipment,
        difficulty,
        exercise_type,
        tracking,
        secondary,
        rest,
        instructions,
    ) in EXERCISES:
        slug = slugify(name)
        if slug in existing:
            continue
        exercise = Exercise(
            slug=slug,
            name=name,
            name_ar=name_ar,
            muscle_group=muscle_group,
            equipment=equipment,
            difficulty=difficulty,
            exercise_type=exercise_type,
            default_tracking_type=tracking,
            secondary_muscles=[m.value for m in secondary],
            default_rest_seconds=rest,
            instructions=instructions,
            is_public=True,
            popularity=RNG.randint(0, 50),
        )
        exercise.search_text = exercise.build_search_text()
        db.add(exercise)
        created += 1
    await db.flush()
    return created


async def seed_foods(db: AsyncSession) -> int:
    existing = {
        name.lower() for name in await db.scalars(select(Food.name).where(Food.user_id.is_(None)))
    }
    created = 0
    for name, name_ar, brand, kcal, protein, carbs, fat, fiber, serving, options in FOODS:
        if name.lower() in existing:
            continue
        food = Food(
            name=name,
            name_ar=name_ar,
            brand=brand,
            calories_per_100g=kcal,
            protein_per_100g=protein,
            carbs_per_100g=carbs,
            fat_per_100g=fat,
            fiber_per_100g=fiber,
            default_serving_grams=serving,
            serving_options=[{"label": label, "grams": grams} for label, grams in options],
            is_verified=True,
        )
        food.search_text = food.build_search_text()
        db.add(food)
        created += 1
    await db.flush()
    return created


async def seed_templates(db: AsyncSession) -> int:
    library = {
        exercise.name: exercise
        for exercise in await db.scalars(select(Exercise).where(Exercise.is_public.is_(True)))
    }
    existing = set(
        await db.scalars(select(WorkoutProgram.name).where(WorkoutProgram.is_template.is_(True)))
    )
    created = 0
    for index, template in enumerate(TEMPLATES):
        if template["name"] in existing:
            continue
        program = WorkoutProgram(
            user_id=None,
            name=template["name"],
            description=template["description"],
            goal=template["goal"],
            difficulty=template["difficulty"],
            location=template["location"],
            days_per_week=template["days_per_week"],
            estimated_minutes=template["estimated_minutes"],
            status=ProgramStatus.ACTIVE,
            is_template=True,
            is_featured=index < 3,
        )
        db.add(program)
        await db.flush()

        equipment_used: set[str] = set()
        for position, (day_name, weekday, items) in enumerate(template["days"]):
            day = WorkoutDay(
                program_id=program.id, name=day_name, position=position, weekday=weekday
            )
            db.add(day)
            await db.flush()
            slot = 0
            for exercise_name, (sets, reps_min, reps_max, rest) in items:
                exercise = library.get(exercise_name)
                if exercise is None:
                    logger.warning("seed.template_exercise_missing", name=exercise_name)
                    continue
                equipment_used.add(exercise.equipment)
                is_timed = exercise.default_tracking_type == TrackingType.DURATION
                db.add(
                    WorkoutDayExercise(
                        day_id=day.id,
                        exercise_id=exercise.id,
                        position=slot,
                        target_sets=sets,
                        target_reps_min=None if is_timed else reps_min,
                        target_reps_max=None if is_timed else reps_max,
                        target_duration_seconds=45 if is_timed else None,
                        rest_seconds=rest,
                        tracking_type=exercise.default_tracking_type,
                    )
                )
                slot += 1
        program.equipment_needed = sorted(equipment_used)
        created += 1
    await db.flush()
    return created


async def seed_reference_data(db: AsyncSession) -> dict[str, int]:
    """Library content every environment needs. Safe to re-run."""
    counts = {
        "exercises": await seed_exercises(db),
        "foods": await seed_foods(db),
        "templates": await seed_templates(db),
    }
    await db.commit()
    logger.info("seed.reference_data", **counts)
    return counts


async def _create_user(
    db: AsyncSession,
    *,
    email: str,
    password: str,
    full_name: str,
    role: str = UserRole.USER,
) -> User | None:
    existing = await db.scalar(select(User).where(func.lower(User.email) == email))
    if existing is not None:
        return None
    user = User(
        email=email,
        password_hash=hash_password(password),
        full_name=full_name,
        role=role,
        email_verified_at=datetime.now(UTC),
        onboarding_completed_at=datetime.now(UTC),
    )
    user.notification_preference = NotificationPreference(user_id=user.id)
    db.add(user)
    await db.flush()
    return user


def _working_weight(base: float, week: int, increment: float = 2.5) -> float:
    """Progressive overload with a little week-to-week noise."""
    progression = base + (week * increment * RNG.choice([0.6, 0.8, 1.0, 1.0]))
    return round(progression / 0.5) * 0.5


async def _seed_workout_history(
    db: AsyncSession, user: User, program: WorkoutProgram, *, weeks: int
) -> int:
    days = sorted(program.days, key=lambda d: d.position)
    if not days:
        return 0

    today = date.today()
    created = 0
    for week in range(weeks, 0, -1):
        week_start = today - timedelta(days=(week * 7) + today.weekday())
        for index, day in enumerate(days):
            # Skip roughly one session in eight — real logs have gaps.
            if RNG.random() < 0.12:
                continue
            session_date = week_start + timedelta(days=day.weekday or index * 2)
            if session_date > today:
                continue

            started_at = datetime.combine(
                session_date, time(hour=RNG.choice([7, 8, 17, 18, 19])), tzinfo=UTC
            )
            duration = RNG.randint(2700, 4500)
            session = WorkoutSession(
                user_id=user.id,
                program_id=program.id,
                day_id=day.id,
                name=day.name,
                status=SessionStatus.COMPLETED,
                started_at=started_at,
                completed_at=started_at + timedelta(seconds=duration),
                duration_seconds=duration,
                perceived_effort=RNG.randint(6, 9),
            )
            db.add(session)
            await db.flush()

            for item in sorted(day.exercises, key=lambda e: e.position):
                session_exercise = WorkoutSessionExercise(
                    session_id=session.id,
                    exercise_id=item.exercise_id,
                    position=item.position,
                    tracking_type=item.tracking_type,
                    rest_seconds=item.rest_seconds,
                    target_snapshot={
                        "sets": item.target_sets,
                        "reps_min": item.target_reps_min,
                        "reps_max": item.target_reps_max,
                    },
                )
                db.add(session_exercise)
                await db.flush()
                _add_sets(db, session_exercise, item, weeks - week)

            # Re-load with the eager options the app uses, so totals and record
            # detection never trigger a lazy load outside the async context.
            await db.flush()
            loaded = await workout_service._load(db, session.id)
            _recompute(loaded)
            await records_service.evaluate_session(db, loaded)
            created += 1

    await db.commit()
    return created


def _add_sets(
    db: AsyncSession,
    session_exercise: WorkoutSessionExercise,
    prescription: WorkoutDayExercise,
    week_index: int,
) -> None:
    exercise = prescription.exercise
    tracking = session_exercise.tracking_type
    target_sets = prescription.target_sets

    for set_number in range(1, target_sets + 1):
        item = WorkoutSet(
            session_exercise_id=session_exercise.id,
            set_number=set_number,
            set_type=SetType.NORMAL,
            is_completed=True,
            completed_at=datetime.now(UTC),
            rpe=float(RNG.choice([7.0, 7.5, 8.0, 8.5, 9.0])),
        )
        if tracking == TrackingType.WEIGHT_REPS:
            base = _STARTING_LOAD.get(exercise.name, 20.0)
            item.weight_kg = _working_weight(base, week_index)
            reps_low = prescription.target_reps_min or 8
            reps_high = prescription.target_reps_max or reps_low + 2
            item.reps = RNG.randint(reps_low, reps_high)
        elif tracking == TrackingType.REPS_ONLY:
            reps_low = prescription.target_reps_min or 8
            reps_high = prescription.target_reps_max or reps_low + 4
            item.reps = RNG.randint(reps_low, reps_high) + week_index // 3
        elif tracking == TrackingType.DURATION:
            item.duration_seconds = 40 + week_index * 2 + RNG.randint(-5, 10)
        elif tracking == TrackingType.DISTANCE:
            item.distance_m = 3000 + week_index * 100 + RNG.randint(-200, 400)
            item.duration_seconds = int(item.distance_m / 2.8)

        records_service.recompute_set_derivatives(item, tracking)
        db.add(item)


def _recompute(session: WorkoutSession) -> None:
    volume = 0.0
    sets = reps = 0
    for item in session.exercises:
        for logged in item.sets:
            if not logged.is_completed:
                continue
            sets += 1
            reps += logged.reps or 0
            volume += logged.volume_kg or 0
    session.total_volume_kg = round(volume, 2)
    session.total_sets = sets
    session.total_reps = reps
    session.estimated_calories = round((session.duration_seconds or 0) / 60 * 6.5)


async def _seed_body_history(db: AsyncSession, user: User, *, days: int) -> None:
    start_weight = 84.0
    target_weight = 78.0
    today = date.today()
    for offset in range(days, -1, -1):
        day = today - timedelta(days=offset)
        # Weigh in most days, not every day.
        if RNG.random() < 0.25:
            continue
        progress = (days - offset) / days
        trend = start_weight - (start_weight - target_weight) * progress * 0.75
        noise = RNG.uniform(-0.45, 0.45)
        db.add(
            BodyWeight(
                user_id=user.id,
                recorded_on=day,
                weight_kg=round(trend + noise, 1),
                body_fat_percent=round(22 - progress * 3 + RNG.uniform(-0.4, 0.4), 1),
            )
        )

    measurements = {
        MeasurementType.WAIST: (92.0, -6.0),
        MeasurementType.CHEST: (102.0, 2.0),
        MeasurementType.LEFT_ARM: (35.0, 1.5),
        MeasurementType.RIGHT_ARM: (35.4, 1.5),
        MeasurementType.LEFT_THIGH: (58.0, 1.0),
        MeasurementType.HIPS: (100.0, -3.0),
    }
    for offset in range(days, -1, -14):
        day = today - timedelta(days=offset)
        progress = (days - offset) / days
        for measurement_type, (base, delta) in measurements.items():
            db.add(
                BodyMeasurement(
                    user_id=user.id,
                    recorded_on=day,
                    measurement_type=measurement_type,
                    value_cm=round(base + delta * progress + RNG.uniform(-0.3, 0.3), 1),
                )
            )
    await db.commit()


async def _seed_nutrition(db: AsyncSession, user: User, *, days: int) -> None:
    foods = list(await db.scalars(select(Food).where(Food.user_id.is_(None)).limit(60)))
    if not foods:
        return
    by_name = {food.name: food for food in foods}

    breakfasts = ["Rolled Oats, dry", "Whole Egg", "Greek Yogurt 0%", "Banana"]
    lunches = ["Chicken Breast, grilled", "Cooked White Rice", "Mixed Salad Leaves", "Olive Oil"]
    dinners = ["Salmon Fillet", "Sweet Potato, baked", "Broccoli, steamed"]
    snacks = ["Whey Protein Powder", "Almonds", "Apple", "Protein Bar"]

    today = date.today()
    for offset in range(days, -1, -1):
        day = today - timedelta(days=offset)
        # Nutrition logging is the least consistent habit — model that.
        if RNG.random() < 0.3:
            continue
        for meal_type, names in (
            (MealType.BREAKFAST, breakfasts),
            (MealType.LUNCH, lunches),
            (MealType.DINNER, dinners),
            (MealType.SNACK, snacks),
        ):
            chosen = [by_name[n] for n in RNG.sample(names, k=min(3, len(names))) if n in by_name]
            if not chosen:
                continue
            meal = Meal(user_id=user.id, logged_on=day, meal_type=meal_type, position=0)
            db.add(meal)
            await db.flush()
            for position, food in enumerate(chosen):
                grams = round(food.default_serving_grams * RNG.uniform(0.8, 1.4), 1)
                factor = grams / 100
                db.add(
                    MealItem(
                        meal_id=meal.id,
                        food_id=food.id,
                        position=position,
                        food_name=food.name,
                        quantity=1,
                        grams=grams,
                        calories=round(food.calories_per_100g * factor, 1),
                        protein_g=round(food.protein_per_100g * factor, 1),
                        carbs_g=round(food.carbs_per_100g * factor, 1),
                        fat_g=round(food.fat_per_100g * factor, 1),
                        fiber_g=round(food.fiber_per_100g * factor, 1),
                    )
                )
            await db.flush()
            await db.refresh(meal, ["items"])
            meal.total_calories = round(sum(i.calories for i in meal.items), 1)
            meal.total_protein_g = round(sum(i.protein_g for i in meal.items), 1)
            meal.total_carbs_g = round(sum(i.carbs_g for i in meal.items), 1)
            meal.total_fat_g = round(sum(i.fat_g for i in meal.items), 1)
            meal.total_fiber_g = round(sum(i.fiber_g for i in meal.items), 1)

        for _ in range(RNG.randint(4, 8)):
            db.add(WaterLog(user_id=user.id, logged_on=day, amount_ml=250))

        await nutrition_service.recompute_day(db, user, day)

    await db.commit()


async def _seed_habits(db: AsyncSession, user: User, *, days: int) -> None:
    definitions = [
        ("Drink 2L of water", "water_drop", "#2E90FA", HabitFrequency.DAILY, 1, 0.85),
        ("10,000 steps", "directions_walk", "#12B76A", HabitFrequency.DAILY, 1, 0.7),
        ("Stretch for 10 minutes", "self_improvement", "#F79009", HabitFrequency.DAILY, 1, 0.55),
        ("Sleep 7+ hours", "bedtime", "#7A5AF8", HabitFrequency.DAILY, 1, 0.75),
    ]
    today = date.today()
    for position, (name, icon, color, frequency, target, rate) in enumerate(definitions):
        habit = Habit(
            user_id=user.id,
            name=name,
            icon=icon,
            color=color,
            frequency=frequency,
            target_count=target,
            position=position,
        )
        db.add(habit)
        await db.flush()

        streak = 0
        best = 0
        for offset in range(days, -1, -1):
            if RNG.random() > rate:
                streak = 0
                continue
            db.add(
                HabitLog(
                    habit_id=habit.id,
                    user_id=user.id,
                    logged_on=today - timedelta(days=offset),
                    count=target,
                    is_completed=True,
                )
            )
            streak += 1
            best = max(best, streak)
        habit.current_streak = streak
        habit.longest_streak = best
    await db.commit()


async def _seed_goals(db: AsyncSession, user: User) -> None:
    bench = await db.scalar(select(Exercise).where(Exercise.name == "Barbell Bench Press"))
    today = date.today()
    goals = [
        UserGoal(
            user_id=user.id,
            goal_type=GoalType.BODY_WEIGHT,
            title="Reach 78 kg",
            start_value=84.0,
            current_value=None,
            target_value=78.0,
            unit="kg",
            is_decreasing=True,
            start_date=today - timedelta(days=90),
            target_date=today + timedelta(days=60),
        ),
        UserGoal(
            user_id=user.id,
            goal_type=GoalType.WORKOUTS_PER_WEEK,
            title="Train 4 times a week",
            start_value=0,
            target_value=4,
            unit="workouts",
            start_date=today - timedelta(days=30),
        ),
        UserGoal(
            user_id=user.id,
            goal_type=GoalType.TOTAL_WORKOUTS,
            title="Complete 100 workouts",
            start_value=0,
            target_value=100,
            unit="workouts",
            start_date=today - timedelta(days=180),
            target_date=today + timedelta(days=185),
        ),
    ]
    if bench is not None:
        goals.append(
            UserGoal(
                user_id=user.id,
                goal_type=GoalType.EXERCISE_1RM,
                title="Bench press 100 kg",
                exercise_id=bench.id,
                start_value=epley_1rm(60, 8),
                target_value=100.0,
                unit="kg",
                start_date=today - timedelta(days=90),
                target_date=today + timedelta(days=120),
            )
        )
    for goal in goals:
        db.add(goal)
    await db.commit()

    from app.services import goal_service

    await goal_service.refresh_all(db, user)
    await db.commit()


async def seed_demo_data(db: AsyncSession, *, weeks: int = 12) -> dict[str, int]:
    """Create the demo and admin accounts with a realistic history."""
    await seed_reference_data(db)

    admin = await _create_user(
        db,
        email=ADMIN_EMAIL,
        password=ADMIN_PASSWORD,
        full_name="FitTrack Admin",
        role=UserRole.ADMIN,
    )
    if admin is not None:
        admin.profile = UserProfile(user_id=admin.id)
        await db.commit()

    user = await _create_user(db, email=DEMO_EMAIL, password=DEMO_PASSWORD, full_name="Sam Rivera")
    if user is None:
        logger.info("seed.demo_user_exists")
        return {"created": 0}

    targets = estimate_targets(
        weight_kg=84.0,
        height_cm=178.0,
        age_years=29,
        gender=Gender.UNDISCLOSED,
        activity_level=ActivityLevel.MODERATE,
        goal=FitnessGoal.LOSE_WEIGHT,
    )
    user.profile = UserProfile(
        user_id=user.id,
        date_of_birth=date(date.today().year - 29, 5, 14),
        gender=Gender.UNDISCLOSED,
        height_cm=178.0,
        current_weight_kg=84.0,
        target_weight_kg=78.0,
        primary_goal=FitnessGoal.LOSE_WEIGHT,
        fitness_level=FitnessLevel.INTERMEDIATE,
        activity_level=ActivityLevel.MODERATE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=[
            Equipment.BARBELL,
            Equipment.DUMBBELL,
            Equipment.CABLE,
            Equipment.MACHINE,
            Equipment.BODYWEIGHT,
        ],
        training_days_per_week=4,
        preferred_session_minutes=65,
        daily_calorie_target=targets["recommended_calories"],
        daily_protein_target_g=targets["recommended_protein_g"],
        daily_carbs_target_g=targets["recommended_carbs_g"],
        daily_fat_target_g=targets["recommended_fat_g"],
        daily_fiber_target_g=targets["recommended_fiber_g"],
        daily_water_target_ml=targets["recommended_water_ml"],
    )
    await db.commit()

    from app.services import program_service

    template = await db.scalar(
        select(WorkoutProgram).where(
            WorkoutProgram.is_template.is_(True), WorkoutProgram.name == "Upper / Lower"
        )
    )
    program = await program_service.duplicate(db, template.id, user, name="Upper / Lower — My Plan")
    await program_service.activate(db, program.id, user)
    program = await program_service.get_for_user(db, program.id, user)

    days = weeks * 7
    workouts = await _seed_workout_history(db, user, program, weeks=weeks)
    await _seed_body_history(db, user, days=days)
    await _seed_nutrition(db, user, days=min(days, 60))
    await _seed_habits(db, user, days=min(days, 60))
    await _seed_goals(db, user)

    summary = {"workouts": workouts, "weeks": weeks}
    logger.info("seed.demo_data", **summary)
    return summary
