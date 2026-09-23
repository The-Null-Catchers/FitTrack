"""Nutrition schemas."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import Field, model_validator

from app.models.enums import MealType
from app.schemas.common import APIModel


class ServingOption(APIModel):
    label: str = Field(..., max_length=80)
    grams: float = Field(..., gt=0, le=5000)


class FoodRead(APIModel):
    id: str
    name: str
    name_ar: str | None = None
    brand: str | None = None
    barcode: str | None = None
    calories_per_100g: float
    protein_per_100g: float
    carbs_per_100g: float
    fat_per_100g: float
    fiber_per_100g: float
    sugar_per_100g: float | None = None
    sodium_mg_per_100g: float | None = None
    serving_options: list[ServingOption] = Field(default_factory=list)
    default_serving_grams: float = 100.0
    is_custom: bool = False
    is_verified: bool = False
    is_favorite: bool = False


class FoodCreate(APIModel):
    name: str = Field(..., min_length=1, max_length=180)
    name_ar: str | None = Field(None, max_length=180)
    brand: str | None = Field(None, max_length=120)
    barcode: str | None = Field(None, max_length=64)
    calories_per_100g: float = Field(..., ge=0, le=900)
    protein_per_100g: float = Field(0, ge=0, le=100)
    carbs_per_100g: float = Field(0, ge=0, le=100)
    fat_per_100g: float = Field(0, ge=0, le=100)
    fiber_per_100g: float = Field(0, ge=0, le=100)
    sugar_per_100g: float | None = Field(None, ge=0, le=100)
    sodium_mg_per_100g: float | None = Field(None, ge=0, le=100000)
    serving_options: list[ServingOption] = Field(default_factory=list)
    default_serving_grams: float = Field(100.0, gt=0, le=5000)


class FoodUpdate(APIModel):
    name: str | None = Field(None, min_length=1, max_length=180)
    brand: str | None = Field(None, max_length=120)
    calories_per_100g: float | None = Field(None, ge=0, le=900)
    protein_per_100g: float | None = Field(None, ge=0, le=100)
    carbs_per_100g: float | None = Field(None, ge=0, le=100)
    fat_per_100g: float | None = Field(None, ge=0, le=100)
    fiber_per_100g: float | None = Field(None, ge=0, le=100)
    serving_options: list[ServingOption] | None = None
    default_serving_grams: float | None = Field(None, gt=0, le=5000)


class MealItemWrite(APIModel):
    food_id: str | None = None
    #: Free-text entry for foods that aren't in the catalogue.
    food_name: str | None = Field(None, min_length=1, max_length=180)
    serving_label: str | None = Field(None, max_length=80)
    quantity: float = Field(1.0, gt=0, le=100)
    grams: float | None = Field(None, gt=0, le=10000)
    # Supplied only for ad-hoc entries; catalogue foods are priced server-side.
    calories: float | None = Field(None, ge=0, le=10000)
    protein_g: float | None = Field(None, ge=0, le=1000)
    carbs_g: float | None = Field(None, ge=0, le=1000)
    fat_g: float | None = Field(None, ge=0, le=1000)
    fiber_g: float | None = Field(None, ge=0, le=1000)

    @model_validator(mode="after")
    def _needs_food_or_name(self) -> MealItemWrite:
        if not self.food_id and not self.food_name:
            raise ValueError("Provide either a food from the catalogue or a food name.")
        if not self.food_id and self.calories is None:
            raise ValueError("Custom entries need at least a calorie value.")
        return self


class MealItemRead(APIModel):
    id: str
    food_id: str | None
    food_name: str
    serving_label: str | None
    quantity: float
    grams: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    position: int


class MealCreate(APIModel):
    logged_on: date
    meal_type: MealType = MealType.SNACK
    name: str | None = Field(None, max_length=120)
    items: list[MealItemWrite] = Field(default_factory=list)
    client_uuid: str | None = Field(None, max_length=64)
    save_as_template: bool = False


class MealUpdate(APIModel):
    meal_type: MealType | None = None
    name: str | None = Field(None, max_length=120)
    logged_on: date | None = None
    items: list[MealItemWrite] | None = None


class MealRead(APIModel):
    id: str
    logged_on: date
    meal_type: MealType
    name: str | None
    position: int
    is_saved_template: bool
    total_calories: float
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    total_fiber_g: float
    items: list[MealItemRead] = Field(default_factory=list)
    created_at: datetime


class WaterLogWrite(APIModel):
    logged_on: date
    amount_ml: int = Field(..., ge=-5000, le=5000)
    client_uuid: str | None = Field(None, max_length=64)


class MacroProgress(APIModel):
    consumed: float
    target: float | None
    remaining: float | None
    percent: float | None


class NutritionDayRead(APIModel):
    logged_on: date
    calories: MacroProgress
    protein_g: MacroProgress
    carbs_g: MacroProgress
    fat_g: MacroProgress
    fiber_g: MacroProgress
    water_ml: MacroProgress
    meals: list[MealRead] = Field(default_factory=list)


class NutritionDaySummary(APIModel):
    logged_on: date
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    water_ml: int
    calorie_target: int | None = None
