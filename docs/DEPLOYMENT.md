# Deploying FitTrack to Fly.io

The deployment runs from a manually triggered GitHub Actions workflow,
**Deploy to Fly** (`.github/workflows/deploy-fly.yml`). It never runs off a
push: deploying provisions billable resources and can reseed a live database.

## One-time setup

1. Create an org-scoped Fly token: `fly tokens create org`. Org scope is needed
   because the workflow creates apps, a Postgres cluster and a Redis database —
   not just deploy into an existing app.
2. Add it to the repository as an Actions secret named **`FLY_API_TOKEN`**
   (Settings → Secrets and variables → Actions → New repository secret).

The token exists only in GitHub. It is never stored in the repository, in a
developer environment, or in any chat transcript.

## Running a deployment

Actions → **Deploy to Fly** → *Run workflow*. Inputs:

| Input | Default | Meaning |
|---|---|---|
| `app_name` | `fittrack-api` | Also the hostname: `<app_name>.fly.dev` |
| `region` | `iad` | Fly region |
| `seed_demo` | `true` | Seed the demo account — **test instances only**, see below |
| `build_apk` | `true` | Build a release APK pointed at the deployed URL |

Three jobs run in order, and each stops the next if it fails:

1. **Deploy** — creates the app, an unmanaged Postgres cluster, an Upstash Redis
   database and a 3 GB volume; generates `JWT_SECRET` and `STORAGE_SIGNING_KEY`
   and sets them with `fly secrets`; deploys with `--remote-only`; seeds.
2. **Verify** — health check, then the 75-check acceptance walk against the
   deployed URL. The log is uploaded as the `acceptance-log` artifact.
3. **APK** — runs the live contract tests against the deployment, then builds
   the release APK with `--dart-define=API_BASE_URL=https://<app>.fly.dev`.

### Checking the result

- **Run summary** — each job writes to the run's summary page: the URL, the last
  lines of the acceptance output, and the APK details.
- **Artifacts** (bottom of the run page) — `fittrack-apk` is the installable
  build; `acceptance-log` is the full verification output.
- **Afterwards**: `fly status --app fittrack-api`, `fly logs --app fittrack-api`.

The APK is **debug-signed**. It installs for testing (enable
install-from-unknown-sources) and is not fit for any store.

## Secrets

Generated inside the deploy job and set with `fly secrets set`, which injects
them as environment variables at runtime:

| Secret | Source |
|---|---|
| `JWT_SECRET` | `openssl rand -hex 32`, generated once and then left alone |
| `STORAGE_SIGNING_KEY` | `openssl rand -hex 32`, HMAC key for signed `/media` URLs |
| `DATABASE_URL` | from `fly postgres attach`, rewritten to `postgresql+asyncpg://` |
| `REDIS_URL` | from `fly redis status` |

`JWT_SECRET` is deliberately not rotated on re-deploy: changing it invalidates
every refresh token and signs all users out.

`.dockerignore` excludes `.env` and `.env.*`, so local development secrets are
never sent to Fly's remote builder.

## The demo account — remove it before storing real data

With `seed_demo = true` the deployment gets:

```
demo@fittrack.app  / FitTrack2024!
admin@fittrack.app / AdminFitTrack2024!
```

Both are **published, known-password accounts on a public HTTPS host**, holding
12 weeks of synthetic, generated history. They exist so a fresh install has
something to show. They are appropriate for a throwaway test instance and
nowhere else.

**Before this instance holds any real personal data:**

1. Re-run the workflow with `seed_demo = false`, so a future deploy cannot
   recreate them.
2. Delete both accounts through the API. `delete-account` cascades to
   everything they own — workouts, nutrition, photos, habits, goals. There is
   no `--remove-demo` seeder flag; this is the supported path.

   The script below is the exact sequence used to verify this procedure
   against a live instance; both deletions succeeded and both subsequent
   logins returned 401.

   ```bash
   BASE=https://fittrack-api.fly.dev

   for acct in "demo@fittrack.app:FitTrack2024!" \
               "admin@fittrack.app:AdminFitTrack2024!"; do
     EMAIL="${acct%%:*}"; PW="${acct#*:}"

     TOKEN=$(curl -sS -X POST "$BASE/api/v1/auth/login" \
       -H 'Content-Type: application/json' \
       -d "{\"email\":\"$EMAIL\",\"password\":\"$PW\"}" \
       | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

     # `confirmation` must be exactly "DELETE"; the endpoint rejects anything else.
     curl -sS -X POST "$BASE/api/v1/auth/delete-account" \
       -H "Authorization: Bearer $TOKEN" \
       -H 'Content-Type: application/json' \
       -d "{\"password\":\"$PW\",\"confirmation\":\"DELETE\"}"
   done
   ```

3. Confirm they are gone — a login attempt must now fail:

   ```bash
   for EMAIL in demo@fittrack.app admin@fittrack.app; do
     curl -s -o /dev/null -w "$EMAIL -> %{http_code}\n" \
       -X POST "$BASE/api/v1/auth/login" \
       -H 'Content-Type: application/json' \
       -d "{\"email\":\"$EMAIL\",\"password\":\"x\"}"
   done
   # expect 401 for both
   ```

4. Rotate `JWT_SECRET` at the same time, so any token minted for the demo
   accounts stops working:
   `fly secrets set --app fittrack-api JWT_SECRET=$(openssl rand -hex 32)`

A test instance that has been through the steps above is still not a production
deployment — see the caveats below.

## FitCoach runs on canned responses

`AI_PROVIDER=mock` is set in `fly.toml`. These endpoints return written,
templated text, not model output:

- `/api/v1/ai/chat`
- `/api/v1/ai/plans/generate`
- `/api/v1/ai/progress-summary`
- `/api/v1/ai/substitutions`

Two things are **not** mocked and behave identically either way:

- **The safety layer**, which runs *before* any provider call. Injury, pain and
  medical messages never reach a model and get a fixed redirect to professional
  care.
- **Workout plan generation**, which is deterministic and rules-based, built
  from the seeded exercise library.

For real responses: `fly secrets set --app fittrack-api AI_PROVIDER=anthropic
AI_API_KEY=<key>`. Nothing else changes.

## Known limits of this setup

- **Single machine.** A Fly volume attaches to exactly one machine, and the
  entrypoint migrates on boot, so concurrent machines would race. Scaling out
  means moving storage to Tigris/S3 (`STORAGE_BACKEND=s3`) and running
  migrations as a release step instead.
- **Unmanaged Postgres.** `fly postgres` is unsupported by Fly and you own
  backups and recovery. `fly mpg` (Managed Postgres) is the supported option and
  costs substantially more.
- **Debug-signed APK.** Fine for sideloading; a real release needs its own
  keystore, which must never be committed.
