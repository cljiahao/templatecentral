<!-- ref: add/integration/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js

Create a new third-party API integration in a Next.js project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Architecture

```
Environment → factories.ts → clients/ → services/ → schemas/
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

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

#### 1. Create Zod Schemas

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

Extend `FetchClient` (`src/integrations/clients/base/fetch-client.ts` — response parsing, `APIError` mapping, 30 s `AbortSignal.timeout`, no retries). Return `unknown`, not the schema type: `request<GithubRepo[]>` would be a type assertion over untrusted network data. The service `safeParse()`s it.

```ts
// src/integrations/clients/github-client.ts
import { FetchClient } from './base/fetch-client';

export class GithubClient extends FetchClient {
  constructor(baseUrl: string, token: string) {
    super(baseUrl, { Authorization: `Bearer ${token}` });
  }

  async getRepos(): Promise<unknown> {
    return this.request<unknown>('user/repos');
  }

  async getRepo(owner: string, repo: string): Promise<unknown> {
    // request() concatenates onto the base URL — encoding stops `../` from escaping the path.
    return this.request<unknown>(
      `repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}`,
    );
  }
}
```

#### 3. Create the Service

```ts
// src/integrations/services/github-service.ts
import { APIError } from '@/integrations/error';
import type { GithubClient } from '../clients/github-client';
import { githubRepoSchema, type GithubRepo } from '../schemas/github-schemas';

export class GithubService {
  constructor(private readonly client: GithubClient) {}

  async getRepos(): Promise<GithubRepo[]> {
    const data = await this.client.getRepos();
    // safeParse so a ZodError never escapes the layer's APIError contract.
    const parsed = githubRepoSchema.array().safeParse(data);

    if (!parsed.success) {
      throw new APIError({ statusCode: 502, data: { message: 'Invalid GitHub API response' } });
    }

    return parsed.data;
  }
}
```

#### 4. Add Factory Function

```ts
// src/integrations/factories.ts
// Build error if a client component imports this — keeps tokens out of the browser bundle.
import 'server-only';
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

> **Naming convention**: Factory functions use PascalCase matching the integration name: `Github()`, `Stripe()`, `SSM()`. Database clients use the `templatecentral:add (database)` skill, not `templatecentral:add (integration)`.

> **Alternative: Axios-based client** — For server-side integrations needing mTLS, API key headers, or request/response logging, use `createAxiosClient` from `src/integrations/clients/base/axios-client.ts` instead of extending `FetchClient`.

#### 5. Consume via Factory

Server-side only — route handlers, server components, server actions. Never from a feature's `api/` service (those run in the browser):

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

- NEVER put business logic in clients; NEVER skip Zod validation of external responses
- Retry only idempotent GETs, with backoff — FetchClient does not retry
- Always throw `APIError` for HTTP failures (imported from `@/integrations/error`) — NEVER throw generic `Error`
- Environment variables go in `.env.local`, referenced via `process.env` — NEVER hardcode API URLs or secrets. Add commented placeholders to `.env.example` so other developers know what's needed.
- NEVER put API keys or tokens in `NEXT_PUBLIC_*` — they are exposed to every browser. Server-side integrations use `process.env` without the prefix. For APIs requiring auth from the browser, proxy through a Next.js API route.
- NEVER import integrations into client components or feature `api/` services — consume them server-side; `import 'server-only'` in `factories.ts` enforces this
- For wiring this integration to a frontend SPA: use `templatecentral:standards` (full-stack-pairing)
- For complex Zod response validation patterns: use `templatecentral:standards` (validation-patterns)

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards