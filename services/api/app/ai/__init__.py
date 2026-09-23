"""AI provider selection."""

from __future__ import annotations

from functools import lru_cache

from app.ai.base import AIProvider, ChatMessage, CompletionRequest, CompletionResult
from app.ai.mock import MockAIProvider
from app.core.config import settings


@lru_cache
def get_ai_provider() -> AIProvider:
    """Return the configured provider, falling back to the local one.

    A missing API key is never an error: the product degrades to the local
    provider rather than breaking the FitCoach surface.
    """
    if settings.AI_PROVIDER == "anthropic" and settings.AI_API_KEY:
        from app.ai.remote import AnthropicProvider

        return AnthropicProvider()
    if settings.AI_PROVIDER == "openai" and settings.AI_API_KEY:
        from app.ai.remote import OpenAIProvider

        return OpenAIProvider()
    return MockAIProvider()


__all__ = [
    "AIProvider",
    "ChatMessage",
    "CompletionRequest",
    "CompletionResult",
    "MockAIProvider",
    "get_ai_provider",
]
