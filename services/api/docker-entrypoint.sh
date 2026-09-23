#!/usr/bin/env bash
# Entrypoint for both the API and the worker.
#
#   api     run migrations, then serve with uvicorn
#   worker  run the arq worker
#   seed    load reference data (add --demo for the demo account)
set -euo pipefail

wait_for_database() {
  local attempts=${DB_WAIT_ATTEMPTS:-30}
  for ((i = 1; i <= attempts; i++)); do
    if python -c "
import asyncio, sys
from sqlalchemy import text
from app.db.session import engine

async def check() -> None:
    async with engine.connect() as connection:
        await connection.execute(text('SELECT 1'))

try:
    asyncio.run(check())
except Exception:
    sys.exit(1)
" 2>/dev/null; then
      return 0
    fi
    echo "Waiting for the database (${i}/${attempts})..."
    sleep 2
  done
  # Re-run once with stderr shown: the loop above hides it, so a configuration
  # error that can never succeed is otherwise indistinguishable from a database
  # that is simply slow to accept connections.
  echo "Database did not become available in time. Last error:" >&2
  python -c "
import asyncio
from sqlalchemy import text
from app.db.session import engine

async def check() -> None:
    async with engine.connect() as connection:
        await connection.execute(text('SELECT 1'))

asyncio.run(check())
" >&2 || true
  return 1
}

case "${1:-api}" in
  api)
    wait_for_database
    echo "Applying migrations..."
    alembic upgrade head
    exec uvicorn app.main:app \
      --host 0.0.0.0 \
      --port 8000 \
      --workers "${WEB_CONCURRENCY:-2}" \
      --proxy-headers \
      --forwarded-allow-ips '*'
    ;;
  worker)
    wait_for_database
    exec arq app.jobs.worker.WorkerSettings
    ;;
  seed)
    wait_for_database
    shift
    exec python -m app.seeds "$@"
    ;;
  migrate)
    wait_for_database
    exec alembic upgrade head
    ;;
  *)
    exec "$@"
    ;;
esac
