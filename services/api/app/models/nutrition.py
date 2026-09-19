"""Foods, meals, daily nutrition rollups and water logs."""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import (
    Boolean,
    Date,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import MealType


class Food(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    """A food item. Nutrients are always stored *per 100 g/ml*.

    ``user_id IS NULL`` means a shared catalogue entry; a value means the row is
    a custom food private to that user.
    """

    __tablename__ = "foods"

    user_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), default=None, index=True
    )
    name: Mapped[str] = mapped_column(String(180), nullable=False, index=True)
    name_ar: Mapped[str | None] = mapped_column(String(180), default=None)
    brand: Mapped[str | None] = mapped_column(String(120), default=None)
    barcode: Mapped[str | None] = mapped_column(String(64), default=None, index=True)

    calories_per_100g: Mapped[float] = mapped_column(Float, nullable=False)
    protein_per_100g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    carbs_per_100g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fat_per_100g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fiber_per_100g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    sugar_per_100g: Mapped[float | None] = mapped_column(Float, default=None)
    sodium_mg_per_100g: Mapped[float | None] = mapped_column(Float, default=None)

    #: e.g. [{"label": "1 medium (118 g)", "grams": 118}]
    serving_options: Mapped[list[dict]] = mapped_column(JSONDict, default=list, nullable=False)
    default_serving_grams: Mapped[float] = mapped_column(Float, default=100.0, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    search_text: Mapped[str] = mapped_column(String(400), default="", nullable=False)

    __table_args__ = (
        Index("ix_foods_search", "search_text"),
        Index("ix_foods_user_name", "user_id", "name"),
    )

    def build_search_text(self) -> str:
        parts = [self.name, self.brand or "", self.name_ar or ""]
        return " ".join(p for p in parts if p).lower()


class FavoriteFood(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "favorite_foods"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    food_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("foods.id", ondelete="CASCADE"), nullable=False
    )

    __table_args__ = (UniqueConstraint("user_id", "food_id", name="uq_favorite_foods"),)


class Meal(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "meals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logged_on: Mapped[date] = mapped_column(Date, nullable=False)
    meal_type: Mapped[str] = mapped_column(String(16), default=MealType.SNACK, nullable=False)
    name: Mapped[str | None] = mapped_column(String(120), default=None)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    #: A saved meal is a reusable template rather than a day's entry.
    is_saved_template: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    # Rollups maintained whenever items change.
    total_calories: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    total_protein_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    total_carbs_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    total_fat_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    total_fiber_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    items: Mapped[list[MealItem]] = relationship(
        back_populates="meal",
        cascade="all, delete-orphan",
        order_by="MealItem.position",
        lazy="selectin",
    )

    __table_args__ = (
        UniqueConstraint("user_id", "client_uuid", name="uq_meals_user_client_uuid"),
        Index("ix_meals_user_date", "user_id", "logged_on"),
    )


class MealItem(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """A portion of a food inside a meal, with nutrients frozen at log time."""

    __tablename__ = "meal_items"

    meal_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("meals.id", ondelete="CASCADE"), nullable=False, index=True
    )
    food_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("foods.id", ondelete="SET NULL"), default=None
    )
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    food_name: Mapped[str] = mapped_column(String(180), nullable=False)
    serving_label: Mapped[str | None] = mapped_column(String(80), default=None)
    quantity: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    grams: Mapped[float] = mapped_column(Float, nullable=False)

    calories: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    protein_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    carbs_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fat_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fiber_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    meal: Mapped[Meal] = relationship(back_populates="items")


class DailyNutrition(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Per-day nutrition rollup, recomputed whenever a meal changes."""

    __tablename__ = "daily_nutrition"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logged_on: Mapped[date] = mapped_column(Date, nullable=False)

    calories: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    protein_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    carbs_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fat_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fiber_g: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    water_ml: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    calorie_target: Mapped[int | None] = mapped_column(Integer, default=None)
    protein_target_g: Mapped[int | None] = mapped_column(Integer, default=None)

    __table_args__ = (
        UniqueConstraint("user_id", "logged_on", name="uq_daily_nutrition_user_day"),
    )


class WaterLog(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "water_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    logged_on: Mapped[date] = mapped_column(Date, nullable=False)
    amount_ml: Mapped[int] = mapped_column(Integer, nullable=False)
    client_uuid: Mapped[str | None] = mapped_column(String(64), default=None)

    __table_args__ = (
        UniqueConstraint("user_id", "client_uuid", name="uq_water_logs_user_client_uuid"),
        Index("ix_water_logs_user_date", "user_id", "logged_on"),
    )
