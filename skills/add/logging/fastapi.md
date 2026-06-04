<!-- ref: add/logging/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Structured Logging

**What already exists in the template:**
- `python-json-logger` in `requirements.txt`
- `src/core/logging.py` — full logging setup
- `src/core/json/logging.json` — JSON formatter config
- Import via `from core.logging import logger`

#### Tier 1 — Base

Add an HTTP middleware in `src/app.py` for request/response logging.

> **Ordering note**: `@app.middleware("http")` is LIFO — the last decorator registered runs first. Place this decorator BEFORE `app.add_middleware(CORSMiddleware, ...)` in the file so it wraps the request outermost and sees the final response status. If the scaffold uses `app.add_middleware()` for everything, add this as `app.add_middleware(LogRequestsMiddleware)` instead to keep ordering predictable.

```python
# src/app.py  (place before add_middleware calls to run outermost)
import time
from fastapi import Request
from core.logging import logger

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.monotonic()
    response = await call_next(request)
    duration_ms = round((time.monotonic() - start) * 1000)
    user_id = getattr(request.state, "user_id", None)
    logger.info(
        "Request",
        extra={
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "user_id": user_id,
        },
    )
    return response
```

App startup/shutdown — add lifespan events in `src/app.py`:

```python
# src/app.py
from contextlib import asynccontextmanager
from core.logging import logger
from core.config import api_settings, common_settings

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("App starting", extra={"port": api_settings.API_PORT, "environment": common_settings.ENVIRONMENT})
    yield
    logger.info("App shutdown", extra={"environment": common_settings.ENVIRONMENT})

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
            extra={
                "reason": "invalid_credentials",
                "ip": request.client.host,
                # Never log: credentials.password
            },
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    logger.info(
        "Login success",
        extra={"user_id": str(user.id), "method": "password"},
    )
    return create_token_response(user)

@router.post("/logout", response_model=dict[str, str])
async def logout(current_user: User = Depends(get_current_user)):
    logger.info("Logout", extra={"user_id": str(current_user.id)})
    return {"status": "ok"}

@router.post("/token/refresh", response_model=TokenResponse)
async def refresh(current_user: User = Depends(get_current_user)):
    logger.info("Token refresh", extra={"user_id": str(current_user.id)})
    return create_token_response(current_user)
```

Access denied — log in your auth dependency:

```python
# src/core/auth.py  (dependency used by protected routes)
from core.logging import logger

async def require_role(required_role: str, request: Request, current_user: User = Depends(get_current_user)):
    if required_role not in current_user.roles:
        logger.warning(
            "Access denied",
            extra={
                "user_id": str(current_user.id),
                "path": request.url.path,
                "required_role": required_role,
            },
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
            extra={"method": "GET", "url": safe_url, "status_code": response.status_code, "duration_ms": duration_ms},
        )
        return response
    except Exception as exc:
        duration_ms = round((time.monotonic() - start) * 1000)
        logger.error(
            "Outbound HTTP error",
            extra={"method": "GET", "url": safe_url, "duration_ms": duration_ms, "error": str(exc)},
        )
        raise
```

**Key domain events** — log inside service-layer functions:

```python
# src/services/projects.py  (example — adapt to your domain)
from core.logging import logger

async def create_project(data: CreateProjectRequest, user_id: str) -> Project:
    project = await db.projects.insert(data)
    logger.info("Project created", extra={"user_id": user_id, "project_id": str(project.id)})
    return project
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — add a SQLAlchemy event listener:

```python
# src/core/db.py  (add after engine creation)
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
            extra={"query_name": query_name, "duration_ms": total_ms},
            # Never log: statement (full SQL text), parameters (bound values)
        )
```

If using a Python ORM client, add middleware at the client level instead.

**Sanitized request context** — extend the HTTP middleware in `src/app.py`:

```python
# Inside log_requests middleware — add before call_next
auth_present = "authorization" in request.headers
logger.debug(
    "Request context",
    extra={
        "method": request.method,
        "path": request.url.path,
        "auth_present": auth_present,
        # Never log: request.headers.get("authorization")
    },
)
```

**Cache hits/misses** — log inside your cache utility:

```python
# src/utils/cache.py
from core.logging import logger

async def cache_get(key: str):
    value = await redis.get(key)
    logger.debug("Cache lookup", extra={"cache_key": key, "hit": value is not None})
    return value
```

---

## Verification

```bash
# Tier 1
uvicorn src.app:app --reload
curl http://localhost:8000/health
# Expect JSON log line: { method: "GET", path: "/health", status_code: 200, duration_ms: <n> }

# Tier 2
# Attempt login with wrong credentials — expect login failure log
# Attempt login with correct credentials — expect login success log
# Hit a protected route without a token — expect access denied log

# Tier 3
# Trigger a slow DB query (or lower threshold temporarily to 0 for testing)
# Expect: { query_name: "...", duration_ms: <n> } warn log

# Confirm no prohibited fields
grep -i "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" <log-output>
```

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards