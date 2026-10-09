<!-- ref: add/integration/fastapi.md
     loaded-by: add/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## FastAPI

Create a new third-party API integration in a FastAPI project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

> **Placeholder names**: `<name>` in the file paths below and `github`/`Github`/`GITHUB` in the code are the same integration name in three casings. Substitute your actual service name for all of them (e.g. `stripe`/`Stripe`/`STRIPE`) — writing a literal `<name>_client.py` while the imports still say `integrations.github_client` breaks every import in this skill.

### Architecture

```
config → client → schemas → service → dependency injection → router
```

- **client** — Async HTTP client using `httpx`
- **schemas** — Pydantic models for validating external API responses
- **service** — Business logic wrapping the client
- **dependency** — FastAPI dependency for injecting the service

### Dependencies

Add to `requirements.txt`:
- `httpx` — Async HTTP client

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Integration Directories

The base template does not include `src/integrations/` or `src/api/dependencies/`. Create them now:

```bash
mkdir -p src/integrations src/api/dependencies
touch src/integrations/__init__.py src/api/dependencies/__init__.py
```

#### 2. Create the Client

**`src/integrations/<name>_client.py`**:

```python
from typing import Any
from urllib.parse import quote

import httpx


class GithubClient:
    """HTTP client for the GitHub API."""

    def __init__(self, base_url: str, token: str) -> None:
        self._client = httpx.AsyncClient(
            base_url=base_url,
            headers={"Authorization": f"Bearer {token}"},
            # httpx defaults to follow_redirects=False — keep it so the token never follows a redirect.
            timeout=30.0,
        )

    async def get_repos(self) -> list[dict[str, Any]]:
        """Fetch the authenticated user's repositories."""
        response = await self._client.get("/user/repos")
        response.raise_for_status()
        return response.json()

    async def get_repo(self, owner: str, repo: str) -> dict[str, Any]:
        """Fetch a specific repository."""
        # safe="" also escapes "/" so a caller-supplied "../" cannot change the upstream path.
        response = await self._client.get(f"/repos/{quote(owner, safe='')}/{quote(repo, safe='')}")
        response.raise_for_status()
        return response.json()

    async def close(self) -> None:
        await self._client.aclose()
```

#### 3. Define Response Schemas

**`src/integrations/<name>_schemas.py`**:

Do NOT inherit `BaseResponseSchema` (`extra="forbid"` rejects unknown upstream fields; camelCase aliases rename them). Use plain `BaseModel` with `extra="ignore"`:

```python
from pydantic import BaseModel, ConfigDict, Field


class GithubRepo(BaseModel):
    """GitHub repository as returned by the upstream API (snake_case preserved)."""

    model_config = ConfigDict(extra="ignore")

    id: int = Field(description="Repository ID.")
    full_name: str = Field(description="Full repository name (owner/repo).")
    description: str | None = Field(default=None, description="Repository description.")
    html_url: str = Field(description="URL to the repository.")
    stargazers_count: int = Field(default=0, description="Star count.")
```

#### 4. Create the Service

**`src/integrations/<name>_service.py`**:

The service maps upstream failures to domain errors — otherwise `httpx` exceptions and `ValidationError` reach the catch-all handler as a generic 500.

```python
from collections.abc import Awaitable, Callable
from typing import Any

import httpx
from fastapi import HTTPException, status
from pydantic import TypeAdapter, ValidationError

from core.exceptions import NoResultsFound
from core.logging import logger
from integrations.github_client import GithubClient
from integrations.github_schemas import GithubRepo

_REPO_LIST = TypeAdapter(list[GithubRepo])


class GithubService:
    """GitHub integration: upstream calls mapped to domain errors and validated models."""

    def __init__(self, client: GithubClient) -> None:
        self._client = client

    async def list_repos(self) -> list[GithubRepo]:
        raw = await self._call(self._client.get_repos)
        return self._validate(lambda: _REPO_LIST.validate_python(raw))

    async def get_repo(self, owner: str, repo: str) -> GithubRepo:
        raw = await self._call(lambda: self._client.get_repo(owner, repo))
        return self._validate(lambda: GithubRepo.model_validate(raw))

    async def _call(self, fn: Callable[[], Awaitable[Any]]) -> Any:
        try:
            return await fn()
        except httpx.HTTPStatusError as exc:
            # Log status only — never the request, whose headers carry the token.
            logger.warning("GitHub upstream error", status=exc.response.status_code)
            if exc.response.status_code == status.HTTP_404_NOT_FOUND:
                raise NoResultsFound("Repository not found.") from exc
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Upstream service error.") from exc
        except httpx.RequestError as exc:
            logger.warning("GitHub upstream unreachable", error_type=type(exc).__name__)
            raise HTTPException(status.HTTP_504_GATEWAY_TIMEOUT, "Upstream service unreachable.") from exc

    @staticmethod
    def _validate[T](parse: Callable[[], T]) -> T:
        try:
            return parse()
        except ValidationError as exc:
            # Never return the errors — their paths/inputs leak the upstream schema and data.
            logger.error("GitHub response failed validation", error_count=exc.error_count())
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Upstream service error.") from exc
```

`NoResultsFound` maps to 404 via `src/error_handler.py`; upstream failures map to 502/504 so a broken dependency is never reported as a bug here.

#### 5. Add Config

Add to `APISettings` in **`src/core/config.py`** (`from pydantic import SecretStr`):

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    GITHUB_API_URL: str = Field(default="https://api.github.com")
    # SecretStr keeps the token out of repr()/logs; read it with .get_secret_value().
    GITHUB_TOKEN: SecretStr
```

Ask the user to add `GITHUB_TOKEN` to `src/.env` (real token — never commit; agent edits to `.env` files are hook-blocked by design):
```
GITHUB_TOKEN=
```

Document in `src/.env.default`:
```
GITHUB_TOKEN=your_github_token_here
```

#### 6. Create a Dependency

**`src/api/dependencies/<name>.py`**:

```python
from collections.abc import AsyncGenerator

from core.config import api_settings
from integrations.github_client import GithubClient
from integrations.github_service import GithubService


async def get_github_service() -> AsyncGenerator[GithubService, None]:
    """Provide a GithubService instance with managed client lifecycle."""
    client = GithubClient(
        base_url=api_settings.GITHUB_API_URL,
        token=api_settings.GITHUB_TOKEN.get_secret_value(),
    )
    try:
        yield GithubService(client)
    finally:
        await client.close()
```

#### 7. Create the Router

First, add a tag to `src/api/tags.py`:

```python
class APITags(StrEnum):
    # ... existing tags ...
    GITHUB = "github"
```

Then create **`src/api/routers/<name>.py`**:

```python
from fastapi import APIRouter, Depends

from api.dependencies.github import get_github_service
from integrations.github_schemas import GithubRepo
from integrations.github_service import GithubService

router = APIRouter(prefix="/github")


@router.get("/repos", response_model=list[GithubRepo])
async def list_repos(service: GithubService = Depends(get_github_service)) -> list[GithubRepo]:
    """List authenticated user's GitHub repos."""
    return await service.list_repos()
```

#### 8. Register the Router

Add the router to **`src/api/routes.py`**:

```python
from api.routers import github
from api.tags import APITags

router.include_router(github.router, tags=[APITags.GITHUB])
```

Mandatory — the router is unreachable until registered.

### Rules

- Use `httpx.AsyncClient` for async HTTP — not `requests`.
- Validate all external responses with Pydantic schemas before returning to callers.
- Client handles HTTP only — no business logic.
- URL-encode every caller-supplied path segment with `quote(value, safe="")`.
- Map `httpx.HTTPStatusError`, `httpx.RequestError`, and `ValidationError` in the service — never return upstream error bodies or validation details to the client.
- Keep the 30 s timeout and `follow_redirects=False`. No automatic retries — add them only for idempotent GETs, with backoff.
- Use FastAPI dependencies for lifecycle management (create → yield → close).
- Keep API tokens in environment variables / config — never hardcode.
- Place integration files in `src/integrations/` — not in `api/`.

### Validate

```bash
python -m pytest test/ -v
ruff check src/
```

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate the server starts and tests pass
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards