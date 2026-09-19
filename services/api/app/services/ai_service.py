"""FitCoach: chat, plan generation, substitutions and progress summaries."""

from __future__ import annotations

import time
import uuid
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.attributes import set_committed_value

from app.ai import ChatMessage, CompletionRequest, get_ai_provider
from app.ai import planner, safety
from app.core.config import settings
from app.core.errors import NotFoundError, PermissionError_, RateLimitError, ValidationError
from app.core.logging import get_logger
from app.models.ai import AIConversation, AIGeneration, AIMessage, UsageRecord
from app.models.enums import (
    AIGenerationKind,
    AIGenerationStatus,
    Equipment,
    ProgramStatus,
    SessionStatus,
)
from app.models.exercise import Exercise
from app.models.program import WorkoutDay, WorkoutDayExercise, WorkoutProgram
from app.models.user import User
from app.models.workout import WorkoutSession
from app.schemas.ai import ChatRequest, PlanGenerationRequest, SubstitutionRequest
from app.services import analytics_service

logger = get_logger(__name__)

#: How many prior turns are replayed to the provider.
CONTEXT_TURNS = 10


async def _quota_check(db: AsyncSession, user: User, metric: str, limit: int) -> UsageRecord:
    today = date.today().isoformat()
    record = await db.scalar(
        select(UsageRecord).where(
            UsageRecord.user_id == user.id,
            UsageRecord.day == today,
            UsageRecord.metric == metric,
        )
    )
    if record is None:
        record = UsageRecord(user_id=user.id, day=today, metric=metric, count=0)
        db.add(record)
        await db.flush()
    if record.count >= limit:
        raise RateLimitError(
            "You've reached today's FitCoach limit. It resets tomorrow.",
            code="ai_quota_exceeded",
        )
    return record


async def _build_context(db: AsyncSession, user: User) -> str:
    """Summarise the user's own data for the system prompt.

    Only included when the profile opts in, and only ever as a summary — raw
    rows never leave the database.
    """
    profile = user.profile
    if profile is None or not profile.ai_context_opt_in:
        return ""

    overview = await analytics_service.training_overview(db, user, time_range="30d")
    active_program = await db.scalar(
        select(WorkoutProgram).where(
            WorkoutProgram.user_id == user.id,
            WorkoutProgram.status == ProgramStatus.ACTIVE,
            WorkoutProgram.is_deleted.is_(False),
        )
    )
    top_groups = ", ".join(
        f"{g['muscle_group']} {g['percent']}%" for g in overview["volume_by_muscle_group"][:4]
    )
    units = "metric (kg/cm)" if profile.unit_system == "metric" else "imperial (lb/in)"

    lines = [
        "TRAINING CONTEXT (the user's own FitTrack data — do not invent anything beyond it):",
        f"- Goal: {profile.primary_goal.replace('_', ' ')}",
        f"- Experience: {profile.fitness_level}",
        f"- Trains {profile.training_days_per_week} days/week, "
        f"~{profile.preferred_session_minutes} min per session, {profile.workout_location}",
        f"- Equipment: {', '.join(profile.available_equipment) or 'bodyweight only'}",
        f"- Units: {units}",
        f"- Last 30 days: {overview['total_workouts']} workouts, "
        f"{round(overview['total_volume_kg']):,} kg total volume, "
        f"{overview['personal_records']} personal records",
    ]
    if top_groups:
        lines.append(f"- Volume split: {top_groups}")
    if active_program:
        lines.append(f"- Active program: {active_program.name}")
    if profile.current_weight_kg:
        lines.append(f"- Body weight: {profile.current_weight_kg} kg")
        if profile.target_weight_kg:
            lines.append(f"- Target weight: {profile.target_weight_kg} kg")
    return "\n".join(lines)


async def _get_or_create_conversation(
    db: AsyncSession, user: User, conversation_id: str | None, first_message: str
) -> AIConversation:
    if conversation_id:
        conversation = await db.scalar(
            select(AIConversation)
            .options(selectinload(AIConversation.messages))
            .where(AIConversation.id == uuid.UUID(conversation_id))
        )
        if conversation is None or conversation.is_deleted:
            raise NotFoundError("We couldn't find that conversation.")
        if conversation.user_id != user.id:
            raise PermissionError_("That conversation belongs to someone else.")
        return conversation

    title = first_message.strip().split("\n")[0][:60] or "New conversation"
    conversation = AIConversation(user_id=user.id, title=title)
    db.add(conversation)
    await db.flush()
    # Mark the (empty) collection as loaded so touching it later never triggers
    # a lazy load outside the async context.
    set_committed_value(conversation, "messages", [])
    return conversation


async def chat(db: AsyncSession, user: User, data: ChatRequest) -> dict[str, Any]:
    record = await _quota_check(db, user, "ai_messages", settings.AI_DAILY_MESSAGE_LIMIT)
    conversation = await _get_or_create_conversation(
        db, user, data.conversation_id, data.message
    )

    db.add(
        AIMessage(conversation_id=conversation.id, role="user", content=data.message)
    )
    await db.flush()

    # The safety layer answers medical questions itself — no model call at all.
    if safety.needs_medical_redirect(data.message):
        reply = AIMessage(
            conversation_id=conversation.id,
            role="assistant",
            content=safety.MEDICAL_RESPONSE,
            safety_redirect=True,
        )
        db.add(reply)
        conversation.last_message_at = datetime.now(UTC)
        record.count += 1
        await db.commit()
        await db.refresh(reply)
        return {
            "conversation_id": str(conversation.id),
            "message": serialize_message(reply),
            "disclaimer": safety.GENERAL_DISCLAIMER,
        }

    history = sorted(conversation.messages, key=lambda m: m.created_at)[-CONTEXT_TURNS:]
    messages = [ChatMessage(role=m.role, content=m.content) for m in history]
    messages.append(ChatMessage(role="user", content=data.message))

    system = safety.SYSTEM_PROMPT
    if data.include_context:
        context = await _build_context(db, user)
        if context:
            system = f"{system}\n\n{context}"

    provider = get_ai_provider()
    generation = AIGeneration(
        user_id=user.id,
        kind=AIGenerationKind.CHAT,
        status=AIGenerationStatus.RUNNING,
        provider=provider.name,
        model=settings.AI_MODEL,
        request_payload={"conversation_id": str(conversation.id)},
    )
    db.add(generation)
    await db.flush()

    started = time.perf_counter()
    try:
        result = await provider.complete(
            CompletionRequest(
                system=system, messages=messages, max_tokens=settings.AI_MAX_TOKENS
            )
        )
    except Exception as exc:
        generation.status = AIGenerationStatus.FAILED
        generation.error_message = str(exc)[:500]
        generation.completed_at = datetime.now(UTC)
        await db.commit()
        raise

    generation.status = AIGenerationStatus.SUCCEEDED
    generation.completed_at = datetime.now(UTC)
    generation.latency_ms = int((time.perf_counter() - started) * 1000)
    generation.input_tokens = result.input_tokens
    generation.output_tokens = result.output_tokens

    reply = AIMessage(
        conversation_id=conversation.id,
        role="assistant",
        content=result.text,
        input_tokens=result.input_tokens,
        output_tokens=result.output_tokens,
    )
    db.add(reply)
    conversation.last_message_at = datetime.now(UTC)
    record.count += 1
    record.tokens += result.input_tokens + result.output_tokens
    await db.commit()
    await db.refresh(reply)

    return {
        "conversation_id": str(conversation.id),
        "message": serialize_message(reply),
        "disclaimer": safety.GENERAL_DISCLAIMER,
    }


async def list_conversations(db: AsyncSession, user: User) -> list[dict[str, Any]]:
    rows = await db.scalars(
        select(AIConversation)
        .options(selectinload(AIConversation.messages))
        .where(AIConversation.user_id == user.id, AIConversation.is_deleted.is_(False))
        .order_by(AIConversation.last_message_at.desc().nullslast())
    )
    return [
        {
            "id": str(c.id),
            "title": c.title,
            "last_message_at": c.last_message_at,
            "created_at": c.created_at,
            "message_count": len(c.messages),
        }
        for c in rows
    ]


