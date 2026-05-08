---
name: shared-add-integration
description: Use when connecting to an external API (e.g., GitHub, Stripe, OpenAI) from any templateCentral project — FastAPI, NestJS, Next.js, or Vite + React.
---

# Add an External Integration

Create a new third-party API integration in a templateCentral project.

## Stack Detection

Before starting, identify the project stack:

| Signal file | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts` / `next.config.js` / `next.config.mjs` | Next.js |
| `vite.config.ts` / `vite.config.js` (no `next.config.*`) | Vite + React |

Then jump directly to the matching stack section below.

## Inputs

- **Service name** — The external service (e.g., `github`, `stripe`, `openai`)
- **Base URL** — The API base URL

---

## FastAPI

Create a new third-party API integration in a FastAPI project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:fastapi-scaffold`. See Step 0.

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

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
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
import httpx


class GithubClient:
    """HTTP client for the GitHub API."""

    def __init__(self, base_url: str, token: str) -> None:
        self._client = httpx.AsyncClient(
            base_url=base_url,
            headers={"Authorization": f"Bearer {token}"},
            timeout=30.0,
        )

    async def get_repos(self) -> list[dict]:
        """Fetch the authenticated user's repositories."""
        response = await self._client.get("/user/repos")
        response.raise_for_status()
        return response.json()

    async def get_repo(self, owner: str, repo: str) -> dict:
        """Fetch a specific repository."""
        response = await self._client.get(f"/repos/{owner}/{repo}")
        response.raise_for_status()
        return response.json()

    async def close(self) -> None:
        await self._client.aclose()
```

#### 3. Define Response Schemas

**`src/integrations/<name>_schemas.py`**:

Integration schemas must NOT inherit from `BaseResponseSchema` — it has `extra="forbid"` (rejects unknown fields from external APIs) and `alias_generator=to_camel` (transforms field names). Use plain `BaseModel` with `extra="ignore"` instead:

```python
from pydantic import BaseModel, ConfigDict, Field


class GithubRepo(BaseModel):
    """GitHub repository response — uses plain BaseModel to preserve external API field names."""

    model_config = ConfigDict(extra="ignore")

    id: int = Field(description="Repository ID.")
    full_name: str = Field(description="Full repository name (owner/repo).")
    description: str | None = Field(default=None, description="Repository description.")
    html_url: str = Field(description="URL to the repository.")
    stargazers_count: int = Field(default=0, description="Star count.")
```

#### 4. Create the Service

**`src/integrations/<name>_service.py`**:

```python
from integrations.github_client import GithubClient
from integrations.github_schemas import GithubRepo


class GithubService:
    """Business logic for GitHub integration."""

    def __init__(self, client: GithubClient) -> None:
        self._client = client

    async def list_repos(self) -> list[GithubRepo]:
        """Fetch and validate all repos."""
        raw = await self._client.get_repos()
        return [GithubRepo.model_validate(r) for r in raw]

    async def get_repo(self, owner: str, repo: str) -> GithubRepo:
        """Fetch and validate a single repo."""
        raw = await self._client.get_repo(owner, repo)
        return GithubRepo.model_validate(raw)
```

#### 5. Add Config

Add the API token to `APISettings` in **`src/core/config.py`**:

```python
class APISettings(BaseSettings):
    # ... existing fields ...
    GITHUB_API_URL: str = Field(default="https://api.github.com")
    GITHUB_TOKEN: str
```

Add to `src/.env` (real token — never commit):
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

from fastapi import Depends

from core.config import api_settings
from integrations.github_client import GithubClient
from integrations.github_service import GithubService


async def get_github_service() -> AsyncGenerator[GithubService, None]:
    """Provide a GithubService instance with managed client lifecycle."""
    client = GithubClient(base_url=api_settings.GITHUB_API_URL, token=api_settings.GITHUB_TOKEN)
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
from api.tags import APITags
from integrations.github_schemas import GithubRepo
from integrations.github_service import GithubService

router = APIRouter(prefix="/github", tags=[APITags.GITHUB])


@router.get("/repos", response_model=list[GithubRepo])
async def list_repos(service: GithubService = Depends(get_github_service)) -> list[GithubRepo]:
    """List authenticated user's GitHub repos."""
    return await service.list_repos()
```

#### 8. Register the Router

Add the router to **`src/api/routes.py`**:

```python
from api.routers import example, github  # add the new import

# in the router registration block:
router.include_router(github.router)
```

