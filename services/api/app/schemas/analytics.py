"""Dashboard and analytics schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.schemas.common import APIModel
from app.schemas.goal import GoalRead
from app.schemas.workout import PersonalRecordRead


class SeriesPoint(APIModel):
    x: date
    y: float


class Series(APIModel):
    key: str
    label: str
    unit: str | None = None
    points: list[SeriesPoint] = Field(default_factory=list)
    #: Optional smoothed line drawn alongside noisy daily data.
    trend: list[SeriesPoint] = Field(default_factory=list)


class ChartResponse(APIModel):
    range: str
    start_date: date
    end_date: date
    series: list[Series] = Field(default_factory=list)
    summary: str | None = None
    change_percent: float | None = None
    change_absolute: float | None = None


class TodayWorkout(APIModel):
    program_id: str
    program_name: str
    day_id: str
    day_name: str
    exercise_count: int
    estimated_minutes: int | None = None
    is_rest_day: bool = False


class ActiveSessionRef(APIModel):
    id: str
    name: str
    started_at: datetime
    completed_set_count: int
    total_set_count: int


class MacroRing(APIModel):
    consumed: float
    target: float | None
    percent: float | None


class WeeklyProgress(APIModel):
    completed: int
    target: int
    percent: float
    #: Monday-first booleans for the current week.
    days: list[bool] = Field(default_factory=list)


class DashboardResponse(APIModel):
    greeting_name: str
    date: date
    today_workout: TodayWorkout | None = None
    active_session: ActiveSessionRef | None = None
    calories: MacroRing
    protein_g: MacroRing
    water_ml: MacroRing
    current_streak_days: int
    longest_streak_days: int
    weekly_workouts: WeeklyProgress
    weight_trend: Series | None = None
    latest_weight_kg: float | None = None
    weight_change_30d_kg: float | None = None
    recent_records: list[PersonalRecordRead] = Field(default_factory=list)
    active_goals: list[GoalRead] = Field(default_factory=list)
    habits_completed_today: int = 0
    habits_total_today: int = 0
    unread_notifications: int = 0


class ExerciseProgressPoint(APIModel):
    performed_on: date
    best_weight_kg: float | None
    best_reps: int | None
    estimated_1rm_kg: float | None
    total_volume_kg: float
    total_sets: int


class ExerciseProgressResponse(APIModel):
    exercise_id: str
    exercise_name: str
    range: str
    points: list[ExerciseProgressPoint] = Field(default_factory=list)
    best_1rm_kg: float | None = None
    change_percent: float | None = None
    summary: str | None = None


class VolumeByMuscleGroup(APIModel):
    muscle_group: str
    volume_kg: float
    set_count: int
    percent: float


class TrainingOverview(APIModel):
    range: str
    total_workouts: int
    total_duration_minutes: int
    total_volume_kg: float
    total_sets: int
    average_session_minutes: float
    workouts_per_week: float
    volume_by_muscle_group: list[VolumeByMuscleGroup] = Field(default_factory=list)
    personal_records: int = 0
    summary: str | None = None
