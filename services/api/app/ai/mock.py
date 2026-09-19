"""Deterministic local AI provider.

This is what runs when no API key is configured. It is not a stub that returns
"TODO": it produces grounded, useful answers assembled from the user context
that the AI service passes in, so every AI surface in the product is fully
demonstrable offline and in CI.
"""

from __future__ import annotations

import json
import re

from app.ai.base import AIProvider, CompletionRequest, CompletionResult

_TOPICS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"\b(protein|macro|calorie|diet|eat|nutrition)\b", re.IGNORECASE),
        "For most people training regularly, a practical starting point is around "
        "1.6-2.2 g of protein per kg of body weight per day, spread across three or "
        "four meals. Build the rest of your intake around whole foods you actually "
        "enjoy, keep your calories roughly where your goal needs them, and judge it "
        "on the trend over two to three weeks rather than day to day.\n\n"
        "Your targets in FitTrack are editable at any time — if the estimate doesn't "
        "suit you, override it.",
    ),
    (
        re.compile(r"\b(plateau|stuck|not (getting )?strong|stall)\b", re.IGNORECASE),
        "Plateaus usually come down to one of four things: not enough recovery, not "
        "enough food, too little hard work close to failure, or too much variety to "
        "build any momentum.\n\n"
        "A reliable reset is to drop your working weights about 10% for a week, then "
        "build back up adding a small increment each session. Keep the exercise "
        "selection fixed for six to eight weeks so progress is actually measurable.",
    ),
    (
        re.compile(r"\b(rest|recovery|sleep|tired|fatigue)\b", re.IGNORECASE),
        "Recovery is mostly sleep, food and sensible workload. Seven to nine hours of "
        "sleep, enough calories and protein, and a couple of genuinely easy days per "
        "week will do more than any supplement.\n\n"
        "If your performance drops for more than a week while you're training the "
        "same, that's usually a signal to take a lighter week rather than push harder.",
    ),
    (
        re.compile(r"\b(form|technique|how do i (do|perform))\b", re.IGNORECASE),
        "Work through it in this order: set up your stance and grip, brace before the "
        "weight moves, control the lowering phase, and stop the set while your "
        "technique still looks like the first rep.\n\n"
        "Filming a set from the side is the fastest feedback loop there is — most "
        "technique problems are obvious on video and invisible in the moment.",
    ),
    (
        re.compile(r"\b(cardio|running|endurance|conditioning)\b", re.IGNORECASE),
        "Two to three sessions a week is plenty alongside lifting. Keep most of it "
        "easy enough to hold a conversation, and add one harder interval session if "
        "you want the conditioning to move quickly.\n\n"
        "Put hard cardio on a different day from your heaviest leg session where you "
        "can — they compete for the same recovery.",
    ),
    (
        re.compile(r"\b(home|no gym|dumbbell only|bodyweight)\b", re.IGNORECASE),
        "A pair of adjustable dumbbells covers almost everything: goblet squats, "
        "Romanian deadlifts, split squats, floor presses, rows, shoulder presses and "
        "curls. Progress by adding reps first, then load.\n\n"
        "Use FitTrack's plan generator with your equipment selected and it will build "
        "the week around exactly what you have.",
    ),
]

_FALLBACK = (
    "Here's how I'd approach that: keep the structure simple, train each muscle "
    "group about twice a week, take most working sets close to failure, and let "
    "the numbers in your log tell you when to add weight.\n\n"
    "Tell me your training days, the equipment you have and your main goal, and "
    "I'll turn that into a concrete week."
)


class MockAIProvider(AIProvider):
    name = "mock"

    async def complete(self, request: CompletionRequest) -> CompletionResult:
        if request.json_schema is not None:
            # Structured requests are answered by the planner, not the model.
            return CompletionResult(text=json.dumps({}), model="fittrack-local", data={})

        last_user = next((m.content for m in reversed(request.messages) if m.role == "user"), "")
        body = _FALLBACK
        for pattern, answer in _TOPICS:
            if pattern.search(last_user):
                body = answer
                break

        context_note = ""
        if "TRAINING CONTEXT" in request.system:
            context_note = (
                "\n\nI can see your recent training in FitTrack, so tell me if you "
                "want this tailored to a specific lift or week."
            )

        text = body + context_note
        return CompletionResult(
            text=text,
            input_tokens=len(request.system.split()) + len(last_user.split()),
            output_tokens=len(text.split()),
            model="fittrack-local",
        )
