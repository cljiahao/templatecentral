<!-- ref: add/error-handling/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI — Error Handling

> **Migration note — response format change**
> This skill replaces FastAPI's default error format (`{"detail": "..."}` / `{"detail": [...]}`)
> with a structured envelope. Before applying, update existing tests:
> - General errors: `response.json()["detail"]` → `response.json()["error"]`
> - Validation field errors: `response.json()["detail"]` → `response.json()["details"]["fieldErrors"]`

**1. Global Exception Handlers (Already Present)**

The template includes `src/error_handler.py`. Enhance it to return consistent field-level errors:

```python
# src/error_handler.py
from typing import Any, Sequence

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette import status

from core.exceptions import InvalidInputError, NoResultsFound
from core.logging import logger

INTERNAL_SERVER_ERROR_DETAIL = "Internal Server Error"


def _sanitize_errors(errors: Sequence[Any]) -> dict[str, list[str]]:
    """Convert Pydantic validation errors to field-level format.
    
    Returns:
      Dict mapping field names to lists of error messages.
    """
    field_errors: dict[str, list[str]] = {}
    for err in errors:
        loc = err.get('loc', [])
        msg = err.get('msg', 'Invalid value')
        
        # loc is a tuple like ('body', 'email') or ('body', 'user', 'email').
        # Skip the first segment ('body', 'query', 'path') and join the rest with '.'
        # so nested schemas produce 'user.email' rather than just 'email'.
        if len(loc) > 1:
            field_name = '.'.join(str(x) for x in loc[1:])
        elif len(loc) == 1:
            field_name = str(loc[0])
        else:
            field_name = 'unknown'
        
        if field_name not in field_errors:
            field_errors[field_name] = []
        field_errors[field_name].append(msg)
    
    return field_errors


def configure_exceptions(app: FastAPI) -> None:
    """Register exception handlers so all errors are handled in one place."""

    @app.exception_handler(InvalidInputError)
    async def invalid_input_handler(
        request: Request, exc: InvalidInputError
    ) -> JSONResponse:
        logger.warning(
            "Invalid input",
            extra={"path": request.url.path, "detail": str(exc), "code": "INVALID_INPUT"},
        )
        # Allow services to attach field-level errors to the exception
        field_errors = getattr(exc, 'field_errors', {})
        content = {
            "error": str(exc),
            "details": {"code": "INVALID_INPUT"}
        }
        if field_errors:
            content["details"]["fieldErrors"] = field_errors
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=content,
        )

    @app.exception_handler(NoResultsFound)
    async def no_results_handler(
        request: Request, exc: NoResultsFound
    ) -> JSONResponse:
        logger.warning(
            "No results found",
            extra={"path": request.url.path, "detail": str(exc), "code": "NOT_FOUND"},
        )
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"error": str(exc), "details": {"code": "NOT_FOUND"}},
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.detail},
            headers=dict(exc.headers) if exc.headers else None,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        field_errors = _sanitize_errors(exc.errors())
        logger.warning(
            "Request validation error",
            extra={"path": request.url.path, "code": "VALIDATION_ERROR"},
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": "Validation failed",
                "details": {"fieldErrors": field_errors, "code": "VALIDATION_ERROR"},
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        logger.exception(
            "Unhandled exception",
            extra={"path": request.url.path, "code": "INTERNAL_ERROR"},
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": INTERNAL_SERVER_ERROR_DETAIL},
        )
```

**2. API Endpoint Example**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, status
from pydantic import BaseModel, Field

from api.schemas.base import BaseRequestSchema
from core.exceptions import InvalidInputError

router = APIRouter(prefix="/projects", tags=["projects"])


class CreateProjectRequest(BaseRequestSchema):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)


class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectResponse)
async def create_project(req: CreateProjectRequest) -> ProjectResponse:
    """Create a new project."""
    # Your logic: project = await db.projects.insert(req.model_dump())
    return ProjectResponse(id="1", name=req.name, description=req.description)


@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str) -> ProjectResponse:
    """Get a project by ID."""
    # Your logic: project = await db.projects.find_by_id(project_id)
    # if not project:
    #     raise NoResultsFound("Project not found")
    return ProjectResponse(id=project_id, name="Sample Project", description=None)
```

**2b. Wiring (Already Present — No Changes Needed)**

The scaffold's `src/app.py` already imports `configure_exceptions` and calls it inside `start_application()`. This skill only replaces the handler bodies in `src/error_handler.py` (Section 1) — do NOT create a new `app = FastAPI(...)` instance or add a duplicate `configure_exceptions(app)` call. Verify the existing wiring looks like this:

```python
# src/app.py — already present in the scaffold; no edits required
def start_application() -> FastAPI:
    app = FastAPI(...)
    configure_security_headers(app)
    configure_cors(app)
    configure_proxy_headers(app)
    configure_exceptions(app)   # ← already wired
    app.include_router(router)
    return app
```

## Testing / Verification

```bash
# Test endpoint with validation error
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'

# Expected 422 response includes fieldErrors mapping

pytest -v
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards