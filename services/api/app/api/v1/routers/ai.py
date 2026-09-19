"""FitCoach endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Response, status

from app.core.deps import CurrentUser, DbSession
from app.core.rate_limit import ai_rate_limit
from app.schemas.ai import (
    AIUsageResponse,
    ChatRequest,
    ChatResponse,
    ConversationRead,
    ConversationSummary,
    PlanGenerationRequest,
    PlanGenerationResponse,
    PlanSaveRequest,
    ProgressSummaryResponse,
    SubstitutionRequest,
    SubstitutionResponse,
)
from app.schemas.common import TimeRange
from app.schemas.program import ProgramRead
from app.services import ai_service, program_service

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post(
    "/chat",
    response_model=ChatResponse,
    summary="Ask FitCoach",
    dependencies=[Depends(ai_rate_limit)],
)
async def chat(payload: ChatRequest, db: DbSession, user: CurrentUser) -> ChatResponse:
    return ChatResponse(**await ai_service.chat(db, user, payload))


@router.get(
    "/conversations", response_model=list[ConversationSummary], summary="Your conversations"
)
async def list_conversations(
    db: DbSession, user: CurrentUser
) -> list[ConversationSummary]:
    return [
        ConversationSummary(**row) for row in await ai_service.list_conversations(db, user)
    ]


@router.get(
    "/conversations/{conversation_id}",
    response_model=ConversationRead,
    summary="Conversation detail",
)
async def get_conversation(
    conversation_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> ConversationRead:
    return ConversationRead(**await ai_service.get_conversation(db, user, conversation_id))


@router.delete(
    "/conversations/{conversation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a conversation",
)
async def delete_conversation(
    conversation_id: uuid.UUID, db: DbSession, user: CurrentUser
) -> Response:
    await ai_service.delete_conversation(db, user, conversation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/plans/generate",
    response_model=PlanGenerationResponse,
    summary="Generate a workout plan (preview only)",
    dependencies=[Depends(ai_rate_limit)],
)
async def generate_plan(
    payload: PlanGenerationRequest, db: DbSession, user: CurrentUser
) -> PlanGenerationResponse:
    return PlanGenerationResponse(**await ai_service.generate_plan(db, user, payload))


@router.post(
    "/plans/save",
    response_model=ProgramRead,
    status_code=status.HTTP_201_CREATED,
    summary="Save a generated plan as a new program",
)
async def save_plan(
    payload: PlanSaveRequest, db: DbSession, user: CurrentUser
) -> ProgramRead:
    program = await ai_service.save_plan(
        db,
        user,
        generation_id=uuid.UUID(payload.generation_id),
        name=payload.name,
        activate=payload.activate,
    )
    full = await program_service.get_for_user(db, program.id, user)
    return ProgramRead(**program_service.serialize(full, detail=True))


@router.post(
    "/substitutions",
    response_model=SubstitutionResponse,
    summary="Suggest exercise substitutions",
)
async def substitutions(
    payload: SubstitutionRequest, db: DbSession, user: CurrentUser
) -> SubstitutionResponse:
    return SubstitutionResponse(**await ai_service.suggest_substitutions(db, user, payload))


@router.get(
    "/progress-summary",
    response_model=ProgressSummaryResponse,
    summary="Summarise your recent training",
)
async def progress_summary(
    db: DbSession, user: CurrentUser, range: TimeRange = "30d"
) -> ProgressSummaryResponse:
    return ProgressSummaryResponse(
        **await ai_service.progress_summary(db, user, time_range=range)
    )


@router.get("/usage", response_model=AIUsageResponse, summary="Today's FitCoach usage")
async def usage(db: DbSession, user: CurrentUser) -> AIUsageResponse:
    return AIUsageResponse(**await ai_service.usage(db, user))
