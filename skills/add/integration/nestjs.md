<!-- ref: add/integration/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS

Create a new third-party API integration in a NestJS project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

> **Placeholder names**: All examples use `github` as the integration name. Replace `github`/`Github` throughout with your actual service name (e.g., `stripe`/`Stripe`, `openai`/`Openai`). File names, class names, and imports must all match.

### Dependencies

```bash
pnpm add @nestjs/axios axios
```

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
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
import {
  BadGatewayException,
  GatewayTimeoutException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { AxiosError } from 'axios';
import { firstValueFrom } from 'rxjs';

import { githubRepoSchema, type GithubRepo } from './<name>-integration.schemas';

const UPSTREAM = '/user/repos';

@Injectable()
export class GithubIntegrationService {
  private readonly logger = new Logger(GithubIntegrationService.name);

  constructor(private readonly http: HttpService) {}

  async listRepos(): Promise<GithubRepo[]> {
    let data: unknown;

    try {
      ({ data } = await firstValueFrom(this.http.get<unknown>(UPSTREAM)));
    } catch (error) {
      // Never log the raw AxiosError — `error.config.headers` carries the Bearer token.
      const status =
        error instanceof AxiosError ? (error.response?.status ?? 0) : 0;
      const timedOut =
        error instanceof AxiosError &&
        (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT');

      this.logger.error(`GitHub ${UPSTREAM} failed with status ${status}`);

      if (timedOut) throw new GatewayTimeoutException('Upstream timed out.');
      throw new BadGatewayException('Upstream request failed.');
    }

    if (!Array.isArray(data)) {
      this.logger.error(`GitHub ${UPSTREAM} returned a non-array body`);
      throw new BadGatewayException('Upstream returned an unexpected shape.');
    }

    // Per-row safeParse: a ZodError is not an HttpException (it would surface as an
    // unformatted 500), and one bad row should not discard the whole list.
    const repos: GithubRepo[] = [];
    let skipped = 0;

    for (const row of data) {
      const parsed = githubRepoSchema.safeParse(row);
      if (parsed.success) repos.push(parsed.data);
      else skipped += 1;
    }

    if (skipped > 0) {
      this.logger.warn(
        `Discarded ${skipped} malformed repo(s) from GitHub ${UPSTREAM}`,
      );
    }

    return repos;
  }
}
```

> **When a malformed row is not skippable** — for example a payment or balance response
> where a partial list is worse than an error — throw instead:
> `throw new BadGatewayException('Upstream returned an unexpected shape.')`. Never rethrow
> the `ZodError` itself and never put its `issues` in the response body; the paths leak
> the upstream schema.

#### 4. Add Config

Add to `envSchema` in **`src/config/env.config.ts`** (validated at import — boot fails if missing):

```typescript
const envSchema = z.object({
  // ... existing fields ...
  GITHUB_API_URL: z.url({ protocol: /^https$/ }).default('https://api.github.com'),
  GITHUB_TOKEN: z.string().min(1),
});
```

```typescript
export const serviceConfig = {
  // ... existing fields ...
  GITHUB_API_URL: env.GITHUB_API_URL,
  GITHUB_TOKEN: env.GITHUB_TOKEN,
};
```

Put the real token in `.env` (never committed) and a placeholder in `.env.example`:
```
GITHUB_API_URL=https://api.github.com
GITHUB_TOKEN=your_github_token_here
```

NEVER use a fallback like `?? ''` for tokens — fail fast at startup instead.

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
      timeout: 30_000,
      // Never follow a redirect off the configured host with the Bearer header attached.
      maxRedirects: 0,
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
- Validate all external responses with Zod `safeParse` — never bare `.parse()`
- Convert upstream failures to `BadGatewayException` / `GatewayTimeoutException`; log status and path only, never the raw error
- Configure `HttpModule.register()` with `baseURL`, auth headers, `timeout`, and `maxRedirects: 0`. No automatic retries — add them only for idempotent GETs, with backoff
- Export the service from the integration module so other modules can import it
- Keep API tokens in environment variables — NEVER hardcode
- Integration modules are self-contained — each has its own module, service, and schemas

### After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards