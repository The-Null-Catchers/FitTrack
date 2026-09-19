"""Food catalogue, meal logging and daily nutrition rollups."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.errors import NotFoundError, PermissionError_, ValidationError
from app.models.nutrition import (
    DailyNutrition,
    FavoriteFood,
    Food,
    Meal,
    MealItem,
    WaterLog,
)
from app.models.user import User
from app.schemas.common import PaginationParams
from app.schemas.nutrition import (
    FoodCreate,
    FoodUpdate,
    MealCreate,
    MealItemWrite,
    MealUpdate,
    WaterLogWrite,
)


def _visible_foods(user: User) -> Any:
    return or_(Food.user_id.is_(None), Food.user_id == user.id)


async def search_foods(
    db: AsyncSession,
    user: User,
    *,
    pagination: PaginationParams,
    query: str | None = None,
    favorites_only: bool = False,
    custom_only: bool = False,
) -> tuple[list[Food], int, set[uuid.UUID]]:
    base = select(Food).where(Food.is_deleted.is_(False), _visible_foods(user))
    if query:
        needle = f"%{query.strip().lower()}%"
        base = base.where(
            or_(Food.search_text.like(needle), func.lower(Food.name).like(needle))
        )
    if custom_only:
        base = base.where(Food.user_id == user.id)
    if favorites_only:
        base = base.where(
            Food.id.in_(select(FavoriteFood.food_id).where(FavoriteFood.user_id == user.id))
        )

    total = int(await db.scalar(select(func.count()).select_from(base.subquery())) or 0)
    rows = list(
        await db.scalars(
            base.order_by(Food.is_verified.desc(), Food.name.asc())
            .offset(pagination.offset)
            .limit(pagination.per_page)
        )
    )
    favorites = await favorite_ids(db, user, [row.id for row in rows])
    return rows, total, favorites


async def favorite_ids(
    db: AsyncSession, user: User, food_ids: list[uuid.UUID] | None = None
) -> set[uuid.UUID]:
    stmt = select(FavoriteFood.food_id).where(FavoriteFood.user_id == user.id)
    if food_ids:
        stmt = stmt.where(FavoriteFood.food_id.in_(food_ids))
    return set(await db.scalars(stmt))


async def recent_foods(db: AsyncSession, user: User, *, limit: int = 20) -> list[Food]:
    """Distinct foods the user logged most recently."""
    rows = await db.execute(
        select(MealItem.food_id, func.max(MealItem.created_at).label("last_used"))
        .join(Meal, Meal.id == MealItem.meal_id)
        .where(
            Meal.user_id == user.id,
            MealItem.food_id.is_not(None),
            Meal.is_deleted.is_(False),
        )
        .group_by(MealItem.food_id)
        .order_by(func.max(MealItem.created_at).desc())
        .limit(limit)
    )
    ids = [row[0] for row in rows]
    if not ids:
        return []
    foods = {
        food.id: food
        for food in await db.scalars(select(Food).where(Food.id.in_(ids)))
    }
    return [foods[i] for i in ids if i in foods]


async def get_food(db: AsyncSession, user: User, food_id: uuid.UUID) -> Food:
    food = await db.scalar(
        select(Food).where(
            Food.id == food_id, Food.is_deleted.is_(False), _visible_foods(user)
        )
    )
    if food is None:
        raise NotFoundError("We couldn't find that food.")
    return food


async def find_by_barcode(db: AsyncSession, user: User, barcode: str) -> Food | None:
    return await db.scalar(
        select(Food).where(
            Food.barcode == barcode.strip(), Food.is_deleted.is_(False), _visible_foods(user)
        )
    )


async def create_food(db: AsyncSession, user: User, data: FoodCreate) -> Food:
    food = Food(
        user_id=user.id,
        **data.model_dump(exclude={"serving_options"}),
        serving_options=[option.model_dump() for option in data.serving_options],
    )
    food.search_text = food.build_search_text()
    db.add(food)
    await db.commit()
    await db.refresh(food)
    return food


async def update_food(
    db: AsyncSession, user: User, food_id: uuid.UUID, data: FoodUpdate
) -> Food:
    food = await get_food(db, user, food_id)
    if food.user_id != user.id and not user.is_admin:
        raise PermissionError_("You can only edit foods you created.")
    values = data.model_dump(exclude_unset=True)
    if "serving_options" in values and values["serving_options"] is not None:
        values["serving_options"] = [
            option if isinstance(option, dict) else option.model_dump()
            for option in values["serving_options"]
        ]
    for field, value in values.items():
        setattr(food, field, value)
    food.search_text = food.build_search_text()
    await db.commit()
    await db.refresh(food)
    return food


async def delete_food(db: AsyncSession, user: User, food_id: uuid.UUID) -> None:
    food = await get_food(db, user, food_id)
    if food.user_id != user.id and not user.is_admin:
        raise PermissionError_("You can only delete foods you created.")
    food.soft_delete()
    await db.commit()


async def toggle_favorite(db: AsyncSession, user: User, food_id: uuid.UUID) -> bool:
    await get_food(db, user, food_id)
    existing = await db.scalar(
        select(FavoriteFood).where(
            FavoriteFood.user_id == user.id, FavoriteFood.food_id == food_id
        )
    )
    if existing is not None:
        await db.delete(existing)
        await db.commit()
        return False
    db.add(FavoriteFood(user_id=user.id, food_id=food_id))
    await db.commit()
    return True


async def _build_items(
    db: AsyncSession, user: User, meal: Meal, items: list[MealItemWrite]
) -> None:
    """Materialise meal items, pricing catalogue foods server-side."""
    food_ids = [uuid.UUID(item.food_id) for item in items if item.food_id]
    foods: dict[uuid.UUID, Food] = {}
    if food_ids:
        rows = await db.scalars(
            select(Food).where(
                Food.id.in_(food_ids), Food.is_deleted.is_(False), _visible_foods(user)
            )
        )
        foods = {row.id: row for row in rows}
        missing = [str(i) for i in food_ids if i not in foods]
        if missing:
            raise ValidationError(
                "Some of those foods aren't available.", details={"food_ids": missing}
            )

    for position, item in enumerate(items):
        if item.food_id:
            food = foods[uuid.UUID(item.food_id)]
            grams = item.grams or (_serving_grams(food, item.serving_label) * item.quantity)
            factor = grams / 100.0
            db.add(
                MealItem(
                    meal_id=meal.id,
                    food_id=food.id,
                    position=position,
                    food_name=food.name,
                    serving_label=item.serving_label,
                    quantity=item.quantity,
                    grams=round(grams, 2),
                    calories=round(food.calories_per_100g * factor, 2),
                    protein_g=round(food.protein_per_100g * factor, 2),
                    carbs_g=round(food.carbs_per_100g * factor, 2),
                    fat_g=round(food.fat_per_100g * factor, 2),
                    fiber_g=round(food.fiber_per_100g * factor, 2),
                )
            )
        else:
            db.add(
                MealItem(
                    meal_id=meal.id,
                    position=position,
                    food_name=item.food_name or "Food",
                    serving_label=item.serving_label,
                    quantity=item.quantity,
                    grams=item.grams or 0,
                    calories=item.calories or 0,
                    protein_g=item.protein_g or 0,
                    carbs_g=item.carbs_g or 0,
                    fat_g=item.fat_g or 0,
                    fiber_g=item.fiber_g or 0,
                )
            )
    await db.flush()


def _serving_grams(food: Food, label: str | None) -> float:
    if label:
        for option in food.serving_options or []:
            if option.get("label") == label:
                return float(option["grams"])
    return float(food.default_serving_grams or 100)


def _rollup_meal(meal: Meal) -> None:
    meal.total_calories = round(sum(i.calories for i in meal.items), 2)
    meal.total_protein_g = round(sum(i.protein_g for i in meal.items), 2)
    meal.total_carbs_g = round(sum(i.carbs_g for i in meal.items), 2)
    meal.total_fat_g = round(sum(i.fat_g for i in meal.items), 2)
    meal.total_fiber_g = round(sum(i.fiber_g for i in meal.items), 2)


async def recompute_day(db: AsyncSession, user: User, on: date) -> DailyNutrition:
    """Refresh the per-day rollup so dashboards read one row, not every meal."""
    totals = (
        await db.execute(
            select(
                func.coalesce(func.sum(Meal.total_calories), 0),
                func.coalesce(func.sum(Meal.total_protein_g), 0),
                func.coalesce(func.sum(Meal.total_carbs_g), 0),
                func.coalesce(func.sum(Meal.total_fat_g), 0),
                func.coalesce(func.sum(Meal.total_fiber_g), 0),
            ).where(
                Meal.user_id == user.id,
                Meal.logged_on == on,
                Meal.is_deleted.is_(False),
                Meal.is_saved_template.is_(False),
            )
        )
    ).one()

    water = int(
        await db.scalar(
            select(func.coalesce(func.sum(WaterLog.amount_ml), 0)).where(
                WaterLog.user_id == user.id, WaterLog.logged_on == on
            )
        )
        or 0
    )

    row = await db.scalar(
        select(DailyNutrition).where(
            DailyNutrition.user_id == user.id, DailyNutrition.logged_on == on
        )
    )
    if row is None:
        row = DailyNutrition(user_id=user.id, logged_on=on)
        db.add(row)

    row.calories, row.protein_g, row.carbs_g, row.fat_g, row.fiber_g = (
        round(float(totals[0]), 2),
        round(float(totals[1]), 2),
        round(float(totals[2]), 2),
        round(float(totals[3]), 2),
        round(float(totals[4]), 2),
    )
    row.water_ml = max(0, water)
    if user.profile:
        row.calorie_target = user.profile.daily_calorie_target
        row.protein_target_g = user.profile.daily_protein_target_g
    await db.flush()
    return row


async def create_meal(db: AsyncSession, user: User, data: MealCreate) -> Meal:
    if data.client_uuid:
        existing = await db.scalar(
            select(Meal)
            .options(selectinload(Meal.items))
            .where(Meal.user_id == user.id, Meal.client_uuid == data.client_uuid)
        )
        if existing is not None:
            return existing

    position = int(
        await db.scalar(
            select(func.count())
            .select_from(Meal)
            .where(
                Meal.user_id == user.id,
                Meal.logged_on == data.logged_on,
                Meal.is_deleted.is_(False),
            )
        )
        or 0
    )

    meal = Meal(
        user_id=user.id,
        logged_on=data.logged_on,
        meal_type=data.meal_type,
        name=data.name,
        position=position,
        is_saved_template=data.save_as_template,
        client_uuid=data.client_uuid,
    )
    db.add(meal)
    await db.flush()
    await _build_items(db, user, meal, data.items)
    await db.refresh(meal, ["items"])
    _rollup_meal(meal)
    await recompute_day(db, user, data.logged_on)
    await db.commit()
    return await get_meal(db, user, meal.id)


async def get_meal(db: AsyncSession, user: User, meal_id: uuid.UUID) -> Meal:
    meal = await db.scalar(
        select(Meal)
        .options(selectinload(Meal.items))
        .where(Meal.id == meal_id)
        .execution_options(populate_existing=True)
    )
    if meal is None or meal.is_deleted:
        raise NotFoundError("We couldn't find that meal.")
    if meal.user_id != user.id:
        raise PermissionError_("That meal belongs to someone else.")
    return meal


async def update_meal(
    db: AsyncSession, user: User, meal_id: uuid.UUID, data: MealUpdate
) -> Meal:
    meal = await get_meal(db, user, meal_id)
    original_day = meal.logged_on

    values = data.model_dump(exclude_unset=True, exclude={"items"})
    for field, value in values.items():
        setattr(meal, field, value)

    if data.items is not None:
        for item in list(meal.items):
            await db.delete(item)
        await db.flush()
        await _build_items(db, user, meal, data.items)
        await db.refresh(meal, ["items"])

    _rollup_meal(meal)
    await recompute_day(db, user, meal.logged_on)
    if original_day != meal.logged_on:
        await recompute_day(db, user, original_day)
    await db.commit()
    return await get_meal(db, user, meal.id)


async def delete_meal(db: AsyncSession, user: User, meal_id: uuid.UUID) -> None:
    meal = await get_meal(db, user, meal_id)
    meal.soft_delete()
    await recompute_day(db, user, meal.logged_on)
    await db.commit()


async def list_meals(
    db: AsyncSession, user: User, *, on: date, include_templates: bool = False
) -> list[Meal]:
    stmt = (
        select(Meal)
        .options(selectinload(Meal.items))
        .where(Meal.user_id == user.id, Meal.is_deleted.is_(False))
    )
    if include_templates:
        stmt = stmt.where(Meal.is_saved_template.is_(True))
    else:
        stmt = stmt.where(Meal.logged_on == on, Meal.is_saved_template.is_(False))
    rows = await db.scalars(stmt.order_by(Meal.position, Meal.created_at))
    return list(rows)


async def log_water(db: AsyncSession, user: User, data: WaterLogWrite) -> int:
    if data.client_uuid:
        existing = await db.scalar(
            select(WaterLog).where(
                WaterLog.user_id == user.id, WaterLog.client_uuid == data.client_uuid
            )
        )
        if existing is not None:
            day = await recompute_day(db, user, data.logged_on)
            await db.commit()
            return day.water_ml

    db.add(
        WaterLog(
            user_id=user.id,
            logged_on=data.logged_on,
            amount_ml=data.amount_ml,
            client_uuid=data.client_uuid,
        )
    )
    await db.flush()
    day = await recompute_day(db, user, data.logged_on)
    await db.commit()
    return day.water_ml


async def get_day(db: AsyncSession, user: User, on: date) -> dict[str, Any]:
    meals = await list_meals(db, user, on=on)
    row = await recompute_day(db, user, on)
    await db.commit()

    profile = user.profile
    targets = {
        "calories": profile.daily_calorie_target if profile else None,
        "protein_g": profile.daily_protein_target_g if profile else None,
        "carbs_g": profile.daily_carbs_target_g if profile else None,
        "fat_g": profile.daily_fat_target_g if profile else None,
        "fiber_g": profile.daily_fiber_target_g if profile else None,
        "water_ml": profile.daily_water_target_ml if profile else None,
    }
    consumed = {
        "calories": row.calories,
        "protein_g": row.protein_g,
        "carbs_g": row.carbs_g,
        "fat_g": row.fat_g,
        "fiber_g": row.fiber_g,
        "water_ml": float(row.water_ml),
    }

    return {
        "logged_on": on,
        **{key: macro_progress(consumed[key], targets[key]) for key in consumed},
        "meals": [serialize_meal(meal) for meal in meals],
    }


def macro_progress(consumed: float, target: float | None) -> dict[str, Any]:
    if not target:
        return {"consumed": round(consumed, 1), "target": None, "remaining": None,
                "percent": None}
    return {
        "consumed": round(consumed, 1),
        "target": float(target),
        "remaining": round(target - consumed, 1),
        "percent": round(min(consumed / target * 100, 999), 1),
    }


def serialize_meal(meal: Meal) -> dict[str, Any]:
    return {
        "id": str(meal.id),
        "logged_on": meal.logged_on,
        "meal_type": meal.meal_type,
        "name": meal.name,
        "position": meal.position,
        "is_saved_template": meal.is_saved_template,
        "total_calories": meal.total_calories,
        "total_protein_g": meal.total_protein_g,
        "total_carbs_g": meal.total_carbs_g,
        "total_fat_g": meal.total_fat_g,
        "total_fiber_g": meal.total_fiber_g,
        "created_at": meal.created_at,
        "items": [
            {
                "id": str(item.id),
                "food_id": str(item.food_id) if item.food_id else None,
                "food_name": item.food_name,
                "serving_label": item.serving_label,
                "quantity": item.quantity,
                "grams": item.grams,
                "calories": item.calories,
                "protein_g": item.protein_g,
                "carbs_g": item.carbs_g,
                "fat_g": item.fat_g,
                "fiber_g": item.fiber_g,
                "position": item.position,
            }
            for item in sorted(meal.items, key=lambda i: i.position)
        ],
    }


def serialize_food(food: Food, *, is_favorite: bool = False) -> dict[str, Any]:
    return {
        "id": str(food.id),
        "name": food.name,
        "name_ar": food.name_ar,
        "brand": food.brand,
        "barcode": food.barcode,
        "calories_per_100g": food.calories_per_100g,
        "protein_per_100g": food.protein_per_100g,
        "carbs_per_100g": food.carbs_per_100g,
        "fat_per_100g": food.fat_per_100g,
        "fiber_per_100g": food.fiber_per_100g,
        "sugar_per_100g": food.sugar_per_100g,
        "sodium_mg_per_100g": food.sodium_mg_per_100g,
        "serving_options": food.serving_options or [],
        "default_serving_grams": food.default_serving_grams,
        "is_custom": food.user_id is not None,
        "is_verified": food.is_verified,
        "is_favorite": is_favorite,
    }


async def range_summary(
    db: AsyncSession, user: User, *, start: date, end: date
) -> list[DailyNutrition]:
    rows = await db.scalars(
        select(DailyNutrition)
        .where(
            DailyNutrition.user_id == user.id,
            DailyNutrition.logged_on >= start,
            DailyNutrition.logged_on <= end,
        )
        .order_by(DailyNutrition.logged_on)
    )
    return list(rows)
