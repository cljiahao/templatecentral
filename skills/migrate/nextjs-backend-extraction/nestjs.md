<!-- ref: migrate/nextjs-backend-extraction/nestjs.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js → NestJS Backend Extraction

Extracts `src/app/api/` route handlers and relevant `src/integrations/` clients from a Next.js project into a sibling NestJS project. Next.js becomes a pure frontend.

**Read `common.md` first.** Phases 1, 2, the Phase 3 skeleton, and Phases 8–10 live in common.md; stack-specific Phases 3–7 are below. Variable substitutions: `[BACKEND]` = NestJS, `[DEV_PORT]` = 3001, `[CORS_VAR]` = `CLIENT_URL`.

```bash
cat "<skill-dir>/nextjs-backend-extraction/common.md"
```

**Phase 1 NestJS deltas:** In 1d, also always include `src/integrations/clients/base/fetch-client.ts` and `src/integrations/clients/base/axios-client.ts` if they exist. Assessment Database line: `[✓ Drizzle / ✓ Mongoose / None detected]`.

---

## Phase 3 — Scaffold NestJS (autonomous)

```bash
cat "<skill-dir>/../scaffold/nestjs/config-files.md"
cat "<skill-dir>/../scaffold/nestjs/source-files.md"
```

Set the project name to `[project-name]-api` in `package.json`.

---

## Phase 4 — Migrate API Routes (autonomous)

For each `route.ts` file identified in Phase 1c, create the corresponding NestJS module.

**Mapping:**

| Next.js | NestJS |
|---|---|
| `src/app/api/<resource>/route.ts` | `src/modules/<resource>/<resource>.controller.ts` + `.service.ts` + `.module.ts` in `../[project-name]-api` |
| `export async function GET()` | `@Get()` on controller method; logic moved to service |
| `export async function POST(request: Request)` | `@Post()` on controller; validate body with `nestjs-zod` DTO |
| `export async function PUT(request, { params })` | `@Put(':id')` with `@Param('id')` |
| `export async function DELETE(_, { params })` | `@Delete(':id')` with `@Param('id')` |
| `handleApiError(label, error)` | Re-throw as `HttpException`; the global filter in the scaffold catches it |
| `NextResponse.json(data, { status: 201 })` | Return plain object; set status with `@HttpCode(201)` |
| `return NextResponse.json({ error: 'Not found' }, { status: 404 })` | `throw new HttpException('Not found', HttpStatus.NOT_FOUND)` |
| Dynamic segment `[id]/route.ts` | Single controller method with `@Param('id')` |

**Controller template** (adapt for each resource). The import list carries only what this template uses — add `Put`, `Delete`, `HttpException`, and `HttpStatus` as the mapping table above calls for them, since the scaffold's ESLint fails the build on an unused import:

```typescript
// src/modules/users/users.controller.ts
import { Body, Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';

@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  @ApiOperation({ summary: 'List users' })
  findAll() {
    return this.usersService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a user by ID' })
  findOne(@Param('id') id: string) {
    return this.usersService.findOne(id);
  }

  @Post()
  @HttpCode(201)
  @ApiOperation({ summary: 'Create a user' })
  create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }
}
```

**Service** — `src/modules/users/users.service.ts`: an `@Injectable()` class whose methods (`findAll`, `findOne(id)`, `create(dto: CreateUserDto)`) take over each route handler's body verbatim, minus the `NextResponse`/`handleApiError` wrapping. Throw `NotFoundException` / `BadRequestException` where the handler returned 404/400.

**Module template:**

```typescript
// src/modules/users/users.module.ts
import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
```

**Zod DTO template** (replaces `safeParse` validation in the route handler):

```typescript
// src/modules/users/dto/create-user.dto.ts
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateUserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.email(),
});

export class CreateUserDto extends createZodDto(CreateUserSchema) {}
```

After creating all module files, register each new module in `AppModule` in `../[project-name]-api/src/app.module.ts`:

```typescript
import { UsersModule } from './modules/users/users.module';

@Module({
  imports: [
    // ... existing imports
    UsersModule,
  ],
})
export class AppModule {}
```

---

## Phase 5 — Migrate Integrations (autonomous)

For each integration file identified in Phase 1d (API-route-imported + base clients):

**FetchClient subclass → NestJS injectable service:**

```typescript
// Example: src/integrations/services/github.service.ts in ../[project-name]-api
import { Injectable } from '@nestjs/common';
import { serviceConfig } from '../../config/env.config';
import { FetchClient } from '../clients/base/fetch-client';

// In src/config/env.config.ts: add both fields to `envSchema` (so a missing value fails at
// boot, not as `Bearer undefined`), e.g. `GITHUB_API_URL: z.url(), GITHUB_TOKEN: z.string().min(1),`
// AND expose them on the hand-written `serviceConfig` object:
//   GITHUB_API_URL: env.GITHUB_API_URL,
//   GITHUB_TOKEN: env.GITHUB_TOKEN,
@Injectable()
export class GithubService extends FetchClient {
  constructor() {
    super(serviceConfig.GITHUB_API_URL, {
      Authorization: `Bearer ${serviceConfig.GITHUB_TOKEN}`,
    });
  }

  async getRepos() {
    return this.request<unknown[]>('repos');
  }
}
```

Copy base client files (`fetch-client.ts`, `axios-client.ts`, `https-agent.ts`) verbatim to `../[project-name]-api/src/integrations/clients/base/`.

Copy schemas alongside the service they belong to.

Register each service as a provider in the relevant feature module (or in a shared `IntegrationsModule` if used by multiple modules). Then apply the Phase 5 cleanup in `common.md`.

---

## Phase 6 — Migrate Database (autonomous)

**If no database detected in Phase 1f:** Skip this phase.

**NestJS + Drizzle:**

1. Copy `src/integrations/database/` → `../[project-name]-api/src/database/`
2. Copy `drizzle.config.ts` → `../[project-name]-api/drizzle.config.ts` (update internal paths)
3. Load and follow the Drizzle database skill for NestJS:
```bash
cat "<skill-dir>/../add/database/typescript/nestjs-drizzle.md"
```
4. Delete `src/integrations/database/` and `drizzle.config.ts` from the Next.js project.

**NestJS + Mongoose:**

1. Copy Mongoose schema files from `src/integrations/database/` → `../[project-name]-api/src/database/`
2. Load and follow the Mongoose database skill for NestJS:
```bash
cat "<skill-dir>/../add/database/typescript/nestjs-mongoose.md"
```
   If the Next.js project uses AWS IAM auth for MongoDB (`@aws-sdk/credential-providers` in its `package.json`), also load the IAM add-on and apply it in place of the standard C2/C7 steps:
```bash
cat "<skill-dir>/../add/database/typescript/nestjs-mongoose-iam.md"
```
3. Delete `src/integrations/database/` from the Next.js project.

**NestJS + Kysely:**

1. Copy `src/integrations/database/types.ts` and `migrations/` → `../[project-name]-api/src/database/`
2. Load and follow the Kysely database skill for NestJS:
```bash
cat "<skill-dir>/../add/database/typescript/nestjs-kysely.md"
```
   If the Next.js project uses AWS IAM auth (`@aws-sdk/rds-signer` in its `package.json`), also load the IAM add-on and apply it in place of the standard B2/B7 steps:
```bash
cat "<skill-dir>/../add/database/typescript/nestjs-kysely-iam.md"
```
3. Delete `src/integrations/database/` from the Next.js project.

---

## Phase 7 — Migrate Auth (autonomous)

**If `proxy.ts` not detected in Phase 1g:** Skip this phase.

Load and follow the NestJS auth skill in `../[project-name]-api`:
```bash
cat "<skill-dir>/../add/auth/nestjs.md"
```

If Phase 6 migrated a database, the auth skill's `AuthService` is a 501 stub. Phase 6 ran before these stubs existed, so its auth section was skipped — replace the stubs with the database-backed implementation now:

| Phase 6 database | Follow |
|---|---|
| Kysely | `cat "<skill-dir>/../add/database/typescript/nestjs-kysely-auth.md"` |
| Drizzle | "Completing Auth Integration" in `cat "<skill-dir>/../add/database/typescript/nestjs-drizzle.md"` |
| Mongoose | `cat "<skill-dir>/../add/database/typescript/nestjs-mongoose-auth.md"` |

Then apply the Phase 7 `proxy.ts` rule in `common.md`.

---

## Phases 8–10 — NestJS-specific details

**Phase 8, step 0 CORS:** none. Browser calls arrive same-origin through the Next.js `/api/external` rewrite, so cookie mode needs no CORS change. Do not set `credentials: true` for the frontend's origin.

**Phase 9 — NestJS CORS config:** no change. The scaffold's `CLIENT_URL` (`serviceConfig.CLIENT_URL` → `setupCors`) only matters for other browser origins that call with Bearer tokens. The Next.js frontend is same-origin through its rewrite, so leave `CLIENT_URL` at its scaffold default.

**Phase 10 — Verify commands:**
```bash
# 1. NestJS backend
cd ../[project-name]-api
pnpm build && pnpm test

# 2. Next.js frontend
cd [original-project-path]
pnpm build && pnpm test
```

For phase 8 steps 1–6, phase 9 AGENTS.md/Next.js updates, and the phase 10 success message, see `common.md`.
