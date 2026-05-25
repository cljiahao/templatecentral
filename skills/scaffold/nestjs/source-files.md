<!-- ref: scaffold/nestjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part C — Verbatim Source Files

### `src/main.ts`

```typescript
import { config } from 'dotenv';

config();

import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { Logger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { appConfig, setupCors, setupSecurity, setupSwagger } from './config';

async function bootstrap(): Promise<void> {
  const trustProxyEnv = process.env.TRUST_PROXY;
  // Fastify: "*" → true (trust all); numeric strings → integer hop count; CIDR strings pass through
  const trustProxy: boolean | number | string | undefined =
    trustProxyEnv === '*' ? true :
    trustProxyEnv && /^\d+$/.test(trustProxyEnv) ? parseInt(trustProxyEnv, 10) :
    trustProxyEnv;
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter(trustProxy ? { trustProxy } : {}),
    { bufferLogs: true },
  );
  const logger = app.get(Logger);
  app.useLogger(logger);

  await setupSecurity(app);
  logger.log('Security middleware configured');

  setupCors(app);
  logger.log('CORS configured');

  setupSwagger(app);
  logger.log('Swagger documentation configured');

  await app.init();
  logger.log('Application initialized');

  const port = appConfig.PORT;
  await app.listen(port, '0.0.0.0');

  logger.log(`${appConfig.PROJECT_NAME} running on: http://localhost:${port}`);
  logger.log(`Swagger docs available at: http://localhost:${port}/docs`);
}

bootstrap().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

### `src/app.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { APP_FILTER, APP_PIPE } from '@nestjs/core';
import { ZodValidationPipe } from 'nestjs-zod';
import { LoggerModule } from 'nestjs-pino';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { BaseModule, ExampleModule } from './modules';
import { appConfig } from './config';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL ?? 'info',
        genReqId: () => crypto.randomUUID(), // correlation ID
        transport:
          appConfig.ENVIRONMENT !== 'prod' && appConfig.ENVIRONMENT !== 'uat'
            ? { target: 'pino-pretty', options: { singleLine: true } }
            : undefined,
      },
    }),
    BaseModule,
    ExampleModule,
  ],
  providers: [
    {
      provide: APP_PIPE,
      useClass: ZodValidationPipe,
    },
    {
      provide: APP_FILTER,
      useClass: HttpExceptionFilter,
    },
  ],
})
export class AppModule {}
```

### `src/common/constants/http.constants.ts`

```typescript
export const HTTP_STATUS_MESSAGES = {
  BAD_REQUEST: 'Bad request',
  UNAUTHORIZED: 'Unauthorized access',
  FORBIDDEN: 'Forbidden resource',
  NOT_FOUND: 'Resource not found',
  METHOD_NOT_ALLOWED: 'Method not allowed',
  CONFLICT: 'Resource conflict',
  TOO_MANY_REQUESTS: 'Too many requests',
  INTERNAL_ERROR: 'Internal server error',
} as const;
```

### `src/common/constants/index.ts`

```typescript
export * from './http.constants';
```

### `src/common/filters/http-exception.filter.ts`

```typescript
import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { ZodSerializationException } from 'nestjs-zod';
import { ZodError } from 'zod';

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost) {
    if (exception instanceof ZodSerializationException) {
      const zodError: unknown = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
    }

    const ctx = host.switchToHttp();
    const reply = ctx.getResponse<FastifyReply>();
    const status = exception.getStatus();
    reply.status(status).send({ statusCode: status, message: exception.message });
  }
}
```

### `src/common/utils/date.utils.ts`

```typescript
export function toISOString(date: Date = new Date()): string {
  return date.toISOString();
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

export function isExpired(expiresAt: Date): boolean {
  return new Date() > expiresAt;
}
```

### `src/common/utils/string.utils.ts`

```typescript
export function convertStrToList(
  value: string | undefined,
  delimiter: string,
): string[] | undefined {
  if (!value) return undefined;
  return value
    .split(delimiter)
    .map((s) => s.trim())
    .filter(Boolean);
}
```

### `src/config/env.config.ts`

```typescript
export const appConfig = {
  PROJECT_NAME: process.env.PROJECT_NAME || 'My Project',
  PROJECT_DESCRIPTION:
    process.env.PROJECT_DESCRIPTION ||
    'API built with [NestJS](https://nestjs.com/) + Fastify',
  PROJECT_VERSION: process.env.PROJECT_VERSION || '0.1.0',
  ENVIRONMENT: process.env.ENVIRONMENT || 'dev',
  PORT: Number.isFinite(parseInt(process.env.PORT ?? '', 10))
    ? parseInt(process.env.PORT!, 10)
    : 3000,
};

export const serviceConfig = {
  CLIENT_URL: (process.env.CLIENT_URL || 'http://localhost:3000').split(','),
};
```

### `src/config/index.ts`

```typescript
export * from './env.config';
export * from './setups/swagger.setup';
export * from './setups/security.setup';
```

### `src/config/setups/security.setup.ts`

```typescript
import fastifyHelmet from '@fastify/helmet';
import type { INestApplication } from '@nestjs/common';
import type { FastifyInstance } from 'fastify';
import { serviceConfig } from '..';

export async function setupSecurity(app: INestApplication): Promise<void> {
  const fastify = app.getHttpAdapter().getInstance() as FastifyInstance;

  await fastify.register(fastifyHelmet, {
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    contentSecurityPolicy: {
      directives: {
        'default-src': ["'self'"],
        'script-src': ["'self'"],
        'style-src': ["'self'", "'unsafe-inline'"],
        'img-src': ["'self'", 'data:', 'https:'],
        'object-src': ["'none'"],
        'base-uri': ["'none'"],
        'frame-ancestors': ["'none'"],
      },
    },
    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true }, // HSTS
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    xFrameOptions: { action: 'deny' },
  });

  fastify.addHook('onSend', async (_request, reply, payload) => {
    void reply.header('Cache-Control', 'no-cache, no-store, must-revalidate, private');
    void reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    return payload;
  });
}

export function setupCors(app: INestApplication): void {
  app.enableCors({
    origin: serviceConfig.CLIENT_URL,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization'],
  });
}
```

### `src/config/setups/swagger.setup.ts`

```typescript
import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { appConfig } from '..';

export function setupSwagger(app: INestApplication): void {
  if (process.env.NODE_ENV === 'production') return;

  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, cleanupOpenApiDoc(document));
}
```

### `src/modules/index.ts`

```typescript
export * from './base/base.module';
export * from './example/example.module';
```

### `src/modules/base/base.controller.ts`

```typescript
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Controller, Get, HttpCode, HttpStatus } from '@nestjs/common';
import { BaseService } from './base.service';

@ApiTags('Base')
@Controller()
export class BaseController {
  constructor(private readonly baseService: BaseService) {}

  @Get()
  @ApiOperation({ summary: 'Root endpoint' })
  getHello(): string {
    return this.baseService.getHello();
  }

  @Get('health')
  @ApiOperation({ summary: 'Health check' })
  @HttpCode(HttpStatus.OK)
  checkHealth(): { status: string } {
    return this.baseService.getHealth();
  }
}
```

### `src/modules/base/base.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { BaseController } from './base.controller';
import { BaseService } from './base.service';

@Module({
  controllers: [BaseController],
  providers: [BaseService],
})
export class BaseModule {}
```

### `src/modules/base/base.service.ts`

```typescript
import { Injectable } from '@nestjs/common';

@Injectable()
export class BaseService {
  getHello(): string {
    return 'Hello World!';
  }

  getHealth(): { status: string } {
    return { status: 'ok' };
  }
}
```

### `src/modules/example/example.controller.ts`

```typescript
import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Param,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiParam, ApiBody } from '@nestjs/swagger';
import { ExampleService } from './example.service';
import { CreateExampleDto, UpdateExampleDto } from './example.dto';
import type { ExampleItem } from './example.types';

@ApiTags('Example')
@Controller('examples')
export class ExampleController {
  constructor(private readonly exampleService: ExampleService) {}

  @Get()
  @ApiOperation({ summary: 'List all examples' })
  findAll(): ExampleItem[] {
    return this.exampleService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get example by ID' })
  @ApiParam({ name: 'id', type: 'string' })
  findOne(@Param('id') id: string): ExampleItem {
    return this.exampleService.findOne(id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a new example' })
  @ApiBody({ type: CreateExampleDto })
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateExampleDto): ExampleItem {
    return this.exampleService.create(dto);
  }

  @Put(':id')
  @ApiOperation({ summary: 'Update an example' })
  @ApiParam({ name: 'id', type: 'string' })
  @ApiBody({ type: UpdateExampleDto })
  update(
    @Param('id') id: string,
    @Body() dto: UpdateExampleDto,
  ): ExampleItem {
    return this.exampleService.update(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete an example' })
  @ApiParam({ name: 'id', type: 'string' })
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string): void {
    this.exampleService.remove(id);
  }
}
```

### `src/modules/example/example.dto.ts`

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateExampleSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

const UpdateExampleSchema = CreateExampleSchema.partial();

export class CreateExampleDto extends createZodDto(CreateExampleSchema) {}
export class UpdateExampleDto extends createZodDto(UpdateExampleSchema) {}
```

### `src/modules/example/example.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { ExampleController } from './example.controller';
import { ExampleService } from './example.service';
import { ExampleRepository } from './example.repository';

@Module({
  controllers: [ExampleController],
  providers: [ExampleService, ExampleRepository],
  exports: [ExampleService],
})
export class ExampleModule {}
```

### `src/modules/example/example.repository.ts`

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import type { ExampleItem } from './example.types';

@Injectable()
export class ExampleRepository {
  private readonly items = new Map<string, ExampleItem>();

  findAll(): ExampleItem[] {
    return Array.from(this.items.values());
  }

  findById(id: string): ExampleItem {
    const item = this.items.get(id);
    if (!item) throw new NotFoundException(`Example with id "${id}" not found`);
    return item;
  }

  create(item: ExampleItem): ExampleItem {
    this.items.set(item.id, item);
    return item;
  }

  update(id: string, data: Partial<ExampleItem>): ExampleItem {
    const existing = this.findById(id);
    const updated = { ...existing, ...data, updatedAt: new Date().toISOString() };
    this.items.set(id, updated);
    return updated;
  }

  remove(id: string): void {
    if (!this.items.has(id)) {
      throw new NotFoundException(`Example with id "${id}" not found`);
    }
    this.items.delete(id);
  }
}
```

### `src/modules/example/example.service.ts`

```typescript
import { Injectable } from '@nestjs/common';
import { ExampleRepository } from './example.repository';
import type { CreateExampleDto, UpdateExampleDto } from './example.dto';
import type { ExampleItem } from './example.types';

@Injectable()
export class ExampleService {
  constructor(private readonly repository: ExampleRepository) {}

  findAll(): ExampleItem[] {
    return this.repository.findAll();
  }

  findOne(id: string): ExampleItem {
    return this.repository.findById(id);
  }

  create(dto: CreateExampleDto): ExampleItem {
    const now = new Date().toISOString();
    const item: ExampleItem = {
      id: crypto.randomUUID(),
      name: dto.name,
      description: dto.description,
      createdAt: now,
      updatedAt: now,
    };
    return this.repository.create(item);
  }

  update(id: string, dto: UpdateExampleDto): ExampleItem {
    return this.repository.update(id, dto);
  }

  remove(id: string): void {
    this.repository.remove(id);
  }
}
```

### `src/modules/example/example.types.ts`

```typescript
export interface ExampleItem {
  id: string;
  name: string;
  description?: string;
  createdAt: string;
  updatedAt: string;
}
```

### `test/app.e2e-spec.ts`

```typescript
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';

describe('AppController (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET / should return "Hello World!"', () => {
    return app
      .inject({ method: 'GET', url: '/' })
      .then((result) => {
        expect(result.statusCode).toBe(200);
        expect(result.payload).toBe('Hello World!');
      });
  });

  it('GET /health should return OK', () => {
    return app
      .inject({ method: 'GET', url: '/health' })
      .then((result) => {
        expect(result.statusCode).toBe(200);
        expect(JSON.parse(result.payload)).toEqual({ status: 'ok' });
      });
  });
});
```

### `test/modules/base.controller.spec.ts`

```typescript
import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { BaseController } from '../../src/modules/base/base.controller';
import { BaseService } from '../../src/modules/base/base.service';

describe('BaseController', () => {
  let controller: BaseController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [BaseController],
      providers: [BaseService],
    }).compile();

    controller = module.get<BaseController>(BaseController);
  });

  it('should return "Hello World!"', () => {
    expect(controller.getHello()).toBe('Hello World!');
  });

  it('should return health status ok', () => {
    expect(controller.checkHealth()).toEqual({ status: 'ok' });
  });
});
```

### `test/modules/example.controller.spec.ts`

```typescript
import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { ExampleController } from '../../src/modules/example/example.controller';
import { ExampleService } from '../../src/modules/example/example.service';
import { ExampleRepository } from '../../src/modules/example/example.repository';

describe('ExampleController', () => {
  let controller: ExampleController;
  let service: ExampleService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [ExampleController],
      providers: [ExampleService, ExampleRepository],
    }).compile();

    controller = module.get<ExampleController>(ExampleController);
    service = module.get<ExampleService>(ExampleService);
  });

  it('should return an empty array initially', () => {
    expect(controller.findAll()).toEqual([]);
  });

  it('should create and retrieve an example', () => {
    const created = controller.create({ name: 'Test', description: 'Desc' });
    expect(created.name).toBe('Test');
    expect(created.id).toBeDefined();

    const found = controller.findOne(created.id);
    expect(found.name).toBe('Test');
  });

  it('should update an example', () => {
    const created = service.create({ name: 'Original' });
    const updated = controller.update(created.id, { name: 'Updated' });
    expect(updated.name).toBe('Updated');
  });

  it('should delete an example', () => {
    const created = service.create({ name: 'ToDelete' });
    controller.remove(created.id);
    expect(controller.findAll()).toEqual([]);
  });
});
```

---

## Scaffold Steps

### 1. Write All Files

Create the target directory and write all files:

- All **Part B** config files verbatim (including `.husky/pre-commit` and `.husky/pre-push`)
- All **Part C** source files verbatim
- Create two empty files: `src/common/types/.gitkeep` and `src/database/.gitkeep`
- Generate `package.json` with the project name substituted (see Generation Conventions)
- Generate `README.md` (see Generation Conventions)

Make `docker-entrypoint.sh` and both husky hooks executable:

```bash
chmod +x docker-entrypoint.sh .husky/pre-commit .husky/pre-push
```

### 2. Update Project Settings

In `package.json`, set `"name"` to the project name (kebab-case).

In `src/config/env.config.ts`, update the fallback defaults:

```typescript
PROJECT_NAME: process.env.PROJECT_NAME || '<Project Name>',
PROJECT_DESCRIPTION:
  process.env.PROJECT_DESCRIPTION ||
  'API built with [NestJS](https://nestjs.com/) + Fastify',
```

In `.env.example`, update:

```env
PROJECT_NAME=<project-name>
```

### 3. Create Environment File

```bash
cp .env.example .env
```

### 4. Install Dependencies

```bash
git init
pnpm install
```

`pnpm install` triggers the `prepare` script which activates husky.

### 5. Verification Gate

**Do NOT generate AGENTS.md until all three pass:**

```bash
pnpm build        # zero compile errors
pnpm test         # all unit tests pass
pnpm test:e2e     # e2e tests pass
```

If any command fails, diagnose and fix before proceeding.

### 6. Generate AGENTS.md (MANDATORY)

Write `<!-- templateCentral: nestjs@4.0.0 -->` on line 1, then:

```markdown
<!-- templateCentral: nestjs@4.0.0 -->
# <Project Name>

## Identity
- **Stack**: NestJS 11, Fastify, Zod + nestjs-zod, Swagger, TypeScript, Vitest
- **Scaffolded from**: templateCentral (templatecentral:scaffold)
- **Created**: <date>

## Architecture Decisions
- One module per feature under `src/modules/`
- Controller → Service (→ Repository for complex queries); simple CRUD may use ORM directly in services
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes and filters in `app.module.ts`; auth guards at controller/route level
- Setup functions (Swagger, security) in `src/config/setups/`

## Key Conventions
- kebab-case filenames (dot-separated), PascalCase classes, camelCase methods
- Named exports only — no `export default`
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint
- Barrel exports at `src/modules/index.ts`
- **Testing**: New or changed controllers/services/repositories must include Vitest tests in the same change (`pnpm test`; e2e when appropriate)

## Commands
- `pnpm start:dev` — development server with hot reload
- `pnpm build` — compile TypeScript
- `pnpm test` — run unit tests
- `pnpm test:e2e` — run e2e tests
- `pnpm check` — format + lint + typecheck

## Code Quality

Every agent writing or modifying code must follow these before marking a task done:

- **YAGNI** — Write only what the current task requires. No speculative helpers, abstractions, or files.
- **DRY** — Don't duplicate logic; extract at the second repetition. Don't extract from a single callsite.
- **SRP** — One responsibility per file and function. Controllers handle HTTP; services handle business logic; never mix.
- **SoC** — Keep concerns separate: HTTP from business logic, DTO validation from domain logic, config from implementation.
- **No premature abstractions** — Wait for the third callsite before extracting a shared helper.
- **No dead code** — No commented-out blocks, unused imports, unused variables, or TODO stubs.
- **No tech debt shortcuts** — No `// fix later`, `// temp`, or workarounds that degrade the codebase.
- **Validate at every boundary** — User input, API responses, env vars: always validate with Zod (`createZodDto`). Never trust external data.
- **Fail loudly** — No empty catch blocks. Log with context; return meaningful HTTP status codes.
- **Least privilege** — Return only the fields the caller needs. Never expose internal IDs without auth checks.
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.
- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat `.env` files are for local development only.

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `templatecentral:standards` (drift-check) at the start of each session to check for convention or dependency drift.

## AI Harness

`.claude/settings.json` at the project root runs the test suite automatically after every file edit — output appears after each change. This is feedback only; it never blocks execution.

<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
```

Update `Identity` with the actual project name and creation date.

### 6b. Create .claude/settings.json

Create `.claude/settings.json` at the project root. If the file already exists, merge the `PostToolUse` hook rather than overwriting.

**`.claude/settings.json`**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "pnpm test --run 2>&1 | tail -20"
          }
        ]
      }
    ]
  }
}
```

Also create `FUTURE.md` at the project root:

**`FUTURE.md`**:
```markdown
# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** The disabled trace hook placeholder in `.claude/settings.json`.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated in v4.0.*
```

### 6c. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `templatecentral:build` — verify the scaffold compiles clean (`pnpm build`)
2. `templatecentral:test` — verify all scaffold tests pass (`pnpm test && pnpm test:e2e`)
3. `templatecentral:review` (update operation) — freshen any deps that have newer compatible versions
4. `templatecentral:review` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6c. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

### 7. Generate CLAUDE.md (Optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Write a short `CLAUDE.md` (architecture and conventions live in `AGENTS.md` only).

Include:
- **Build & Dev** verified commands: `pnpm start:dev`, `pnpm build`, `pnpm test`, `pnpm test:e2e`, `pnpm lint`
- **templateCentral skills**: `templatecentral:scaffold` (done), `templatecentral:standards`, `templatecentral:add` (module, auth, database, integration, test)
- **Workflow**: simple/medium → templateCentral skills; complex → Superpowers
- NEVER put secrets in `CLAUDE.md`

### 7b. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from **Scaffold: optional Task Management** in templateCentral's root `AGENTS.md`. If no, skip.

### 8. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs, use the `templatecentral:cleanup` skill.

NestJS-specific steps (the skill covers these):
- Delete `src/modules/example/` directory
- Remove `ExampleModule` import and reference from `src/modules/index.ts`
- Remove `ExampleModule` from `imports` array in `src/app.module.ts`
- Delete `test/modules/example.controller.spec.ts`

---

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — **never** commit real secrets or paste JWT/DB credentials into `AGENTS.md` / `CLAUDE.md`
- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `dist/`, or `.env` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove the `base/` module — it provides the health check endpoint
- NEVER install packages globally — always use pnpm/npm within the project
- NEVER remove `test/` directory structure when cleaning up example code