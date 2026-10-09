<!-- ref: add/database/python/pymongo-async-auth.md
     loaded-by: add/database/python.md → add/SKILL.md
     prereq: Stack = FastAPI, DB = MongoDB via PyMongo async, auth stubs from templatecentral:add (auth) present (`src/api/services/auth_service.py` exists). Loaded alongside pymongo-async.md (M4 `User`, M5 `UserRepository`, M6 unique email index must exist). Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Completing Auth Integration (PyMongo)

> Replaces the 501 stubs from `templatecentral:add` (auth) with database-backed implementations. The `User` model (M4), `UserRepository` (M5) and the unique email index (M6) of `pymongo-async.md` already cover it.

### Step A — Replace stubs in `src/api/services/auth_service.py`

```python
import secrets
from typing import Any

from fastapi import HTTPException, status
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from api.repositories.user_repository import UserRepository
from core.security import create_access_token, hash_password, verify_password
from models.user import User

# Verified on the miss path so an unknown email costs the same as a wrong
# password — without it, response timing leaks which accounts exist. Hashed at
# import with the live PasswordHasher so its cost always matches real hashes.
DUMMY_HASH = hash_password(secrets.token_urlsafe(16))

type Db = AsyncDatabase[dict[str, Any]]


async def register_user(db: Db, email: str, password: str, name: str) -> dict:
    user = User(email=email, hashed_password=hash_password(password), name=name)
    try:
        user = await UserRepository(db).insert(user)
    except DuplicateKeyError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        ) from None
    return {"id": user.id, "email": user.email, "name": user.name}


async def login_user(db: Db, email: str, password: str) -> str:
    user = await UserRepository(db).find_by_email(email)
    password_ok = verify_password(
        password, user.hashed_password if user else DUMMY_HASH
    )
    if user is None or not password_ok or user.id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
    return create_access_token(subject=user.id)


async def get_user(db: Db, user_id: str) -> dict:
    user = await UserRepository(db).find_by_id(user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )
    return {"id": user.id, "email": user.email, "name": user.name}
```

### Step B — Replace `src/api/routers/auth.py`

If rate limiting was added by the auth skill, preserve any existing `@limiter.limit` decorators and `request: Request` parameters when replacing this file:

```python
from typing import Annotated

from fastapi import APIRouter, Depends

from api.dependencies.auth import get_current_user
from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import get_user, login_user, register_user
from database.mongo import DbDep

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
async def register(body: RegisterRequest, db: DbDep) -> UserResponse:
    """Register a new user account."""
    user = await register_user(
        db, email=body.email, password=body.password, name=body.name
    )
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: DbDep) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = await login_user(db, email=body.email, password=body.password)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
async def get_me(
    db: DbDep, user_id: Annotated[str, Depends(get_current_user)]
) -> UserResponse:
    """Get the current authenticated user."""
    user = await get_user(db, user_id=user_id)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])
```

### Step C — Drop the duplicate create route

`POST /auth/register` now creates users, so remove `create_user` from `src/api/routers/users.py` (and its service function and test) unless admins need a separate create path.

Then run the **After Writing Code** steps of `pymongo-async.md` (build, then review).
