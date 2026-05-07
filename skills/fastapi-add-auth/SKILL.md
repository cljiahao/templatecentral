---
name: fastapi-add-auth
description: Use when the user wants to add authentication, JWT tokens, password hashing, or user login/registration to a FastAPI project.
---

# Add Auth to FastAPI

Add JWT-based authentication to a FastAPI project scaffolded from templateCentral.

> **Stub notice:** The auth service created here is intentionally incomplete — `register_user` stores nothing and `login_user` raises HTTP 501 until a database is available. Run `fastapi-add-database` after this skill to complete the integration.

## Prerequisites

Requires a project scaffolded with `templatecentral:fastapi-scaffold`. See Step 0.

## Dependencies

Add to `requirements.txt`:
- `PyJWT[crypto]>=2.12.0` — JWT encoding/decoding
- `bcrypt` — Password hashing (use directly; passlib is unmaintained and incompatible with bcrypt ≥ 4.1.1)
- `email-validator` — Pydantic `EmailStr` validation (validates email format in request schemas)

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Add Auth Schemas

Create request/response schemas for auth endpoints.

**`src/api/schemas/request/auth.py`**:
```python
from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class RegisterRequest(BaseRequestSchema):
    """Registration request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(min_length=12, description="User password — minimum 12 characters (NIST SP 800-63B).")
    name: str = Field(description="User display name.")


class LoginRequest(BaseRequestSchema):
    """Login request."""

    email: EmailStr = Field(description="User email address.")
    password: str = Field(description="User password.")
```

**`src/api/schemas/response/auth.py`**:
```python
from pydantic import BaseModel, Field

from api.schemas.base import BaseResponseSchema


class TokenResponse(BaseModel):
    """JWT token response — uses plain BaseModel to preserve OAuth2-standard snake_case (RFC 6749)."""

    access_token: str = Field(description="JWT access token.")
    token_type: str = Field(default="bearer", description="Token type.")


class UserResponse(BaseResponseSchema):
    """Authenticated user info."""

    id: str = Field(description="User ID.")
    email: str = Field(description="User email.")
    name: str = Field(description="User display name.")
```

### 2. Extend Config

Add `SECRET_KEY` and `ACCESS_TOKEN_EXPIRE_MINUTES` to `APISettings` in **`src/core/config.py`**:

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    SECRET_KEY: str = Field(description="JWT signing key — generate with: openssl rand -hex 32")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=30)
```

Add to `src/.env` (real value — never commit):
```
SECRET_KEY=
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

Document in `src/.env.default`:
```
SECRET_KEY=<generate with: openssl rand -hex 32>
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

> Run `openssl rand -hex 32` and paste the output as `SECRET_KEY`.

> **Security**: `SECRET_KEY` has no default — Pydantic will raise a validation error at startup if unset, which is the correct behavior. NEVER use a hardcoded default like `"change-me"` for secrets.

### 3. Create Security Module

**`src/core/security.py`** — JWT token creation/verification and password hashing:

```python
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import HTTPException

from core.config import api_settings

ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    """Hash a plaintext password."""
    if len(password.encode()) > 72:
        raise HTTPException(status_code=400, detail="Password must be 72 characters or fewer")
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(12)).decode("utf-8")  # cost 12 — OWASP minimum


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    if len(plain_password.encode()) > 72:
        return False  # bcrypt 5.0 raises ValueError for >72 bytes; no valid hash exists
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))


def create_access_token(subject: str, expires_delta: timedelta | None = None) -> str:
    """Create a JWT access token."""
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=api_settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode = {"sub": subject, "exp": expire}
    return jwt.encode(to_encode, api_settings.SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> str | None:
    """Decode and validate a JWT token. Returns the subject or None."""
    try:
        # algorithms is a security whitelist — never omit or use ["none"]; omitting allows algorithm confusion attacks
        payload = jwt.decode(token, api_settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        return None
```

### 4. Create Auth Dependency

Create **`src/api/dependencies/`** directory (does not exist in base template), then add both **`src/api/dependencies/__init__.py`** (empty, marks the directory as a Python package) and **`src/api/dependencies/auth.py`** — `get_current_user` dependency for protecting routes:

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from core.security import decode_access_token

bearer_scheme = HTTPBearer()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    """Extract and validate the current user from the JWT token."""
    user_id = decode_access_token(credentials.credentials)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        )
    return user_id
```

### 5. Create Auth Service

**`src/api/services/auth_service.py`** — orchestrates registration and login. This is a stub; complete it after running `fastapi-add-database`.

```python
from fastapi import HTTPException, status

from core.security import create_access_token, hash_password, verify_password


def register_user(email: str, password: str, name: str) -> dict:
    """Register a new user. Persist to database after running fastapi-add-database."""
    hashed = hash_password(password)
    user_id = "generated-id"
    return {"id": user_id, "email": email, "name": name, "hashed_password": hashed}


def login_user(email: str, password: str) -> str:
    """Authenticate user and return JWT. Implement DB lookup after running fastapi-add-database."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run fastapi-add-database to complete auth.",
    )
```

### 6. Add Auth Tag

Add `AUTH` to the `APITags` enum in **`src/api/tags.py`**:

```python
class APITags(StrEnum):
    # ... existing tags
    AUTH = "auth"
```

### 7. Create Auth Router

**`src/api/routers/auth.py`**:

```python
from fastapi import APIRouter, Depends

from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import login_user, register_user
from api.tags import APITags

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest) -> UserResponse:
    """Register a new user account."""
    user = register_user(email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = login_user(email=body.email, password=body.password)
    return TokenResponse(access_token=token)
```

### 8. Register the Router

Add the auth router to `src/api/routes.py`:

```python
from api.routers import auth
from api.tags import APITags

router.include_router(auth.router, tags=[APITags.AUTH])
```

### 9. Protect Routes

Use the `get_current_user` dependency on any endpoint that requires auth:

```python
from api.dependencies.auth import get_current_user

@router.get("/me", response_model=UserResponse)
def get_me(user_id: str = Depends(get_current_user)) -> UserResponse:
    """Get the current authenticated user. Implement DB lookup after running fastapi-add-database."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run fastapi-add-database to complete auth.",
    )
```

## Rate Limiting (Required for Production)

Industry best practice: max 3 failed auth attempts per 15 minutes. Add `slowapi` to `requirements.txt`, then:

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request

limiter = Limiter(key_func=get_remote_address)
# In app.py:
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# On auth endpoints:
@router.post("/login")
@limiter.limit("3/15minutes")
async def login(request: Request, body: LoginRequest) -> TokenResponse: ...
```

## Rules

- **SECRET_KEY must be kept secret** — never commit to version control. Add to `src/.env` and `.gitignore`.
- Use `HTTPBearer` scheme so Swagger UI gets the "Authorize" button.
- Always hash passwords with `bcrypt` — never store plaintext. For new projects, prefer `argon2id` (OWASP and NIST SP 800-63B recommendation) — it is memory-hard and more resistant to GPU-based attacks than bcrypt. Use the `argon2-cffi` package for Python; bcrypt remains acceptable if already in use.
- `get_current_user` returns the user ID (subject). Extend it to return a full user object once you have a database.
- **Rate limiting is mandatory for production** — add `slowapi` before going live.

## Validate

```bash
pytest test/ -v     # auth tests pass
ruff check src/     # zero lint errors
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate the server starts and tests pass
2. `shared-review-agent` — check code standards
