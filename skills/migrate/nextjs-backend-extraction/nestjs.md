<!-- ref: migrate/nextjs-backend-extraction/nestjs.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = NestJS. Do not invoke this file directly. -->

# Next.js → NestJS Backend Extraction

Extracts `src/app/api/` route handlers and relevant `src/integrations/` clients from a Next.js project into a sibling NestJS project. Next.js becomes a pure frontend.

**Read `common.md` first.** Phases 1, 2, 8, 9, 10 live there. Phases 3–7 are below. Variable substitutions: `[BACKEND]` = NestJS, `[DEV_PORT]` = 3001, `[CORS_VAR]` = `CLIENT_URL`.

```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/migrate/nextjs-backend-extraction/common.md"
```

**Phase 1 NestJS deltas:** In 1d, also always include `src/integrations/clients/base/fetch-client.ts` and `src/integrations/clients/base/axios-client.ts` if they exist. Assessment Database line: `[✓ Drizzle / ✓ Mongoose / None detected]`.

---

## Phase 3 — Scaffold NestJS (autonomous)

```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/nestjs/config-files.md"
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/nestjs/source-files.md"
```

Set the project name to `[project-name]-api` in `package.json`. (See `common.md` Phase 3 for shared context.)

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

**Controller template** (adapt for each resource):

```typescript
// src/modules/users/users.controller.ts
import {
  Controller, Get, Post, Put, Delete,
  Body, Param, HttpCode, HttpException, HttpStatus,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';

@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  findAll() {
    return this.usersService.findAll();
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.usersService.findOne(id);
  }

  @Post()
  @HttpCode(201)
  create(@Body() dto: CreateUserDto) {
    return this.usersService.create(dto);
  }
}
```

**Service template** (move business logic from the route handler body here):

```typescript
// src/modules/users/users.service.ts
import { Injectable } from '@nestjs/common';

@Injectable()
export class UsersService {
  async findAll() {
    return [];
  }

  async findOne(id: string) {
    return null;
  }

  async create(dto: unknown) {
    return dto;
  }
}
```

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
import { FetchClient } from '../clients/base/fetch-client';

@Injectable()
export class GithubService extends FetchClient {
  constructor() {
    super(process.env.GITHUB_API_URL!, {
      Authorization: `Bearer ${process.env.GITHUB_TOKEN!}`,
    });
  }

  async getRepos() {
    return this.request<unknown[]>('repos');
  }
}
```

Copy base client files (`fetch-client.ts`, `axios-client.ts`, `https-agent.ts`) verbatim to `../[project-name]-api/src/integrations/clients/base/`.

Copy schemas alongside the service they belong to.

Register each service as a provider in the relevant feature module (or in a shared `IntegrationsModule` if used by multiple modules).

**Clean up Next.js `src/integrations/`:**
- Delete each file that was moved.
- If `src/integrations/` is empty after removal (no frontend-only entries remain), delete the directory.
- If frontend-only entries remain, leave the directory intact.

---

## Phase 6 — Migrate Database (autonomous)

**If no database detected in Phase 1f:** Skip this phase.

**NestJS + Drizzle:**

1. Copy `src/integrations/database/` → `../[project-name]-api/src/database/`
2. Copy `drizzle.config.ts` → `../[project-name]-api/drizzle.config.ts` (update internal paths)
3. Load and follow the Drizzle database skill for NestJS:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/database/typescript/nestjs-drizzle.md"
```
4. Delete `src/integrations/database/` and `drizzle.config.ts` from the Next.js project.

**NestJS + Mongoose:**

1. Copy Mongoose schema files from `src/integrations/database/` → `../[project-name]-api/src/database/`
2. Load and follow the Mongoose database skill for NestJS:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/database/typescript/nestjs-mongoose.md"
```
3. Delete `src/integrations/database/` from the Next.js project.

---

## Phase 7 — Migrate Auth (autonomous)

**If `proxy.ts` not detected in Phase 1g:** Skip this phase.

Load and follow the NestJS auth skill in `../[project-name]-api`:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/add/auth/nestjs.md"
```

**Important:** `proxy.ts` remains in the Next.js project — it continues to protect frontend routes at the edge. After migration, update any hardcoded Next.js `/api/auth/...` paths in `proxy.ts` to use `process.env.NEXT_PUBLIC_API_URL`.

---

## Phases 8–10 — NestJS-specific details

**Phase 8, step 0 CORS:** Enable CORS credentials on the backend (`credentials: true`) if using cookie-based sessions.

**Phase 9 — NestJS CORS config:** The NestJS scaffold already reads `CLIENT_URL` (via `serviceConfig.CLIENT_URL` from `src/config/env.config.ts`, used by `setupCors`) — no code change needed. Set it to the Next.js origin. Add to `../[project-name]-api/.env.example`:
```
# Frontend origin for CORS
CLIENT_URL=http://localhost:3000
```

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
