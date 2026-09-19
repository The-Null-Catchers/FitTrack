"""Shared response envelopes and query primitives."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import date, datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class APIModel(BaseModel):
    """Base for every schema: ORM-friendly, trims incidental whitespace."""

    model_config = ConfigDict(from_attributes=True, str_strip_whitespace=True)


class PageMeta(APIModel):
    page: int
    per_page: int
    total: int
    total_pages: int
    has_next: bool
    has_previous: bool


class Page(APIModel, Generic[T]):
    """Uniform list envelope used by every collection endpoint."""

    items: list[T]
    meta: PageMeta

    @classmethod
    def build(cls, items: Sequence[T], *, total: int, page: int, per_page: int) -> Page[T]:
        total_pages = max(1, -(-total // per_page)) if per_page else 1
        return cls(
            items=list(items),
            meta=PageMeta(
                page=page,
                per_page=per_page,
                total=total,
                total_pages=total_pages,
                has_next=page < total_pages,
                has_previous=page > 1,
            ),
        )


class PaginationParams(BaseModel):
    page: int = Field(1, ge=1)
    per_page: int = Field(20, ge=1, le=100)

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.per_page


class DateRangeParams(BaseModel):
    start_date: date | None = None
    end_date: date | None = None


TimeRange = Literal["7d", "30d", "3m", "6m", "1y", "all"]


class MessageResponse(APIModel):
    message: str
    success: bool = True


class ErrorDetail(APIModel):
    code: str
    message: str
    details: dict = Field(default_factory=dict)
    request_id: str | None = None


class ErrorResponse(APIModel):
    error: ErrorDetail


class HealthResponse(APIModel):
    status: str
    version: str
    environment: str
    time: datetime


class ReadinessResponse(APIModel):
    status: str
    checks: dict[str, str]
