"""Version 1 API router."""

from fastapi import APIRouter

from app.api.v1.routers import (
    admin,
    ai,
    auth,
    exercises,
    goals,
    habits,
    notifications,
    nutrition,
    profile,
    programs,
    progress,
    sync,
    workouts,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(profile.router)
api_router.include_router(exercises.router)
api_router.include_router(programs.router)
api_router.include_router(workouts.router)
api_router.include_router(workouts.records_router)
api_router.include_router(progress.router)
api_router.include_router(nutrition.router)
api_router.include_router(habits.router)
api_router.include_router(goals.router)
api_router.include_router(ai.router)
api_router.include_router(notifications.router)
api_router.include_router(sync.router)
api_router.include_router(admin.router)

__all__ = ["api_router"]
