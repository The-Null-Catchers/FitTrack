"""The FitCoach safety layer."""

from __future__ import annotations

import pytest

from app.ai.safety import GENERAL_DISCLAIMER, MEDICAL_RESPONSE, needs_medical_redirect


@pytest.mark.parametrize(
    "message",
    [
        "My shoulder hurts when I bench press, what should I do?",
        "I think I tore my hamstring last week",
        "Can I train with sciatica?",
        "I have high blood pressure, is squatting safe?",
        "What medication helps with recovery?",
        "I felt dizzy during my set and had chest pain",
        "I'm pregnant — how should I train?",
    ],
)
def test_medical_messages_are_redirected(message):
    assert needs_medical_redirect(message) is True


@pytest.mark.parametrize(
    "message",
    [
        "How many sets should I do for chest?",
        "Build me a 4-day dumbbell programme",
        "What's a good protein target for me?",
        "I have muscle soreness after leg day, is that normal?",
        "How do I fix my squat depth?",
        "My progress in Spain was good, any tips?",
    ],
)
def test_ordinary_training_questions_pass_through(message):
    assert needs_medical_redirect(message) is False


def test_the_medical_response_points_to_a_professional():
    assert "professional" in MEDICAL_RESPONSE
    assert "physiotherapist" in MEDICAL_RESPONSE
    # It must not offer a diagnosis or treatment of its own.
    assert "you probably have" not in MEDICAL_RESPONSE.lower()


def test_the_disclaimer_separates_fitness_from_healthcare():
    assert "not medical" in GENERAL_DISCLAIMER


async def test_chat_endpoint_redirects_medical_questions(client, auth_headers):
    response = await client.post(
        "/api/v1/ai/chat",
        json={"message": "My lower back hurts after deadlifts, what's wrong with it?"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["message"]["safety_redirect"] is True
    assert "professional" in body["message"]["content"]
    assert body["disclaimer"] == GENERAL_DISCLAIMER


async def test_chat_endpoint_answers_training_questions(client, auth_headers):
    response = await client.post(
        "/api/v1/ai/chat",
        json={"message": "How much protein should I eat to build muscle?"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["message"]["safety_redirect"] is False
    assert len(body["message"]["content"]) > 50
    assert body["conversation_id"]
