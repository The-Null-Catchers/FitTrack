# API

Base URL `/api/v1`. Interactive docs at `/docs`, schema at `/openapi.json`.

---

## Conventions

### Authentication

All endpoints require `Authorization: Bearer <access_token>` except
`/health`, `/ready`, the auth endpoints below, and the public parts of the
exercise library and template list.

Access tokens last 15 minutes. Rotate with `/auth/refresh`; the old refresh
token is immediately invalid. **Replaying a rotated refresh token revokes every
session for that account** — it is treated as a possible theft, not a mistake.

### Errors

```json
{
  "error": {
    "code": "workout_in_progress",
    "message": "You already have a workout in progress. Finish or discard it first.",
    "details": { "session_id": "5f3c…" },
    "request_id": "8a1b…"
  }
}
```

`message` is written for end users and can be shown as-is. `code` is stable and
safe to branch on. `request_id` also comes back in the `X-Request-ID` header and
appears in the server logs.

| Status | Typical `code` |
| --- | --- |
| 400 | `bad_request` |
| 401 | `unauthenticated`, `invalid_credentials`, `token_expired`, `token_reused` |
| 403 | `forbidden`, `account_suspended` |
| 404 | `not_found` |
| 409 | `conflict`, `email_taken`, `workout_in_progress` |
| 422 | `validation_error` (with `details.fields`) |
| 429 | `rate_limited` (with `Retry-After`) |
| 503 | `service_unavailable` |

### Pagination

```json
{
  "items": [],
  "meta": { "page": 1, "per_page": 20, "total": 0, "total_pages": 1, "has_next": false, "has_previous": false }
}
```

Query with `?page=1&per_page=20` (max 100).

### Units

Every weight is kilograms, every length centimetres, every distance metres,
every duration seconds. Unit preference is a client display concern.

### Time ranges

Chart and analytics endpoints take `?range=` one of `7d`, `30d`, `3m`, `6m`,
`1y`, `all`.

---

## Authentication

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/auth/register` | Returns tokens and the user. Rate limited. |
| POST | `/auth/login` | Identical response for unknown email and wrong password. |
| POST | `/auth/refresh` | Rotates the refresh token. |
| POST | `/auth/logout` | `all_devices` revokes every session. |
| POST | `/auth/forgot-password` | Always 200 — never confirms whether an account exists. |
| POST | `/auth/reset-password` | Single-use token; revokes all sessions. |
| POST | `/auth/verify-email` | |
| POST | `/auth/resend-verification` | |
| POST | `/auth/change-password` | |
| GET | `/auth/sessions` | Signed-in devices. |
| DELETE | `/auth/sessions/{id}` | Revoke one device. |
| POST | `/auth/delete-account` | Requires `confirmation: "DELETE"`. |

```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo@fittrack.app","password":"FitTrack2024!"}'
```

## Profile

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/profile` | Current user with the fitness profile. |
| PATCH | `/profile` | Name, locale, timezone, theme. |
| PATCH | `/profile/fitness` | Goal, level, equipment, height, weight. |
| POST | `/profile/onboarding` | Everything the wizard collects, in one call. |
| GET | `/profile/nutrition-targets/estimate` | Informational; carries a disclaimer. |
| PUT | `/profile/nutrition-targets` | A manual value pins the targets. |
| POST | `/profile/nutrition-targets/use-estimate` | Explicitly re-adopt the estimate. |
| POST | `/profile/avatar` | `multipart/form-data`. |
| GET | `/profile/export` | Full JSON export, `Content-Disposition: attachment`. |
| GET | `/profile/statistics` | Counts of everything stored. |

## Exercises

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/exercises` | `q`, `muscle_group`, `equipment`, `difficulty`, `exercise_type`, `sort`. |
| GET | `/exercises/filters` | Every valid filter value. |
| GET | `/exercises/{id}` | Detail with instructions and media. |
| POST | `/exercises` | Creates a **private** exercise. |
| PATCH/DELETE | `/exercises/{id}` | Only your own. |

Custom exercises are visible only to their creator. Publishing to the shared
library is an admin action.

## Programs

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/programs` | Yours, optionally including templates. |
| GET | `/programs/templates` | Six curated starter plans. |
| GET | `/programs/active` | The active plan, or `null`. |
| POST | `/programs` | Create with days and prescriptions. |
| POST | `/programs/{id}/duplicate` | Clone a template or your own plan. |
| POST | `/programs/{id}/activate` | Archives the previously active plan. |
| POST | `/programs/{id}/archive` | |
| POST | `/programs/{id}/days` | |
| POST | `/programs/days/{id}/exercises` | |
| POST | `/programs/days/{id}/exercises/reorder` | Ordered id list. |
| PATCH/DELETE | `/programs/day-exercises/{id}` | |

Exactly one program can be active at a time.

