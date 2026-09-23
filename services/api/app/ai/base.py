"""LLM provider abstraction.

FitCoach is an enhancement, never a dependency: the whole product works with
``AI_PROVIDER=mock``, which produces deterministic, genuinely useful responses
built from the user's own data instead of calling an external service.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass(slots=True)
class ChatMessage:
    role: str
    content: str


@dataclass(slots=True)
class CompletionRequest:
    system: str
    messages: list[ChatMessage]
    max_tokens: int = 1024
    temperature: float = 0.7
    #: When set, the provider is asked to answer with JSON matching this schema.
    json_schema: dict[str, Any] | None = None


@dataclass(slots=True)
class CompletionResult:
    text: str
    input_tokens: int = 0
    output_tokens: int = 0
    model: str = ""
    data: dict[str, Any] = field(default_factory=dict)


class AIProvider(ABC):
    name: str = "base"

    @abstractmethod
    async def complete(self, request: CompletionRequest) -> CompletionResult: ...

    async def health(self) -> str:
        return "ok"
