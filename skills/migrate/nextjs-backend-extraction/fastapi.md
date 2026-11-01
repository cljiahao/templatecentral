<!-- ref: migrate/nextjs-backend-extraction/fastapi.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js → FastAPI Backend Extraction

Moves `src/app/api/` and the integrations it uses into a sibling FastAPI project; Next.js becomes a pure frontend.

**Read `common.md` first** (Phases 1, 2, the Phase 3 skeleton, 8–10); Phases 3–7 are below.

```bash
cat "<skill-dir>/nextjs-backend-extraction/common.md"
```

**Phase 1 FastAPI deltas:** In 1d, the TS base clients (`fetch-client.ts`, `axios-client.ts`) are not moved (Phase 5 uses `httpx`). Assessment Database line: `[✓ Drizzle / ✓ Kysely (both require an ORM choice at Phase 6) / ✓ Mongoose → PyMongo async / None detected]`.

---

## Phase 3 — Scaffold FastAPI (autonomous)

```bash
cat "<skill-dir>/../scaffold/fastapi/source-files.md"
```

Set `PROJECT_NAME` in `src/.env.default`.

---

## Phase 4 — Migrate API Routes (autonomous)

Create a FastAPI router for each Phase 1c `route.ts`.

**Mapping:**

| Next.js | FastAPI |
|---|---|
| `src/app/api/<resource>/route.ts` | `src/api/routers/<resource>.py` in `../[project-name]-api` |
| `export async function GET()` | `@router.get("/<resource>")` |
| `export async function POST(request: Request)` | `@router.post("/<resource>", status_code=201)` with Pydantic request model |
| `export async function PUT(request, { params })` | `@router.put("/<resource>/{id}")` |
| `export async function PATCH(request, { params })` | `@router.patch("/<resource>/{id}")` |
| `export async function DELETE(_, { params })` | `@router.delete("/<resource>/{id}")` |
| `handleApiError(label, error)` / error `NextResponse` | Service raises `NoResultsFound` (404) / `InvalidInputError` (400) from `core.exceptions` |
| Dynamic segment `[id]/route.ts` | `/{id}` path parameter on the same router |
| Zod `safeParse` validation | Pydantic model as function parameter |

Layers: **router → service → schemas**. No business logic in the router.

**Router template** (adapt for each resource):

```python
# src/api/routers/users.py
from fastapi import APIRouter

from api.schemas.request.users import CreateUserRequest
from api.schemas.response.users import UserResponse
from api.services.users import UsersService

router = APIRouter()


@router.get("/users", response_model=list[UserResponse])
async def get_users() -> list[UserResponse]:
    return await UsersService.find_all()


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str) -> UserResponse:
    return await UsersService.find_one(user_id)


@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(body: CreateUserRequest) -> UserResponse:
    return await UsersService.create(body)
```

**Request schema template:**

```python
# src/api/schemas/request/users.py
from pydantic import EmailStr, Field

from api.schemas.base import BaseRequestSchema


class CreateUserRequest(BaseRequestSchema):
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
```

Port every Zod constraint — a bare `str` silently drops the validation. `EmailStr` needs `email-validator` in `requirements.txt`. Fields are `snake_case`; `BaseRequestSchema`'s `to_camel` alias accepts both key styles.

**Response schema template:**

```python
# src/api/schemas/response/users.py
from api.schemas.base import BaseResponseSchema


class UserResponse(BaseResponseSchema):
    id: str
    name: str
    email: str
```

**Service** — `src/api/services/users.py`: `UsersService` whose `find_all()`, `find_one(user_id)` (raises `NoResultsFound` when absent) and `create(body: CreateUserRequest)` take over the handler bodies.

**Register each new router in `../[project-name]-api/src/api/routes.py`:**

1. Add `USERS = "users"` (or the appropriate resource name) to `APITags` in `src/api/tags.py`.
2. Import the router module and register it in `src/api/routes.py`:

```python
from api.routers import users
from api.tags import APITags

router.include_router(users.router, tags=[APITags.USERS])
```

**Remove the scaffold's example** after adding all routers:
- Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
- Remove the `example` import and its `include_router(example.router, ...)` line from `src/api/routes.py`
- Remove `EXAMPLE` from `APITags` in `src/api/tags.py`

---

## Phase 5 — Migrate Integrations (autonomous)

For each Phase 1d integration:

**TypeScript FetchClient/AxiosClient subclass → Python httpx wrapper:**

```python
# Example: src/integrations/github_client.py in ../[project-name]-api
from functools import lru_cache

import httpx

from core.config import github_settings


class GithubClient:
    def __init__(self) -> None:
        self._base_url = github_settings.GITHUB_API_URL
        self._headers = {
            "Authorization": f"Bearer {github_settings.GITHUB_TOKEN.get_secret_value()}"
        }

    async def get_repos(self) -> list[dict]:
        async with httpx.AsyncClient(
            base_url=self._base_url, headers=self._headers
        ) as client:
            response = await client.get("/repos")
            response.raise_for_status()
            return response.json()


@lru_cache(maxsize=1)
def get_github_client() -> GithubClient:
    return GithubClient()
```

`github_settings` is a `pydantic-settings` class beside `APISettings` in `src/core/config.py` (`GITHUB_API_URL: str`, `GITHUB_TOKEN: SecretStr`), so a missing value fails at boot. Inject the client with `Annotated[GithubClient, Depends(get_github_client)]` and pass it to the service.

Then apply the Phase 5 cleanup in `common.md`.

---

## Phase 6 — Migrate Database (autonomous)

**If no database detected in Phase 1f:** Skip this phase.

**FastAPI + Drizzle or Kysely:** ⛔ GATE — both are TypeScript-only.

Ask:
> "Your Next.js project uses [Drizzle / Kysely] (TypeScript-only). FastAPI requires a Python ORM. Which would you like to use?
> - SQLAlchemy — relational databases (PostgreSQL, MySQL, SQLite)
> - PyMongo async — MongoDB (Pydantic models + repositories; Beanie ODM only on explicit request — it pins Python 3.13)"

Then load and follow the matching skill:
```bash
# If SQLAlchemy
cat "<skill-dir>/../add/database/python/sqlalchemy.md"

# If MongoDB (Beanie instead only if the user explicitly asked for it)
cat "<skill-dir>/../add/database/python/pymongo-async.md"
```

It scaffolds only the connection layer. Port each Drizzle table / Kysely `types.ts` interface to a SQLAlchemy model or a Pydantic model + repository, and have the user review the ported schemas before Phase 7. After they confirm, delete `src/integrations/database/` (and any `drizzle.config.ts`) from Next.js.

**FastAPI + Mongoose:**

Load and follow the PyMongo async skill (`beanie.md` only if the user explicitly wants an ODM — it pins Python 3.13):
```bash
cat "<skill-dir>/../add/database/python/pymongo-async.md"
```

Port each Mongoose schema to a Pydantic model in `src/models/` plus a `BaseRepository` subclass (unique indexes go into `ensure_indexes`). Delete `src/integrations/database/` from Next.js.

---

## Phase 7 — Migrate Auth (autonomous)

**If `proxy.ts` not detected in Phase 1g:** Skip this phase.

Load and follow the FastAPI auth skill in `../[project-name]-api`:
```bash
cat "<skill-dir>/../add/auth/fastapi.md"
```

If Phase 6 migrated a database, `auth_service.py` is still a 501 stub (Phase 6 ran first). Replace it now:

| Phase 6 database | Follow |
|---|---|
| SQLAlchemy | "Completing Auth Integration" in `cat "<skill-dir>/../add/database/python/sqlalchemy.md"` |
| PyMongo async | `cat "<skill-dir>/../add/database/python/pymongo-async-auth.md"` |
| Beanie | "Completing Auth Integration" in `cat "<skill-dir>/../add/database/python/beanie.md"` |

Then apply the Phase 7 `proxy.ts` rule in `common.md`.

---

## Phases 8–10 — FastAPI-specific details

**Phase 8, step 0 CORS:** none (same-origin through the `/api/external` rewrite). Do not set `allow_credentials=True` for the frontend's origin.

**Phase 9 — FastAPI CORS config:** no change. `CORS_ORIGINS` (in `src/.env.default`, the only env-defaults file) matters only for other browser origins using Bearer tokens.

**Phase 10 — Verify commands:**
```bash
# 1. FastAPI backend
cd ../[project-name]-api
pip install -r requirements.txt && python -m pytest test/ -q

# 2. Next.js frontend
cd [original-project-path]
pnpm build && pnpm test
```

The rest of Phases 8–10 is in `common.md`.