## Workouts

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/workout-sessions/active` | The in-progress session — what "resume" loads. |
| GET | `/workout-sessions` | History. Filter by date range or exercise. |
| POST | `/workout-sessions` | Start. Idempotent on `client_uuid`. |
| GET | `/workout-sessions/{id}` | Detail with previous performance and progression hints. |
| POST | `/workout-sessions/{id}/finish` | Returns the session plus any records set. |
| POST | `/workout-sessions/{id}/discard` | |
| POST | `/workout-sessions/{id}/duplicate` | Repeat a past workout. |
| POST | `/workout-sessions/{id}/exercises` | Add mid-session. |
| POST | `/workout-sessions/exercises/{id}/replace` | Keeps position and logged sets. |
| POST | `/workout-sessions/exercises/{id}/sets` | Log a set. |
| PUT/DELETE | `/workout-sessions/sets/{id}` | |
| GET | `/personal-records` | Current bests, or full history. |

Starting with a `client_uuid` you have used before returns the existing session
rather than creating a second one — which is what makes an offline retry safe.

## Progress

| Method | Path |
| --- | --- |
| GET | `/progress/dashboard` |
| GET | `/progress/summary` |
| GET/POST/DELETE | `/progress/weights` |
| GET/POST/DELETE | `/progress/measurements` |
| GET/POST/PATCH/DELETE | `/progress/photos` |
| GET | `/progress/photos/compare?before_id=&after_id=` |
| GET | `/progress/charts/weight` · `volume` · `nutrition` · `measurements` |
| GET | `/progress/exercises` · `/progress/exercises/{id}` |
| GET | `/progress/overview` |

Photo responses contain short-lived signed URLs. A raw storage key is never
returned.

## Nutrition

| Method | Path |
| --- | --- |
| GET | `/nutrition/day?on=YYYY-MM-DD` |
| GET | `/nutrition/range?start_date=&end_date=` |
| GET | `/nutrition/foods` · `/foods/recent` · `/foods/barcode/{barcode}` |
| POST/PATCH/DELETE | `/nutrition/foods` |
| POST | `/nutrition/foods/{id}/favorite` |
| GET/POST/PATCH/DELETE | `/nutrition/meals` |
| POST | `/nutrition/water` |

Catalogue foods are priced server-side from grams — a client cannot invent the
calories for a known food.

## Habits and goals

| Method | Path |
| --- | --- |
| GET/POST/PATCH/DELETE | `/habits` |
| POST/DELETE | `/habits/{id}/log` |
| GET | `/habits/{id}/history` |
| GET/POST/PATCH/DELETE | `/goals` |

Goal progress is recomputed from the domain that owns it — body weight from
weigh-ins, strength goals from personal records, frequency from completed
sessions.

## FitCoach

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/ai/chat` | Rate limited; returns a standing disclaimer. |
| GET/DELETE | `/ai/conversations` · `/ai/conversations/{id}` | |
| POST | `/ai/plans/generate` | **Preview only** — nothing is written. |
| POST | `/ai/plans/save` | Creates a new program; never overwrites. |
| POST | `/ai/substitutions` | Alternatives for available equipment. |
| GET | `/ai/progress-summary` | Plain-language read of your own numbers. |
| GET | `/ai/usage` | Today's usage against the quota. |

Messages that read as pain, injury, medication or a medical condition are
answered by the safety layer with `safety_redirect: true` and never reach a
model.

## Sync

| Method | Path |
| --- | --- |
| POST | `/sync/push` |
| GET | `/sync/pull?since=<ISO8601>` |

```json
{
  "operations": [
    {
      "client_uuid": "weight-1710000000",
      "entity": "body_weight",
      "operation": "create",
      "payload": { "recorded_on": "2026-03-14", "weight_kg": 82.4 }
    }
  ]
}
```

Each result comes back as `applied`, `duplicate`, `conflict` or `failed`, with a
message. One failing operation does not abort the batch.

Supported entities: `workout_session`, `body_weight`, `body_measurement`,
`meal`, `water_log`, `habit_log`.

When pulling, URL-encode the `since` timestamp — a `+` in a query string is a
space. Use the `server_time` from the previous pull as the next `since`.

## Admin

Every route requires the `admin` role.

| Method | Path |
| --- | --- |
| GET | `/admin/overview` |
| GET | `/admin/users` · `/admin/users/{id}` |
| PATCH | `/admin/users/{id}` |
| POST/PATCH | `/admin/exercises` |
| GET | `/admin/templates` · POST `/admin/templates/{id}/feature` |
| GET | `/admin/ai-usage` · `/admin/storage` · `/admin/health` · `/admin/audit-logs` |

Admin endpoints return aggregates and counts. There is no admin route that
returns a user's progress photos, meals or FitCoach conversations.

## Health

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/health` | Liveness. Always 200 while the process is up. |
| GET | `/ready` | Readiness. 503 when the database is unreachable. |

Redis and storage are reported in `/ready` but do not fail it: the API degrades
rather than refusing traffic when a soft dependency is down.
