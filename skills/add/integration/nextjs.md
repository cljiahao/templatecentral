<!-- ref: add/integration/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
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