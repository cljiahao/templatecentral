---
name: nestjs-add-integration
description: Use when connecting to an external API (e.g., GitHub, Stripe, OpenAI) from a NestJS project and need an HTTP client module, Zod schemas, and injectable service.
---

# Add an External Integration to NestJS

Create a new third-party API integration in a NestJS project scaffolded from templateCentral.

## Inputs

- **Service name** — The external service (e.g., `github`, `stripe`, `openai`)
- **Base URL** — The API base URL

> **Placeholder names**: All examples use `github` as the integration name. Replace `github`/`Github` throughout with your actual service name (e.g., `stripe`/`Stripe`, `openai`/`Openai`). File names, class names, and imports must all match.

## Dependencies

```bash
pnpm add @nestjs/axios axios
```

## Steps

### 1. Create Integration Module Directory

Create `src/modules/<name>-integration/` with:
- `<name>-integration.module.ts`
- `<name>-integration.service.ts`
- `<name>-integration.schemas.ts`

### 2. Define Zod Schemas

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

### 3. Create the Service

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

### 4. Add Config

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

### 5. Create the Module

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

### 6. Export from Modules Barrel

Add the integration module to `src/modules/index.ts`:

```typescript
export * from './<name>-integration/<name>-integration.module';
```

### 7. Register in AppModule

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

### 8. Validate

```bash
pnpm start:dev
```

Confirm the server starts with no DI or import errors.

## Rules

- Use `@nestjs/axios` + `HttpModule` — not raw `axios` or `fetch`
- Validate all external responses with Zod schemas — external data is untrusted
- Configure `HttpModule.register()` with `baseURL`, auth headers, and timeout
- Export the service from the integration module so other modules can import it
- Keep API tokens in environment variables — NEVER hardcode
- Integration modules are self-contained — each has its own module, service, and schemas
