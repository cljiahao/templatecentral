<!-- ref: add/database/python/beanie.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = Beanie (MongoDB async ODM) — explicit opt-in only; the default MongoDB path is pymongo-async.md. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI + Beanie (MongoDB)

### B0. Opt-in gate — Beanie pins the project to Python 3.13

The default is PyMongo async (`cat "<skill-dir>/database/python/pymongo-async.md"`, stays on Python 3.14). Continue only if the user explicitly wants Beanie **and** accepts a Python 3.13 pin.

Beanie declares `Requires-Python <3.14` (see `.claude/rules/fastapi.md`). Never bypass it with `--ignore-requires-python`. Check whether a newer release lifted the cap:

```bash
python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('https://pypi.org/pypi/beanie/json'))['info']['requires_python'])"
```

- **No longer excludes 3.14** → skip the pin (if that release is 3.x, raise B1's `<3` ceiling only after checking its breaking changes against this guide).
- **Still `<3.14`** → confirm the trade-off with the user (3.13 gets security fixes until 2029-10), then pin: `ARG PYTHON=python:3.13.16-slim` in `Dockerfile`, `target-version = "py313"` in `pyproject.toml`, `"pythonVersion": "3.13"` in `pyrightconfig.json`, `python-version: "3.13"` in every setup-python step (`ci.yml`, and `mutation.yml` if present), `Python 3.13` in AGENTS.md `## Stack`; recreate the venv with `python3.13 -m venv .venv` and reinstall both requirements files. `ci.yml` is harness-seeded: recompute its `origin_hash` in `.claude/harness.json` (harness-kit-finalize.md Step E), and re-apply the pin if `templatecentral:migrate` re-syncs it. Revert to 3.14 once Beanie supports it.

### B1. Install Dependencies

Add to `requirements.txt` (why these floors: `.claude/rules/fastapi.md`):

```
beanie>=2.2,<3
pymongo>=4.13
```

> Beanie 2.x runs on PyMongo's `AsyncMongoClient` — never add Motor (deprecated).

### B2. Create MongoDB Connection

Run `TC_PART=leaf TC_LEAF=add/database/python/beanie bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/database/python/beanie/template/` (listed in `<skill-dir>/database/python/beanie/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**`src/database/mongo.py`**:

Copied verbatim from `<skill-dir>/database/python/beanie/template/src/database/mongo.py` by the copy step; do not re-type it.

### B3. Add Configuration

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

Ask the user to add `MONGODB_URL` and `MONGODB_DB_NAME` to `src/.env` (agent `.env` edits are blocked); document the placeholders in `src/.env.default`:
```
MONGODB_URL=mongodb://localhost:27017
MONGODB_DB_NAME=mydb
```

### B4. Wire into FastAPI Lifespan

Update **`src/app.py`** — add the lifespan to the `start_application()` function where the `FastAPI` instance is created:

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from database.mongo import close_mongo, init_mongo


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    try:
        # init_beanie connects and builds indexes, so a bad URL fails the boot.
        await init_mongo()
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
from typing import Annotated

from beanie import Document, Indexed
from pydantic import EmailStr


class User(Document):
    # The unique index (built by init_beanie at boot) is what makes B7's
    # DuplicateKeyError → 409 fire; a plain `EmailStr` stores duplicates silently.
    email: Annotated[EmailStr, Indexed(unique=True)]
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

Documents are used directly (no session injection); construction and hashing live in a service, the router only maps HTTP.

**`src/api/schemas/request/user.py`**:

Copied verbatim from `<skill-dir>/database/python/beanie/template/src/api/schemas/request/user.py` by the copy step; do not re-type it.

**`src/api/schemas/response/user.py`** — no `hashed_password` field:

Copied verbatim from `<skill-dir>/database/python/beanie/template/src/api/schemas/response/user.py` by the copy step; do not re-type it.

**`src/api/services/user_service.py`**:

Copied verbatim from `<skill-dir>/database/python/beanie/template/src/api/services/user_service.py` by the copy step; do not re-type it.

**`src/api/routers/users.py`** (register it in `src/api/routes.py` with a `USERS` tag). It has no auth of its own — keep it off deployed environments until Step D below (or your own guard) protects it:

```python
from beanie import PydanticObjectId
from fastapi import APIRouter, HTTPException, status

from api.schemas.request.user import CreateUserRequest
from api.schemas.response.user import UserResponse
from api.services import user_service
from models.user import User

router = APIRouter()


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

> **Unbounded query**: `User.find().to_list()` loads the whole collection — paginate for real use (`templatecentral:add` (pagination)).
>
> **Important**: never return raw Beanie documents — map to a Pydantic response schema (the return annotation) so fields like `hashed_password` never leak.

### B8. Tests and Validate

The lifespan connects to MongoDB, so a `with TestClient(app)` fixture fails without one. In **`test/conftest.py`**, seed settings (CI has no `src/.env`) and build the client without `with` — merge, keeping existing seeding and fixtures (`SECRET_KEY`, `auth_headers`):

```python
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

Data-access tests need a real MongoDB — use `pymongo-async.md` M8's `docker-compose.yml` service and skip-if-unreachable fixture, calling `init_beanie(database=..., document_models=DOCUMENT_MODELS)` instead of `ensure_indexes()`.

```bash
ruff check src/ test/
python -m pyright src/
python -m pytest test/ -q
```

---

## Completing Auth Integration (Beanie)

> **Only if `templatecentral:add` (auth) ran first** — replaces its 501 stubs with database-backed code.

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
import asyncio
import secrets

from bson import ObjectId
from fastapi import HTTPException, status
from pymongo.errors import DuplicateKeyError

from core.security import create_access_token, hash_password, verify_password
from models.user import User

# Verified on the miss path so an unknown email costs the same as a wrong
# password — without it, response timing leaks which accounts exist. Hashed at
# import with the live PasswordHasher so its cost always matches real hashes.
DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


# argon2 is ~100 ms of CPU per call: asyncio.to_thread keeps it off the event loop.
async def register_user(email: str, password: str, name: str) -> dict:
    hashed = await asyncio.to_thread(hash_password, password)
    # The unique index, not a find-then-insert check, stops concurrent duplicates.
    try:
        user = await User(email=email, hashed_password=hashed, name=name).insert()
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        ) from None
    return {"id": str(user.id), "email": user.email, "name": user.name}


async def login_user(email: str, password: str) -> str:
    user = await User.find_one(User.email == email)
    password_ok = await asyncio.to_thread(
        verify_password, password, user.hashed_password if user else DUMMY_HASH
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

No session dependency — the lifespan owns the connection. Keep any `@limiter.limit` decorators and `request: Request` parameters the auth skill added:

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

### Step D — Lock down `src/api/routers/users.py`

`POST /auth/register` now creates users — drop `create_user` from the users router and service unless admins need it, and require login on the rest (unauthenticated, `GET /users` lists every email):

```python
router = APIRouter(dependencies=[Depends(get_current_user)])
```

Scope `get_user` to the caller's own id, or gate it on an admin role, before exposing it.

---

## Rules

- **Opt-in only** — add a database only on request.
- Place document models in `src/models/` — not in `api/`.
- Never put `from __future__ import annotations` in a Beanie model module — it silently breaks `Optional[Link["X"]]` and `BackLink` detection on every Python version.
- `database/` holds infrastructure only (connection, init/close functions) — no business logic.
- Keep `MONGODB_URL` in `src/.env` — NEVER hardcode production credentials.
- Always register document models in `DOCUMENT_MODELS` and call `init_beanie()` in the lifespan event.
- Beanie uses Pydantic v2 natively — leverage field validators and computed fields.
- Never return raw Beanie documents — always map to a Pydantic response schema.

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.