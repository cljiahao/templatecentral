<!-- ref: add/database/python/beanie.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = Beanie (MongoDB async ODM) — explicit opt-in only; the default MongoDB path is pymongo-async.md. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + Beanie (MongoDB)

### B0. Opt-in gate — Beanie pins the project to Python 3.13

The default MongoDB path is PyMongo async — `cat "<skill-dir>/database/python/pymongo-async.md"` — which runs on the scaffold's Python 3.14. Continue here only if the user explicitly wants the Beanie ODM **and** accepts the Python 3.13 pin below.

Every Beanie release from 2.0.1 through 2.2.0 declares `Requires-Python <3.14`. The cap is a maintainer decision pending Beanie v3 (no release date) — see BeanieODM/beanie#1257, #1362 (the PR lifting it, closed unmerged) and #1373 — not a reproduced failure: models, `Link`/`BackLink`, inserts and queries showed no breakage on 3.14, but `fetch_links` and migrations are untested, and installing past `Requires-Python` is unsupported. Never force it with `--ignore-requires-python`. First check whether a newer release lifted the cap:

```bash
python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('https://pypi.org/pypi/beanie/json'))['info']['requires_python'])"
```

If it no longer excludes 3.14, skip the checklist (if that release is 3.x, raise the `<3` ceiling in B1 only after checking its breaking changes against this guide). If it still prints `<3.14`, confirm the trade-off with the user, then **pin this project to Python 3.13** (security-fixes-only upstream until 2029-10): set `ARG PYTHON=python:3.13.16-slim` in the `Dockerfile`, `target-version = "py313"` in `pyproject.toml`, `"pythonVersion": "3.13"` in `pyrightconfig.json`, `python-version: "3.13"` in every setup-python step (`.github/workflows/ci.yml`, and `mutation.yml` if present), update the `Python 3.14` entry in AGENTS.md `## Stack`, then recreate the venv with `python3.13 -m venv .venv` and reinstall `requirements.txt` + `requirements-dev.txt`. Revert to 3.14 once Beanie supports it. `ci.yml` is a harness-seeded file: recompute its `origin_hash` in `.claude/harness.json` (harness-kit-finalize.md Step E) so `verify-harness.sh` accepts the change, and re-apply the 3.13 pin if a `templatecentral:migrate` re-sync rewrites `ci.yml`.

### B1. Install Dependencies

Add to `requirements.txt` — floors match the templateCentral plugin's `.claude/rules/fastapi.md`. The `beanie` floor makes a 3.14 venv fail loudly instead of silently resolving 2.0.0 (the only 2.x release without the cap); the `pymongo` floor is a hard requirement: `AsyncMongoClient` does not exist before 4.13, so an older PyMongo breaks the import in Step B2 below.

```
beanie>=2.2,<3
pymongo>=4.13
```

> **Beanie** is an async ODM for MongoDB built on PyMongo's async API and Pydantic v2. It integrates natively with FastAPI's Pydantic ecosystem. Beanie 2.x is built on PyMongo's native async client (`AsyncMongoClient`) — Motor is deprecated and must NOT be added as a dependency.

### B2. Create MongoDB Connection

**`src/database/mongo.py`**:

```python
from beanie import init_beanie
from pymongo import AsyncMongoClient

from core.config import api_settings

mongo_client: AsyncMongoClient | None = None


async def init_mongo() -> None:
    global mongo_client
    mongo_client = AsyncMongoClient(api_settings.MONGODB_URL)
    db = mongo_client[api_settings.MONGODB_DB_NAME]

    from models import DOCUMENT_MODELS

    await init_beanie(database=db, document_models=DOCUMENT_MODELS)


async def close_mongo() -> None:
    global mongo_client
    if mongo_client:
        await mongo_client.close()  # AsyncMongoClient.close() is a coroutine
        mongo_client = None
```

### B3. Add Configuration

Add to `APISettings` in **`src/core/config.py`**:

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    MONGODB_URL: str = Field(
        description="MongoDB connection URL — must be set in environment"
    )
    MONGODB_DB_NAME: str = Field(description="MongoDB database name")
```

Required fields make pyright flag `api_settings = APISettings()` (it cannot see pydantic-settings read them from the environment) — the scaffold's line already carries `# pyright: ignore[reportCallIssue]`; add it if missing.

Ask the user to add `MONGODB_URL` and `MONGODB_DB_NAME` to `src/.env` (agent edits to `.env` files are hook-blocked by design); document the placeholders in `src/.env.default`:
```
MONGODB_URL=mongodb://localhost:27017
MONGODB_DB_NAME=mydb
```

### B4. Wire into FastAPI Lifespan

Update **`src/app.py`** — add the lifespan to the `start_application()` function where the `FastAPI` instance is created:

```python
from contextlib import asynccontextmanager

from fastapi import FastAPI

from database.mongo import close_mongo, init_mongo


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_mongo()
    try:
        yield
    finally:
        await close_mongo()


# In start_application(), pass lifespan:
app = FastAPI(lifespan=lifespan, ...)
```

### B5. Create a Document Model

**`src/models/user.py`** (example):

If using `EmailStr`, add `email-validator` to `requirements.txt`.

```python
from beanie import Document
from pydantic import EmailStr


class User(Document):
    email: EmailStr
    name: str
    hashed_password: str

    class Settings:
        name = "users"
```

### B6. Register Document Models

Create **`src/models/__init__.py`** (or update the existing one):

```python
from models.user import User

DOCUMENT_MODELS = [User]
```

This list is imported by `database/mongo.py` during `init_beanie()`.

### B7. Usage

Beanie documents are used directly — no session injection needed. Keep construction and hashing in a service, and let the router only map HTTP to it.

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
```

**`src/api/schemas/response/user.py`** — no `hashed_password` field, and `extra="forbid"` on the base keeps it that way:

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
from beanie import PydanticObjectId

from api.schemas.request.user import CreateUserRequest
from core.security import hash_password
from models.user import User


async def list_users() -> list[User]:
    return await User.find().to_list()


async def get_user(user_id: PydanticObjectId) -> User | None:
    return await User.get(user_id)


async def create_user(payload: CreateUserRequest) -> User:
    user = User(
        **payload.model_dump(exclude={"password"}),
        hashed_password=hash_password(payload.password),
    )
    return await user.insert()
```

**Router:**

```python
from beanie import PydanticObjectId
from fastapi import HTTPException, status

from api.schemas.request.user import CreateUserRequest
from api.schemas.response.user import UserResponse
from api.services import user_service
from models.user import User


def to_response(user: User) -> UserResponse:
    # Explicit fields: hashed_password never reaches the response, and the
    # document's ObjectId id becomes the schema's str id.
    return UserResponse(id=str(user.id), email=user.email, name=user.name)


# No response_model=: the return annotation is the response model (ruff FAST001
# flags the duplicate on the 3.13 target this path pins).
@router.get("/users")
async def list_users() -> list[UserResponse]:
    return [to_response(u) for u in await user_service.list_users()]


# PydanticObjectId as the path type makes FastAPI reject malformed ids with 422.
@router.get("/users/{user_id}")
async def get_user(user_id: PydanticObjectId) -> UserResponse:
    user = await user_service.get_user(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found."
        )
    return to_response(user)


@router.post("/users", status_code=status.HTTP_201_CREATED)
async def create_user(payload: CreateUserRequest) -> UserResponse:
    return to_response(await user_service.create_user(payload))
```

> **Unbounded query**: `User.find().to_list()` loads the entire collection into memory. Paginate it for real use — run `templatecentral:add` (pagination).
>
> **Important**: Never return raw Beanie documents directly — always map to a Pydantic response schema (declared as the return annotation) to control serialization and avoid leaking internal fields like `hashed_password`.

### B8. Validate

```bash
python -m pytest test/ -q
```

Confirm all tests pass.

---

## Completing Auth Integration (Beanie)

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

### Step A — Update `src/models/user.py` and register it

If `email-validator` is not yet in `requirements.txt`, add it first (`EmailStr` requires it).

```python
# src/models/user.py
from datetime import UTC, datetime
from typing import Annotated

from beanie import Document, Indexed
from pydantic import EmailStr, Field


class User(Document):
    email: Annotated[EmailStr, Indexed(unique=True)]
    hashed_password: str
    name: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    class Settings:
        name = "users"
```

Update `src/models/__init__.py`:

```python
from models.user import User

DOCUMENT_MODELS = [User]
```

### Step B — Replace stubs in `src/api/services/auth_service.py`

```python
import secrets

from bson import ObjectId
from fastapi import HTTPException, status

from core.security import create_access_token, hash_password, verify_password
from models.user import User

# Verified on the miss path so an unknown email costs the same as a wrong
# password — without it, response timing leaks which accounts exist. Hashed at
# import with the live PasswordHasher so its cost always matches real hashes.
DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


async def register_user(email: str, password: str, name: str) -> dict:
    if await User.find_one(User.email == email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )
    user = await User(
        email=email,
        hashed_password=hash_password(password),
        name=name,
    ).insert()
    return {"id": str(user.id), "email": user.email, "name": user.name}


async def login_user(email: str, password: str) -> str:
    user = await User.find_one(User.email == email)
    password_ok = verify_password(
        password, user.hashed_password if user else DUMMY_HASH
    )
    if user is None or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=str(user.id))


async def get_user(user_id: str) -> dict:
    user = await User.get(ObjectId(user_id)) if ObjectId.is_valid(user_id) else None
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )
    return {"id": str(user.id), "email": user.email, "name": user.name}
```

### Step C — Replace `src/api/routers/auth.py`

No session dependency is needed — Beanie manages its own connection via the lifespan event. If rate limiting was added by the auth skill, preserve any existing `@limiter.limit` decorators and `request: Request` parameters when replacing this file:

```python
from typing import Annotated

from fastapi import APIRouter, Depends

from api.dependencies.auth import get_current_user
from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import get_user, login_user, register_user

router = APIRouter(prefix="/auth")


@router.post("/register")
async def register(body: RegisterRequest) -> UserResponse:
    """Register a new user account."""
    user = await register_user(email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login")
async def login(body: LoginRequest) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = await login_user(email=body.email, password=body.password)
    return TokenResponse(access_token=token)


@router.get("/me")
async def get_me(user_id: Annotated[str, Depends(get_current_user)]) -> UserResponse:
    """Get the current authenticated user."""
    user = await get_user(user_id=user_id)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])
```

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- Place document models in `src/models/` — not in `api/`.
- Never put `from __future__ import annotations` in a Beanie model module — it silently breaks `Optional[Link["X"]]` and `BackLink` detection on every Python version.
- `database/` holds infrastructure only (connection, init/close functions) — no business logic.
- Keep `MONGODB_URL` in `src/.env` — NEVER hardcode production credentials.
- Always register document models in `DOCUMENT_MODELS` and call `init_beanie()` in the lifespan event.
- Beanie uses Pydantic v2 natively — leverage field validators and computed fields.
- Never return raw Beanie documents — always map to a Pydantic response schema.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards