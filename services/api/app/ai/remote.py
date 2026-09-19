"""Hosted LLM providers (Anthropic and OpenAI-compatible endpoints)."""

from __future__ import annotations

import json
from typing import Any

import httpx

from app.ai.base import AIProvider, CompletionRequest, CompletionResult
from app.core.config import settings
from app.core.errors import ServiceUnavailableError
from app.core.logging import get_logger

logger = get_logger(__name__)


class AnthropicProvider(AIProvider):
    name = "anthropic"
    endpoint = "https://api.anthropic.com/v1/messages"

    async def complete(self, request: CompletionRequest) -> CompletionResult:
        system = request.system
        if request.json_schema is not None:
            system += (
                "\n\nRespond with a single JSON object matching this schema and "
                "nothing else:\n" + json.dumps(request.json_schema)
            )

        payload: dict[str, Any] = {
            "model": settings.AI_MODEL,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "system": system,
            "messages": [
                {"role": m.role, "content": m.content} for m in request.messages
            ],
        }
        try:
            async with httpx.AsyncClient(timeout=settings.AI_TIMEOUT_SECONDS) as client:
                response = await client.post(
                    self.endpoint,
                    json=payload,
                    headers={
                        "x-api-key": settings.AI_API_KEY,
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json",
                    },
                )
        except httpx.HTTPError as exc:
            logger.warning("ai.request_failed", provider=self.name, error=str(exc))
            raise ServiceUnavailableError("FitCoach isn't available right now.") from exc

        if response.status_code >= 400:
            logger.warning("ai.error_response", provider=self.name, status=response.status_code)
            raise ServiceUnavailableError("FitCoach isn't available right now.")

        body = response.json()
        text = "".join(
            block.get("text", "") for block in body.get("content", []) if block.get("type") == "text"
        )
        usage = body.get("usage", {})
        return CompletionResult(
            text=text,
            input_tokens=usage.get("input_tokens", 0),
            output_tokens=usage.get("output_tokens", 0),
            model=body.get("model", settings.AI_MODEL),
            data=_extract_json(text) if request.json_schema is not None else {},
        )


class OpenAIProvider(AIProvider):
    name = "openai"
    endpoint = "https://api.openai.com/v1/chat/completions"

    async def complete(self, request: CompletionRequest) -> CompletionResult:
        messages = [{"role": "system", "content": request.system}]
        messages += [{"role": m.role, "content": m.content} for m in request.messages]

        payload: dict[str, Any] = {
            "model": settings.AI_MODEL,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "messages": messages,
        }
        if request.json_schema is not None:
            payload["response_format"] = {"type": "json_object"}

        try:
            async with httpx.AsyncClient(timeout=settings.AI_TIMEOUT_SECONDS) as client:
                response = await client.post(
                    self.endpoint,
                    json=payload,
                    headers={"Authorization": f"Bearer {settings.AI_API_KEY}"},
                )
        except httpx.HTTPError as exc:
            logger.warning("ai.request_failed", provider=self.name, error=str(exc))
            raise ServiceUnavailableError("FitCoach isn't available right now.") from exc

        if response.status_code >= 400:
            logger.warning("ai.error_response", provider=self.name, status=response.status_code)
            raise ServiceUnavailableError("FitCoach isn't available right now.")

        body = response.json()
        text = body["choices"][0]["message"]["content"]
        usage = body.get("usage", {})
        return CompletionResult(
            text=text,
            input_tokens=usage.get("prompt_tokens", 0),
            output_tokens=usage.get("completion_tokens", 0),
            model=body.get("model", settings.AI_MODEL),
            data=_extract_json(text) if request.json_schema is not None else {},
        )


def _extract_json(text: str) -> dict[str, Any]:
    """Pull a JSON object out of a model response, tolerating code fences."""
    candidate = text.strip()
    if candidate.startswith("```"):
        candidate = candidate.split("```")[1]
        candidate = candidate.removeprefix("json").strip()
    start = candidate.find("{")
    end = candidate.rfind("}")
    if start == -1 or end == -1:
        return {}
    try:
        parsed = json.loads(candidate[start : end + 1])
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}
