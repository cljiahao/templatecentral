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
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards