<!-- ref: add/database/python/pymongo-async.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = MongoDB via PyMongo's native async driver (default MongoDB path). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + MongoDB (PyMongo async)

PyMongo's `AsyncMongoClient` with Pydantic models and a thin repository layer — no ODM, so the project stays on the scaffold's Python 3.14. Auth-stub completion lives in the sibling add-on `pymongo-async-auth.md`, which the router loads alongside this guide only when `templatecentral:add` (auth) ran first.

### M1. Install Dependencies

Add to `requirements.txt` (`AsyncMongoClient` does not exist before 4.13):

```
pymongo>=4.13
```

`email-validator` is also needed for `EmailStr` — skip if `templatecentral:add` (auth) already added it.

### M2. Add Configuration

Add to `APISettings` in **`src/core/config.py`** (`from pydantic import SecretStr`):

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    # SecretStr: the URL usually embeds credentials; keeps them out of repr()/logs.
    MONGODB_URL: SecretStr = Field(
        description="MongoDB connection URL — must be set in environment"
    )
    MONGODB_DB_NAME: str = Field(description="MongoDB database name")
```

Required fields make pyright flag `api_settings = APISettings()` (it cannot see pydantic-settings read them from the environment) — the scaffold's line already carries `# pyright: ignore[reportCallIssue]`; add it if missing.

Ask the user to add both to `src/.env` (agent edits to `.env` files are hook-blocked by design); document the placeholders in `src/.env.default`:

```
MONGODB_URL=mongodb://localhost:27017
MONGODB_DB_NAME=mydb
```

### M3. Create the Client

**`src/database/mongo.py`** (plus an empty `src/database/__init__.py`):

```python
from typing import Annotated, Any

from fastapi import Depends
from pymongo import AsyncMongoClient
from pymongo.asynchronous.database import AsyncDatabase

from core.config import api_settings, common_settings

_client: AsyncMongoClient[dict[str, Any]] | None = None


async def init_mongo() -> None:
    global _client
    _client = AsyncMongoClient(
        api_settings.MONGODB_URL.get_secret_value(),
        # Outside dev, require TLS (overrides any tls=false in the URL): a non-TLS
        # server fails the boot instead of receiving credentials in plaintext.
        tls=common_settings.ENVIRONMENT != "dev",
        # Surface an unreachable server in seconds, not the 30 s default per request.
        serverSelectionTimeoutMS=5000,
        tz_aware=True,
    )
    # The client connects lazily; ping so a bad URL fails the boot, not the first request.
    await _client.admin.command("ping")


async def close_mongo() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None


def get_db() -> AsyncDatabase[dict[str, Any]]:
    if _client is None:
        raise RuntimeError("MongoDB client not initialised — is the lifespan wired?")
    return _client[api_settings.MONGODB_DB_NAME]


DbDep = Annotated[AsyncDatabase[dict[str, Any]], Depends(get_db)]
```

### M4. Create a Model

Domain models are plain Pydantic models in **`src/models/`** — `id` is the hex string of Mongo's `_id`, set by the repository.

**`src/models/user.py`**:

```python
from datetime import UTC, datetime

from pydantic import BaseModel, Field


class User(BaseModel):
    id: str | None = None
    email: str
    name: str
    hashed_password: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
```

### M5. Create the Repositories

Create the `api/repositories/` directory (with an empty `__init__.py`) if it does not already exist.

**`src/api/repositories/base.py`**:

```python
from collections.abc import Mapping
from typing import Any

from bson import ObjectId
from pydantic import BaseModel
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

MAX_PAGE_SIZE = 100


class BaseRepository[T: BaseModel]:
    model: type[T]
    collection_name: str
    # update() writes only these keys, so a request body can never set
    # hashed_password or smuggle a "$" operator into the update document.
    updatable_fields: frozenset[str] = frozenset()

    def __init__(self, db: AsyncDatabase[dict[str, Any]]) -> None:
        self.collection = db[self.collection_name]

    def _to_model(self, doc: dict[str, Any]) -> T:
        doc["id"] = str(doc.pop("_id"))
        return self.model.model_validate(doc)

    async def find_by_id(self, id_: str) -> T | None:
        # A malformed id is "not found", not a 500 from bson.errors.InvalidId.
        if not ObjectId.is_valid(id_):
            return None
        doc = await self.collection.find_one({"_id": ObjectId(id_)})
        return self._to_model(doc) if doc else None

    async def find_many(self, *, limit: int = 20, skip: int = 0) -> list[T]:
        # Clamped here too, so no caller can load the whole collection into memory.
        limit = max(1, min(limit, MAX_PAGE_SIZE))
        cursor = self.collection.find({}).sort("_id", 1).skip(max(0, skip)).limit(limit)
        return [self._to_model(doc) async for doc in cursor]

    async def insert(self, entity: T) -> T:
        result = await self.collection.insert_one(
            entity.model_dump(by_alias=True, exclude={"id"})
        )
        return entity.model_copy(update={"id": str(result.inserted_id)})

    async def update(self, id_: str, changes: Mapping[str, Any]) -> T | None:
        rejected = changes.keys() - self.updatable_fields
        if rejected:
            raise ValueError(f"Fields not updatable: {sorted(rejected)}")
        if not ObjectId.is_valid(id_):
            return None
        if not changes:
            return await self.find_by_id(id_)
        doc = await self.collection.find_one_and_update(
            {"_id": ObjectId(id_)},
            {"$set": dict(changes)},
            return_document=ReturnDocument.AFTER,
        )
        return self._to_model(doc) if doc else None

    async def delete(self, id_: str) -> bool:
        if not ObjectId.is_valid(id_):
            return False
        result = await self.collection.delete_one({"_id": ObjectId(id_)})
        return result.deleted_count == 1
```

**`src/api/repositories/user_repository.py`**:

```python
from api.repositories.base import BaseRepository
from models.user import User


class UserRepository(BaseRepository[User]):
    model = User
    collection_name = "users"
    updatable_fields = frozenset({"name"})

    async def find_by_email(self, email: str) -> User | None:
        doc = await self.collection.find_one({"email": email})
        return self._to_model(doc) if doc else None

    async def ensure_indexes(self) -> None:
        # The unique index, not a find-then-insert check, is what stops duplicate
        # accounts under concurrent registrations.
        await self.collection.create_index("email", unique=True)
```

> **NoSQL injection:** build filters only from typed scalars (`{"email": email}` where `email: str` came through a Pydantic schema). Never pass a request dict — or `request.query_params` — into `find`/`find_one`/`update_*`: `{"email": {"$ne": ""}}` matches every document.

### M6. Wire into FastAPI Lifespan

Update **`src/app.py`** — if a lifespan already exists (e.g. from `templatecentral:add` (logging)), merge these calls into it:

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from api.repositories.user_repository import UserRepository
from database.mongo import close_mongo, get_db, init_mongo


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    try:
        await init_mongo()
        await UserRepository(get_db()).ensure_indexes()
        yield
    finally:
        # Also on a failed boot, so the client's monitor tasks never leak.
        await close_mongo()


# inside start_application():
app = FastAPI(lifespan=lifespan, title=common_settings.PROJECT_NAME, ...)
```

### M7. Schemas, Service, Router

**`src/api/schemas/request/user.py`**:

```python
from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class CreateUserRequest(BaseRequestSchema):
    email: EmailStr = Field(description="User email address.")
    name: str = Field(min_length=1, max_length=100, description="Display name.")
    password: str = Field(
        min_length=12, max_length=128, description="12-128 characters."
    )


class UpdateUserRequest(BaseRequestSchema):
    name: str | None = Field(default=None, min_length=1, max_length=100)
```

**`src/api/schemas/response/user.py`** — no `hashed_password` field; `model_validate(..., from_attributes=True)` copies only declared fields:

```python
from pydantic import Field

from api.schemas.base import BaseResponseSchema


class UserResponse(BaseResponseSchema):
    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="Display name.")
```

**`src/api/services/user_service.py`**:

```python
import asyncio
from typing import Any

from fastapi import HTTPException, status
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from api.repositories.user_repository import UserRepository
from api.schemas.request.user import CreateUserRequest, UpdateUserRequest
from core.security import hash_password
from models.user import User

type Db = AsyncDatabase[dict[str, Any]]


async def list_users(db: Db, *, limit: int, skip: int) -> list[User]:
    return await UserRepository(db).find_many(limit=limit, skip=skip)


async def get_user(db: Db, user_id: str) -> User:
    user = await UserRepository(db).find_by_id(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found."
        )
    return user


async def create_user(db: Db, payload: CreateUserRequest) -> User:
    # argon2 is ~100 ms of CPU: off the event loop, or it stalls every request.
    hashed = await asyncio.to_thread(hash_password, payload.password)
    user = User(email=payload.email, name=payload.name, hashed_password=hashed)
    try:
        return await UserRepository(db).insert(user)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Email already registered."
        ) from None


async def update_user(db: Db, user_id: str, payload: UpdateUserRequest) -> User:
    # exclude_none: an explicit `"name": null` would otherwise $set null and leave a
    # document that no longer validates as User.
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    user = await UserRepository(db).update(user_id, changes)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found."
        )
    return user
```

`core.security.hash_password` comes from `templatecentral:add` (auth). Without auth, create `src/core/security.py` with the argon2id `PasswordHasher` block from that guide (Step 3) and add `argon2-cffi` to `requirements.txt`.

**`src/api/routers/users.py`** (register it in `src/api/routes.py` and add a `USERS` tag to `APITags`). It has no auth of its own — keep it off any deployed environment until `pymongo-async-auth.md` Step C (or your own guard) protects it:

```python
from typing import Annotated

from fastapi import APIRouter, Path, Query, status

from api.schemas.request.user import CreateUserRequest, UpdateUserRequest
from api.schemas.response.user import UserResponse
from api.services import user_service
from database.mongo import DbDep

router = APIRouter(prefix="/users")

# Malformed ids get a 422 at the edge; well-formed unknown ids get the service's 404.
UserId = Annotated[str, Path(pattern=r"^[0-9a-fA-F]{24}$")]


@router.get("", response_model=list[UserResponse])
async def list_users(
    db: DbDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    skip: Annotated[int, Query(ge=0)] = 0,
) -> list[UserResponse]:
    users = await user_service.list_users(db, limit=limit, skip=skip)
    return [UserResponse.model_validate(u, from_attributes=True) for u in users]


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(db: DbDep, user_id: UserId) -> UserResponse:
    user = await user_service.get_user(db, user_id)
    return UserResponse.model_validate(user, from_attributes=True)


@router.post("", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(db: DbDep, payload: CreateUserRequest) -> UserResponse:
    user = await user_service.create_user(db, payload)
    return UserResponse.model_validate(user, from_attributes=True)


@router.patch("/{user_id}", response_model=UserResponse)
async def update_user(
    db: DbDep, user_id: UserId, payload: UpdateUserRequest
) -> UserResponse:
    user = await user_service.update_user(db, user_id, payload)
    return UserResponse.model_validate(user, from_attributes=True)
```

### M8. Local MongoDB and Tests

mongomock does not support PyMongo's async API, so data-access tests run against a real MongoDB. Add a dev-only service to **`docker-compose.yml`** (bound to loopback — this instance has no auth):

```yaml
services:
  mongo:
    image: mongo:8
    ports:
      - "127.0.0.1:27017:27017"
    volumes:
      - mongo-data:/data/db

volumes:
  mongo-data:
```

Add `"integration: needs a running MongoDB"` to `markers` in `pyproject.toml`.

**`test/conftest.py`** — settings are read at import and CI has no `src/.env`, so seed placeholders, and build the client without `with` so unit tests never open a MongoDB connection. Merge, don't overwrite: keep any seeding and fixtures already there (`SECRET_KEY` and `auth_headers` from `templatecentral:add` (auth)):

```python
"""Root conftest — shared fixtures available to all tests."""

import os
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("MONGODB_URL", "mongodb://localhost:27017")
os.environ.setdefault("MONGODB_DB_NAME", "app_test")


@pytest.fixture
def client() -> Generator[TestClient]:
    """FastAPI test client — without `with`, so the MongoDB lifespan does not run."""
    from app import app

    client = TestClient(app)
    yield client
    client.close()
```

**`test/test_integration/conftest.py`** (plus an empty `__init__.py`):

```python
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
        serverSelectionTimeoutMS=1000,  # localhost answers in ms; keeps skips fast
        tz_aware=True,
    )
    try:
        await client.admin.command("ping")
    except ServerSelectionTimeoutError:
        await client.close()
        # Skip on a laptop without Mongo; an explicitly configured URL (CI) must work.
        if EXPLICIT_URL:
            raise
        pytest.skip(
            "MongoDB not reachable on localhost:27017 — run `docker compose up -d mongo`"
        )
    db = client[f"test_{uuid4().hex}"]  # throwaway database per test
    await UserRepository(db).ensure_indexes()
    yield db
    await client.drop_database(db.name)
    await client.close()


@pytest.fixture
async def api(
    mongo_db: AsyncDatabase[dict[str, Any]],
) -> AsyncIterator[httpx2.AsyncClient]:
    # Same event loop as mongo_db (TestClient would run the app on another loop),
    # and ASGITransport skips the lifespan so the app never opens its own client.
    app.dependency_overrides[get_db] = lambda: mongo_db
    transport = httpx2.ASGITransport(app=app)
    async with httpx2.AsyncClient(
        transport=transport, base_url="http://test"
    ) as client:
        yield client
    app.dependency_overrides.clear()
```

**`test/test_integration/test_users.py`**:

```python
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
```

CI runs these only if MongoDB is available: add a `mongo:8` service to the test job in `.github/workflows/ci.yml` and set `MONGODB_TEST_URL=mongodb://localhost:27017`. `ci.yml` is harness-seeded — recompute its `origin_hash` in `.claude/harness.json` (harness-kit-finalize.md Step E) so `verify-harness.sh` accepts the change.

### M9. Validate

```bash
docker compose up -d mongo
ruff check src/ test/
pyright
python -m pytest test/ -q
```

Confirm all tests pass and the integration tests ran (not skipped).

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- Never add Motor (deprecated) or mongomock (no async PyMongo support).
- Domain models in `src/models/`, data access in `src/api/repositories/`, `database/` holds connection infrastructure only.
- Keep `MONGODB_URL` in `src/.env` — NEVER hardcode credentials; leave TLS on outside dev.
- Never pass request dicts or query params into Mongo filters or update documents — typed scalars and `updatable_fields` only.
- Every list query is bounded (`find_many` clamps to `MAX_PAGE_SIZE`); paginate further with `templatecentral:add` (pagination).
- Create indexes in the lifespan (idempotent); uniqueness lives in the index, not in a find-then-insert check.
- Never return domain models directly — always a `response_model` schema without `hashed_password` (`model_validate(..., from_attributes=True)` copies only its declared fields).

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
