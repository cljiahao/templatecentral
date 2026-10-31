<!-- ref: add/auth/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI

Add JWT-based authentication to a FastAPI project scaffolded from templateCentral.

> **Stub notice:** The auth service created here is intentionally incomplete — `register_user` stores nothing and `login_user` raises HTTP 501 until a database is available. Run `templatecentral:add` (database) after this skill to complete the integration.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Dependencies

Add to `requirements.txt`:
- `PyJWT[crypto]` — JWT encoding/decoding
- `argon2-cffi` — Password hashing (argon2id algorithm; OWASP recommended)
- `email-validator` — Pydantic `EmailStr` validation (validates email format in request schemas)

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Add Auth Schemas

First run `TC_PART=leaf TC_LEAF=add/auth/fastapi TC_TREE=template bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/auth/fastapi/template/` into the project per `<skill-dir>/auth/fastapi/template.manifest` — the files of Steps 1, 3, 4, 5, 6, 8 and the two new test files of Step 11 — and writes nothing, ending with a `STOP:` line, when a path is in the way.

Request/response schemas for auth endpoints:

**`src/api/schemas/request/auth.py`**:
Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/schemas/request/auth.py` by the copy step; do not re-type it.

**`src/api/schemas/response/auth.py`**:
Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/schemas/response/auth.py` by the copy step; do not re-type it.

#### 2. Extend Config

Add `SECRET_KEY` and `ACCESS_TOKEN_EXPIRE_MINUTES` to `APISettings` in **`src/core/config.py`**:

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    SECRET_KEY: str = Field(
        description="JWT signing key — generate with: openssl rand -hex 32"
    )
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=30)
```

Required fields make pyright flag `api_settings = APISettings()` (it cannot see pydantic-settings read them from the environment) — the scaffold's line already carries `# pyright: ignore[reportCallIssue]`; add it if missing.

> `TRUST_PROXY` already exists in the scaffold's `APISettings` (`src/core/config.py`) and `src/.env.default` — do not re-add it.

Ask the user to add `SECRET_KEY` and `ACCESS_TOKEN_EXPIRE_MINUTES` to `src/.env` (real value — never commit; agent edits to `.env` files are hook-blocked by design):
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

#### 3. Create Security Module

**`src/core/security.py`** — JWT token creation/verification and password hashing:

Copied verbatim from `<skill-dir>/auth/fastapi/template/src/core/security.py` by the copy step; do not re-type it.

#### 4. Create Auth Dependency

The copy step created **`src/api/dependencies/`** (not in the base template) with an empty **`src/api/dependencies/__init__.py`** (marks it as a Python package) and **`src/api/dependencies/auth.py`** — `get_current_user` dependency for protecting routes:

Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/dependencies/auth.py` by the copy step; do not re-type it.

#### 5. Create Authorization Helpers

**`src/api/dependencies/authz.py`** — deny-by-default role and ownership checks. Authentication says who the caller is; these decide what the caller may touch:

Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/dependencies/authz.py` by the copy step; do not re-type it.

Use `require_roles` in place of `get_current_user` on role-gated routes, and `ensure_owner` on record-by-id handlers (see Rules):

```python
@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    item_id: str, user_id: Annotated[str, Depends(require_roles("admin"))]
) -> None: ...


@router.get("/{item_id}", response_model=ItemResponse)
def get_item(
    item_id: str, user_id: Annotated[str, Depends(get_current_user)]
) -> ItemResponse:
    item = item_service.get(item_id)  # None when no such record
    ensure_owner(item.owner_id if item else None, user_id)
    return ItemResponse.model_validate(item)
```

Once `templatecentral:add` (database) adds a users store, make `get_current_roles` read the user's roles from it.

#### 6. Create Auth Service

**`src/api/services/auth_service.py`** — orchestrates registration and login. This is a stub; complete it after running `templatecentral:add` (database).

Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/services/auth_service.py` by the copy step; do not re-type it.

#### 7. Add Auth Tag

Add `AUTH` to the `APITags` enum in **`src/api/tags.py`**:

```python
class APITags(StrEnum):
    # ... existing tags
    AUTH = "auth"
```

#### 8. Create Auth Router

**`src/api/routers/auth.py`**:

Copied verbatim from `<skill-dir>/auth/fastapi/template/src/api/routers/auth.py` by the copy step; do not re-type it.

#### 9. Register the Router

Add the auth router to `src/api/routes.py`:

```python
from api.routers import auth
from api.tags import APITags

router.include_router(auth.router, tags=[APITags.AUTH])
```

#### 10. Protect Routes

Use the `get_current_user` dependency on any endpoint that requires auth — starting with this `/me` stub in `src/api/routers/auth.py` (merge the imports into that file's block):

```python
from typing import Annotated

from fastapi import Depends, HTTPException, status

from api.dependencies.auth import get_current_user
from api.schemas.response.auth import UserResponse


@router.get("/me", response_model=UserResponse)
async def get_me(user_id: Annotated[str, Depends(get_current_user)]) -> UserResponse:
    """Get the current authenticated user. Implement DB lookup after running `templatecentral:add` (database)."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run `templatecentral:add` (database) to complete auth.",
    )
```

#### 11. Tests

Settings load at import and CI has no `src/.env`, so seed a throwaway key before the app is imported — replace **`test/conftest.py`** (the import moves into the fixture for the same reason):

```python
"""Root conftest — shared fixtures available to all tests."""

import os
import secrets
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("SECRET_KEY", secrets.token_hex(32))


@pytest.fixture
def client() -> Generator[TestClient]:
    """FastAPI test client."""
    from app import app

    with TestClient(app) as client:
        yield client


@pytest.fixture
def auth_headers() -> dict[str, str]:
    """Bearer header for a synthetic user — for routes behind get_current_user."""
    from core.security import create_access_token

    return {"Authorization": f"Bearer {create_access_token('test-user')}"}
```

**`test/test_api/test_auth.py`** — covers the parts that stay unchanged when `templatecentral:add` (database) completes the stubs:

Copied verbatim from `<skill-dir>/auth/fastapi/template/test/test_api/test_auth.py` by the copy step; do not re-type it.

**`test/test_api/test_authz.py`** — a probe app guards one route with the real dependencies, so the checks are tested apart from any feature router:

Copied verbatim from `<skill-dir>/auth/fastapi/template/test/test_api/test_authz.py` by the copy step; do not re-type it.

### Browser Client (Cookie Mode)

**Apply when a browser SPA calls this API** — a Vite + React frontend (`templatecentral:add (auth)` on Vite sends `credentials: 'include'` + `X-CSRF-Token`, never a Bearer header), or Next.js client components calling the backend. `templatecentral:standards (full-stack-pairing)` points here. Without it every guarded route answers that SPA with 401.

**Same-origin only:** the SPA must reach this API through a reverse proxy on its own origin (Vite `server.proxy` in dev, nginx `location /api/` in production, or a Next.js `rewrites()` path — snippets in `templatecentral:standards (full-stack-pairing)`); `XSRF-TOKEN` is a host-only cookie, so an SPA on another host cannot read it and every non-GET would 403.

Design (OWASP CSRF + Session Management cheat sheets, RFC 10017 *OAuth 2.0 for Browser-Based Applications* §6.1 cookie rules): the JWT rides in an `HttpOnly; Secure; SameSite=Strict; Path=/` cookie named `__Host-session` (`session` in dev, where `Secure` is off for plain-http localhost) — never in JS-readable storage. Unsafe methods carry a **signed double-submit** CSRF token: the readable `XSRF-TOKEN` cookie holds `nonce.HMAC(key, session, nonce)`, the SPA echoes it in `X-CSRF-Token`, and the server recomputes the HMAC against the session cookie — so a token injected from a sibling subdomain or lifted from another session fails. Bearer requests skip the check (browsers never attach `Authorization` on their own), so API clients keep working unchanged.

Run `TC_PART=leaf TC_LEAF=add/auth/fastapi TC_TREE=template-cookie bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` first: it writes `test/test_api/test_auth_cookie.py` (4) from `<skill-dir>/auth/fastapi/template-cookie/`.

**1. `src/core/security.py`** — add `import hashlib`, `import hmac`, `import secrets` to the imports, change the config import to `from core.config import api_settings, common_settings`, and append:

```python
# --- Browser client (cookie mode) -------------------------------------------------
# Secure is dropped only in dev (plain-http localhost); the __Host- prefix requires
# Secure, so the session cookie takes its hardened name everywhere else.
COOKIE_SECURE = common_settings.ENVIRONMENT != "dev"
SESSION_COOKIE = "__Host-session" if COOKIE_SECURE else "session"
CSRF_COOKIE = "XSRF-TOKEN"  # readable by the SPA, which echoes it in CSRF_HEADER
CSRF_HEADER = "X-CSRF-Token"
# Sub-key so the CSRF HMAC never shares raw key material with JWT signing.
_CSRF_KEY = hmac.new(
    api_settings.SECRET_KEY.encode(), b"csrf-v1", hashlib.sha256
).digest()


def _csrf_signature(session: str, nonce: str) -> str:
    # Length-prefixed message (OWASP signed double-submit) binds the token to the session.
    message = f"{len(session)}!{session}!{len(nonce)}!{nonce}".encode()
    return hmac.new(_CSRF_KEY, message, hashlib.sha256).hexdigest()


def create_csrf_token(session: str) -> str:
    """Issue a CSRF token bound to this session value (signed double-submit)."""
    nonce = secrets.token_urlsafe(32)
    return f"{nonce}.{_csrf_signature(session, nonce)}"


def verify_csrf_token(token: str, session: str) -> bool:
    nonce, _, signature = token.partition(".")
    return bool(nonce) and hmac.compare_digest(
        signature, _csrf_signature(session, nonce)
    )
```

**2. `src/api/dependencies/auth.py`** — replace the file. `get_current_user` keeps its name and return value, so every guarded route gains cookie support with no edits; keep any line `templatecentral:add (logging)` added (e.g. `request.state.user_id = user_id` before the return):

```python
from typing import Annotated

from fastapi import Depends, HTTPException, Request, Response, status
from fastapi.security import APIKeyCookie, HTTPAuthorizationCredentials, HTTPBearer

from core.config import api_settings
from core.security import (
    COOKIE_SECURE,
    CSRF_COOKIE,
    CSRF_HEADER,
    SESSION_COOKIE,
    create_csrf_token,
    decode_access_token,
    verify_csrf_token,
)

# auto_error=False on both: either credential may be absent; get_current_user decides.
bearer_scheme = HTTPBearer(auto_error=False)
session_cookie = APIKeyCookie(name=SESSION_COOKIE, auto_error=False)
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})


def get_current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    session: Annotated[str | None, Depends(session_cookie)],
) -> str:
    """Resolve the user from a Bearer header (API clients) or the session cookie (browsers)."""
    if credentials is not None:
        # Browsers never attach Authorization on their own — no CSRF exposure.
        token = credentials.credentials
    elif session is not None:
        if request.method not in SAFE_METHODS:
            header = request.headers.get(CSRF_HEADER, "")
            if header != request.cookies.get(CSRF_COOKIE) or not verify_csrf_token(
                header, session
            ):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="CSRF token missing or invalid.",
                )
        token = session
    else:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user_id = decode_access_token(token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        )
    return user_id


def require_json(request: Request) -> None:
    """415 unless the body is declared JSON — FastAPI parses a body with no Content-Type
    as JSON too, so this keeps /auth/session out of reach of CORS-simple requests."""
    media_type = request.headers.get("content-type", "").partition(";")[0].strip()
    if media_type.lower() != "application/json":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Content-Type must be application/json.",
        )


def set_session_cookies(response: Response, token: str) -> None:
    """Set the HttpOnly session cookie plus a fresh CSRF token bound to it."""
    max_age = api_settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    for name, value, httponly in (
        (SESSION_COOKIE, token, True),
        # Readable on purpose: the SPA echoes it back in the X-CSRF-Token header.
        (CSRF_COOKIE, create_csrf_token(token), False),
    ):
        response.set_cookie(
            name,
            value,
            max_age=max_age,
            path="/",
            secure=COOKIE_SECURE,
            httponly=httponly,
            samesite="strict",
        )


def clear_session_cookies(response: Response) -> None:
    """Expire both cookies (attributes must match, or __Host- deletion is ignored)."""
    for name, httponly in ((SESSION_COOKIE, True), (CSRF_COOKIE, False)):
        response.delete_cookie(
            name, path="/", secure=COOKIE_SECURE, httponly=httponly, samesite="strict"
        )
```

**3. `src/api/routers/auth.py`** — add the browser login and logout (merge `Response`, `status`, `require_json` and the two cookie helpers into the imports). `/auth/login` keeps returning the token for API clients; `/auth/session` returns 204 so the JWT never reaches JavaScript, and minting a fresh session + CSRF pair on every login also defeats session fixation:

```python
@router.post(
    "/session",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    dependencies=[Depends(require_json)],
)
def create_session(body: LoginRequest, response: Response) -> None:
    """Browser login: set the HttpOnly session cookie (no token in the body)."""
    # Call login_user exactly as /login does — the database guide adds a `db` argument.
    token = login_user(email=body.email, password=body.password)
    set_session_cookies(response, token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
def logout(response: Response) -> None:
    """Clear the session and CSRF cookies."""
    clear_session_cookies(response)
```

`/session` needs no CSRF token: `require_json` answers 415 to anything but `Content-Type: application/json` (FastAPI would otherwise parse a body with *no* Content-Type as JSON — a CORS-simple request that skips preflight), and a cross-origin JSON `fetch` must pass a CORS preflight the allowlist rejects — the custom-request-header defense OWASP lists for API endpoints. Rate-limit it like `/login` (see Rate Limiting).

No CORS change: the SPA's proxied requests are same-origin and never preflight.

**4. `test/test_api/test_auth_cookie.py`** — a probe app isolates the cookie machinery from the login stub and from whichever database variant completes it:

Copied verbatim from `<skill-dir>/auth/fastapi/template-cookie/test/test_api/test_auth_cookie.py` by the copy step; do not re-type it.

### Rate Limiting (Required for Production)

Target: max 3 auth attempts per 15 minutes per client IP. Add `slowapi` to `requirements.txt`, then:

```python
from fastapi import Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# get_remote_address reads request.client.host — correct behind a proxy only when
# TRUST_PROXY is set (see Rules), otherwise every user shares the proxy's bucket.
limiter = Limiter(key_func=get_remote_address)
# In app.py:
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


# On auth endpoints — limit /register as well as /login (both are
# unauthenticated and CPU-expensive via argon2 hashing), plus /session in cookie mode.
# Keep each handler's current `def`/`async def` — only add the decorator and `request`.
@router.post("/register", response_model=UserResponse)
@limiter.limit("3/15minutes")
def register(request: Request, body: RegisterRequest) -> UserResponse: ...


@router.post("/login", response_model=TokenResponse)
@limiter.limit("3/15minutes")
def login(request: Request, body: LoginRequest) -> TokenResponse: ...


@router.post(
    "/session",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    dependencies=[Depends(require_json)],
)
@limiter.limit("3/15minutes")
def create_session(request: Request, body: LoginRequest, response: Response) -> None: ...
```

### Rules

- **SECRET_KEY must be kept secret** — never commit to version control. Add to `src/.env` and `.gitignore`.
- Use `HTTPBearer` scheme so Swagger UI gets the "Authorize" button.
- Browser SPA clients get cookie mode (above), never a token in `localStorage` — Bearer stays for non-browser clients.
- Always hash passwords with argon2id (`argon2-cffi` package) — never store plaintext. Memory-hard and resistant to GPU-based brute-force (OWASP recommendation).
- `get_current_user` returns the user ID (subject). Extend it to return a full user object once you have a database.
- Every handler that loads a record by id calls `ensure_owner` (or filters the query by owner) before returning or changing it.
- Role-gated routes depend on `require_roles(...)`. Roles come from `get_current_roles`, never from the token, so a revoked role stops working on the next request.
- When completing `login_user`, return the same 401 for unknown email and wrong password, and run `verify_password` against a dummy hash when the user is missing — otherwise response timing reveals which emails are registered.
- **Rate limiting is mandatory for production** — add `slowapi` before going live.
- **TRUST_PROXY must be set when behind a reverse proxy** — `get_remote_address` reads `request.client.host`. Set `TRUST_PROXY` to your VPC CIDR (single-hop: ALB → App) or `TRUST_PROXY=10.0.0.0/8,172.16.0.0/12` (two-hop: ALB → Traefik → App). Without it, the proxy's IP is the apparent client, making rate limiting shared across all users (ineffective).

### Validate

```bash
python -m pytest test/ -v     # auth tests pass
ruff check src/ test/         # zero lint errors
python -m pyright src/        # zero type errors
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate the server starts and tests pass
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards

---
