<!-- ref: standards/validation-patterns/fastapi.md
     loaded-by: standards/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### FastAPI (Python + Pydantic)

Schemas live in `src/api/schemas/request/` and `src/api/schemas/response/`, one module per resource, subclassing `BaseRequestSchema` / `BaseResponseSchema` (`api.schemas.base`). Bound pagination: `page` default 1, `ge=1`, `le=10_000`; `limit` default 10, `ge=1`, `le=100`; `sort` `max_length=64` with pattern `^(asc|desc)_\w+$` (the OFFSET cost grows with page). `EmailStr` needs `email-validator` in `requirements.in` (installed by `templatecentral:add (auth)`). Login accepts any non-empty password (`min_length=1`): the 12-character minimum is a signup rule, and enforcing it at login locks out existing accounts and discloses the policy.

**1. Router validates, service decides**

FastAPI validates bodies, query models (`Annotated[PaginationQuery, Query()]`), `Form()` models and `UploadFile` before the handler; `src/error_handler.py` turns `RequestValidationError` into a sanitized 422, so a failed `Form()` login never echoes the password. Routers only call services; every check beyond the schema lives in `api/services/`.

```python
# src/api/services/projects.py — upload excerpt
import uuid

from fastapi import UploadFile

from core.exceptions import InvalidInputError

ALLOWED_CONTENT_TYPES = frozenset({"image/jpeg", "image/png", "application/pdf"})
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


async def store_project_file(file: UploadFile) -> str:
    """Validate an upload and persist it under a server-generated key."""
    # content_type is client-supplied, so it is only a first filter: sniff magic bytes for sensitive files, and keep the error message fixed.
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise InvalidInputError("File type must be JPEG, PNG, or PDF")

    # file.size comes from the parsed multipart spool and rejects before read; the post-read length check covers a missing size.
    if file.size is not None and file.size > MAX_UPLOAD_BYTES:
        raise InvalidInputError("File must be under 10MB")
    contents = await file.read()
    if len(contents) > MAX_UPLOAD_BYTES:
        raise InvalidInputError("File must be under 10MB")

    # file.filename is attacker-controlled, including ../, absolute paths and NUL bytes: never build a storage path from it, keep it as display metadata.
    storage_key = str(uuid.uuid4())
    # Hand storage_key + contents to the storage layer here.
    return storage_key
```

> Also cap the request body at the reverse proxy / ingress — `UploadFile` spools the whole part to disk before any of these checks run.

**2. External API Response Validation**

```python
# src/integrations/github_service.py
from urllib.parse import quote

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from core.exceptions import NoResultsFoundError
from core.logging import logger


class GitHubUser(BaseModel):
    # External API shape: ignore unknown fields, and don't inherit BaseResponseSchema
    model_config = ConfigDict(extra="ignore")

    id: int
    login: str = Field(min_length=1)
    email: str | None = None


async def fetch_github_user(username: str) -> GitHubUser:
    """Fetch a GitHub user; an absent user raises NoResultsFoundError, other failures RuntimeError."""
    # Encode the path segment — an unencoded `../` or `?` rewrites the request URL
    url = f"https://api.github.com/users/{quote(username, safe='')}"
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.get(url)

    if response.status_code == httpx.codes.NOT_FOUND:
        raise NoResultsFoundError("GitHub user not found")
    response.raise_for_status()

    try:
        return GitHubUser.model_validate(response.json())
    except ValidationError as e:
        # An upstream contract break is a 500, not the caller's 400; str(e) echoes input values, so log structured errors without them and drop the chain.
        logger.error(
            "GitHub response failed validation",
            errors=e.errors(include_input=False, include_url=False),
        )
        raise RuntimeError("Invalid GitHub API response") from None
```

Verify: an empty `name` posts to a 422; `python -m pytest test/ -v`.

## After Writing Code

Dispatch in order:
1. the project's check command (`ruff check src/ && python -m pyright src/`) — validate compilation
2. review utility (`cat "<skill-dir>/../review/SKILL.md"`) — check code standards
