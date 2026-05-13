<!-- ref: migrate/nextjs-backend-extraction/fastapi.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = FastAPI. Do not invoke this file directly. -->

# Next.js → FastAPI Backend Extraction

Extracts `src/app/api/` route handlers and relevant `src/integrations/` clients from a Next.js project into a sibling FastAPI project. Next.js becomes a pure frontend.

---

## Phase 1 — Assessment (autonomous)

Scan the Next.js project root. Run each check in order.

**1a. Verify templateCentral marker**

Read `AGENTS.md`. If `<!-- templateCentral: nextjs@` is not on line 1, exit:
> "This skill requires a Next.js project scaffolded with templatecentral:scaffold. No changes made."

**1b. Read project name**

Read `package.json` → `name` field. This becomes `[project-name]`. The FastAPI project will be created at `../[project-name]-api`.

**1c. Inventory API routes**

List all `src/app/api/**/route.ts` files. For each, read the exported function names to determine HTTP methods (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).

**1d. Identify integrations to move**

For each `route.ts` file, scan import statements for any path starting with `@/integrations/` or `../integrations/`. Collect the unique set. Also always include `src/integrations/clients/base/fetch-client.ts` and `src/integrations/clients/base/axios-client.ts` if they exist.

**1e. Identify integrations staying in Next.js**

List all files under `src/integrations/` that were NOT collected in 1d.

**1f. Detect database**

Check for `drizzle.config.ts` (Drizzle) or `src/integrations/database/` containing `.schema.ts` files (Mongoose schemas). Record which ORM if found.

**1g. Detect auth**

Check whether `proxy.ts` or `src/proxy.ts` exists. Record presence.

**Print the assessment:**

```
📋 Backend Extraction Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project:          [project-name]  →  ../[project-name]-api (FastAPI)

API routes (move to FastAPI):
  [list each route.ts with methods, e.g. src/app/api/users/route.ts  GET POST]

Integrations to move (imported by API routes):
  [list each file path]

Integrations staying in Next.js:
  [list each file path, or "None"]

Database:         [✓ Drizzle (requires ORM choice at Phase 6) / ✓ Mongoose → Beanie / None detected]
Auth:             [✓ proxy.ts detected / None detected]

Next.js after migration: pure frontend, calls NEXT_PUBLIC_API_URL
New backend URL:  http://localhost:8000 (dev) / NEXT_PUBLIC_API_URL (prod)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 2 — Scope Confirmation ⛔ GATE

Do not proceed until the user responds. Ask:

> "This will create `../[project-name]-api` (FastAPI), migrate the items listed above, and rewire Next.js as a pure frontend. This cannot be automatically undone. Proceed? (yes / no)"

If no → print "No changes made." and exit.

---

## Phase 3 — Scaffold FastAPI (autonomous)

Determine the sibling path: `../[project-name]-api`.

Load and follow the FastAPI scaffold steps:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/fastapi/config-files.md"
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/fastapi/source-files.md"
```

Work from `../[project-name]-api` as the project root. Set the project name in `src/.env.default`.

**Do not run post-scaffold agents** (build, test, update, review) — verification happens in Phase 10.

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
| `export async function DELETE(_, { params })` | `@router.delete('/{id}')` |
| `handleApiError(label, error)` | `raise HTTPException(status_code=..., detail=...)` |
| Dynamic segment `[id]/route.ts` | `/{id}` path parameter on the same router |
| Zod `safeParse` validation | Pydantic model as function parameter (FastAPI validates automatically) |

**Router template** (adapt for each resource):

```python
# src/api/routers/users.py
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/users", tags=["users"])


class CreateUserRequest(BaseModel):
    name: str
    email: str


@router.get("/")
async def get_users():
    # Move logic from Next.js GET handler body here
    return []


@router.get("/{user_id}")
async def get_user(user_id: str):
    user = None
    if not user:
        raise HTTPException(status_code=404, detail="Not found")
    return user


@router.post("/", status_code=201)
async def create_user(body: CreateUserRequest):
    # Move logic from Next.js POST handler body here
    return body.model_dump()
```

Register each new router in `../[project-name]-api/src/api/__init__.py`:

```python
from fastapi import APIRouter
from .routers.users import router as users_router

api_router = APIRouter()
api_router.include_router(users_router)
```

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


@lru_cache
def get_github_client() -> GithubClient:
    return GithubClient()
```

Use `get_github_client` as a FastAPI dependency:

```python
from fastapi import Depends
from ..integrations.github_client import GithubClient, get_github_client

@router.get("/repos")
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
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/database/python/sqlalchemy.md"

# If Beanie
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/database/python/beanie.md"
```

The Drizzle schema files define the shape of your data — you will need to re-implement the table/collection definitions in SQLAlchemy models or Beanie documents. The skill scaffolds the database layer; porting the schema is your responsibility.

Delete `src/integrations/database/` and `drizzle.config.ts` from the Next.js project after confirming the FastAPI schema is in place.

**FastAPI + Mongoose:**

Load and follow the Beanie skill (Beanie is the Pydantic-native equivalent for MongoDB in Python):
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/database/python/beanie.md"
```

Port Mongoose schemas to Beanie Documents. Delete `src/integrations/database/` from the Next.js project.

---

## Phase 7 — Migrate Auth (autonomous)

**If `proxy.ts` not detected in Phase 1g:** Skip this phase.

Load and follow the FastAPI auth skill in `../[project-name]-api`:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/auth/fastapi.md"
```

**Important:** `proxy.ts` remains in the Next.js project — it continues to protect frontend routes at the edge. After migration, update any hardcoded Next.js `/api/auth/...` paths in `proxy.ts` to use `process.env.NEXT_PUBLIC_API_URL`.

---

## Phase 8 — Rewire Next.js Frontend (autonomous)

1. **Delete `src/app/api/`** — all route handlers have moved to FastAPI.

2. **Update `src/lib/constants/env.ts`** — add `API_BASE`:

```typescript
export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8000';
```

3. **Update feature service files** — for each file under `src/features/` that calls `fetch('/api/...')`, replace with `API_BASE`:

```typescript
// Before
const res = await fetch('/api/users');

// After
import { API_BASE } from '@/lib/constants/env';
const res = await fetch(`${API_BASE}/users`);
```

4. **Update `.env.example`** — add:

```
# Backend API (FastAPI)
# Dev default: http://localhost:8000
NEXT_PUBLIC_API_URL=http://localhost:8000
```

5. **Update `.env.local`** — add the same line.

6. **Clean up `src/integrations/`** — after Phase 5 cleanup, scan for any remaining entries that are now unused (no imports anywhere in the Next.js codebase). Delete unused files. If the directory is empty, delete it.

---

## Phase 9 — Update Config & Docs (autonomous)

**FastAPI project (`../[project-name]-api`):**

The FastAPI scaffold reads `CORS_ORIGINS` from `src/.env.default`. Update the value:

```
CORS_ORIGINS=http://localhost:3000
```

If a separate `.env.example` exists, add:
```
# Frontend origin for CORS (comma-separated for multiple origins)
CORS_ORIGINS=http://localhost:3000
```

Update `../[project-name]-api/AGENTS.md` — prepend to Project-Specific Notes:
```
- Extracted from `[project-name]` (Next.js frontend) — see `../[project-name]`
- Frontend calls this API; set CORS_ORIGINS to the Next.js origin in production
```

**Next.js project:**

Update `AGENTS.md` Architecture Decisions — replace the BFF note with:
```
- API routes removed — backend extracted to `../[project-name]-api` (FastAPI)
- This project is a pure frontend; all data fetching uses `NEXT_PUBLIC_API_URL`
```

---

## Phase 10 — Verify (autonomous)

Run in sequence. Stop and report the exact error on first failure.

```bash
# 1. FastAPI backend
cd ../[project-name]-api
pip install -r requirements.txt && pytest

# 2. Next.js frontend
cd [original-project-path]
pnpm build && pnpm test
```

**If all pass**, print:

```
✓ Migration complete.

Next.js frontend: [original-project-path]
  → Pure frontend. Set NEXT_PUBLIC_API_URL in your deployment environment.

FastAPI backend:  ../[project-name]-api
  → Set CORS_ORIGINS to the Next.js origin in your deployment environment.

Next steps:
- Review proxy.ts — update any hardcoded /api paths to use NEXT_PUBLIC_API_URL
- Re-implement your Drizzle schema in SQLAlchemy/Beanie if not yet done
- Set up Docker Compose if you want both services running locally with one command
- Configure CI/CD pipelines for each repo independently
```

**If any command fails**, print the exact error output and stop. Do not continue to the next phase.
