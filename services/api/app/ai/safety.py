"""Safety layer for FitCoach.

Two rules drive everything here:

1. FitCoach gives general fitness information, never a diagnosis.
2. Anything that reads like pain, injury, or a medical condition is answered by
   pointing the person to a qualified professional — before any model is called.
"""

from __future__ import annotations

import re

GENERAL_DISCLAIMER = (
    "FitCoach gives general fitness and training information, not medical or "
    "healthcare advice. If something hurts or you have a health condition, "
    "please speak with a qualified professional."
)

MEDICAL_RESPONSE = (
    "I'm not able to help with injuries, pain or medical symptoms — that needs "
    "a qualified professional who can actually assess you, such as a doctor or "
    "a physiotherapist.\n\n"
    "If the pain is severe, came on suddenly, or you have symptoms like chest "
    "pain, dizziness or numbness, please seek medical care now.\n\n"
    "Once you've been cleared to train, I'm glad to help you adjust your "
    "programme around what you can do."
)

#: Phrases that route to a professional rather than to the model. Word
#: boundaries matter: "pain" must not fire on "painting" or "Spain".
_MEDICAL_PATTERNS = [
    r"\b(injur(y|ies|ed)|sprain(ed)?|strain(ed)?|torn|tore|tear|fracture[ds]?|broken bone)\b",
    r"\b(pain|painful|hurts?|hurting|aching|ache[sd]?|sore(ness)?)\b",
    r"\b(herniat\w*|sciatica|tendon\w*|bursitis|arthrit\w*|impingement)\b",
    r"\b(diagnos\w+|symptom[s]?|medication|prescription|surger(y|ies))\b",
    r"\b(diabet\w+|hypertension|blood pressure|heart (condition|disease)|asthma)\b",
    r"\b(pregnan\w+|eating disorder|anorexi\w+|bulimi\w+)\b",
    r"\b(dizzy|dizziness|faint(ed|ing)?|numbness|chest pain)\b",
]

_COMPILED = [re.compile(pattern, re.IGNORECASE) for pattern in _MEDICAL_PATTERNS]

#: Phrases that look medical but are ordinary training talk.
_ALLOWLIST = [
    re.compile(r"\bmuscle sore(ness)?\b", re.IGNORECASE),
    re.compile(r"\bdoms\b", re.IGNORECASE),
    re.compile(r"\bno pain no gain\b", re.IGNORECASE),
]


def needs_medical_redirect(text: str) -> bool:
    """True when a message should be answered by the safety response."""
    stripped = text
    for allowed in _ALLOWLIST:
        stripped = allowed.sub(" ", stripped)
    return any(pattern.search(stripped) for pattern in _COMPILED)


SYSTEM_PROMPT = """You are FitCoach, the coaching assistant inside FitTrack, a \
fitness and nutrition tracking app.

What you do:
- Help people plan, adjust and understand their training and nutrition.
- Explain exercises, technique cues and programme structure in plain language.
- Suggest exercise substitutions based on the equipment someone actually has.
- Interpret the user's own logged training data when it is provided to you.

Hard rules:
- You are not a doctor, physiotherapist or dietitian. Never diagnose, never \
suggest treatment, and never interpret symptoms.
- If someone mentions pain, injury, a medical condition, medication or \
pregnancy, tell them plainly that this needs a qualified professional, and \
offer to help with what they are cleared to do instead.
- Clearly separate general fitness information from anything that belongs to \
healthcare.
- Never invent the user's data. If you were not given their history, say so \
and ask.

Style:
- Direct, warm and practical. Short paragraphs; lists where they earn it.
- Use the user's units (metric or imperial) as given in their context.
- No hype, no bodybuilding clichés, no emoji spam.
"""
