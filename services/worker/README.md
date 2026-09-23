# FitTrack Worker

The background worker is not a separate codebase: it runs the same image as the
API with a different entrypoint command, so models, services and configuration
can never drift between the two.

```bash
docker compose up -d worker          # as part of the stack
docker compose run --rm worker       # one-off
arq app.jobs.worker.WorkerSettings   # locally, from services/api
```

## What it runs

| Job | Schedule | Purpose |
| --- | --- | --- |
| `send_workout_reminders` | hourly | Nudges users whose reminder time has arrived and who haven't trained today |
| `send_habit_reminders` | hourly | Reminds about habits still unticked, with the streak at stake |
| `send_weekly_summaries` | Mondays 08:00 | Digest of the previous week's training |
| `refresh_goal_progress` | twice daily | Recomputes goal progress and missed deadlines |
| `close_stale_sessions` | daily 04:00 | Abandons workouts left running longer than 36 hours |
| `cleanup_expired_records` | daily 04:30 | Prunes expired tokens, revoked sessions, read notifications, old sync ledger rows |
| `purge_deleted_accounts` | daily 05:00 | Hard-deletes accounts soft-deleted 30+ days ago, including stored objects |
| `process_progress_photo` | on demand | Re-derives a thumbnail for a photo stored without one |

Reminder jobs run hourly and filter down to the users whose configured time
falls inside the current hour, rather than scheduling a cron entry per user.

Job definitions live in [`services/api/app/jobs/`](../api/app/jobs/).
