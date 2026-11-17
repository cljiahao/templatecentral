import os
from collections.abc import AsyncIterator
from typing import Any
from uuid import uuid4

import httpx2
import pytest
from pymongo import AsyncMongoClient
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import ServerSelectionTimeoutError

from api.repositories.user_repository import UserRepository
from app import app
from database.mongo import get_db

EXPLICIT_URL = os.environ.get("MONGODB_TEST_URL")


@pytest.fixture
async def mongo_db() -> AsyncIterator[AsyncDatabase[dict[str, Any]]]:
    client: AsyncMongoClient[dict[str, Any]] = AsyncMongoClient(
        EXPLICIT_URL or "mongodb://localhost:27017",
        serverSelectionTimeoutMS=1000,
        tz_aware=True,
    )
    try:
        await client.admin.command("ping")
    except ServerSelectionTimeoutError:
        await client.close()
        # Skip when no Mongo is reachable, but an explicitly configured URL must work.
        if EXPLICIT_URL:
            raise
        pytest.skip(
            "MongoDB not reachable on localhost:27017 — run `docker compose up -d mongo`"
        )
    db = client[f"test_{uuid4().hex}"]
    await UserRepository(db).ensure_indexes()
    yield db
    await client.drop_database(db.name)
    await client.close()


@pytest.fixture
async def api(
    mongo_db: AsyncDatabase[dict[str, Any]],
) -> AsyncIterator[httpx2.AsyncClient]:
    # Same event loop as mongo_db; ASGITransport skips the lifespan so the app opens no client.
    app.dependency_overrides[get_db] = lambda: mongo_db
    transport = httpx2.ASGITransport(app=app)
    async with httpx2.AsyncClient(
        transport=transport, base_url="http://test"
    ) as client:
        yield client
    app.dependency_overrides.clear()
