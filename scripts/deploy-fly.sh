#!/usr/bin/env bash
# Deploy the FitTrack API to Fly.io with persistent Postgres and Redis.
#
#   FLY_API_TOKEN=... ./scripts/deploy-fly.sh
#
# Idempotent: every step checks for what it creates, so a re-run after a
# failure resumes rather than duplicating. No secret is ever written to a file
# or into the image — `fly secrets set` injects them at runtime.
set -euo pipefail

APP="${FLY_APP:-fittrack-api}"
REGION="${FLY_REGION:-iad}"
PG_APP="${APP}-db"
REDIS_NAME="${APP}-redis"
ORG="${FLY_ORG:-personal}"
VOLUME="fittrack_storage"
API_DIR="$(cd "$(dirname "$0")/../services/api" && pwd)"

command -v fly >/dev/null || { echo "fly not on PATH" >&2; exit 1; }
[[ -n "${FLY_API_TOKEN:-}" ]] || { echo "FLY_API_TOKEN is not set" >&2; exit 1; }

cd "$API_DIR"

step() { printf '\n=== %s ===\n' "$1"; }

step "Authentication"
fly auth whoami

step "Application"
if fly apps list | awk '{print $1}' | grep -qx "$APP"; then
  echo "$APP already exists."
else
  fly apps create "$APP" --org "$ORG"
fi

step "Postgres (persistent)"
if fly apps list | awk '{print $1}' | grep -qx "$PG_APP"; then
  echo "$PG_APP already exists."
else
  fly postgres create \
    --name "$PG_APP" \
    --org "$ORG" \
    --region "$REGION" \
    --initial-cluster-size 1 \
    --vm-size shared-cpu-1x \
    --volume-size 10
fi

# `fly postgres attach` sets DATABASE_URL as postgres://…, but this app needs
# the async driver in the DSN (config.py reads DATABASE_URL directly and
# strips +asyncpg only for Alembic). Attach, then rewrite the scheme.
step "Attaching Postgres"
if fly secrets list --app "$APP" 2>/dev/null | grep -q '^DATABASE_URL'; then
  echo "DATABASE_URL already set."
else
  fly postgres attach "$PG_APP" --app "$APP" --yes
fi

step "Rewriting DATABASE_URL for asyncpg"
RAW_DSN="$(fly ssh console --app "$APP" -C 'printenv DATABASE_URL' 2>/dev/null | tr -d '\r' || true)"
if [[ -z "$RAW_DSN" ]]; then
  echo "Could not read DATABASE_URL from a running machine." >&2
  echo "Set it by hand once the app has booted:" >&2
  echo "  fly secrets set --app $APP DATABASE_URL='postgresql+asyncpg://…'" >&2
else
  case "$RAW_DSN" in
    postgresql+asyncpg://*) echo "Already an asyncpg DSN." ;;
    postgres://*|postgresql://*)
      ASYNC_DSN="postgresql+asyncpg://${RAW_DSN#*://}"
      fly secrets set --app "$APP" --stage "DATABASE_URL=$ASYNC_DSN"
      echo "DATABASE_URL rewritten to the asyncpg scheme (staged)."
      ;;
    *) echo "Unrecognised DSN scheme; leaving it alone." >&2 ;;
  esac
fi

step "Redis (persistent)"
if fly redis list 2>/dev/null | grep -q "$REDIS_NAME"; then
  echo "$REDIS_NAME already exists."
else
  fly redis create --name "$REDIS_NAME" --org "$ORG" --region "$REGION" --no-replicas
fi
REDIS_URL="$(fly redis status "$REDIS_NAME" 2>/dev/null | grep -oE 'redis://[^ ]+' | head -1 || true)"
if [[ -n "$REDIS_URL" ]]; then
  fly secrets set --app "$APP" --stage "REDIS_URL=$REDIS_URL"
else
  echo "Could not read the Redis URL; set REDIS_URL by hand." >&2
fi

step "Application secrets (generated here, never stored)"
if fly secrets list --app "$APP" 2>/dev/null | grep -q '^JWT_SECRET'; then
  echo "JWT_SECRET already set; leaving it. Rotating it would sign every user out."
else
  fly secrets set --app "$APP" --stage \
    "JWT_SECRET=$(openssl rand -hex 32)" \
    "STORAGE_SIGNING_KEY=$(openssl rand -hex 32)"
fi

# Signed media URLs are minted for whatever host this names, so it has to be an
# address the phone can reach — not localhost, not an internal name.
fly secrets set --app "$APP" --stage \
  "APP_PUBLIC_URL=https://${APP}.fly.dev" \
  "STORAGE_PUBLIC_BASE_URL=https://${APP}.fly.dev/media" \
  "CORS_ORIGINS=https://${APP}.fly.dev"

step "Storage volume"
if fly volumes list --app "$APP" 2>/dev/null | grep -q "$VOLUME"; then
  echo "Volume $VOLUME already exists."
else
  fly volumes create "$VOLUME" --app "$APP" --region "$REGION" --size 3 --yes
fi

step "Deploy"
# --remote-only builds on Fly's builders: no local Docker daemon required.
# The entrypoint runs `alembic upgrade head` before uvicorn starts, so this
# deploy also migrates.
fly deploy --remote-only --app "$APP"

# SEED_DEMO=true adds demo@fittrack.app with 12 weeks of SYNTHETIC history, so
# the app has something to show on first launch. It is a known-password account
# on a public host — test instances only. See "Removing the demo account" in
# docs/DEPLOYMENT.md before this instance holds anything real.
if [[ "${SEED_DEMO:-false}" == "true" ]]; then
  step "Seed reference data and the demo account"
  fly ssh console --app "$APP" -C "docker-entrypoint.sh seed --demo"
else
  step "Seed reference data"
  fly ssh console --app "$APP" -C "docker-entrypoint.sh seed"
fi

step "Health"
curl -fsS "https://${APP}.fly.dev/health" && echo

cat <<EOF

Deployed: https://${APP}.fly.dev

Next, verify before trusting it:
  FITTRACK_URL=https://${APP}.fly.dev python scripts/acceptance.py
  cd apps/mobile && flutter test test/contract/live_api_contract_test.dart \\
    --dart-define=LIVE_API=true --dart-define=API_BASE_URL=https://${APP}.fly.dev

Then build the APK against it:
  flutter build apk --release --dart-define=API_BASE_URL=https://${APP}.fly.dev
EOF
