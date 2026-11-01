<!-- ref: migrate/nextjs-backend-extraction/nestjs.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Next.js → NestJS Backend Extraction

Moves `src/app/api/` and the integrations it uses into a sibling NestJS project; Next.js becomes a pure frontend.

**Read `common.md` first** (Phases 1, 2, the Phase 3 skeleton, 8–10); Phases 3–7 are below.

```bash
cat "<skill-dir>/nextjs-backend-extraction/common.md"
```

**Phase 1 NestJS deltas:** In 1d, always include `src/integrations/clients/base/fetch-client.ts` and `axios-client.ts` if they exist. Assessment Database line: `[✓ Drizzle / ✓ Mongoose / None detected]`.

---

## Phase 3 — Scaffold NestJS (autonomous)

```bash
cat "<skill-dir>/../scaffold/nestjs/source-files.md"
```

Scaffold Step 1 copies `<skill-dir>/../scaffold/nestjs/template/`. Set the `package.json` name to `[project-name]-api`.

---

## Phase 4 — Migrate API Routes (autonomous)

Create a NestJS module for each Phase 1c `route.ts`.

**Mapping:**

| Next.js | NestJS |
|---|---|
| `src/app/api/<resource>/route.ts` | `src/modules/<resource>/<resource>.controller.ts` + `.service.ts` + `.module.ts` in `../[project-name]-api` |
| `export async function GET()` | `@Get()`; logic in the service |
| `export async function POST(request: Request)` | `@Post()` with a `nestjs-zod` DTO body |
| `export async function PUT(request, { params })` | `@Put(':id')` with `@Param('id')` |
| `export async function DELETE(_, { params })` | `@Delete(':id')` with `@Param('id')` |
| `handleApiError(label, error)` | Re-throw as `HttpException` (the scaffold's global filter catches it) |
| `NextResponse.json(data, { status: 201 })` | Return the object; `@HttpCode(201)` |
| `return NextResponse.json({ error: 'Not found' }, { status: 404 })` | `throw new HttpException('Not found', HttpStatus.NOT_FOUND)` |
| Dynamic segment `[id]/route.ts` | Single controller method with `@Param('id')` |

**Controller template** (adapt for each resource). Add `Put`, `Delete`, `HttpException` and `HttpStatus` imports only when used: ESLint fails the build on an unused import:

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

**Service** — `src/modules/users/users.service.ts`: an `@Injectable()` class whose `findAll`, `findOne(id)` and `create(dto: CreateUserDto)` take over the handler bodies without the `NextResponse`/`handleApiError` wrapping. Throw `NotFoundException` / `BadRequestException` where the handler returned 404/400.

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

Register each new module in `AppModule` (`../[project-name]-api/src/app.module.ts`):

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

For each Phase 1d integration and base client:

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

Register each service as a provider in its feature module (or a shared `IntegrationsModule`). Then apply the Phase 5 cleanup in `common.md`.

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
   If the Next.js project uses MongoDB IAM auth (`@aws-sdk/credential-providers` in `package.json`), also apply the IAM add-on in place of C2/C7:
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
   If it uses RDS IAM auth (`@aws-sdk/rds-signer` in `package.json`), also apply the IAM add-on in place of B2/B7:
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

If Phase 6 migrated a database, `AuthService` is still a 501 stub (Phase 6 ran first). Replace it now:

| Phase 6 database | Follow |
|---|---|
| Kysely | `cat "<skill-dir>/../add/database/typescript/nestjs-kysely-auth.md"` |
| Drizzle | "Completing Auth Integration" in `cat "<skill-dir>/../add/database/typescript/nestjs-drizzle.md"` |
| Mongoose | `cat "<skill-dir>/../add/database/typescript/nestjs-mongoose-auth.md"` |

Then apply the Phase 7 `proxy.ts` rule in `common.md`.

---

## Phases 8–10 — NestJS-specific details

**Phase 8, step 0 CORS:** none (same-origin through the `/api/external` rewrite). Do not set `credentials: true` for the frontend's origin.

**Phase 9 — NestJS CORS config:** no change. Leave `CLIENT_URL` at its scaffold default; it matters only for other browser origins using Bearer tokens.

**Phase 10 — Verify commands:**
```bash
# 1. NestJS backend
cd ../[project-name]-api
pnpm build && pnpm test

# 2. Next.js frontend
cd [original-project-path]
pnpm build && pnpm test
```

The rest of Phases 8–10 is in `common.md`.
