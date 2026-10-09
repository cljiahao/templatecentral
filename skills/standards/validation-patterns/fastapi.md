<!-- ref: standards/validation-patterns/fastapi.md
     loaded-by: standards/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### FastAPI (Python + Pydantic)

**1. Request Model with Validation**

Schemas live under `src/api/schemas/request/` and `src/api/schemas/response/`, one module per resource.

```python
# src/api/schemas/request/project.py
from pydantic import ConfigDict, Field

from api.schemas.base import BaseRequestSchema


class CreateProjectRequest(BaseRequestSchema):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)

    model_config = ConfigDict(
        json_schema_extra={"example": {"name": "My Project", "description": "A great project"}}
    )
```

```python
# src/api/schemas/response/project.py
from datetime import datetime

from api.schemas.base import BaseResponseSchema


class ProjectResponse(BaseResponseSchema):
    id: str
    name: str
    description: str | None
    created_at: datetime
```

`EmailStr` needs `email-validator` in `requirements.txt` (installed by `templatecentral:add (auth)`).

```python
# src/api/schemas/request/auth.py
from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class LoginRequest(BaseRequestSchema):
    email: EmailStr
    # Login accepts any non-empty password — the 12-char minimum is a signup/reset rule.
    # Enforcing it here would lock out existing accounts and disclose the policy.
    password: str = Field(..., min_length=1, max_length=128)
```

```python
# src/api/schemas/request/pagination.py
from pydantic import Field

from api.schemas.base import BaseRequestSchema


class PaginationQuery(BaseRequestSchema):
    page: int = Field(default=1, ge=1, le=10_000)
    limit: int = Field(default=10, ge=1, le=100)
    sort: str | None = Field(None, max_length=64, pattern=r"^(asc|desc)_\w+$")
```

**2. Router validates, service decides**

Request bodies, query models, and `UploadFile` are validated by FastAPI before the handler runs; a failure raises `RequestValidationError`, which `src/error_handler.py` turns into a sanitized 422. Routers stay thin — every check beyond the schema lives in `api/services/`.

```python
# src/api/routers/projects.py
from typing import Annotated

from fastapi import APIRouter, File, Query, UploadFile, status

from api.schemas.request.pagination import PaginationQuery
from api.schemas.request.project import CreateProjectRequest
from api.schemas.response.project import ProjectResponse
from api.services import projects as project_service

router = APIRouter(prefix="/projects", tags=["projects"])


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectResponse)
async def create_project(req: CreateProjectRequest) -> ProjectResponse:
    return await project_service.create_project(req)


@router.get("", response_model=list[ProjectResponse])
async def list_projects(query: Annotated[PaginationQuery, Query()]) -> list[ProjectResponse]:
    return await project_service.list_projects(query)


@router.post("/upload", response_model=dict[str, dict[str, str]])
async def upload_project_file(file: Annotated[UploadFile, File()]) -> dict[str, dict[str, str]]:
    storage_key = await project_service.store_project_file(file)
    return {"data": {"storageKey": storage_key}}
```

```python
# src/api/services/projects.py (upload excerpt)
import uuid

from fastapi import UploadFile

from core.exceptions import InvalidInputError

ALLOWED_CONTENT_TYPES = frozenset({"image/jpeg", "image/png", "application/pdf"})
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


async def store_project_file(file: UploadFile) -> str:
    """Validate an upload and persist it under a server-generated key."""
    # content_type is the client-supplied header — a cheap first filter only. For anything
    # security-sensitive, also sniff magic bytes (e.g. python-magic) before storing/serving.
    # The message is fixed: never echo the submitted value back.
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise InvalidInputError("File type must be JPEG, PNG, or PDF")

    # file.size comes from the parsed multipart spool, so it can reject before read();
    # the post-read length check covers a missing size.
    if file.size is not None and file.size > MAX_UPLOAD_BYTES:
        raise InvalidInputError("File must be under 10MB")
    contents = await file.read()
    if len(contents) > MAX_UPLOAD_BYTES:
        raise InvalidInputError("File must be under 10MB")

    # file.filename is attacker-controlled (`../`, absolute paths, NUL bytes) — NEVER build
    # a storage path from it. Keep it as display metadata only.
    storage_key = str(uuid.uuid4())
    # Hand storage_key + contents to the storage layer here.
    return storage_key
```

> Also cap the request body at the reverse proxy / ingress — `UploadFile` spools the whole part to disk before any of these checks run.

**3. Form Data Validation**

Annotate a Pydantic model with `Form()` — FastAPI validates form bodies against the model natively (model form data since 0.113, `extra="forbid"` support since 0.114). A failure goes through the same sanitized 422 handler, so the submitted password is never echoed.

```python
# src/api/routers/auth.py
from typing import Annotated

from fastapi import APIRouter, Form, status

from api.schemas.request.auth import LoginRequest
from api.services import auth as auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=dict[str, dict[str, str]], status_code=status.HTTP_200_OK)
async def login(req: Annotated[LoginRequest, Form()]) -> dict[str, dict[str, str]]:
    return await auth_service.login(req)
```

**4. External API Response Validation**

```python
# src/integrations/github_service.py
from urllib.parse import quote

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from core.exceptions import NoResultsFound
from core.logging import logger


class GitHubUser(BaseModel):
    # External API shape: ignore unknown fields, and don't inherit BaseResponseSchema
    model_config = ConfigDict(extra="ignore")

    id: int
    login: str = Field(min_length=1)
    email: str | None = None


async def fetch_github_user(username: str) -> GitHubUser:
    """Fetch a GitHub user; raise NoResultsFound (404) if absent, RuntimeError (500) otherwise."""
    # Encode the path segment — an unencoded `../` or `?` rewrites the request URL
    url = f"https://api.github.com/users/{quote(username, safe='')}"
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.get(url)

    if response.status_code == httpx.codes.NOT_FOUND:
        raise NoResultsFound("GitHub user not found")
    response.raise_for_status()

    try:
        return GitHubUser.model_validate(response.json())
    except ValidationError as e:
        # An upstream contract break is a 500, not the caller's 400. str(e) echoes input
        # values, so log the structured errors without them and drop the exception chain.
        logger.error(
            "GitHub response failed validation",
            errors=e.errors(include_input=False, include_url=False),
        )
        raise RuntimeError("Invalid GitHub API response") from None
```

## Testing / Verification

```bash
# Empty name → 422
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'

python -m pytest test/ -v
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards