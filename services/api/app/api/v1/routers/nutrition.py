"""Nutrition endpoints: foods, meals, water and daily totals."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Response, status

from app.core.deps import CurrentUser, DbSession, Pagination
from app.schemas.common import Page
from app.schemas.nutrition import (
    FoodCreate,
    FoodRead,
    FoodUpdate,
    MealCreate,
    MealRead,
    MealUpdate,
    NutritionDayRead,
    NutritionDaySummary,
    WaterLogWrite,
)
from app.services import nutrition_service

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.get("/day", response_model=NutritionDayRead, summary="A day's nutrition")
async def get_day(db: DbSession, user: CurrentUser, on: date | None = None) -> NutritionDayRead:
    return NutritionDayRead(**await nutrition_service.get_day(db, user, on or date.today()))


@router.get("/range", response_model=list[NutritionDaySummary], summary="Daily totals over a range")
async def get_range(
    db: DbSession, user: CurrentUser, start_date: date, end_date: date
) -> list[NutritionDaySummary]:
    rows = await nutrition_service.range_summary(db, user, start=start_date, end=end_date)
    return [
        NutritionDaySummary(
            logged_on=row.logged_on,
            calories=row.calories,
            protein_g=row.protein_g,
            carbs_g=row.carbs_g,
            fat_g=row.fat_g,
            fiber_g=row.fiber_g,
            water_ml=row.water_ml,
            calorie_target=row.calorie_target,
        )
        for row in rows
    ]


# --- foods -------------------------------------------------------------


@router.get("/foods", response_model=Page[FoodRead], summary="Search foods")
async def search_foods(
    db: DbSession,
    user: CurrentUser,
    pagination: Pagination,
    q: Annotated[str | None, Query(max_length=120)] = None,
    favorites_only: bool = False,
    custom_only: bool = False,
) -> Page[FoodRead]:
    rows, total, favorites = await nutrition_service.search_foods(
        db,
        user,
        pagination=pagination,
        query=q,
        favorites_only=favorites_only,
        custom_only=custom_only,
    )
    return Page.build(
        [
            FoodRead(**nutrition_service.serialize_food(row, is_favorite=row.id in favorites))
            for row in rows
        ],
        total=total,
        page=pagination.page,
        per_page=pagination.per_page,
    )


@router.get("/foods/recent", response_model=list[FoodRead], summary="Recently logged foods")
async def recent_foods(db: DbSession, user: CurrentUser) -> list[FoodRead]:
    rows = await nutrition_service.recent_foods(db, user)
    favorites = await nutrition_service.favorite_ids(db, user, [r.id for r in rows])
    return [
        FoodRead(**nutrition_service.serialize_food(row, is_favorite=row.id in favorites))
        for row in rows
    ]


@router.get("/foods/barcode/{barcode}", response_model=FoodRead | None, summary="Barcode lookup")
async def barcode_lookup(barcode: str, db: DbSession, user: CurrentUser) -> FoodRead | None:
    food = await nutrition_service.find_by_barcode(db, user, barcode)
    return FoodRead(**nutrition_service.serialize_food(food)) if food else None


@router.post(
    "/foods",
    response_model=FoodRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a custom food",
)
async def create_food(payload: FoodCreate, db: DbSession, user: CurrentUser) -> FoodRead:
    food = await nutrition_service.create_food(db, user, payload)
    return FoodRead(**nutrition_service.serialize_food(food))


@router.patch("/foods/{food_id}", response_model=FoodRead, summary="Edit a custom food")
async def update_food(
    food_id: uuid.UUID, payload: FoodUpdate, db: DbSession, user: CurrentUser
) -> FoodRead:
    food = await nutrition_service.update_food(db, user, food_id, payload)
    return FoodRead(**nutrition_service.serialize_food(food))


@router.delete(
    "/foods/{food_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a custom food",
)
async def delete_food(food_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await nutrition_service.delete_food(db, user, food_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/foods/{food_id}/favorite", summary="Toggle a food favourite")
async def toggle_favorite(food_id: uuid.UUID, db: DbSession, user: CurrentUser) -> dict[str, bool]:
    return {"is_favorite": await nutrition_service.toggle_favorite(db, user, food_id)}


# --- meals -------------------------------------------------------------


@router.get("/meals", response_model=list[MealRead], summary="Meals for a day")
async def list_meals(
    db: DbSession,
    user: CurrentUser,
    on: date | None = None,
    templates: bool = False,
) -> list[MealRead]:
    rows = await nutrition_service.list_meals(
        db, user, on=on or date.today(), include_templates=templates
    )
    return [MealRead(**nutrition_service.serialize_meal(row)) for row in rows]


@router.post(
    "/meals",
    response_model=MealRead,
    status_code=status.HTTP_201_CREATED,
    summary="Log a meal",
)
async def create_meal(payload: MealCreate, db: DbSession, user: CurrentUser) -> MealRead:
    meal = await nutrition_service.create_meal(db, user, payload)
    return MealRead(**nutrition_service.serialize_meal(meal))


@router.get("/meals/{meal_id}", response_model=MealRead, summary="Meal detail")
async def get_meal(meal_id: uuid.UUID, db: DbSession, user: CurrentUser) -> MealRead:
    meal = await nutrition_service.get_meal(db, user, meal_id)
    return MealRead(**nutrition_service.serialize_meal(meal))


@router.patch("/meals/{meal_id}", response_model=MealRead, summary="Edit a meal")
async def update_meal(
    meal_id: uuid.UUID, payload: MealUpdate, db: DbSession, user: CurrentUser
) -> MealRead:
    meal = await nutrition_service.update_meal(db, user, meal_id, payload)
    return MealRead(**nutrition_service.serialize_meal(meal))


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a meal")
async def delete_meal(meal_id: uuid.UUID, db: DbSession, user: CurrentUser) -> Response:
    await nutrition_service.delete_meal(db, user, meal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- water -------------------------------------------------------------


@router.post("/water", summary="Log water")
async def log_water(payload: WaterLogWrite, db: DbSession, user: CurrentUser) -> dict[str, int]:
    total = await nutrition_service.log_water(db, user, payload)
    return {"water_ml": total}
