<!-- ref: migrate/nextjs-backend-extraction/fastapi.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = FastAPI. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js → FastAPI Backend Extraction

Extracts `src/app/api/` route handlers and relevant `src/integrations/` clients from a Next.js project into a sibling FastAPI project. Next.js becomes a pure frontend.

**Read `common.md` first.** Phases 1, 2, the Phase 3 skeleton, and Phases 8–10 live in common.md; stack-specific Phases 3–7 are below. Variable substitutions: `[BACKEND]` = FastAPI, `[DEV_PORT]` = 8000, `[CORS_VAR]` = `CORS_ORIGINS`.

```bash
cat "<skill-dir>/nextjs-backend-extraction/common.md"
```

**Phase 1 FastAPI deltas:** In 1d, TypeScript base clients (`fetch-client.ts`, `axios-client.ts`) are NOT moved — replaced by `httpx` wrappers in Phase 5. Assessment Database line: `[✓ Drizzle (requires ORM choice at Phase 6) / ✓ Mongoose → Beanie / None detected]`.

---

## Phase 3 — Scaffold FastAPI (autonomous)

```bash
cat "<skill-dir>/../scaffold/fastapi/config-files.md"
cat "<skill-dir>/../scaffold/fastapi/source-files.md"
```

Set the project name in `src/.env.default`. (See `common.md` Phase 3 for shared context.)

---

## Phase 4 — Migrate API Routes (autonomous)

For each `route.ts` file identified in Phase 1c, create the corresponding FastAPI router.

**Mapping:**

| Next.js | FastAPI |
|---|---|
| `src/app/api/<resource>/route.ts` | `src/api/routers/<resource>.py` in `../[project-name]-api` |
| `export async function GET()` | `@router.get('/')` |
| `export async function POST(request: Request)` | `@router.post('/', status_code=201)` with Pydantic request model |
| `export async function PUT(request, { params })` | `@router.put('/{id}')` with path param |
| `export async function PATCH(request, { params })` | `@router.patch('/{id}')` with path param |
| `export async function DELETE(_, { params })` | `@router.delete('/{id}')` |
| `handleApiError(label, error)` | `raise HTTPException(status_code=..., detail=...)` |
| Dynamic segment `[id]/route.ts` | `/{id}` path parameter on the same router |
| Zod `safeParse` validation | Pydantic model as function parameter (FastAPI validates automatically) |

The scaffold uses a layered architecture: **router → service → schemas**. Do not put business logic in the router file.

**Router template** (adapt for each resource):

```python
# src/api/routers/users.py
from fastapi import APIRouter, HTTPException

from api.schemas.request.users import CreateUserRequest
from api.schemas.response.users import UserResponse
from api.services.users import UsersService

router = APIRouter()


@router.get("/users", response_model=list[UserResponse])
async def get_users() -> list[UserResponse]:
    return await UsersService.find_all()


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str) -> UserResponse:
    user = await UsersService.find_one(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Not found")
    return user


@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(body: CreateUserRequest) -> UserResponse:
    return await UsersService.create(body)
```

**Request schema template:**

```python
# src/api/schemas/request/users.py
from api.schemas.base import BaseRequestSchema


class CreateUserRequest(BaseRequestSchema):
    name: str
    email: str
```

Note: `BaseRequestSchema` uses `alias_generator=to_camel` — define fields in `snake_case` and FastAPI will accept both `snake_case` and `camelCase` JSON keys automatically.

**Response schema template:**

```python
# src/api/schemas/response/users.py
from api.schemas.base import BaseResponseSchema


class UserResponse(BaseResponseSchema):
    id: str
    name: str
    email: str
```

**Service template** (move business logic from the route handler body here):

```python
# src/api/services/users.py
from api.schemas.request.users import CreateUserRequest
from api.schemas.response.users import UserResponse


class UsersService:
    @staticmethod
    async def find_all() -> list[UserResponse]:
        return []

    @staticmethod
    async def find_one(user_id: str) -> UserResponse | None:
        return None

    @staticmethod
    async def create(dto: CreateUserRequest) -> UserResponse:
        raise NotImplementedError
```

**Register each new router in `../[project-name]-api/src/api/routes.py`:**

1. Add `USERS = "users"` (or the appropriate resource name) to `APITags` in `src/api/tags.py`.
2. Import the router module and register it in `src/api/routes.py`:

```python
from api.routers import users
from api.tags import APITags

router.include_router(users.router, tags=[APITags.USERS])
```

**Remove the scaffold's example placeholder:** After adding all resource routers, clean up the example boilerplate that ships with the scaffold:
- Delete `src/api/routers/example.py`, `src/api/schemas/request/example.py`, `src/api/schemas/response/example.py`, `src/api/services/example.py`, `test/test_api/test_example.py`
- Remove the `example` import and its `include_router(example.router, ...)` line from `src/api/routes.py`
- Remove `EXAMPLE` from `APITags` in `src/api/tags.py`

---

## Phase 5 — Migrate Integrations (autonomous)

For each integration file identified in Phase 1d (API-route-imported):

**TypeScript FetchClient/AxiosClient subclass → Python httpx wrapper:**

```python
# Example: src/integrations/github_client.py in ../[project-name]-api
import httpx
from functools import lru_cache
import os


class GithubClient:
    def __init__(self):
        self._base_url = os.environ["GITHUB_API_URL"]
        self._headers = {"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}"}

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

Use `get_github_client` as a FastAPI dependency:

```python
from fastapi import Depends
from ..integrations.github_client import GithubClient, get_github_client

@router.get("/repos", response_model=list)
async def list_repos(client: GithubClient = Depends(get_github_client)):
    return await client.get_repos()
```

Note: The TypeScript base client files (`fetch-client.ts`, `axios-client.ts`) have no Python equivalent — write the `httpx` wrapper directly as shown above. Do not copy the TypeScript files.

**Clean up Next.js `src/integrations/`:**
- Delete each file that was moved.
- If `src/integrations/` is empty after removal (no frontend-only entries remain), delete the directory.
- If frontend-only entries remain, leave the directory intact.

---

## Phase 6 — Migrate Database (autonomous)

**If no database detected in Phase 1f:** Skip this phase.

**FastAPI + Drizzle:** ⛔ GATE — Drizzle is TypeScript-only and has no Python equivalent.

Ask:
> "Your Next.js project uses Drizzle ORM (TypeScript-only). FastAPI requires a Python ORM. Which would you like to use?
> - SQLAlchemy — relational databases (PostgreSQL, MySQL, SQLite)
> - Beanie — MongoDB (async, Pydantic-native)"

After the user answers, load and follow the corresponding skill:
```bash
# If SQLAlchemy
cat "<skill-dir>/../add/database/python/sqlalchemy.md"

# If Beanie
cat "<skill-dir>/../add/database/python/beanie.md"
```

The Drizzle schema files define the shape of your data. Port each Drizzle table definition to an equivalent SQLAlchemy model or Beanie document, then present the ported schemas to the user for review before proceeding. The database skill scaffolds the connection layer; schema porting is a required step before Phase 7.

Delete `src/integrations/database/` and `drizzle.config.ts` from the Next.js project after confirming the FastAPI schema is in place.

**FastAPI + Mongoose:**

Load and follow the Beanie skill (Beanie is the Pydantic-native equivalent for MongoDB in Python):
```bash
cat "<skill-dir>/../add/database/python/beanie.md"
```

Port Mongoose schemas to Beanie Documents. Delete `src/integrations/database/` from the Next.js project.

---

## Phase 7 — Migrate Auth (autonomous)

**If `proxy.ts` not detected in Phase 1g:** Skip this phase.

Load and follow the FastAPI auth skill in `../[project-name]-api`:
```bash
cat "<skill-dir>/../add/auth/fastapi.md"
```

**Important:** `proxy.ts` remains in the Next.js project — it continues to protect frontend routes at the edge. After migration, update any hardcoded Next.js `/api/auth/...` paths in `proxy.ts` to use `process.env.NEXT_PUBLIC_API_URL`.

---

## Phases 8–10 — FastAPI-specific details

**Phase 8, step 0 CORS:** Enable CORS credentials on the backend (`allow_credentials=True`) if using cookie-based sessions.

**Phase 9 — FastAPI CORS config:** The FastAPI scaffold ships with `CORS_ORIGINS=http://localhost:3000` in `src/.env.default`. Verify this value is present. No separate `.env.example` — `src/.env.default` is the single source of truth for default env values.

**Phase 10 — Verify commands:**
```bash
# 1. FastAPI backend
cd ../[project-name]-api
pip install -r requirements.txt && python -m pytest test/ -q

# 2. Next.js frontend
cd [original-project-path]
pnpm build && pnpm test
```

For phase 8 steps 1–6, phase 9 AGENTS.md/Next.js updates, and the phase 10 success message, see `common.md`.
