<!-- ref: add/database/python/pymongo-async.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = MongoDB via PyMongo's native async driver (default MongoDB path). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + MongoDB (PyMongo async)

PyMongo's `AsyncMongoClient` with Pydantic models and a thin repository layer — no ODM, so the project stays on Python 3.14. Auth-stub completion is the sibling add-on `pymongo-async-auth.md`.

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

Pyright flags `api_settings = APISettings()` for required env fields; keep (or add) its `# pyright: ignore[reportCallIssue]`.

Ask the user to add both to `src/.env` (agent `.env` edits are blocked); document the placeholders in `src/.env.default`:

```
MONGODB_URL=mongodb://localhost:27017
MONGODB_DB_NAME=mydb
```

### M3. Create the Client

Run `TC_PART=leaf TC_LEAF=add/database/python/pymongo-async bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/python/pymongo-async/template/` (listed in `<skill-dir>/database/python/pymongo-async/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/database/mongo.py`** (plus an empty `src/database/__init__.py`):

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/database/mongo.py` by the copy step; do not re-type it.

### M4. Create a Model

Domain models are plain Pydantic models in **`src/models/`** — `id` is the hex string of Mongo's `_id`, set by the repository.

**`src/models/user.py`**:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/models/user.py` by the copy step; do not re-type it.

### M5. Create the Repositories

Create the `api/repositories/` directory (with an empty `__init__.py`) if it does not already exist.

**`src/api/repositories/base.py`**:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/api/repositories/base.py` by the copy step; do not re-type it.

**`src/api/repositories/user_repository.py`**:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/api/repositories/user_repository.py` by the copy step; do not re-type it.

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

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/api/schemas/request/user.py` by the copy step; do not re-type it.

**`src/api/schemas/response/user.py`** — no `hashed_password` field; `model_validate(..., from_attributes=True)` copies only declared fields:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/api/schemas/response/user.py` by the copy step; do not re-type it.

**`src/api/services/user_service.py`**:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/src/api/services/user_service.py` by the copy step; do not re-type it.

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

mongomock has no async API, so data-access tests use a real MongoDB. Add a dev-only service to **`docker-compose.yml`** (bound to loopback — this instance has no auth):

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

**`test/conftest.py`** — seed placeholder settings (CI has no `src/.env`) and build the client without `with` so unit tests never connect. Merge, keeping existing seeding and fixtures (`SECRET_KEY` and `auth_headers` from `templatecentral:add` (auth)):

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

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/test/test_integration/conftest.py` by the copy step; do not re-type it.

**`test/test_integration/test_users.py`**:

Copied verbatim from `<skill-dir>/database/python/pymongo-async/template/test/test_integration/test_users.py` by the copy step; do not re-type it.

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

- **Opt-in only** — add a database only on request.
- Never add Motor (deprecated) or mongomock (no async PyMongo support).
- Domain models in `src/models/`, data access in `src/api/repositories/`, `database/` holds connection infrastructure only.
- Keep `MONGODB_URL` in `src/.env` — NEVER hardcode credentials; leave TLS on outside dev.
- Never pass request dicts or query params into Mongo filters or update documents — typed scalars and `updatable_fields` only.
- Every list query is bounded (`find_many` clamps to `MAX_PAGE_SIZE`); paginate further with `templatecentral:add` (pagination).
- Create indexes in the lifespan (idempotent); uniqueness lives in the index, not in a find-then-insert check.
- Never return domain models directly — always a `response_model` schema without `hashed_password` (`model_validate(..., from_attributes=True)` copies only its declared fields).

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.
