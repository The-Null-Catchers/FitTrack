"""End-to-end acceptance walk against a running FitTrack API.

Exercises the path a reviewer would take by hand: register, onboard, browse the
library, clone a plan, start a workout, log sets, resume it, finish it, see the
records, log weight and meals, upload a private photo, set a goal, use FitCoach,
sync a batch of offline changes, and confirm the admin surface never exposes
private content.

    ./scripts/acceptance.sh                   # against the compose stack
    FITTRACK_URL=https://api.example.com python3 scripts/acceptance.py

Prints every check and exits non-zero if any of them failed.
"""
import io
import os
import sys
import uuid
from datetime import date, datetime, timedelta, timezone

import httpx

BASE = os.environ.get("FITTRACK_URL", "http://localhost:8000").rstrip("/")
V1 = f"{BASE}/api/v1"
passed, failed = [], []


def check(name, condition, detail=""):
    (passed if condition else failed).append(name)
    print(f"  {'PASS' if condition else 'FAIL'}  {name}" + (f"  — {detail}" if detail and not condition else ""))


with httpx.Client(timeout=30) as c:
    print("\n== health ==")
    r = c.get(f"{BASE}/health"); check("GET /health", r.status_code == 200 and r.json()["status"] == "ok")
    r = c.get(f"{BASE}/ready"); check("GET /ready reports the database", r.json()["checks"]["database"] == "ok")
    r = c.get(f"{BASE}/openapi.json"); check("OpenAPI schema served", r.status_code == 200 and len(r.json()["paths"]) > 100, str(r.status_code))

    print("\n== 1. register ==")
    email = f"reviewer-{uuid.uuid4().hex[:8]}@example.com"
    r = c.post(f"{V1}/auth/register", json={"email": email, "password": "ReviewPass1!", "full_name": "Alex Reviewer"})
    check("register", r.status_code == 201, r.text[:200])
    tok = r.json()["access_token"]
    H = {"Authorization": f"Bearer {tok}"}
    check("onboarding not yet complete", r.json()["user"]["onboarding_completed"] is False)

    print("\n== 2. onboarding ==")
    r = c.post(f"{V1}/profile/onboarding", headers=H, json={
        "date_of_birth": "1995-04-12", "gender": "undisclosed", "height_cm": 178,
        "current_weight_kg": 84, "target_weight_kg": 78, "unit_system": "metric",
        "primary_goal": "lose_weight", "fitness_level": "intermediate",
        "activity_level": "moderate", "workout_location": "gym",
        "available_equipment": ["barbell", "dumbbell", "cable", "machine"],
        "training_days_per_week": 4, "preferred_session_minutes": 60,
    })
    check("onboarding", r.status_code == 201, r.text[:200])
    prof = r.json()["profile"]
    check("calorie target estimated", prof["daily_calorie_target"] > 1200, str(prof["daily_calorie_target"]))
    check("protein target estimated", prof["daily_protein_target_g"] > 100)

    print("\n== 3. browse exercises ==")
    r = c.get(f"{V1}/exercises", headers=H, params={"per_page": 5})
    check("exercise library paginated", r.status_code == 200 and r.json()["meta"]["total"] >= 80, str(r.json()["meta"]["total"]))
    r = c.get(f"{V1}/exercises", headers=H, params={"q": "bench", "muscle_group": "chest"})
    check("search + filter", len(r.json()["items"]) > 0)
    ex_id = r.json()["items"][0]["id"]
    r = c.get(f"{V1}/exercises/{ex_id}", headers=H)
    check("exercise detail has instructions", isinstance(r.json()["instructions"], list))

    print("\n== 4. create a workout plan ==")
    r = c.get(f"{V1}/programs/templates")
    check("templates seeded", len(r.json()) == 6, str(len(r.json())))
    tpl = next(t for t in r.json() if t["name"] == "Push / Pull / Legs")
    r = c.post(f"{V1}/programs/{tpl['id']}/duplicate", headers=H, json={"name": "My PPL"})
    check("clone a template", r.status_code == 201 and r.json()["exercise_count"] == 15, r.text[:200])
    prog = r.json()
    r = c.post(f"{V1}/programs/{prog['id']}/activate", headers=H)
    check("activate the plan", r.json()["status"] == "active")
    day = r.json()["days"][0]

    print("\n== 5-7. start a workout and record sets ==")
    r = c.post(f"{V1}/workout-sessions", headers=H, json={"program_id": prog["id"], "day_id": day["id"], "client_uuid": "e2e-w-1"})
    check("start workout", r.status_code == 201, r.text[:200])
    sess = r.json()
    check("prescription copied to the session", sess["exercises"][0]["target_snapshot"]["sets"] == 4)
    se = sess["exercises"][0]
    for n, (w, reps) in enumerate([(80, 8), (82.5, 7), (85, 5)], start=1):
        r = c.post(f"{V1}/workout-sessions/exercises/{se['id']}/sets", headers=H,
                   json={"set_number": n, "weight_kg": w, "reps": reps, "is_completed": True, "rpe": 8})
        check(f"log set {n}", r.status_code == 201, r.text[:200])
    logged = r.json()["sets"]
    check("volume computed", logged[0]["volume_kg"] == 640, str(logged[0]["volume_kg"]))
    check("estimated 1RM computed", abs(logged[0]["estimated_1rm_kg"] - 101.33) < 0.02)

    print("\n== resume after closing the app ==")
    r = c.get(f"{V1}/workout-sessions/active", headers=H)
    check("resume an unfinished workout", r.json() is not None and r.json()["id"] == sess["id"])
    check("logged sets survived", len(r.json()["exercises"][0]["sets"]) == 3)

    print("\n== idempotent start ==")
    r = c.post(f"{V1}/workout-sessions", headers=H, json={"program_id": prog["id"], "day_id": day["id"], "client_uuid": "e2e-w-1"})
    check("replayed start returns the same session", r.json()["id"] == sess["id"])

    print("\n== 8. finish + personal records ==")
    r = c.post(f"{V1}/workout-sessions/{sess['id']}/finish", headers=H, json={"duration_seconds": 3600, "perceived_effort": 8})
    check("finish workout", r.status_code == 200, r.text[:200])
    done = r.json()
    check("totals computed", done["total_sets"] == 3 and done["total_reps"] == 20, f"{done['total_sets']}/{done['total_reps']}")
    check("calories estimated", done["estimated_calories"] > 0)
    types = {p["record_type"] for p in done["personal_records"]}
    check("personal records detected", {"max_weight", "estimated_1rm", "max_reps", "max_volume"} <= types, str(types))

    print("\n== 9. history and charts ==")
    r = c.get(f"{V1}/workout-sessions", headers=H)
    check("workout history", r.json()["meta"]["total"] == 1 and r.json()["items"][0]["pr_count"] > 0)
    r = c.get(f"{V1}/progress/exercises/{se['exercise']['id']}", headers=H, params={"range": "6m"})
    check("exercise progression chart", r.status_code == 200 and len(r.json()["points"]) == 1)
    r = c.get(f"{V1}/progress/overview", headers=H, params={"range": "30d"})
    check("training overview", r.json()["total_workouts"] == 1 and len(r.json()["volume_by_muscle_group"]) > 0)

    print("\n== 10. weight and measurements ==")
    r = c.post(f"{V1}/progress/weights", headers=H, json={"recorded_on": str(date.today()), "weight_kg": 83.2})
    check("log weight", r.status_code == 201)
    r = c.post(f"{V1}/progress/measurements", headers=H, json={"recorded_on": str(date.today()), "measurement_type": "waist", "value_cm": 87.5})
    check("log measurement", r.status_code == 201)
    r = c.get(f"{V1}/progress/charts/weight", headers=H, params={"range": "30d"})
    check("weight chart", r.status_code == 200)

    print("\n== 11. nutrition ==")
    r = c.get(f"{V1}/nutrition/foods", headers=H, params={"q": "chicken breast"})
    food = r.json()["items"][0]
    r = c.post(f"{V1}/nutrition/meals", headers=H, json={
        "logged_on": str(date.today()), "meal_type": "lunch",
        "items": [{"food_id": food["id"], "grams": 200}]})
    check("log a meal", r.status_code == 201 and abs(r.json()["total_calories"] - 330) < 1, r.text[:200])
    r = c.post(f"{V1}/nutrition/water", headers=H, json={"logged_on": str(date.today()), "amount_ml": 500})
    check("log water", r.json()["water_ml"] == 500)
    r = c.get(f"{V1}/nutrition/day", headers=H)
    d = r.json()
    check("macro progress against targets", d["calories"]["target"] > 0 and d["protein_g"]["consumed"] > 60)

    print("\n== 12. private progress photo ==")
    from PIL import Image
    buf = io.BytesIO(); Image.new("RGB", (900, 1200), "#3f6f9f").save(buf, format="PNG")
    r = c.post(f"{V1}/progress/photos", headers=H,
               files={"file": ("front.png", buf.getvalue(), "image/png")},
               data={"taken_on": str(date.today()), "pose": "front", "weight_kg": "83.2"})
    check("upload a progress photo", r.status_code == 201, r.text[:200])
    photo = r.json()
    check("served through a signed URL", "signature=" in (photo["url"] or ""))
    path = photo["url"].split(BASE, 1)[-1]
    check("signed URL resolves", c.get(f"{BASE}{path}").status_code == 200)
    check("unsigned URL is refused", c.get(f"{BASE}{path.split('?')[0]}").status_code == 403)

    print("\n== 13. goals ==")
    r = c.post(f"{V1}/goals", headers=H, json={
        "goal_type": "body_weight", "title": "Reach 78 kg", "start_value": 84,
        "target_value": 78, "unit": "kg", "is_decreasing": True})
    check("create a goal", r.status_code == 201)
    goal = r.json()
    check("goal tracks the logged weight", goal["current_value"] == 83.2 and goal["progress_percent"] > 0, str(goal["progress_percent"]))

    print("\n== 14. personal records screen ==")
    r = c.get(f"{V1}/personal-records", headers=H)
    check("records listed", len(r.json()) >= 4)

    print("\n== 15. FitCoach ==")
    r = c.post(f"{V1}/ai/chat", headers=H, json={"message": "How much protein should I eat to gain muscle?"})
    check("coach answers a training question", r.status_code == 200 and r.json()["message"]["safety_redirect"] is False, r.text[:200])
    check("disclaimer present", "not medical" in r.json()["disclaimer"])
    r = c.post(f"{V1}/ai/chat", headers=H, json={"message": "My shoulder hurts when I bench, what is wrong?"})
    check("medical question is redirected", r.json()["message"]["safety_redirect"] is True)
    check("redirect names a professional", "professional" in r.json()["message"]["content"])

    print("\n== 16. AI plan generation ==")
    r = c.post(f"{V1}/ai/plans/generate", headers=H, json={
        "goal": "gain_muscle", "experience": "intermediate", "days_per_week": 4,
        "session_minutes": 60, "equipment": ["dumbbell"], "location": "home"})
    check("generate a plan", r.status_code == 200 and len(r.json()["plan"]["days"]) == 4, r.text[:200])
    gen = r.json()
    check("every day has exercises", all(len(d["exercises"]) > 0 for d in gen["plan"]["days"]))
    r = c.post(f"{V1}/ai/plans/save", headers=H, json={"generation_id": gen["generation_id"], "name": "Coach plan"})
    check("save as a new program", r.status_code == 201 and r.json()["generated_by_ai"] is True)
    r = c.get(f"{V1}/programs/active", headers=H)
    check("existing plan untouched", r.json()["id"] == prog["id"])

    print("\n== 17. offline sync ==")
    ops = [
        {"client_uuid": "e2e-offline-weight", "entity": "body_weight",
         "payload": {"recorded_on": str(date.today() - timedelta(days=1)), "weight_kg": 83.6}},
        {"client_uuid": "e2e-offline-water", "entity": "water_log",
         "payload": {"logged_on": str(date.today()), "amount_ml": 250}},
        {"client_uuid": "e2e-offline-workout", "entity": "workout_session",
         "payload": {"client_uuid": "e2e-offline-workout", "program_id": prog["id"],
                     "day_id": prog["days"][1]["id"], "name": "Pull",
                     "started_at": (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(),
                     "finished": True, "duration_seconds": 3300,
                     "exercises": [{"exercise_id": prog["days"][1]["exercises"][0]["exercise"]["id"],
                                    "position": 0, "tracking_type": "weight_reps", "rest_seconds": 150,
                                    "sets": [{"set_number": 1, "weight_kg": 70, "reps": 8, "is_completed": True},
                                             {"set_number": 2, "weight_kg": 70, "reps": 7, "is_completed": True}]}]}},
    ]
    r = c.post(f"{V1}/sync/push", headers=H, json={"operations": ops})
    check("push offline changes", r.json()["applied"] == 3, r.text[:300])
    r = c.post(f"{V1}/sync/push", headers=H, json={"operations": ops})
    check("replay is deduplicated", r.json()["duplicates"] == 3 and r.json()["applied"] == 0)
    r = c.get(f"{V1}/workout-sessions", headers=H)
    check("offline workout appears in history", r.json()["meta"]["total"] == 2)
    r = c.get(f"{V1}/sync/pull", headers=H)
    check("delta pull returns records", len(r.json()["body_weights"]) >= 2)

    print("\n== 18. dashboard ==")
    r = c.get(f"{V1}/progress/dashboard", headers=H)
    dash = r.json()
    check("dashboard populated", dash["greeting_name"] == "Alex" and dash["calories"]["consumed"] > 0)
    check("weekly progress present", dash["weekly_workouts"]["target"] == 4 and len(dash["weekly_workouts"]["days"]) == 7)
    check("records on the dashboard", len(dash["recent_records"]) > 0)
    check("goals on the dashboard", len(dash["active_goals"]) > 0)

    print("\n== 19. data export and privacy ==")
    r = c.get(f"{V1}/profile/export", headers=H)
    check("data export", r.status_code == 200 and "attachment" in r.headers["content-disposition"])
    check("export omits raw storage keys", "storage_key" not in r.text)
    check("export covers every domain", all(k in r.json() for k in
        ["workout_sessions", "body_weights", "meals", "goals", "progress_photos", "personal_records"]))

    print("\n== 20. admin ==")
    r = c.get(f"{V1}/admin/overview", headers=H)
    check("admin routes closed to users", r.status_code == 403)
    r = c.post(f"{V1}/auth/login", json={"email": "admin@fittrack.app", "password": "AdminFitTrack2024!"})
    AH = {"Authorization": f"Bearer {r.json()['access_token']}"}
    r = c.get(f"{V1}/admin/overview", headers=AH)
    check("admin overview", r.status_code == 200 and r.json()["total_users"] >= 2)
    r = c.get(f"{V1}/admin/users", headers=AH, params={"q": "reviewer"})
    uid = r.json()["items"][0]["id"]
    r = c.get(f"{V1}/admin/users/{uid}", headers=AH)
    check("admin sees photo counts", r.json()["progress_photo_count"] == 1)
    check("admin never sees photo URLs", "signature=" not in r.text and "storage_key" not in r.text)
    r = c.get(f"{V1}/progress/photos", headers=AH)
    check("admin cannot read another user's photos", r.json() == [])
    r = c.get(f"{V1}/admin/audit-logs", headers=AH, params={"action": "auth.register"})
    check("registration audited", r.json()["meta"]["total"] >= 1)
    r = c.get(f"{V1}/admin/health", headers=AH)
    check("system health", r.json()["database"] == "ok")

    print("\n== 21. demo account ==")
    r = c.post(f"{V1}/auth/login", json={"email": "demo@fittrack.app", "password": "FitTrack2024!"})
    check("demo sign-in", r.status_code == 200)
    DH = {"Authorization": f"Bearer {r.json()['access_token']}"}
    r = c.get(f"{V1}/progress/dashboard", headers=DH)
    check("demo dashboard has a weight trend", len(r.json()["weight_trend"]["points"]) > 10)
    r = c.get(f"{V1}/workout-sessions", headers=DH)
    check("demo has workout history", r.json()["meta"]["total"] > 20, str(r.json()["meta"]["total"]))
    r = c.get(f"{V1}/progress/charts/volume", headers=DH, params={"range": "3m"})
    check("demo volume chart has data", len(r.json()["series"][0]["points"]) > 10)
    r = c.get(f"{V1}/habits", headers=DH)
    check("demo habits with streaks", len(r.json()) == 4 and any(h["longest_streak"] > 3 for h in r.json()))

print(f"\n{'=' * 60}\n{len(passed)} passed, {len(failed)} failed")
if failed:
    print("FAILED:", ", ".join(failed))
    sys.exit(1)
