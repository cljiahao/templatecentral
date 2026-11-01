<!-- ref: add/integration/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React

### Architecture

```
ENV → services/ → { clients/, schemas/ }
```

- **clients/** — Thin HTTP clients that extend `FetchClient` from `src/lib/clients/`
- **schemas/** — Zod schemas for validating external responses
- **services/** — Business logic wrapping the client

Create `src/integrations/` on first use (not in the template); the base `FetchClient` is `src/lib/clients/fetch-client.ts`.

### Steps

#### Step 0 — Verify context

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

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

Extend `FetchClient` (`src/lib/clients/fetch-client.ts` — response parsing, `APIError` mapping, 30 s timeout). Return `unknown`, not the schema type: `request<GithubRepo[]>` would be a type assertion over untrusted network data. The service `parse()`s it. The example calls an unauthenticated public endpoint — see the Security note in Step 4.

```ts
// src/integrations/clients/github-client.ts
import { FetchClient } from '@/lib/clients/fetch-client';

export class GithubClient extends FetchClient {
  async getUserRepos(username: string): Promise<unknown> {
    return this.request<unknown>(`users/${encodeURIComponent(username)}/repos`);
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

  async getUserRepos(username: string): Promise<GithubRepo[]> {
    const data = await this.client.getUserRepos(username);
    return githubRepoSchema.array().parse(data);
  }
}
```

#### 4. Create a Configured Instance

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

> **Security**: do not put API tokens or secrets in `VITE_*` variables; they ship in the client bundle. For authenticated APIs, proxy through a backend endpoint that adds the auth header; `VITE_*` is for non-sensitive config only.

#### 5. Consume via React Query Hook

Create the consumer feature first (`templatecentral:add (feature)`, e.g. `repos`), then add the hook:

```ts
// src/features/repos/hooks/use-repos.query.ts
import { useQuery } from '@tanstack/react-query';
import { Github } from '@/integrations/github';

export const useRepos = (username: string) => {
  return useQuery({
    queryKey: ['github', 'repos', username],
    queryFn: () => Github.getUserRepos(username),
    enabled: username.length > 0,
  });
};
```

Export from the feature's barrel (`hooks/index.ts` → `index.ts`) so consumers import via `@/features/repos`.

#### 6. Validate

```bash
pnpm build && pnpm test
```

Build and tests pass; the integration works end-to-end in the browser.

### Rules

- Keep business logic out of clients; client methods return `unknown`
- Zod-validate every external response
- Do not hardcode API URLs or secrets; centralize in `src/lib/constants/env.ts`
- Throw `APIError` for HTTP failures, not a generic `Error`. `ZodError` from schema `parse()` is expected for validation failures and should propagate naturally.
- Components reach integrations through React Query hooks in features

### After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.