async def get_conversation(
    db: AsyncSession, user: User, conversation_id: uuid.UUID
) -> dict[str, Any]:
    conversation = await db.scalar(
        select(AIConversation)
        .options(selectinload(AIConversation.messages))
        .where(AIConversation.id == conversation_id)
    )
    if conversation is None or conversation.is_deleted:
        raise NotFoundError("We couldn't find that conversation.")
    if conversation.user_id != user.id:
        raise PermissionError_("That conversation belongs to someone else.")
    messages = sorted(conversation.messages, key=lambda m: m.created_at)
    return {
        "id": str(conversation.id),
        "title": conversation.title,
        "last_message_at": conversation.last_message_at,
        "created_at": conversation.created_at,
        "message_count": len(messages),
        "messages": [serialize_message(m) for m in messages],
    }


async def delete_conversation(
    db: AsyncSession, user: User, conversation_id: uuid.UUID
) -> None:
    conversation = await db.get(AIConversation, conversation_id)
    if conversation is None or conversation.is_deleted:
        raise NotFoundError("We couldn't find that conversation.")
    if conversation.user_id != user.id:
        raise PermissionError_("That conversation belongs to someone else.")
    conversation.soft_delete()
    await db.commit()


async def generate_plan(
    db: AsyncSession, user: User, data: PlanGenerationRequest
) -> dict[str, Any]:
    """Produce a plan *preview*. Nothing is written to the user's programs."""
    await _quota_check(db, user, "ai_plans", 20)

    plan = await planner.generate(
        db,
        goal=data.goal,
        experience=data.experience,
        days_per_week=data.days_per_week,
        session_minutes=data.session_minutes,
        equipment=[e.value for e in data.equipment],
        location=data.location,
        preferred_exercise_ids=[uuid.UUID(i) for i in data.preferred_exercise_ids],
        excluded_exercise_ids=[uuid.UUID(i) for i in data.excluded_exercise_ids],
        user_id=user.id,
    )
    if not any(day["exercises"] for day in plan["days"]):
        raise ValidationError(
            "We couldn't build a plan from the equipment you selected. Try adding "
            "bodyweight or more equipment.",
            code="plan_not_possible",
        )

    provider = get_ai_provider()
    generation = AIGeneration(
        user_id=user.id,
        kind=AIGenerationKind.WORKOUT_PLAN,
        status=AIGenerationStatus.SUCCEEDED,
        provider=provider.name,
        model=settings.AI_MODEL,
        request_payload=data.model_dump(mode="json"),
        result_payload=plan,
        completed_at=datetime.now(UTC),
    )
    db.add(generation)

    record = await _quota_check(db, user, "ai_plans", 20)
    record.count += 1
    await db.commit()
    await db.refresh(generation)

    return {
        "generation_id": str(generation.id),
        "plan": plan,
        "disclaimer": safety.GENERAL_DISCLAIMER,
    }


async def save_plan(
    db: AsyncSession,
    user: User,
    *,
    generation_id: uuid.UUID,
    name: str | None,
    activate: bool,
) -> WorkoutProgram:
    """Persist a previewed plan as a brand-new program.

    An existing program is never modified or overwritten — saving always
    creates a new one.
    """
    generation = await db.get(AIGeneration, generation_id)
    if generation is None or generation.kind != AIGenerationKind.WORKOUT_PLAN:
        raise NotFoundError("We couldn't find that generated plan.")
    if generation.user_id != user.id:
        raise PermissionError_("That plan belongs to someone else.")

    plan = generation.result_payload
    program = WorkoutProgram(
        user_id=user.id,
        name=name or plan["name"],
        description=plan["description"],
        goal=plan["goal"],
        difficulty=plan["difficulty"],
        location=None,
        days_per_week=plan["days_per_week"],
        estimated_minutes=plan["estimated_minutes"],
        equipment_needed=plan["equipment_needed"],
        status=ProgramStatus.DRAFT,
        generated_by_ai=True,
    )
    db.add(program)
    await db.flush()

    for position, day in enumerate(plan["days"]):
        workout_day = WorkoutDay(
            program_id=program.id,
            name=day["name"],
            position=position,
            weekday=day.get("weekday"),
        )
        db.add(workout_day)
        await db.flush()
        for slot, entry in enumerate(day["exercises"]):
            if not entry.get("exercise_id"):
                continue
            prescription = entry["prescription"]
            exercise = await db.get(Exercise, uuid.UUID(entry["exercise_id"]))
            if exercise is None:
                continue
            db.add(
                WorkoutDayExercise(
                    day_id=workout_day.id,
                    exercise_id=exercise.id,
                    position=slot,
                    target_sets=prescription["sets"],
                    target_reps_min=prescription.get("reps_min"),
                    target_reps_max=prescription.get("reps_max"),
                    target_duration_seconds=prescription.get("duration_seconds"),
                    target_rpe=prescription.get("rpe"),
                    rest_seconds=prescription.get("rest_seconds", 90),
                    tracking_type=exercise.default_tracking_type,
                    notes=prescription.get("notes"),
                )
            )

    if activate:
        from app.services import program_service

        await program_service._set_status(db, program, user, ProgramStatus.ACTIVE)

    await db.commit()
    return program


async def suggest_substitutions(
    db: AsyncSession, user: User, data: SubstitutionRequest
) -> dict[str, Any]:
    """Find alternatives for an exercise using the same muscle group."""
    source = await db.get(Exercise, uuid.UUID(data.exercise_id))
    if source is None or source.is_deleted:
        raise NotFoundError("We couldn't find that exercise.")

    equipment = {e.value for e in data.available_equipment} or {
        Equipment.BODYWEIGHT,
        Equipment.DUMBBELL,
    }
    equipment.add(Equipment.BODYWEIGHT)

    rows = await db.scalars(
        select(Exercise)
        .where(
            Exercise.id != source.id,
            Exercise.is_deleted.is_(False),
            Exercise.is_public.is_(True),
            Exercise.muscle_group == source.muscle_group,
            Exercise.equipment.in_(list(equipment)),
        )
        .order_by(Exercise.popularity.desc())
        .limit(data.limit * 3)
    )

    options: list[dict[str, Any]] = []
    for candidate in rows:
        shared = set(candidate.secondary_muscles or []) & set(source.secondary_muscles or [])
        rationale = (
            f"Same primary muscle ({candidate.muscle_group.replace('_', ' ')}), using "
            f"{candidate.equipment.replace('_', ' ')}."
        )
        if shared:
            rationale += f" Also shares {', '.join(sorted(shared))}."
        options.append(
            {
                "exercise_id": str(candidate.id),
                "exercise_name": candidate.name,
                "equipment": candidate.equipment,
                "rationale": rationale,
            }
        )
        if len(options) >= data.limit:
            break

    db.add(
        AIGeneration(
            user_id=user.id,
            kind=AIGenerationKind.EXERCISE_SUBSTITUTION,
            status=AIGenerationStatus.SUCCEEDED,
            provider="rules",
            request_payload=data.model_dump(mode="json"),
            result_payload={"count": len(options)},
            completed_at=datetime.now(UTC),
        )
    )
    await db.commit()
    return {"source_exercise_id": str(source.id), "options": options}


async def progress_summary(
    db: AsyncSession, user: User, *, time_range: str = "30d"
) -> dict[str, Any]:
    """A plain-language read of the user's own numbers — no medical claims."""
    overview = await analytics_service.training_overview(db, user, time_range=time_range)
    weight = await analytics_service.body_weight_chart(db, user, time_range=time_range)

    bullets: list[str] = []
    if overview["total_workouts"]:
        bullets.append(
            f"You completed {overview['total_workouts']} workouts "
            f"({overview['workouts_per_week']} per week on average)."
        )
        bullets.append(
            f"Total volume was {round(overview['total_volume_kg']):,} kg across "
            f"{overview['total_sets']} working sets."
        )
        if overview["volume_by_muscle_group"]:
            top = overview["volume_by_muscle_group"][0]
            bullets.append(
                f"Most of your volume went to {top['muscle_group'].replace('_', ' ')} "
                f"({top['percent']}%)."
            )
        if overview["personal_records"]:
            bullets.append(
                f"You set {overview['personal_records']} personal "
                f"record{'s' if overview['personal_records'] != 1 else ''}."
            )
    else:
        bullets.append("No workouts were logged in this period.")

    if weight["change_absolute"] is not None:
        direction = "down" if weight["change_absolute"] < 0 else "up"
        bullets.append(
            f"Body weight is {direction} {abs(weight['change_absolute']):g} kg over the "
            "same window."
        )

    exercises = await analytics_service.trained_exercises(db, user, limit=3)
    for entry in exercises:
        progress = await analytics_service.exercise_progress(
            db, user, uuid.UUID(entry["id"]), time_range=time_range
        )
        if progress["summary"]:
            bullets.append(progress["summary"])

    headline = (
        f"{overview['total_workouts']} workouts in the last {time_range}"
        if overview["total_workouts"]
        else "No training logged yet in this period"
    )

    db.add(
        AIGeneration(
            user_id=user.id,
            kind=AIGenerationKind.PROGRESS_SUMMARY,
            status=AIGenerationStatus.SUCCEEDED,
            provider="rules",
            request_payload={"range": time_range},
            result_payload={"bullets": bullets},
            completed_at=datetime.now(UTC),
        )
    )
    await db.commit()

    return {
        "range": time_range,
        "headline": headline,
        "bullets": bullets,
        "disclaimer": safety.GENERAL_DISCLAIMER,
    }


async def usage(db: AsyncSession, user: User) -> dict[str, Any]:
    today = date.today().isoformat()
    rows = {
        metric: count
        for metric, count in await db.execute(
            select(UsageRecord.metric, UsageRecord.count).where(
                UsageRecord.user_id == user.id, UsageRecord.day == today
            )
        )
    }
    return {
        "day": today,
        "messages_used": rows.get("ai_messages", 0),
        "messages_limit": settings.AI_DAILY_MESSAGE_LIMIT,
        "plans_generated": rows.get("ai_plans", 0),
    }


def serialize_message(message: AIMessage) -> dict[str, Any]:
    return {
        "id": str(message.id),
        "role": message.role,
        "content": message.content,
        "payload": message.payload or {},
        "safety_redirect": message.safety_redirect,
        "created_at": message.created_at,
    }


async def recent_workout_names(db: AsyncSession, user: User, limit: int = 5) -> list[str]:
    rows = await db.scalars(
        select(WorkoutSession.name)
        .where(
            WorkoutSession.user_id == user.id,
            WorkoutSession.status == SessionStatus.COMPLETED,
            WorkoutSession.is_deleted.is_(False),
        )
        .order_by(WorkoutSession.started_at.desc())
        .limit(limit)
    )
    return list(rows)


async def admin_usage_rows(db: AsyncSession, *, days: int = 14) -> list[dict[str, Any]]:
    """Per-day AI usage for the admin dashboard."""
    from datetime import timedelta

    since = datetime.now(UTC) - timedelta(days=days)
    rows = await db.execute(
        select(
            func.date(AIGeneration.created_at),
            AIGeneration.kind,
            func.count(),
            func.coalesce(func.sum(AIGeneration.input_tokens), 0),
            func.coalesce(func.sum(AIGeneration.output_tokens), 0),
            func.sum(
                func.case((AIGeneration.status == AIGenerationStatus.FAILED, 1), else_=0)
            ),
        )
        .where(AIGeneration.created_at >= since)
        .group_by(func.date(AIGeneration.created_at), AIGeneration.kind)
        .order_by(func.date(AIGeneration.created_at).desc())
    )
    return [
        {
            "day": str(day),
            "kind": kind,
            "requests": int(count),
            "input_tokens": int(input_tokens),
            "output_tokens": int(output_tokens),
            "failures": int(failures or 0),
        }
        for day, kind, count, input_tokens, output_tokens, failures in rows
    ]
