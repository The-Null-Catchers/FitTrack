<div align="center">

# FitTrack

**A fitness and nutrition platform — Flutter app, FastAPI backend, Next.js admin dashboard.**

Workouts, programs, nutrition, body metrics, goals, habits, progress analytics
and an AI coach, built offline-first.

[![CI](https://github.com/Archipelago-alt/FitTrack/actions/workflows/ci.yml/badge.svg)](https://github.com/Archipelago-alt/FitTrack/actions/workflows/ci.yml)

</div>

---

## Contents

- [What it does](#what-it-does)
- [Screenshots](#screenshots)
- [Architecture](#architecture)
- [Technology](#technology)
- [Repository layout](#repository-layout)
- [Running it](#running-it)
- [Demo account](#demo-account)
- [Database](#database)
- [API](#api)
- [Tests](#tests)
- [CI/CD](#cicd)
- [Security and privacy](#security-and-privacy)
- [Design decisions worth knowing](#design-decisions-worth-knowing)
- [Roadmap](#roadmap)

---

## What it does

**Train.** Build a program or clone one of six starter templates, then log a
workout set by set. Each exercise shows what you lifted last time, the target
copied from your plan, and a rest timer that keeps running when you put the
phone down. Warm-up, drop and failure sets are first-class. Swap an exercise
mid-session without losing the sets you already logged.

**Don't lose anything.** The workout in progress lives in SQLite on the device
and is written after every set, so closing the app — or losing signal entirely —
costs nothing. Changes made offline queue in an outbox keyed by a
client-generated id, which the server treats as an idempotency key: a retried
batch can't double-write.

**See the numbers move.** Personal records are detected automatically (max
weight, estimated 1RM, reps, volume, distance, time). Charts cover body weight,
training volume, frequency, per-exercise progression, measurements and
nutrition, over six time ranges.

**Eat deliberately.** Log meals against a 60-food catalogue or your own foods,
with macro rings, water tracking and calorie targets that are estimated from
your profile but never overwrite a manual choice.

**Get help.** FitCoach answers training questions and generates complete
programs from the real exercise library. It works with no API key configured,
and it routes anything that reads as pain, injury or a medical condition to a
qualified professional before any model is called.

Everything works in English and Arabic, light and dark.

## Screenshots

> Add screenshots to `docs/screenshots/` and reference them here.

| Home | Workout | Nutrition | Progress |
| --- | --- | --- | --- |
| _`docs/screenshots/home.png`_ | _`docs/screenshots/workout.png`_ | _`docs/screenshots/nutrition.png`_ | _`docs/screenshots/progress.png`_ |

Run `docker compose up -d && docker compose run --rm api seed --demo`, sign in
as the demo user, and every screen is populated with twelve weeks of history.

## Architecture

```mermaid
graph TB
    subgraph clients["Clients"]
        mobile["Flutter app<br/><small>iOS · Android</small>"]
        admin["Next.js admin<br/><small>operators</small>"]
    end

    subgraph edge["Edge"]
        nginx["nginx<br/><small>TLS · rate limiting</small>"]
    end

    subgraph services["Services"]
        api["FastAPI<br/><small>REST · OpenAPI</small>"]
        worker["arq worker<br/><small>reminders · cleanup</small>"]
    end

    subgraph data["Data"]
        pg[("PostgreSQL<br/><small>34 tables</small>")]
        redis[("Redis<br/><small>rate limits · queue</small>")]
        s3[("S3-compatible<br/><small>photos · media</small>")]
    end

    subgraph providers["Swappable providers"]
        ai["AI<br/><small>mock · Anthropic · OpenAI</small>"]
        email["Email<br/><small>console · SMTP</small>"]
        push["Push<br/><small>console · FCM</small>"]
    end

    mobile -->|"HTTPS + JWT"| nginx
    admin -->|"HTTPS + JWT"| nginx
    nginx --> api
    api --> pg
    api --> redis
    api --> s3
    api -.->|"enqueue"| redis
    redis -.->|"dequeue"| worker
    worker --> pg
    worker --> s3
    api --> ai
    worker --> email
    worker --> push

    mobile -.->|"outbox replay<br/>on reconnect"| nginx
```

### The offline path

The mobile client is not a thin view over the API; it owns the workout while it
is happening.

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant A as Flutter app
    participant D as SQLite (device)
    participant S as FastAPI

    U->>A: Start workout
    A->>D: Save session (client_uuid)
    A--)S: POST /workout-sessions (best effort)
    S--)A: previous performance + progression hints

    loop Every set
        U->>A: Enter weight and reps, tap ✓
        A->>D: Persist immediately
        Note over A: Volume and estimated 1RM<br/>computed on device
    end

    U->>A: Finish
    alt Online
        A->>S: POST /finish with all sets
        S-->>A: Session + personal records
    else Offline
        A->>D: Queue in outbox
        Note over A,D: Nothing is lost
        A->>S: POST /sync/push on reconnect
        S-->>A: applied | duplicate per operation
    end
```

Because every queued operation carries the id the device generated, the server
can tell a genuine change from a replay. Pushing the same batch twice is safe
by construction, not by luck.

More detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Technology

| Layer | Choice | Why |
| --- | --- | --- |
| Mobile | Flutter, Riverpod, GoRouter, Dio, sqflite, fl_chart | One codebase; Riverpod keeps state testable without a widget tree |
| Backend | FastAPI, SQLAlchemy 2.0 (async), Alembic, Pydantic v2 | Async end to end; typed schemas that double as the OpenAPI contract |
| Database | PostgreSQL 16 | Real constraints and indexes; portable column types let the suite run on SQLite |
| Cache / queue | Redis 7, arq | Rate limiting, caches and the job queue on one dependency |
| Storage | S3-compatible (MinIO locally) | Signed URLs for private content |
| Admin | Next.js 14 (App Router), TypeScript, Tailwind, TanStack Query | Server-rendered shell, cached client queries |
| AI | Provider abstraction: local, Anthropic, OpenAI | The product must work with no API key |
| Infra | Docker, docker compose, nginx, GitHub Actions | One command to a working stack |

## Repository layout

```
fittrack/
├── apps/
│   ├── mobile/           Flutter client
│   │   ├── lib/core/     theme, router, network, database, widgets
│   │   ├── lib/features/ domain · data · application · presentation
│   │   ├── lib/l10n/     app_en.arb, app_ar.arb
│   │   └── test/         unit, DAO, widget and controller tests
│   └── admin/            Next.js admin dashboard
├── services/
│   ├── api/              FastAPI service
│   │   ├── app/models/       SQLAlchemy (34 tables)
│   │   ├── app/schemas/      Pydantic request/response
│   │   ├── app/services/     business logic
│   │   ├── app/api/v1/       routers
│   │   ├── app/ai/           provider abstraction, safety layer, planner
│   │   ├── app/jobs/         background tasks
│   │   ├── app/seeds/        exercises, foods, templates, demo data
│   │   ├── alembic/          migrations
│   │   └── tests/            167 tests
│   └── worker/           runs the API image with the worker entrypoint
├── infra/
│   ├── docker/           production compose overlay
│   └── nginx/            TLS termination, rate limiting, routing
├── docs/                 architecture and API notes
├── .github/workflows/    CI and release pipelines
└── docker-compose.yml
```

## Running it

### The whole stack

```bash
git clone https://github.com/Archipelago-alt/FitTrack.git
cd FitTrack
cp .env.example .env          # safe defaults; nothing secret is committed
docker compose up -d
docker compose run --rm api seed --demo
```

| Service | URL |
| --- | --- |
| API | <http://localhost:8000> |
| API docs | <http://localhost:8000/docs> |
| Admin dashboard | <http://localhost:3000> |
| MinIO console | <http://localhost:9001> |

The API waits for PostgreSQL, applies migrations and then serves. Nothing else
is needed.

### The API on its own

```bash
cd services/api
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

export DATABASE_URL="postgresql+asyncpg://fittrack:fittrack@localhost:5432/fittrack"
alembic upgrade head
python -m app.seeds --demo

uvicorn app.main:app --reload
```

### The mobile app

```bash
cd apps/mobile
./tool/bootstrap_platforms.sh     # generates android/ and ios/
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator's route to your machine. Use `localhost` on
the iOS simulator, or your LAN address on a physical device.

The platform folders are generated rather than committed: they contain a binary
Gradle wrapper, and everything that makes the app *this* app lives in `lib/`,
`test/` and `pubspec.yaml`.

### The admin dashboard

```bash
cd apps/admin
npm install
npm run dev     # http://localhost:3000
```

## Demo account

After `seed --demo`:

| Role | Email | Password |
| --- | --- | --- |
| User | `demo@fittrack.app` | `FitTrack2024!` |
| Admin | `admin@fittrack.app` | `AdminFitTrack2024!` |

The demo user has twelve weeks of workouts, weight and measurement history,
nutrition logs, habits with streaks and active goals — enough that every chart
and dashboard is populated the moment you sign in. The data is synthetic;
nothing real is ever seeded.

## Database

34 tables covering identity, training, nutrition, body metrics, habits, goals,
AI usage, notifications and audit.

```bash
cd services/api
alembic upgrade head                        # apply
alembic revision --autogenerate -m "..."    # create
alembic downgrade -1                        # roll back one
alembic check                               # fails if models and schema differ
```

`alembic check` runs in CI, so a model change without a migration cannot merge.

Columns use portable type decorators (`GUID`, JSON with a `JSONB` variant), which
is what lets the test suite run against in-memory SQLite while production runs
on PostgreSQL — same Python semantics, native types on each backend.

## API

Interactive docs at `/docs`, the schema at `/openapi.json`.

```
/api/v1/auth              register · login · refresh · reset · sessions · delete
/api/v1/profile           profile · onboarding · targets · avatar · export
/api/v1/exercises         library search, filters, custom exercises
/api/v1/programs          programs, templates, days, prescriptions
/api/v1/workout-sessions  start · log sets · finish · history · previous
/api/v1/personal-records  current bests and history
/api/v1/progress          dashboard · weight · measurements · photos · charts
/api/v1/nutrition         foods · meals · water · daily totals
/api/v1/habits            habits and completion logs
/api/v1/goals             goals with automatic progress
/api/v1/ai                FitCoach chat · plan generation · substitutions
/api/v1/notifications     notifications and preferences
/api/v1/sync              offline push and delta pull
/api/v1/admin             metrics · users · templates · audit · health
```

Every response follows one shape. Errors:

```json
{
  "error": {
    "code": "workout_in_progress",
    "message": "You already have a workout in progress. Finish or discard it first.",
    "details": { "session_id": "…" },
    "request_id": "…"
  }
}
```

Lists:

```json
{ "items": [], "meta": { "page": 1, "per_page": 20, "total": 0, "total_pages": 1, "has_next": false, "has_previous": false } }
```

Error messages are written for end users. No screen in this product shows
"Error 500".

## Tests

```bash
# Backend — 167 tests, no services required
cd services/api && pytest -q

# Mobile
cd apps/mobile && flutter test

# Admin
cd apps/admin && npm run typecheck && npm run lint && npm run build
```

Backend coverage includes registration and sign-in, refresh-token rotation and
replay detection, onboarding and target overrides, library permissions,
program cloning, the full workout flow (start → log → resume → finish → records),
warm-up sets never setting records, nutrition maths, habit streaks, goal
tracking, offline sync idempotency, photo privacy, admin permissions, the
progression rules and the AI safety layer.

Mobile tests cover the offline DAOs against real SQLite, the workout controller's
whole offline path, the rest timer, unit conversion, 1RM, error mapping,
English/Arabic parity and the set-logging row.

## CI/CD

**On every pull request** — backend lint, format and tests; migrations applied
against a real PostgreSQL with `alembic check` for drift; admin format,
typecheck, lint and build; Flutter format, analyze and test; both container
images built and the API image smoke-tested; compose files validated.

**On `main` and tags** — container images published to GHCR; a release APK and
AAB built and uploaded. Signing runs only when the keystore secrets exist, and
the key material is decoded at build time and deleted afterwards. No signing key
is ever committed.

## Security and privacy

- Passwords hashed with bcrypt (cost 12). A sign-in attempt for an unknown
  address spends the same time as a wrong password, so the endpoint can't be
  used to enumerate accounts.
- Short-lived access tokens with refresh-token rotation. Replaying a rotated
  token revokes every session for that account.
- Progress photos are private: stored under unguessable keys, served only
  through short-lived signed URLs, and stripped of EXIF (including GPS) on
  upload. Administrators see counts, never content.
- Rate limiting on auth, uploads and AI, backed by Redis and failing open so a
  degraded cache can't take the product down.
- Uploads validated on MIME type and size, re-encoded server-side, and written
  under a namespaced key that a crafted filename cannot escape.
- Structured logs with credentials, tokens and signed URLs redacted at the
  formatter, not at each call site.
- Audit log for every authentication event and administrative change.
- Account deletion is immediate from the user's side; a background job hard-
  deletes the data and stored objects 30 days later.
- Data export returns everything stored for an account as JSON — with signed
  download links for photos rather than raw storage paths.

## Design decisions worth knowing

**The product works without AI.** `AI_PROVIDER=mock` is the default and is not a
stub: plan generation is grounded in the real exercise library, filtered by the
user's equipment and experience, with goal-appropriate set and rep schemes. A
hosted model adds nuance to the coaching notes; it isn't load-bearing.

**Safety comes before the model.** Anything that reads as pain, injury,
medication or a medical condition is answered by the safety layer and never
reaches a provider. FitCoach separates general fitness information from anything
that belongs to healthcare, and says so.

**Progression is rules-based.** "Add 2.5 kg" comes from a deterministic engine —
two sessions at the top of the rep range, not at RPE 9.5+ — not from a model. It
is explainable, testable and always available. It only ever suggests.

**Estimates never overwrite choices.** Calorie and macro targets are estimated
from your profile, but the moment you set one by hand the estimate stops
recalculating. Re-adopting it is one explicit tap.

**Nothing in the app is codegen'd.** Models, JSON and localisation are written by
hand, so `pub get && test` is the whole setup and there's no generated code to
drift out of sync.

## Roadmap

- Apple Health and Google Fit import for steps and body composition
- Barcode scanning wired to an external food provider (the lookup endpoint and
  the provider seam already exist)
- Superset and circuit timing in the session UI
- Web dashboard for users, reusing the admin design system
- Social: shared programs and workout-based challenges
- Push delivery via FCM in production (provider and scheduling are in place)

---

## Licence

MIT. See [`LICENSE`](LICENSE).
