"""FitCoach conversations, messages and generation records."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict
from app.models.enums import AIGenerationKind, AIGenerationStatus


class AIConversation(Base, UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "ai_conversations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(160), default="New conversation", nullable=False)
    last_message_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None, index=True
    )

    messages: Mapped[list[AIMessage]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="AIMessage.created_at",
        lazy="selectin",
    )


class AIMessage(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "ai_messages"

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("ai_conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    #: Structured payload attached to an assistant turn (e.g. a generated plan).
    payload: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    #: True when the safety layer redirected the user to a professional.
    safety_redirect: Mapped[bool] = mapped_column(default=False, nullable=False)

    conversation: Mapped[AIConversation] = relationship(back_populates="messages")


class AIGeneration(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """One AI job: chat turn, plan generation or progress summary."""

    __tablename__ = "ai_generations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[str] = mapped_column(
        String(32), default=AIGenerationKind.CHAT, nullable=False, index=True
    )
    status: Mapped[str] = mapped_column(
        String(16), default=AIGenerationStatus.PENDING, nullable=False, index=True
    )
    provider: Mapped[str] = mapped_column(String(32), default="mock", nullable=False)
    model: Mapped[str] = mapped_column(String(64), default="", nullable=False)

    request_payload: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)
    result_payload: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)
    error_message: Mapped[str | None] = mapped_column(Text, default=None)

    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    latency_ms: Mapped[int | None] = mapped_column(Integer, default=None)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)

    __table_args__ = (Index("ix_ai_generations_user_created", "user_id", "created_at"),)


class UsageRecord(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    """Daily metered usage, used for quotas and the admin AI usage report."""

    __tablename__ = "usage_records"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day: Mapped[str] = mapped_column(String(10), nullable=False)
    metric: Mapped[str] = mapped_column(String(48), nullable=False)
    count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    __table_args__ = (Index("ix_usage_records_lookup", "user_id", "day", "metric", unique=True),)


class Subscription(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "subscriptions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tier: Mapped[str] = mapped_column(String(16), default="free", nullable=False)
    status: Mapped[str] = mapped_column(String(24), default="active", nullable=False)
    platform: Mapped[str | None] = mapped_column(String(24), default=None)
    external_id: Mapped[str | None] = mapped_column(String(128), default=None)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), default=None)
