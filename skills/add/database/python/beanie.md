<!-- ref: add/database/python/beanie.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = Beanie (MongoDB async ODM). Do not invoke this file directly. -->
## FastAPI + Beanie (MongoDB)

### B1. Install Dependencies

Add to `requirements.txt` (floors tracked in the templateCentral plugin's `.claude/rules/fastapi.md` — AsyncMongoClient requires a modern PyMongo):

```
beanie
pymongo
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
    MONGODB_URL: str = Field(description="MongoDB connection URL — must be set in environment")
    MONGODB_DB_NAME: str = Field(description="MongoDB database name")
```

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

from database.mongo import init_mongo, close_mongo


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_mongo()
    yield
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

Beanie documents are used directly — no session injection needed:

Create Pydantic response schemas (in `api/schemas/`) and use `response_model`:

```python
from api.schemas.request.user import CreateUserRequest  # create these schemas
from api.schemas.response.user import UserResponse
from models.user import User

@router.get("/users", response_model=list[UserResponse])
async def list_users():
    return await User.find().to_list()

@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str):
    return await User.get(user_id)

@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(payload: CreateUserRequest):
    user = User(**payload.model_dump(), hashed_password="...")  # use hash_password() from core/security.py
    await user.insert()
    return user
```

> **Important**: Never return raw Beanie documents directly — always use `response_model` with a Pydantic schema to control serialization and avoid leaking internal fields like `hashed_password`.

### B8. Validate

```bash
pytest test/
```

Confirm all tests pass.

---

## Completing Auth Integration (Beanie)

> **Only apply this section if `templatecentral:add` (auth) was run before this skill.** It replaces the 501 stubs with real database-backed implementations.

### Step A — Update `src/models/user.py` and register it

If `email-validator` is not yet in `requirements.txt`, add it first (`EmailStr` requires it).

```python
# src/models/user.py
from datetime import datetime, timezone
from typing import Annotated

from beanie import Document, Indexed
from pydantic import EmailStr, Field


class User(Document):
    email: Annotated[EmailStr, Indexed(unique=True)]
    hashed_password: str
    name: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

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
from fastapi import HTTPException, status
from beanie import PydanticObjectId

from core.security import create_access_token, hash_password, verify_password
from models.user import User


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
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=str(user.id))


async def get_user(user_id: str) -> dict:
    try:
        oid = PydanticObjectId(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        ) from None
    user = await User.get(oid)
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
from fastapi import APIRouter, Depends

from api.dependencies.auth import get_current_user
from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import get_user, login_user, register_user

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
async def register(body: RegisterRequest) -> UserResponse:
    """Register a new user account."""
    user = await register_user(email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = await login_user(email=body.email, password=body.password)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
async def get_me(user_id: str = Depends(get_current_user)) -> UserResponse:
    """Get the current authenticated user."""
    user = await get_user(user_id=user_id)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])
```

---

## Rules

- **Opt-in only** — the base template has no database. Only add when explicitly requested.
- Place document models in `src/models/` — not in `api/`.
- `database/` holds infrastructure only (connection, init/close functions) — no business logic.
- Keep `MONGODB_URL` in `src/.env` — NEVER hardcode production credentials.
- Always register document models in `DOCUMENT_MODELS` and call `init_beanie()` in the lifespan event.
- Beanie uses Pydantic v2 natively — leverage field validators and computed fields.
- Never return raw Beanie documents — always use `response_model` with a Pydantic schema.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards