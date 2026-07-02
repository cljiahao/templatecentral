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

```python
# src/app.py
import time

import structlog
from asgi_correlation_id import CorrelationIdMiddleware
from asgi_correlation_id.context import correlation_id
from fastapi import Request

from core.logging import logger


# @app.middleware("http") is LIFO — the last-registered runs outermost. Register this
# request logger so it wraps the request outermost and sees the final response status.
@app.middleware("http")
async def log_requests(request: Request, call_next):
    # Bind the correlation id (set by CorrelationIdMiddleware) so every log line for this
    # request carries request_id — no threading it through call sites.
    structlog.contextvars.bind_contextvars(request_id=correlation_id.get())
    start = time.monotonic()
    try:
        response = await call_next(request)
        duration_ms = round((time.monotonic() - start) * 1000)
        user_id = getattr(request.state, "user_id", None)
        logger.info(
            "Request",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            duration_ms=duration_ms,
            user_id=user_id,
        )
        return response
    finally:
        # Clear even if call_next raised, so context never leaks to the next request.
        structlog.contextvars.clear_contextvars()
```

Register `CorrelationIdMiddleware` in `start_application()` — it must run **before** (wrap) the request logger so the id is set when logs are emitted:

```python
# src/app.py — inside start_application(), with the other app.add_middleware(...) calls
app.add_middleware(CorrelationIdMiddleware)
```

App startup/shutdown — add lifespan events in `src/app.py`:

```python
# src/app.py
from contextlib import asynccontextmanager

from core.config import api_settings, common_settings
from core.logging import logger


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("App starting", port=api_settings.API_PORT, environment=common_settings.ENVIRONMENT)
    yield
    logger.info("App shutdown", environment=common_settings.ENVIRONMENT)


app = FastAPI(lifespan=lifespan, ...)
```

Unhandled exceptions are already logged via the `Exception` handler in `src/error_handler.py` (`logger.exception`). No extra wiring for Tier 1.

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — log inside auth routers in `src/api/routers/`:

```python
# src/api/routers/auth.py
from core.logging import logger


@router.post("/login", response_model=TokenResponse)
async def login(credentials: LoginRequest, request: Request):
    user = await authenticate(credentials)
    if not user:
        logger.warning(
            "Login failure",
            reason="invalid_credentials",
            # request.client.host is the proxy's IP unless TRUST_PROXY is set —
            # one-hop (ALB → App): TRUST_PROXY=<VPC CIDR, e.g. 10.0.0.0/8>;
            # two-hop (ALB → Traefik → App): TRUST_PROXY=10.0.0.0/8,172.16.0.0/12.
            # See `templatecentral:add` (auth) — Rate Limiting section.
            ip=request.client.host,
            # Never log: credentials.password
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    logger.info("Login success", user_id=str(user.id), method="password")
    return create_token_response(user)


@router.post("/logout", response_model=dict[str, str])
async def logout(current_user: User = Depends(get_current_user)):
    logger.info("Logout", user_id=str(current_user.id))
    return {"status": "ok"}


@router.post("/token/refresh", response_model=TokenResponse)
async def refresh(current_user: User = Depends(get_current_user)):
    logger.info("Token refresh", user_id=str(current_user.id))
    return create_token_response(current_user)
```

Access denied — log in your auth dependency:

```python
# src/api/dependencies/auth.py  (dependency used by protected routes)
from core.logging import logger


async def require_role(required_role: str, request: Request, current_user: User = Depends(get_current_user)):
    if required_role not in current_user.roles:
        logger.warning(
            "Access denied",
            user_id=str(current_user.id),
            path=request.url.path,
            required_role=required_role,
        )
        raise HTTPException(status_code=404, detail="Not found")
    return current_user
```

**Outbound HTTP calls** — create a wrapper in `src/utils/http_client.py`:

```python
# src/utils/http_client.py
import time
from urllib.parse import urlparse, urlunparse

import httpx

from core.logging import logger


def _sanitize_url(url: str) -> str:
    """Strip query string to avoid logging secrets in query params."""
    parsed = urlparse(url)
    return urlunparse(parsed._replace(query=""))


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
        logger.error("Outbound HTTP error", method="GET", url=safe_url, duration_ms=duration_ms, error=str(exc))
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
            # Never log: statement (full SQL text), parameters (bound values)
        )
```

If using a Python ORM client, add middleware at the client level instead.

**Sanitized request context** — bind extra fields in the `log_requests` middleware (they flow to every line for the request):

```python
# Inside log_requests middleware — bind before call_next
structlog.contextvars.bind_contextvars(
    method=request.method,
    path=request.url.path,
    auth_present="authorization" in request.headers,
    # Never bind the authorization header VALUE — the redaction processor drops it by key,
    # but don't rely on that as your only guard.
)
```

**Cache hits/misses** — log inside your cache utility:

```python
# src/utils/cache.py
from core.logging import logger


async def cache_get(key: str):
    value = await redis.get(key)
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

# Confirm no prohibited fields leak (the redaction processor should mask these by key)
grep -i "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" <log-output>
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
