"""Shared pytest fixtures.

Tests run against an in-memory SQLite database so the suite needs no services
in CI. The portable column types in ``app.db.types`` keep model behaviour
identical to PostgreSQL.
"""

from __future__ import annotations

import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
os.environ.setdefault("STORAGE_BACKEND", "local")
os.environ.setdefault("AI_PROVIDER", "mock")
os.environ.setdefault("JWT_SECRET", "test-secret-not-used-anywhere-real")

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import (  # noqa: E402
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.deps import get_db  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.main import app as fastapi_app  # noqa: E402
from app.models import Base  # noqa: E402
from app.models.enums import UserRole  # noqa: E402
from app.models.notification import NotificationPreference  # noqa: E402
from app.models.user import User, UserProfile  # noqa: E402

TEST_PASSWORD = "TestPass123!"


@pytest.fixture
async def engine() -> AsyncIterator:
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session_factory(engine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


@pytest.fixture
async def db(session_factory) -> AsyncIterator[AsyncSession]:
    async with session_factory() as session:
        yield session


@pytest.fixture
async def client(session_factory) -> AsyncIterator[AsyncClient]:
    async def override_get_db() -> AsyncIterator[AsyncSession]:
        async with session_factory() as session:
            yield session

    fastapi_app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as http:
        yield http
    fastapi_app.dependency_overrides.clear()


async def _make_user(
    db: AsyncSession, *, email: str, full_name: str, role: str = UserRole.USER
) -> User:
    user = User(
        email=email,
        password_hash=hash_password(TEST_PASSWORD),
        full_name=full_name,
        role=role,
        email_verified_at=datetime.now(UTC),
    )
    user.profile = UserProfile(user_id=user.id)
    user.notification_preference = NotificationPreference(user_id=user.id)
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest.fixture
async def user(db) -> User:
    return await _make_user(db, email="rider@example.com", full_name="Alex Rider")


@pytest.fixture
async def admin_user(db) -> User:
    return await _make_user(
        db, email="admin@example.com", full_name="Admin User", role=UserRole.ADMIN
    )


async def _login(client: AsyncClient, email: str) -> str:
    response = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": TEST_PASSWORD}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture
async def auth_headers(client, user) -> dict[str, str]:
    token = await _login(client, user.email)
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def admin_headers(client, admin_user) -> dict[str, str]:
    token = await _login(client, admin_user.email)
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def seeded_library(db):
    """The public exercise library, foods and starter templates."""
    from app.seeds.seeder import seed_reference_data

    await seed_reference_data(db)
    return True
