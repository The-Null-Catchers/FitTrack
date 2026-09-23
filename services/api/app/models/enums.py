"""Domain enumerations.

These are stored as short strings rather than native DB enums so that adding a
value never requires a migration lock on a large table.
"""

from __future__ import annotations

from enum import StrEnum


class UserRole(StrEnum):
    USER = "user"
    ADMIN = "admin"
    SUPPORT = "support"


class UserStatus(StrEnum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    PENDING_DELETION = "pending_deletion"


class UnitSystem(StrEnum):
    METRIC = "metric"
    IMPERIAL = "imperial"


class Gender(StrEnum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"
    UNDISCLOSED = "undisclosed"


class FitnessGoal(StrEnum):
    LOSE_WEIGHT = "lose_weight"
    GAIN_MUSCLE = "gain_muscle"
    IMPROVE_STRENGTH = "improve_strength"
    IMPROVE_ENDURANCE = "improve_endurance"
    GENERAL_FITNESS = "general_fitness"
    MAINTAIN_WEIGHT = "maintain_weight"


class FitnessLevel(StrEnum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class WorkoutLocation(StrEnum):
    GYM = "gym"
    HOME = "home"
    OUTDOOR = "outdoor"
    MIXED = "mixed"


class ActivityLevel(StrEnum):
    SEDENTARY = "sedentary"
    LIGHT = "light"
    MODERATE = "moderate"
    ACTIVE = "active"
    VERY_ACTIVE = "very_active"


class MuscleGroup(StrEnum):
    CHEST = "chest"
    BACK = "back"
    SHOULDERS = "shoulders"
    ARMS = "arms"
    LEGS = "legs"
    CORE = "core"
    CARDIO = "cardio"
    MOBILITY = "mobility"
    FULL_BODY = "full_body"


class Equipment(StrEnum):
    BARBELL = "barbell"
    DUMBBELL = "dumbbell"
    CABLE = "cable"
    MACHINE = "machine"
    BODYWEIGHT = "bodyweight"
    RESISTANCE_BAND = "resistance_band"
    KETTLEBELL = "kettlebell"
    CARDIO_MACHINE = "cardio_machine"
    OTHER = "other"


class Difficulty(StrEnum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class ExerciseType(StrEnum):
    STRENGTH = "strength"
    CARDIO = "cardio"
    MOBILITY = "mobility"
    PLYOMETRIC = "plyometric"
    OLYMPIC = "olympic"
    STRETCH = "stretch"


class TrackingType(StrEnum):
    """How a set is recorded for a given exercise."""

    WEIGHT_REPS = "weight_reps"
    REPS_ONLY = "reps_only"
    DURATION = "duration"
    DISTANCE = "distance"
    CALORIES = "calories"
    ASSISTED_WEIGHT = "assisted_weight"


class ProgramStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    ARCHIVED = "archived"


class SessionStatus(StrEnum):
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    ABANDONED = "abandoned"


class SetType(StrEnum):
    NORMAL = "normal"
    WARMUP = "warmup"
    DROP = "drop"
    FAILURE = "failure"
    BACKOFF = "backoff"


class PersonalRecordType(StrEnum):
    MAX_WEIGHT = "max_weight"
    ESTIMATED_1RM = "estimated_1rm"
    MAX_REPS = "max_reps"
    MAX_VOLUME = "max_volume"
    MAX_DISTANCE = "max_distance"
    BEST_TIME = "best_time"


class MeasurementType(StrEnum):
    WAIST = "waist"
    CHEST = "chest"
    LEFT_ARM = "left_arm"
    RIGHT_ARM = "right_arm"
    LEFT_THIGH = "left_thigh"
    RIGHT_THIGH = "right_thigh"
    HIPS = "hips"
    NECK = "neck"
    SHOULDERS = "shoulders"
    CALF = "calf"
    FOREARM = "forearm"
    CUSTOM = "custom"


class PhotoPose(StrEnum):
    FRONT = "front"
    SIDE = "side"
    BACK = "back"


class MealType(StrEnum):
    BREAKFAST = "breakfast"
    LUNCH = "lunch"
    DINNER = "dinner"
    SNACK = "snack"
    CUSTOM = "custom"


class HabitFrequency(StrEnum):
    DAILY = "daily"
    WEEKLY = "weekly"


class GoalType(StrEnum):
    BODY_WEIGHT = "body_weight"
    EXERCISE_1RM = "exercise_1rm"
    WORKOUTS_PER_WEEK = "workouts_per_week"
    TOTAL_WORKOUTS = "total_workouts"
    DISTANCE = "distance"
    NUTRITION_ADHERENCE = "nutrition_adherence"
    BODY_MEASUREMENT = "body_measurement"
    CUSTOM = "custom"


class GoalStatus(StrEnum):
    ACTIVE = "active"
    ACHIEVED = "achieved"
    MISSED = "missed"
    ABANDONED = "abandoned"


class NotificationType(StrEnum):
    WORKOUT_REMINDER = "workout_reminder"
    GOAL_REMINDER = "goal_reminder"
    HABIT_REMINDER = "habit_reminder"
    PROGRESS_REMINDER = "progress_reminder"
    WEEKLY_SUMMARY = "weekly_summary"
    PERSONAL_RECORD = "personal_record"
    SYSTEM = "system"


class NotificationChannel(StrEnum):
    PUSH = "push"
    EMAIL = "email"
    IN_APP = "in_app"


class AIGenerationKind(StrEnum):
    CHAT = "chat"
    WORKOUT_PLAN = "workout_plan"
    PROGRESS_SUMMARY = "progress_summary"
    EXERCISE_SUBSTITUTION = "exercise_substitution"


class AIGenerationStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class MediaKind(StrEnum):
    IMAGE = "image"
    VIDEO = "video"
    ILLUSTRATION = "illustration"


class SubscriptionTier(StrEnum):
    FREE = "free"
    PRO = "pro"
    LIFETIME = "lifetime"
