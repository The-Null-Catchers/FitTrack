# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# FitTrack API — multi-stage build.
# Dependencies are installed into a virtualenv in the builder stage so the
# runtime image carries no compilers and no build cache.
# ---------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY pyproject.toml ./
COPY app ./app

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip && pip install .


FROM python:3.11-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 fittrack

COPY --from=builder /opt/venv /opt/venv

WORKDIR /srv/app
COPY --chown=fittrack:fittrack app ./app
COPY --chown=fittrack:fittrack alembic ./alembic
COPY --chown=fittrack:fittrack alembic.ini pyproject.toml ./
COPY --chown=fittrack:fittrack docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /srv/app/var/storage && chown -R fittrack:fittrack /srv/app/var

USER fittrack
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["api"]
