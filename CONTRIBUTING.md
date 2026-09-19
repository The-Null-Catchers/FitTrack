# Contributing

## Setup

```bash
cp .env.example .env
docker compose up -d
docker compose run --rm api seed --demo
```

## Before you push

```bash
cd services/api && ruff check app tests && ruff format app tests && pytest -q
cd apps/admin  && npm run format && npm run lint && npm run typecheck && npm run build
cd apps/mobile && dart format lib test && flutter analyze && flutter test
```

CI runs exactly these, plus the migration and Docker builds.

## Conventions

- **Layers.** Routers parse and delegate; services hold the rules; models hold
  the schema. A router that queries the database, or a service that imports
  `Request`, will be sent back.
- **Migrations.** Any model change needs `alembic revision --autogenerate`.
  `alembic check` runs in CI and fails on drift.
- **Errors users read.** Every message returned to a client is written for a
  person. If you find yourself writing "Error 500", stop.
- **Units.** Store metric. Convert at the edge.
- **Idempotency.** Anything a client can retry takes a `client_uuid`.
- **Tests.** New behaviour needs a test. Bug fixes need the test that fails
  without the fix.
- **No secrets.** `.env` is gitignored; `.env.example` holds placeholders only.

## Commit messages

Describe what changed and why, in the imperative. The body matters more than the
subject for anything non-obvious.
