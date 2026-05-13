<!-- ref: migrate/nextjs-backend-extraction/nestjs.md
     loaded-by: migrate/nextjs-backend-extraction.md → migrate/SKILL.md
     prereq: Stack = Next.js, target backend = NestJS. Do not invoke this file directly. -->

# Next.js → NestJS Backend Extraction

Extracts `src/app/api/` route handlers and relevant `src/integrations/` clients from a Next.js project into a sibling NestJS project. Next.js becomes a pure frontend.

---

## Phase 1 — Assessment (autonomous)

Scan the Next.js project root. Run each check in order.

**1a. Verify templateCentral marker**

Read `AGENTS.md`. If `<!-- templateCentral: nextjs@` is not on line 1, exit:
> "This skill requires a Next.js project scaffolded with templatecentral:scaffold. No changes made."

**1b. Read project name**

Read `package.json` → `name` field. This becomes `[project-name]`. The NestJS project will be created at `../[project-name]-api`.

**1c. Inventory API routes**

List all `src/app/api/**/route.ts` files. For each, read the exported function names to determine HTTP methods (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).

**1d. Identify integrations to move**

For each `route.ts` file, scan import statements for any path starting with `@/integrations/` or `../integrations/`. Collect the unique set. Also always include `src/integrations/clients/base/fetch-client.ts` and `src/integrations/clients/base/axios-client.ts` if they exist.

**1e. Identify integrations staying in Next.js**

List all files under `src/integrations/` that were NOT collected in 1d.

**1f. Detect database**

Check for `drizzle.config.ts` (Drizzle) or `src/integrations/database/` containing `.schema.ts` files (Mongoose schemas). Record which ORM if found.

**1g. Detect auth**

Check whether `proxy.ts` or `src/proxy.ts` exists. Record presence.

**Print the assessment:**

```
📋 Backend Extraction Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project:          [project-name]  →  ../[project-name]-api (NestJS)

API routes (move to NestJS):
  [list each route.ts with methods, e.g. src/app/api/users/route.ts  GET POST]

Integrations to move (imported by API routes):
  [list each file path]

Integrations staying in Next.js:
  [list each file path, or "None"]

Database:         [✓ Drizzle / ✓ Mongoose / None detected]
Auth:             [✓ proxy.ts detected / None detected]

Next.js after migration: pure frontend, calls NEXT_PUBLIC_API_URL
New backend URL:  http://localhost:3001 (dev) / NEXT_PUBLIC_API_URL (prod)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 2 — Scope Confirmation ⛔ GATE

Do not proceed until the user responds. Ask:

> "This will create `../[project-name]-api` (NestJS), migrate the items listed above, and rewire Next.js as a pure frontend. This cannot be automatically undone. Proceed? (yes / no)"

If no → print "No changes made." and exit.

---

## Phase 3 — Scaffold NestJS (autonomous)

Determine the sibling path: `../[project-name]-api`.

Load and follow the NestJS scaffold steps:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/nestjs/config-files.md"
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/scaffold/nestjs/source-files.md"
```

Work from `../[project-name]-api` as the project root. Set the project name to `[project-name]-api` in `package.json`.

**Do not run post-scaffold agents** (build, test, update, review) — verification happens in Phase 10.

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
import { Controller, Get, Post, Body, Param, HttpCode } from '@nestjs/common';
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
  email: z.string().email(),
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
- If `src/integrations/` is empty after removal, delete the directory.
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

## Phase 8 — Rewire Next.js Frontend (autonomous)

1. **Delete `src/app/api/`** — all route handlers have moved to NestJS.

2. **Update `src/lib/constants/env.ts`** — add `API_BASE`:

```typescript
export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3001';
```

3. **Update feature service files** — for each file under `src/features/` that calls `fetch('/api/...')`, replace with `API_BASE`:

```typescript
// Before
const res = await fetch('/api/users');

// After
import { API_BASE } from '@/lib/constants/env';
const res = await fetch(`${API_BASE}/users`);
```

4. **Update `.env.example`** — add:

```
# Backend API (NestJS)
# Dev default: http://localhost:3001
NEXT_PUBLIC_API_URL=http://localhost:3001
```

5. **Update `.env.local`** — add the same line.

6. **Clean up `src/integrations/`** — after Phase 5 cleanup, if the directory is empty, delete it.

---

## Phase 9 — Update Config & Docs (autonomous)

**NestJS project (`../[project-name]-api`):**

Update CORS config to read `FRONTEND_URL`. In the NestJS scaffold's `src/config/index.ts` (or wherever `setupCors` is defined):

```typescript
const frontendUrl = process.env.FRONTEND_URL ?? 'http://localhost:3000';
// cors origin: [frontendUrl]
```

Add to `../[project-name]-api/.env.example`:
```
# Frontend origin for CORS
FRONTEND_URL=http://localhost:3000
```

Update `../[project-name]-api/AGENTS.md` — prepend to Project-Specific Notes:
```
- Extracted from `[project-name]` (Next.js frontend) — see `../[project-name]`
- Frontend calls this API; set FRONTEND_URL to the Next.js origin in production
```

**Next.js project:**

Update `AGENTS.md` Architecture Decisions — replace the BFF note with:
```
- API routes removed — backend extracted to `../[project-name]-api` (NestJS)
- This project is a pure frontend; all data fetching uses `NEXT_PUBLIC_API_URL`
```

---

## Phase 10 — Verify (autonomous)

Run in sequence. Stop and report the exact error on first failure.

```bash
# 1. NestJS backend
cd ../[project-name]-api
pnpm build
pnpm test

# 2. Next.js frontend
cd [original-project-path]
pnpm build
pnpm test
```

**If all pass**, print:

```
✓ Migration complete.

Next.js frontend: [original-project-path]
  → Pure frontend. Set NEXT_PUBLIC_API_URL in your deployment environment.

NestJS backend:   ../[project-name]-api
  → Set FRONTEND_URL to the Next.js origin in your deployment environment.

Next steps:
- Review proxy.ts — update any hardcoded /api paths to use NEXT_PUBLIC_API_URL
- Set up Docker Compose if you want both services running locally with one command
- Configure CI/CD pipelines for each repo independently
```

**If any command fails**, print the exact error output and stop.
