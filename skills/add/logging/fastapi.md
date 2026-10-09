<!-- ref: add/logging/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Structured Logging (structlog)

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**What already exists in the template:**
- `structlog` in the installed dependencies (`requirements.txt`)
- `src/core/logging.py` — structlog configured for stdlib interop: JSON in prod/uat, colored console in dev, daily-rotating JSON files in dev, plus a key-based redaction processor (`password`, `token`, `authorization`, `cookie`, …)
- Import via `from core.logging import logger` — a structlog bound logger
- **Call convention:** pass structured fields as kwargs — `logger.info("Event", key=value)` — NOT stdlib's `extra={...}`. Bind request-scoped context once with `structlog.contextvars.bind_contextvars(...)` and it flows to every subsequent line automatically (across `async`/`await`).

#### Tier 1 — Base

**Request IDs + request logging.** Install `asgi-correlation-id` (reads `X-Request-ID` or generates a UUID) and wire two middlewares in `src/app.py`.

```bash
pip install "asgi-correlation-id>=4.3" && pip freeze > requirements.txt
```

Define the middleware as a module-level function — `app` does not exist at import time (the scaffold builds it inside `start_application()`), so a top-level `@app.middleware("http")` decorator raises `NameError`.

```python
# src/app.py
import time

import structlog
from asgi_correlation_id import CorrelationIdMiddleware
from asgi_correlation_id.context import correlation_id
from fastapi import Request

from core.logging import logger


async def log_requests(request: Request, call_next):
    # Clear at the START, not in a `finally`: the scaffold's `Exception` handler runs in
    # Starlette's outermost ServerErrorMiddleware, i.e. after this function unwinds — clearing
    # on the way out would strip request_id from the one log line you most need it on.
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(request_id=correlation_id.get())
    start = time.monotonic()
    response = await call_next(request)
    logger.info(
        "Request",
        method=request.method,
        path=request.url.path,
        status_code=response.status_code,
        duration_ms=round((time.monotonic() - start) * 1000),
        user_id=getattr(request.state, "user_id", None),
    )
    return response
```

Keep `CorrelationIdMiddleware`'s default UUID validator — it discards a malformed inbound `X-Request-ID` and generates a fresh one, so a client cannot inject arbitrary text (newlines, fake fields) into every log line via the header.

Register both middlewares inside `start_application()`, the same way the scaffold's `configure_*` helpers register things. Middleware registration is LIFO — the **last** registered runs outermost — and `CorrelationIdMiddleware` must wrap the request logger so the correlation id contextvar is already set when `log_requests` reads it. So register `log_requests` **first** and `CorrelationIdMiddleware` **last**:

```python
# src/app.py — inside start_application(), after the other configure_*(app) calls
app.middleware("http")(log_requests)
app.add_middleware(CorrelationIdMiddleware)
```

App startup/shutdown — add a module-level lifespan in `src/app.py` and pass it to the existing `FastAPI(...)` call inside `start_application()`:

```python
# src/app.py
from contextlib import asynccontextmanager

from fastapi import FastAPI

from core.config import api_settings, common_settings
from core.logging import logger


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("App starting", port=api_settings.API_PORT, environment=common_settings.ENVIRONMENT)
    yield
    logger.info("App shutdown", environment=common_settings.ENVIRONMENT)


# inside start_application():
app = FastAPI(lifespan=lifespan, title=common_settings.PROJECT_NAME, ...)
```

`user_id` is `None` until authentication is wired — after `templatecentral:add` (auth), have `get_current_user` set `request.state.user_id = user_id` as a side effect before returning. `log_requests` reads `request.state` only after `await call_next(request)` completes (which runs the full dependency chain), so it picks up the value automatically with no other change needed.

Unhandled exceptions are already logged via the `Exception` handler in `src/error_handler.py` (`logger.exception`). No extra wiring for Tier 1.

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — log inside `src/api/routers/auth.py`, against the actual routes and return types from `templatecentral:add` (auth) — `get_current_user` returns the bare user-id string (subject), not a `User` object, until a database-backed user model exists:

```python
# src/api/routers/auth.py
from fastapi import HTTPException, Request

from api.schemas.response.auth import TokenResponse
from core.logging import logger
from core.security import decode_access_token


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, request: Request) -> TokenResponse:
    try:
        token = login_user(body.email, body.password)
    except HTTPException:
        logger.warning(
            "Login failure",
            reason="invalid_credentials",
            # Proxy IP unless TRUST_PROXY is set (see add (auth) — Rate Limiting);
            # request.client is None on some ASGI transports.
            ip=request.client.host if request.client else None,
        )
        raise

    logger.info("Login success", user_id=decode_access_token(token), method="password")
    return TokenResponse(access_token=token)
```

Add the equivalent `try`/`except` + `logger.info`/`logger.warning` pair to `/auth/register` and any other auth endpoint you add (e.g. logout, token refresh) once it exists — none of those beyond `/login` and `/register` are part of the base `add (auth)` skill.

Access denied — log in your auth dependency once you've added role-based access control (roles are illustrative here; the base `get_current_user` has no concept of roles until you add a database-backed user model):

```python
# src/api/dependencies/auth.py  (example — adapt once you have a User model with roles)
from typing import Annotated

from fastapi import Depends, HTTPException, Request

from core.logging import logger


def require_role(required_role: str):
    # Factory: a bare `required_role: str` parameter on a dependency would be parsed as a
    # client-supplied query param, letting the caller choose the role being checked.
    async def checker(request: Request, user_id: Annotated[str, Depends(get_current_user)]):
        user = await get_user_with_roles(user_id)
        if required_role not in user.roles:
            logger.warning(
                "Access denied",
                user_id=user_id,
                path=request.url.path,
                required_role=required_role,
            )
            raise HTTPException(status_code=404, detail="Not found")
        return user

    return checker
```

Use as `Depends(require_role("admin"))`.

**Outbound HTTP calls** — create a wrapper in `src/utils/http_client.py`:

```python
# src/utils/http_client.py
import time
from urllib.parse import urlparse, urlunparse

import httpx

from core.logging import logger


def _sanitize_url(url: str) -> str:
    """Drop userinfo, query, and fragment — any of them can carry credentials or tokens."""
    parsed = urlparse(url)
    netloc = parsed.hostname or ""
    if parsed.port:
        netloc += f":{parsed.port}"
    return urlunparse(parsed._replace(netloc=netloc, query="", fragment=""))


async def http_get(url: str, **kwargs) -> httpx.Response:
    safe_url = _sanitize_url(url)
    start = time.monotonic()
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, **kwargs)
        duration_ms = round((time.monotonic() - start) * 1000)
        logger.info(
            "Outbound HTTP",
            method="GET",
            url=safe_url,
            status_code=response.status_code,
            duration_ms=duration_ms,
        )
        return response
    except Exception as exc:
        duration_ms = round((time.monotonic() - start) * 1000)
        # Exception type only — httpx messages embed the full, unsanitized request URL.
        logger.error("Outbound HTTP error", method="GET", url=safe_url, duration_ms=duration_ms, error_type=type(exc).__name__)
        raise
```

**Key domain events** — log inside service-layer functions:

```python
# src/api/services/projects.py  (example — adapt to your domain)
from core.logging import logger


async def create_project(data: CreateProjectRequest, user_id: str) -> Project:
    project = await db.projects.insert(data)
    logger.info("Project created", user_id=user_id, project_id=str(project.id))
    return project
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — add a SQLAlchemy event listener:

```python
# src/database/session.py  (add after engine creation)
import time

from sqlalchemy import event

from core.logging import logger


@event.listens_for(engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    conn.info.setdefault("query_start_time", []).append(time.monotonic())


@event.listens_for(engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    total_ms = round((time.monotonic() - conn.info["query_start_time"].pop()) * 1000)
    if total_ms > 500:
        # Use the SQL verb as a label — never log full SQL text or bound parameters
        query_name = statement.split()[0].upper() if isinstance(statement, str) and statement.strip() else "unknown"
        logger.warning(
            "Slow DB query",
            query_name=query_name,
            duration_ms=total_ms,
        )
```

On Beanie/PyMongo, register a `pymongo.monitoring.CommandListener` instead and log `event.command_name` + `event.duration_micros // 1000` from `succeeded()` — never `event.command` (it contains the filter values).

**Sanitized request context** — bind extra fields in the `log_requests` middleware (they flow to every line for the request):

```python
# Inside log_requests middleware — bind before call_next
structlog.contextvars.bind_contextvars(
    method=request.method,
    path=request.url.path,
    auth_present="authorization" in request.headers,
)
```

**Cache hits/misses** — log inside your cache utility:

```python
# src/utils/cache.py
from core.logging import logger


async def cache_get(key: str):
    value = await redis.get(key)
    # Log a key prefix, not the full key, if keys embed user data (e.g. "session:<email>").
    logger.debug("Cache lookup", cache_key=key, hit=value is not None)
    return value
```

---

## Validate

```bash
# Tier 1
uvicorn app:app --app-dir src --reload
curl http://localhost:8000/health
# Expect a structured log line with: event="Request", method, path, status_code, duration_ms, request_id

# Tier 2
# Attempt login with wrong credentials — expect login failure log
# Attempt login with correct credentials — expect login success log
# Hit a protected route without a token — expect access denied log

# Tier 3
# Trigger a slow DB query (or lower threshold temporarily to 0 for testing)
# Expect: event="Slow DB query", query_name, duration_ms

# Confirm no prohibited fields leak.
# The redaction processor only masks the keys listed in `_SENSITIVE_KEYS` in
# `src/core/logging.py` — read that list first, extend it with your domain's PII
# (e.g. phone, address, national_id), then grep for the keys you expect masked:
grep -i "password\|secret\|token\|authorization\|cookie" <log-output>

# Anything you grep for that is NOT in `_SENSITIVE_KEYS` is unredacted by design —
# a hit there means you must add the key to `_SENSITIVE_KEYS`, not that the
# processor failed.
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
