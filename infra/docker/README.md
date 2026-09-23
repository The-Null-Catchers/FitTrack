# Infrastructure

| File | Purpose |
| --- | --- |
| [`../../docker-compose.yml`](../../docker-compose.yml) | Local stack: PostgreSQL, Redis, MinIO, API, worker, admin dashboard |
| [`docker-compose.prod.yml`](./docker-compose.prod.yml) | Single-host production overlay: pinned images, nginx, no bind mounts |
| [`../nginx/nginx.conf`](../nginx/nginx.conf) | TLS termination, rate limiting, routing between the API and the dashboard |

## Local

```bash
cp .env.example .env
docker compose up -d
docker compose run --rm api seed --demo
```

* API — <http://localhost:8000>, docs at `/docs`
* Admin dashboard — <http://localhost:3000>
* MinIO console — <http://localhost:9001>

## Production notes

* Set `JWT_SECRET` to a value from `openssl rand -hex 32`. The application
  refuses to be useful with the development default in any real deployment.
* Point `DATABASE_URL` at a managed PostgreSQL instance with automated backups;
  the compose `postgres` service is for development only.
* Set `CORS_ORIGINS` to your real origins — never `*`.
* Object storage should be a real bucket (S3, R2, Spaces). The `local` backend
  keeps files on the container filesystem and does not survive a redeploy.
* Run at least one `worker` replica; without it reminders, weekly summaries and
  cleanup never run.
* Migrations run automatically on API start. For zero-downtime deploys, run
  `docker compose run --rm api migrate` first and then roll the API.
