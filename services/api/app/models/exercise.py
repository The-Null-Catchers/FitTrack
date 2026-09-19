"""Exercise library."""

from __future__ import annotations

import uuid

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import Difficulty, ExerciseType, MediaKind, MuscleGroup, TrackingType


class Exercise(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "exercises"

    slug: Mapped[str] = mapped_column(String(160), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(160), nullable=False, index=True)
    name_ar: Mapped[str | None] = mapped_column(String(160), default=None)
    description: Mapped[str | None] = mapped_column(Text, default=None)
    instructions: Mapped[list[str]] = mapped_column(JSONDict, default=list, nullable=False)

    muscle_group: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    secondary_muscles: Mapped[list[str]] = mapped_column(JSONDict, default=list, nullable=False)
    equipment: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    difficulty: Mapped[str] = mapped_column(String(16), default=Difficulty.BEGINNER, nullable=False)
    exercise_type: Mapped[str] = mapped_column(
        String(16), default=ExerciseType.STRENGTH, nullable=False
    )
    default_tracking_type: Mapped[str] = mapped_column(
        String(24), default=TrackingType.WEIGHT_REPS, nullable=False
    )
    default_rest_seconds: Mapped[int] = mapped_column(Integer, default=90, nullable=False)
    is_unilateral: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    video_url: Mapped[str | None] = mapped_column(String(512), default=None)
    image_key: Mapped[str | None] = mapped_column(String(512), default=None)

    # Public library entries are visible to everyone; user-created ones are private.
    is_public: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="SET NULL"), default=None, index=True
    )

    # Lower-cased "name + aliases + muscle + equipment" haystack for fast search.
    search_text: Mapped[str] = mapped_column(String(512), default="", nullable=False)
    aliases: Mapped[list[str]] = mapped_column(JSONDict, default=list, nullable=False)
    popularity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    media: Mapped[list[ExerciseMedia]] = relationship(
        back_populates="exercise", cascade="all, delete-orphan", lazy="selectin"
    )

    __table_args__ = (
        Index("ix_exercises_search", "search_text"),
        Index("ix_exercises_group_equipment", "muscle_group", "equipment"),
    )

    def build_search_text(self) -> str:
        parts = [self.name, *(self.aliases or []), self.muscle_group, self.equipment]
        parts.extend(self.secondary_muscles or [])
        if self.name_ar:
            parts.append(self.name_ar)
        return " ".join(str(p) for p in parts if p).lower()


class ExerciseMedia(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "exercise_media"

    exercise_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[str] = mapped_column(String(16), default=MediaKind.IMAGE, nullable=False)
    storage_key: Mapped[str | None] = mapped_column(String(512), default=None)
    external_url: Mapped[str | None] = mapped_column(String(512), default=None)
    caption: Mapped[str | None] = mapped_column(String(255), default=None)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    exercise: Mapped[Exercise] = relationship(back_populates="media")


# Re-exported for readability at call sites.
MUSCLE_GROUPS = [m.value for m in MuscleGroup]
