<!-- ref: add/error-handling/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Error Handling

### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

> **Migration note — response format change**
> This skill replaces FastAPI's default error format (`{"detail": "..."}` / `{"detail": [...]}`)
> with a structured envelope. Before applying, update existing tests:
> - General errors: `response.json()["detail"]` → `response.json()["error"]`
> - Validation field errors: `response.json()["detail"]` → `response.json()["details"]["fieldErrors"]`

**1. Global Exception Handlers (Already Present)**

The template includes `src/error_handler.py`. Enhance it to return consistent field-level errors:

```python
# src/error_handler.py
from collections.abc import Sequence
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from starlette import status
from starlette.exceptions import HTTPException as StarletteHTTPException

from core.exceptions import InvalidInputError, NoResultsFound
from core.logging import logger
from core.security_headers import SECURITY_HEADERS

INTERNAL_SERVER_ERROR_DETAIL = "Internal server error"
_NO_BODY_STATUSES = frozenset({204, 205, 304})


def _sanitize_errors(errors: Sequence[Any]) -> dict[str, list[str]]:
    """Convert Pydantic validation errors to field-level format.

    Returns:
      Dict mapping field names to lists of error messages.
    """
    field_errors: dict[str, list[str]] = {}
    for err in errors:
        loc = err.get("loc", ())
        # Drop the leading 'body'/'query'/'path' segment so nested fields read 'user.email'.
        parts = loc[1:] if len(loc) > 1 else loc
        field_name = ".".join(str(x) for x in parts) or "unknown"
        # Only `msg` is forwarded — Pydantic's `input`/`ctx` echo user data back to the client.
        field_errors.setdefault(field_name, []).append(err.get("msg", "Invalid value"))
    return field_errors


def configure_exceptions(app: FastAPI) -> None:
    """Register exception handlers so all errors are handled in one place."""

    @app.exception_handler(InvalidInputError)
    async def invalid_input_handler(
        request: Request, exc: InvalidInputError
    ) -> JSONResponse:
        logger.warning(
            "Invalid input",
            path=request.url.path,
            detail=str(exc),
            code="INVALID_INPUT",
        )
        field_errors = getattr(exc, "field_errors", {})
        details: dict[str, Any] = {"code": "INVALID_INPUT"}
        if field_errors:
            details["fieldErrors"] = field_errors
        content = {"error": str(exc), "details": details}
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=content,
        )

    @app.exception_handler(NoResultsFound)
    async def no_results_handler(request: Request, exc: NoResultsFound) -> JSONResponse:
        logger.warning(
            "No results found",
            path=request.url.path,
            detail=str(exc),
            code="NOT_FOUND",
        )
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"error": str(exc), "details": {"code": "NOT_FOUND"}},
        )

    # Starlette's base class also covers router-level 404/405 raised outside FastAPI routes.
    # Replacing FastAPI's default handler means re-implementing its no-body rule:
    # 1xx/204/205/304 must go out without a body, or uvicorn errors mid-response
    # and resets the connection.
    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(
        request: Request, exc: StarletteHTTPException
    ) -> Response:
        headers = dict(exc.headers) if exc.headers else None
        if exc.status_code < 200 or exc.status_code in _NO_BODY_STATUSES:
            return Response(status_code=exc.status_code, headers=headers)
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.detail},
            headers=headers,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        field_errors = _sanitize_errors(exc.errors())
        logger.warning(
            "Request validation error",
            path=request.url.path,
            code="VALIDATION_ERROR",
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            content={
                "error": "Validation failed",
                "details": {"fieldErrors": field_errors, "code": "VALIDATION_ERROR"},
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception(
            "Unhandled exception",
            path=request.url.path,
            code="INTERNAL_ERROR",
        )
        # Runs in ServerErrorMiddleware, outside SecurityHeadersMiddleware: add them here.
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": INTERNAL_SERVER_ERROR_DETAIL},
            headers={k.decode(): v.decode() for k, v in SECURITY_HEADERS},
        )
```

**2. API Endpoint Example**

Schemas live in their own modules, one per direction — never inline in the router.

```python
# src/api/schemas/request/project.py
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class CreateProjectRequest(BaseRequestSchema):
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
```

```python
# src/api/schemas/response/project.py
from pydantic import Field

from api.schemas.base import BaseResponseSchema


class ProjectResponse(BaseResponseSchema):
    id: str = Field(description="Project ID.")
    name: str = Field(description="Project name.")
    description: str | None = Field(default=None, description="Project description.")
```

```python
# src/api/routers/projects.py
from fastapi import APIRouter, status

from api.schemas.request.project import CreateProjectRequest
from api.schemas.response.project import ProjectResponse

router = APIRouter(prefix="/projects")


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectResponse)
async def create_project(req: CreateProjectRequest) -> ProjectResponse:
    """Create a new project."""
    raise NotImplementedError("Call the project service to persist the request.")


@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str) -> ProjectResponse:
    """Get a project by ID."""
    raise NotImplementedError(
        "Call the project service; raise NoResultsFound when the lookup returns nothing."
    )
```

Register the router with an `APITags` tag in `src/api/routes.py` (see `add/endpoint/fastapi.md`). Replace each `raise NotImplementedError` with a service call. The router imports no exception types: the service raises `InvalidInputError` for domain validation failures (→ 400) and `NoResultsFound` for missing records (→ 404) from `core.exceptions`, and the handlers in Section 1 turn both into the structured envelope.

**2b. Wiring** — already present: the scaffold's `start_application()` in `src/app.py` calls `configure_exceptions(app)`. Only replace the handler bodies; do NOT add a second `FastAPI(...)` or `configure_exceptions` call.

## Validate

```bash
# Expect 422 with details.fieldErrors.name
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'
python -m pytest test/ -v
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards