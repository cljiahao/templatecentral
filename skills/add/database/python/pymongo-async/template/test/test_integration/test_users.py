from typing import Any

import httpx2
import pytest
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from api.repositories.user_repository import UserRepository
from models.user import User

pytestmark = pytest.mark.integration

Db = AsyncDatabase[dict[str, Any]]
FAKE_HASH = "placeholder-hash"  # repository tests never verify it


def make_user(email: str = "ada@example.com") -> User:
    return User(email=email, name="Ada", hashed_password=FAKE_HASH)


async def test_insert_round_trips_id(mongo_db: Db) -> None:
    repo = UserRepository(mongo_db)
    created = await repo.insert(make_user())
    found = await repo.find_by_id(created.id or "")
    assert found is not None
    assert (found.id, found.email) == (created.id, created.email)


async def test_malformed_id_is_not_found(mongo_db: Db) -> None:
    assert await UserRepository(mongo_db).find_by_id("not-an-object-id") is None


async def test_duplicate_email_is_rejected(mongo_db: Db) -> None:
    repo = UserRepository(mongo_db)
    await repo.insert(make_user())
    with pytest.raises(DuplicateKeyError):
        await repo.insert(make_user())


@pytest.mark.parametrize("field", ["hashed_password", "$where"])
async def test_update_rejects_fields_outside_allow_list(
    mongo_db: Db, field: str
) -> None:
    repo = UserRepository(mongo_db)
    created = await repo.insert(make_user())
    with pytest.raises(ValueError, match="not updatable"):
        await repo.update(created.id or "", {field: "x"})


async def test_find_many_pages(mongo_db: Db) -> None:
    repo = UserRepository(mongo_db)
    for i in range(3):
        await repo.insert(make_user(f"u{i}@example.com"))
    page = await repo.find_many(limit=2, skip=1)
    assert [u.email for u in page] == ["u1@example.com", "u2@example.com"]


async def test_create_user_hides_password_hash(api: httpx2.AsyncClient) -> None:
    body = {
        "email": "ada@example.com",
        "name": "Ada",
        "password": "correct-horse-battery",
    }
    r = await api.post("/users", json=body)
    assert r.status_code == 201
    assert set(r.json()) == {"id", "email", "name"}
    assert (await api.post("/users", json=body)).status_code == 409


async def test_get_user_validates_id(api: httpx2.AsyncClient) -> None:
    assert (await api.get("/users/not-an-id")).status_code == 422
    assert (await api.get("/users/" + "0" * 24)).status_code == 404
