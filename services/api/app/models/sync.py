"""Server-side record of offline sync operations.

The mobile client stamps every mutation it queues with a ``client_uuid``. This
table records which of those operations the server has already applied so a
replayed batch is answered from the ledger instead of being applied twice.
"""

from __future__ import annotations

import uuid

from sqlalchemy import ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
from app.db.types import GUID, JSONDict


class SyncOperation(Base, UUIDPrimaryKeyMixin, TimestampMixin):
    __tablename__ = "sync_operations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    client_uuid: Mapped[str] = mapped_column(String(64), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(48), nullable=False)
    operation: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="applied", nullable=False)
    server_id: Mapped[str | None] = mapped_column(String(64), default=None)
    result: Mapped[dict] = mapped_column(JSONDict, default=dict, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "client_uuid", name="uq_sync_operations_user_client"),
        Index("ix_sync_operations_user_created", "user_id", "created_at"),
    )
