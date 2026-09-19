"""Portable column types.

The API runs on PostgreSQL, but the test suite runs on SQLite so that CI needs
no services. These decorators give both backends the same Python-level
semantics while still using native Postgres types in production.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import JSON, CHAR, TypeDecorator
from sqlalchemy.dialects.postgresql import JSONB, UUID as PgUUID
from sqlalchemy.engine import Dialect


class GUID(TypeDecorator):
    """UUID column: native ``uuid`` on PostgreSQL, 32-char hex elsewhere."""

    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect: Dialect) -> Any:
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PgUUID(as_uuid=True))
        return dialect.type_descriptor(CHAR(32))

    def process_bind_param(self, value: Any, dialect: Dialect) -> Any:
        if value is None:
            return None
        if not isinstance(value, uuid.UUID):
            value = uuid.UUID(str(value))
        return value if dialect.name == "postgresql" else value.hex

    def process_result_value(self, value: Any, dialect: Dialect) -> uuid.UUID | None:
        if value is None:
            return None
        return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))


#: JSON document column — JSONB on PostgreSQL, JSON elsewhere.
JSONDict = JSON().with_variant(JSONB(), "postgresql")
