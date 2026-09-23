"""SQLAlchemy models.

Importing this package registers every mapper, which Alembic autogenerate and
``Base.metadata.create_all`` both rely on.
"""

from app.db.base import Base
from app.models.ai import (
    AIConversation,
    AIGeneration,
    AIMessage,
    Subscription,
    UsageRecord,
)
from app.models.body import BodyMeasurement, BodyWeight, ProgressPhoto
from app.models.exercise import Exercise, ExerciseMedia
from app.models.goal import UserGoal
from app.models.habit import Habit, HabitLog
from app.models.notification import Notification, NotificationPreference
from app.models.nutrition import (
    DailyNutrition,
    FavoriteFood,
    Food,
    Meal,
    MealItem,
    WaterLog,
)
from app.models.program import WorkoutDay, WorkoutDayExercise, WorkoutProgram
from app.models.sync import SyncOperation
from app.models.user import AuditLog, User, UserProfile, UserSession, VerificationToken
from app.models.workout import (
    PersonalRecord,
    WorkoutSession,
    WorkoutSessionExercise,
    WorkoutSet,
)

__all__ = [
    "AIConversation",
    "AIGeneration",
    "AIMessage",
    "AuditLog",
    "Base",
    "BodyMeasurement",
    "BodyWeight",
    "DailyNutrition",
    "Exercise",
    "ExerciseMedia",
    "FavoriteFood",
    "Food",
    "Habit",
    "HabitLog",
    "Meal",
    "MealItem",
    "Notification",
    "NotificationPreference",
    "PersonalRecord",
    "ProgressPhoto",
    "Subscription",
    "SyncOperation",
    "UsageRecord",
    "User",
    "UserGoal",
    "UserProfile",
    "UserSession",
    "VerificationToken",
    "WaterLog",
    "WorkoutDay",
    "WorkoutDayExercise",
    "WorkoutProgram",
    "WorkoutSession",
    "WorkoutSessionExercise",
    "WorkoutSet",
]
