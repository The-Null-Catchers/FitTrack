#!/usr/bin/env bash
# Run the acceptance walk against the compose stack.
#
#   docker compose up -d
#   docker compose run --rm api seed --demo
#   ./scripts/acceptance.sh
set -euo pipefail

cd "$(dirname "$0")/.."

URL="${FITTRACK_URL:-http://localhost:8000}"

echo "Waiting for $URL ..."
for _ in $(seq 1 30); do
  if curl -fsS "$URL/health" > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

python3 -m pip install --quiet httpx pillow
FITTRACK_URL="$URL" python3 scripts/acceptance.py