The router will not be reachable until it is registered here — this step is mandatory.

### Rules

- Use `httpx.AsyncClient` for async HTTP — not `requests`.
- Validate all external responses with Pydantic schemas before returning to callers.
- Client handles HTTP only — no business logic. Service handles business logic.
- Use FastAPI dependencies for lifecycle management (create → yield → close).
- Keep API tokens in environment variables / config — never hardcode.
- Place integration files in `src/integrations/` — not in `api/`.

### Validate

```bash
pytest test/ -v     # tests pass
ruff check src/     # zero lint errors
```

### After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate the server starts and tests pass
2. `shared-review-agent` — check code standards

---

## NestJS

Create a new third-party API integration in a NestJS project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:nestjs-scaffold`. See Step 0.

> **Placeholder names**: All examples use `github` as the integration name. Replace `github`/`Github` throughout with your actual service name (e.g., `stripe`/`Stripe`, `openai`/`Openai`). File names, class names, and imports must all match.

### Dependencies

```bash
pnpm add @nestjs/axios axios
```

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Integration Module Directory

Create `src/modules/<name>-integration/` with:
- `<name>-integration.module.ts`
- `<name>-integration.service.ts`
- `<name>-integration.schemas.ts`

#### 2. Define Zod Schemas

**`src/modules/<name>-integration/<name>-integration.schemas.ts`**:

```typescript
import { z } from 'zod';

export const githubRepoSchema = z.object({
  id: z.number(),
  full_name: z.string(),
  description: z.string().nullable(),
  html_url: z.url(),
  stargazers_count: z.number().default(0),
});

export type GithubRepo = z.infer<typeof githubRepoSchema>;
```

#### 3. Create the Service

**`src/modules/<name>-integration/<name>-integration.service.ts`**:

```typescript
import { Injectable } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { firstValueFrom } from 'rxjs';

import { githubRepoSchema, type GithubRepo } from './<name>-integration.schemas';

@Injectable()
export class GithubIntegrationService {
  constructor(private readonly http: HttpService) {}

  async listRepos(): Promise<GithubRepo[]> {
    const { data } = await firstValueFrom(
      this.http.get('/user/repos'),
    );
    return data.map((r: unknown) => githubRepoSchema.parse(r));
  }
}
```

#### 4. Add Config

Add the API token to `serviceConfig` in **`src/config/env.config.ts`**:

```typescript
export const serviceConfig = {
  // ... existing fields ...
  GITHUB_API_URL: process.env.GITHUB_API_URL ?? 'https://api.github.com',
  GITHUB_TOKEN: process.env.GITHUB_TOKEN!,
};
```

Add to `.env` (real token — never commit):
```
GITHUB_API_URL=https://api.github.com
GITHUB_TOKEN=
```

Document in `.env.example` (placeholder for documentation):
```
GITHUB_API_URL=https://api.github.com
GITHUB_TOKEN=your_github_token_here
```

#### 5. Create the Module

**`src/modules/<name>-integration/<name>-integration.module.ts`**:

```typescript
import { Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';

import { serviceConfig } from '../../config/env.config';
import { GithubIntegrationService } from './<name>-integration.service';

@Module({
  imports: [
    HttpModule.register({
      baseURL: serviceConfig.GITHUB_API_URL,
      headers: {
        Authorization: `Bearer ${serviceConfig.GITHUB_TOKEN}`,
      },
      timeout: 30000,
    }),
  ],
  providers: [GithubIntegrationService],
  exports: [GithubIntegrationService],
})
export class GithubIntegrationModule {}
```

#### 6. Export from Modules Barrel

Add the integration module to `src/modules/index.ts`:

```typescript
export * from './<name>-integration/<name>-integration.module';
```

#### 7. Register in AppModule

```typescript
import { GithubIntegrationModule } from './modules';

@Module({
  imports: [
    GithubIntegrationModule,
    // ...
  ],
})
export class AppModule {}
```

#### 8. Validate

```bash
pnpm start:dev
```

Confirm the server starts with no DI or import errors.

### Rules

- Use `@nestjs/axios` + `HttpModule` — not raw `axios` or `fetch`
- Validate all external responses with Zod schemas — external data is untrusted
- Configure `HttpModule.register()` with `baseURL`, auth headers, and timeout
- Export the service from the integration module so other modules can import it
- Keep API tokens in environment variables — NEVER hardcode
- Integration modules are self-contained — each has its own module, service, and schemas

### Validate

```bash
pnpm build    # zero compile errors
pnpm test     # tests pass
```

### After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

---

## Next.js

Create a new third-party API integration in a Next.js project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:nextjs-scaffold`. See Step 0.

### Architecture

```
Environment → factories.ts → services/ → clients/ → schemas/
```

- **clients/** — Thin HTTP clients that make requests
- **schemas/** — Zod schemas for validating external responses
- **services/** — Business logic wrapping the client
- **factories.ts** — Factory functions for creating service instances (at `src/integrations/factories.ts`)
- **error.ts** — Custom `APIError` class (at `src/integrations/error.ts`)

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Zod Schemas

Define schemas first — the client and service will import types from here:

```ts
// src/integrations/schemas/github-schemas.ts
import { z } from 'zod';

export const githubRepoSchema = z.object({
  id: z.number(),
  name: z.string(),
  full_name: z.string(),
  private: z.boolean(),
});

export type GithubRepo = z.infer<typeof githubRepoSchema>;
```

#### 2. Create the Client

Extend the base `FetchClient` (at `src/integrations/clients/base/fetch-client.ts`) which handles response parsing, error mapping, and content-type negotiation:

```ts
// src/integrations/clients/github-client.ts
import { FetchClient } from './base/fetch-client';
import type { GithubRepo } from '../schemas/github-schemas';

export class GithubClient extends FetchClient {
  constructor(baseUrl: string, token: string) {
    super(baseUrl, { Authorization: `Bearer ${token}` });
  }

  async getRepos() {
    return this.request<GithubRepo[]>('user/repos');
  }

  async getRepo(owner: string, repo: string) {
    return this.request<GithubRepo>(`repos/${owner}/${repo}`);
  }
}
```

#### 3. Create the Service

```ts
// src/integrations/services/github-service.ts
import type { GithubClient } from '../clients/github-client';
import { githubRepoSchema, type GithubRepo } from '../schemas/github-schemas';

export class GithubService {
  constructor(private readonly client: GithubClient) {}

  async getRepos(): Promise<GithubRepo[]> {
    const data = await this.client.getRepos();
    return githubRepoSchema.array().parse(data);
  }
}
```

#### 4. Add Factory Function

```ts
// src/integrations/factories.ts
import { GithubClient } from './clients/github-client';
import { GithubService } from './services/github-service';

export function Github() {
  if (!process.env.GITHUB_TOKEN) {
    throw new Error('GITHUB_TOKEN is required');
  }
  const client = new GithubClient(
    process.env.GITHUB_API_URL ?? 'https://api.github.com',
    process.env.GITHUB_TOKEN,
  );
  return new GithubService(client);
}
```

> **Naming convention**: Factory functions use PascalCase matching the integration name: `Github()`, `Stripe()`, `SSM()`. Database clients use the `add-database` skill, not `add-integration`.

> **Alternative: Axios-based client** — For server-side integrations needing mTLS, API key headers, or request/response logging, use `createAxiosClient` from `src/integrations/clients/base/axios-client.ts` instead of extending `FetchClient`.

#### 5. Consume via Factory

In feature services or API routes:

```ts
import { Github } from '@/integrations/factories';

const repos = await Github().getRepos();
```

#### 6. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors. Verify the integration works end-to-end in the browser or via API route.

### Rules

- Clients are thin — they only make HTTP requests. NEVER put business logic in clients
- Schemas validate external responses with Zod — NEVER skip validation on external API responses
- Services contain business logic and call clients
- Factories create configured service instances
- Always throw `APIError` for HTTP failures (imported from `@/integrations/error`) — NEVER throw generic `Error`
- Environment variables go in `.env.local`, referenced via `process.env` — NEVER hardcode API URLs or secrets. Add commented placeholders to `.env.example` so other developers know what's needed.
- NEVER put API keys or tokens in `NEXT_PUBLIC_*` — they are exposed to every browser. Server-side integrations use `process.env` without the prefix. For APIs requiring auth from the browser, proxy through a Next.js API route.
- NEVER consume integrations directly in components — go through feature services or API routes
- For wiring this integration to a frontend SPA: use `shared-full-stack-pairing`
- For complex Zod response validation patterns: use `shared-validation-patterns`

### Validate

```bash
pnpm build    # zero errors
pnpm check    # zero type errors
```

### After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards

---

## Vite + React

Create a new third-party API integration in a Vite + React project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:vite-react-scaffold`. See Step 0.

### Architecture

```
ENV → services/ → clients/ → schemas/
```

- **clients/** — Thin HTTP clients that extend `FetchClient` from `src/lib/clients/`
- **schemas/** — Zod schemas for validating external responses
- **services/** — Business logic wrapping the client

Create `src/integrations/` on first integration — this directory does not exist in the base template. The base `FetchClient` lives in `src/lib/clients/fetch-client.ts`.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Zod Schemas

Define schemas first — the client and service will import types from here:

```ts
// src/integrations/schemas/github-schemas.ts
import { z } from 'zod';

export const githubRepoSchema = z.object({
  id: z.number(),
  name: z.string(),
  full_name: z.string(),
  private: z.boolean(),
});

export type GithubRepo = z.infer<typeof githubRepoSchema>;
```

#### 2. Create the Client

Extend the base `FetchClient` (at `src/lib/clients/fetch-client.ts`) which handles response parsing, error mapping, and content-type negotiation:

```ts
// src/integrations/clients/github-client.ts
import { FetchClient } from '@/lib/clients/fetch-client';
import type { GithubRepo } from '../schemas/github-schemas';

export class GithubClient extends FetchClient {
  constructor(baseUrl: string, headers: Record<string, string>) {
    super(baseUrl, headers);
  }

  async getRepos() {
    return this.request<GithubRepo[]>('user/repos');
  }

  async getRepo(owner: string, repo: string) {
    return this.request<GithubRepo>(`repos/${owner}/${repo}`);
  }
}
```

#### 3. Create the Service

```ts
// src/integrations/services/github-service.ts
import type { GithubClient } from '../clients/github-client';
import { githubRepoSchema, type GithubRepo } from '../schemas/github-schemas';

export class GithubService {
  constructor(private readonly client: GithubClient) {}

  async getRepos(): Promise<GithubRepo[]> {
    const data = await this.client.getRepos();
    return githubRepoSchema.array().parse(data);
  }
}
```

#### 4. Create a Configured Instance

Create the instance at the integrations root:

```ts
// src/integrations/github.ts
import { ENV } from '@/lib/constants/env';
import { GithubClient } from './clients/github-client';
import { GithubService } from './services/github-service';

const client = new GithubClient(
  ENV.GITHUB_API_URL ?? 'https://api.github.com',
  { Accept: 'application/json' },
);

export const Github = new GithubService(client);
```

Add the env var to `src/lib/constants/env.ts` and add `VITE_GITHUB_API_URL=https://api.github.com` to `.env.example`:

```ts
export const ENV = {
  // ... existing
  GITHUB_API_URL: import.meta.env.VITE_GITHUB_API_URL as string | undefined,
} as const;
```

> **Security**: NEVER put API tokens or secrets in `VITE_*` environment variables — they are embedded in the client bundle and visible to users. For APIs requiring authentication, route requests through your backend (see `full-stack-pairing` skill) and have the backend add the auth header. Only use `VITE_*` for non-sensitive config like API base URLs.

#### 5. Consume via React Query Hook

Create the consumer feature first using the `add-feature` skill (e.g., `repos`), then add the hook inside it:

```ts
// src/features/repos/hooks/use-repos.query.ts
import { useQuery } from '@tanstack/react-query';
import { Github } from '@/integrations/github';

export const useRepos = () => {
  return useQuery({
    queryKey: ['github', 'repos'],
    queryFn: () => Github.getRepos(),
  });
};
```

Export from the feature's barrel (`hooks/index.ts` → `index.ts`) so consumers import via `@/features/repos`.

#### 6. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds with no type errors and all tests pass. Verify the integration works end-to-end in the browser.

### Rules

- Clients are thin — they only make HTTP requests; NEVER put business logic in clients
- Schemas validate external responses with Zod — external data is untrusted; NEVER skip Zod validation on external API responses
- Services contain business logic and call clients
- NEVER hardcode API URLs or secrets — centralize in `src/lib/constants/env.ts`
- Throw `APIError` for HTTP failures — NEVER throw generic `Error`. `ZodError` from schema `parse()` is expected for validation failures and should propagate naturally.
- NEVER consume integrations directly in components — go through React Query hooks in features

### Validate

```bash
pnpm build    # zero errors
pnpm test     # tests pass
```

### After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
