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
  // Fastify trustProxy: "*" → trust all; number = hop count (1 = one-hop ALB→App, 2 = two-hop ALB→Traefik→App); CIDR string = trusted range.
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
- Write `package.json` verbatim from `config-files.md`, substituting the project `"name"` (kebab-case)
- Write `README.md` (brief project intro + the commands from `package.json` scripts)

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

### 6. Write project AGENTS.md

Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

```markdown
<!-- templateCentral: nestjs@4.0.0 -->
# AGENTS.md — [Project Name]

## Stack
NestJS 11 · Fastify · Zod + nestjs-zod · Swagger · TypeScript strict · Vitest · pnpm · Node ≥24

## Commands
```bash
pnpm start:dev    # dev server with hot reload
pnpm build        # compile TypeScript
pnpm test         # run unit tests
pnpm test:e2e     # run e2e tests
pnpm check        # format + lint + typecheck
```

## Architecture
- `src/modules/<name>/` — one module per feature (controller → service → optional repository)
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes/filters in `app.module.ts`; auth guards at controller level
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/nest-verify` | typecheck + lint + test in one pass |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (module)` | full feature module |
| `templatecentral:add (endpoint)` | new route + DTO + service method |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |
| `templatecentral:audit` | full ecosystem + accuracy audit |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod (`createZodDto`) at every boundary
- kebab-case filenames, PascalCase classes, camelCase methods; named exports only
- No secrets in code — use env vars; document in `.env.example`

## AI Harness
PreToolUse: blocks secrets and CI pipeline files only (exit 2): `.env*` (except `.env.example`), `.github/workflows/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`. Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/compact): re-injects AGENTS.md routing context + universal invariants so they survive compaction (PostCompact is observability-only and cannot inject).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: `pnpm exec tsc --noEmit --incremental 2>&1 | tail -5` after every Edit/Write. Feedback-only.
Stop hook: runs full test suite; exit 2 feeds failures to Claude via stderr; exit 0 on pass.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
```

### 6b. Create .claude/settings.json

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (below). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present.

**`.claude/settings.json`**:
```json
{
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.local)",
      "Read(.env.*.local)",
      "Read(.env.development)",
      "Read(.env.development.*)",
      "Read(.env.dev)",
      "Read(.env.production)",
      "Read(.env.production.*)",
      "Read(.env.staging)",
      "Read(.env.staging.*)",
      "Read(.env.uat)",
      "Read(.env.test)",
      "Read(./secrets/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/protect-files.sh" }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-no-verify.sh" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "node .claude/hooks/user-prompt-guard.js" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-edit-typecheck.sh" }]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/post-tool-failure.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/stop-checks.sh" }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/subagent-stop.sh" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-context.sh" }]
      }
    ]
  },
  "skillListingBudgetFraction": 0.02
}
```

Hook logic lives in `.claude/hooks/` scripts (seeded below) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `.github/workflows/`, cert/credential files; warns on governance files (`AGENTS.md`, `CLAUDE.md`, `Dockerfile`). Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — blocks `git commit --no-verify`, direct commits/force-push to protected branches (`main`/`uat`/`develop`), and `rm -rf` on source dirs.
- `user-prompt-guard.js` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs).
- `post-edit-typecheck.sh` (PostToolUse) — incremental `tsc` feedback, filtered to TS edits in-script. Feedback-only; exit 0 always.
- `post-tool-failure.sh` (PostToolUseFailure) — surfaces tool error context for self-correction.
- `stop-checks.sh` (Stop) — runs the test suite; exit 2 forces a fix before the turn ends.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted TS changes so it can't hand back broken code.
- `session-context.sh` (SessionStart: startup/resume/compact) — re-injects AGENTS.md routing context + universal invariants. This is the working post-compaction recovery path; PostCompact is observability-only and cannot inject context, so it is not used.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**`.claude/hooks/protect-files.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Edit|Write) — protect secrets, CI, cert, and governance files.
# Exit 2 = hard block; exit 1 = warn (human approval expected); exit 0 = allow.
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$file" ] && exit 0
base="${file##*/}"

# Hard block: .env* except the committed templates
if [[ "$base" == .env* && "$base" != ".env.example" && "$base" != ".env.default" ]]; then
  echo "BLOCKED: writing $base is not allowed. Add placeholders to .env.example; keep real secrets out of the repo." >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || root="."
rel="${file#"$root"/}"

if [[ "$rel" == .github/workflows/* ]]; then
  echo "BLOCKED: $rel is a CI/CD pipeline definition — requires human review." >&2
  exit 2
elif [[ "$rel" =~ \.(pem|key|p12|pfx|secret)$ ]] || [[ "$base" == "credentials.json" || "$base" == ".netrc" || "$base" == ".secrets" ]]; then
  echo "BLOCKED: $rel is a certificate or credential file — must never be committed." >&2
  exit 2
fi

reason=""
case "$rel" in
  AGENTS.md|CLAUDE.md) reason="agent instruction file — prompt-injection attack surface" ;;
  docs/CONSTITUTION.md) reason="binding invariants document — changes affect all agents and this project's behaviour" ;;
  .claude/settings.json) reason="harness config — editing it can silently disable every hook" ;;
  .claude/hooks/*) reason="enforcement hook script — editing it can weaken or disable a guard" ;;
  Dockerfile) reason="container image definition" ;;
esac
if [ -n "$reason" ]; then
  echo "PROTECTED FILE: $rel — $reason. Confirm human approval and note it in the PR." >&2
  exit 1
fi
exit 0
```

**`.claude/hooks/block-no-verify.sh`**:
```bash
#!/usr/bin/env bash
# PreToolUse(Bash) — block hook-bypass and destructive git/shell commands. Exit 2 = block.
input=$(cat)
cmd=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(((JSON.parse(b||'{}').tool_input)||{}).command||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
[ -z "$cmd" ] && exit 0

if echo "$cmd" | grep -qE 'git[[:space:]]+commit' && echo "$cmd" | grep -qE '\-\-no-verify|[[:space:]]-[a-z]*n'; then
  echo "BLOCKED: --no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$branch" == "main" || "$branch" == "uat" || "$branch" == "develop" ]]; then
    echo "BLOCKED: direct commit to protected branch '$branch'. Create a feature branch first." >&2
    exit 2
  fi
fi
if echo "$cmd" | grep -qE 'git[[:space:]]+push' && { { echo "$cmd" | grep -qE '\-\-force([[:space:]=]|$)|[[:space:]]-[a-z]*f' && echo "$cmd" | grep -qE '\bmain\b|\buat\b|\bdevelop\b'; } || echo "$cmd" | grep -qE '[[:space:]]\+(main|uat|develop)\b'; }; then
  echo "BLOCKED: force-push to a protected branch (--force/-f or +refspec). Open a PR instead." >&2
  exit 2
fi
if echo "$cmd" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*r|[[:space:]]--recursive' && echo "$cmd" | grep -qE '[[:space:]]-[a-zA-Z]*f|[[:space:]]--force' && echo "$cmd" | grep -qE '(^|[[:space:]/])(src|app|lib|test|\.claude|\.husky|\.git|node_modules)([[:space:]/]|$)'; then
  echo "BLOCKED: recursive rm on a source directory. Confirm with a human first." >&2
  exit 2
fi
exit 0
```

**`.claude/hooks/user-prompt-guard.js`**:
```javascript
#!/usr/bin/env node
// UserPromptSubmit — OWASP LLM01 injection guard + LLM02 credential-leak detection. Exit 2 = block.
const input = require('fs').readFileSync(0, 'utf8');
let prompt = '';
try { prompt = (JSON.parse(input || '{}').prompt) || ''; } catch { process.exit(0); }
const lower = prompt.toLowerCase();

const injection = [
  'ignore previous instructions',
  'ignore all instructions',
  'disregard your',
  'forget your instructions',
  'override your',
  'new instructions:',
  'system prompt:',
  'your real instructions',
  'you are now a different ai',
  'you are no longer bound',
  'pretend you are not bound',
  'pretend you have no restrictions',
  'act as if you have no restrictions',
  'developer mode enabled',
];
for (const p of injection) {
  if (lower.includes(p)) {
    process.stderr.write(`Blocked: prompt matches an injection pattern (OWASP LLM01): "${p}"\n`);
    process.exit(2);
  }
}

const credentials = [
  [/AKIA[0-9A-Z]{16}/, 'AWS access key ID'],
  [/ghp_[A-Za-z0-9]{36}/, 'GitHub personal access token'],
  [/github_pat_[A-Za-z0-9_]{82}/, 'GitHub fine-grained PAT'],
  [/sk-ant-[A-Za-z0-9\-_]{90,}/, 'Anthropic API key'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'PEM private key block'],
  [/mongodb(\+srv)?:\/\/[^:]+:[^@]+@/i, 'database URL with embedded credentials'],
];
for (const [re, label] of credentials) {
  if (re.test(prompt)) {
    process.stderr.write(`Blocked: prompt may contain a real credential — ${label} (OWASP LLM02). Do not paste secrets; use env vars.\n`);
    process.exit(2);
  }
}
process.exit(0);
```

**`.claude/hooks/post-edit-typecheck.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on TS edits only. Feedback-only (never blocks).
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx) ;; *) exit 0 ;; esac
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
pnpm exec tsc --noEmit --incremental 2>&1 | tail -5
exit 0
```

**`.claude/hooks/post-tool-failure.sh`**:
```bash
#!/usr/bin/env bash
# PostToolUseFailure — surface tool error context for self-correction. Always exit 0.
input=$(cat)
printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const d=JSON.parse(b||'{}');process.stderr.write('Tool failure: '+(d.tool_name||'unknown')+(d.error?(' — '+d.error):'')+'\n')}catch(e){}})" 2>/dev/null
exit 0
```

**`.claude/hooks/stop-checks.sh`**:
```bash
#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(String(JSON.parse(b||'{}').stop_hook_active||false))}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] || [ "$active" = "True" ] && exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm test --run 2>&1); EC=$?
echo "$OUTPUT" | tail -20 >&2
[ $EC -ne 0 ] && exit 2 || exit 0
```

**`.claude/hooks/subagent-stop.sh`**:
```bash
#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted TS changes so it can't hand back broken code.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
if git diff --name-only HEAD 2>/dev/null | grep -qE '\.(ts|tsx)$' || \
   git diff --cached --name-only 2>/dev/null | grep -qE '\.(ts|tsx)$'; then
  OUTPUT=$(pnpm exec tsc --noEmit 2>&1); EC=$?
  if [ $EC -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
exit 0
```

**`.claude/hooks/session-context.sh`**:
```bash
#!/usr/bin/env bash
# SessionStart(startup|resume|compact) — re-inject routing context + universal invariants.
# Plain stdout is added to Claude's context (per Claude Code hooks docs); this is what survives compaction.
echo "=== templateCentral routing context ==="
head -30 AGENTS.md 2>/dev/null

# If a CONSTITUTION.md exists, re-inject it (project binding invariants survive compaction)
if [ -f docs/CONSTITUTION.md ]; then
  echo ""
  echo "=== Project invariants (docs/CONSTITUTION.md) ==="
  cat docs/CONSTITUTION.md
fi

cat <<'EOF'

## Always-on invariants (survive compaction)
1. Secrets are never read or written by the agent — .env* and secrets/** are guarded.
2. Run the quality gate (typecheck + tests) before declaring any task done.
3. Work on a feature branch — never commit directly to main/uat/develop.
4. Protected files — AGENTS.md, CLAUDE.md, Dockerfile, .claude/settings.json, .claude/hooks/*, docs/CONSTITUTION.md — require human approval.
5. Respect the architecture/dependency boundaries documented in AGENTS.md and docs/CONSTITUTION.md.
EOF
```

Make all hook scripts executable:
```bash
chmod +x .claude/hooks/*.sh
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

*Seams from [templateCentral v4.0](https://github.com/cljiahao/templatecentral). None activated.*
```

### 6c. Create project skill files (`.claude/skills/`)

Create `.claude/skills/nest-verify.md`:

```markdown
---
name: nest-verify
description: Run typecheck, lint, and tests for this NestJS project in one pass
allowed-tools: Bash(pnpm *)
---

Run all quality checks in sequence:

```bash
pnpm exec tsc --noEmit --incremental && pnpm check && pnpm test --run
```

Report failures with the exact error output. Fix before proceeding.
```

### 6c. Seed `docs/CONSTITUTION.md`

Create `docs/CONSTITUTION.md` as the binding invariants document for this project.
It takes precedence over `AGENTS.md` and all skill guidance when there is a conflict.
Fill in the `[...]` placeholders with the actual project values.

**`docs/CONSTITUTION.md`**:
```markdown
# CONSTITUTION.md

## 1. Purpose

This document defines the non-negotiable invariants for **[Project Name]**.
It applies to all contributors — human and AI agent alike. When `AGENTS.md`,
templateCentral skills, or any other guidance conflicts with this document,
**this document wins**. No PR may be merged that violates these rules without
an explicit `## Human Approval Override` section in the PR description.

## 2. Architecture Invariants

[Define the load-bearing architectural rules: layering, module boundaries,
factory/composition-root patterns, forbidden cross-imports, etc.]

## 3. Security Invariants

- Secrets NEVER appear in code, git, logs, or build output — use environment
  variables loaded from a secrets manager.
- All API routes authenticate before executing business logic.
- All mutations write to an audit log.

## 4. Testing Invariants

- New services must have integration tests (success, error, at least one edge case).
- New API routes must have route tests covering 401, 200, and at least one error path.
- CI must stay green — no PR may be merged with failing tests.

## 5. Git & PR Invariants

- Branch from `main`. Protected branches (`main`, `uat`, `develop`) — no direct commits.
- Every PR to `uat` and `main` requires the PR template fully filled.

## 6. Agent Governance Rules

### Protected files — human approval required

The following files require explicit human approval noted in the PR under
`## Protected File Changes`. Agents MUST NOT modify them without approval.

- `AGENTS.md` / `CLAUDE.md` — agent instruction files
- `docs/CONSTITUTION.md` — this document
- `.claude/settings.json` — harness wiring
- `.claude/hooks/*` — enforcement hooks
- `Dockerfile`
[Add project-specific protected files here]

### Behavioural rules

- Run the quality gate (`pnpm check` / `python -m pytest`) before declaring any task done.
- Never use `--no-verify` on commits — this bypasses pre-commit hooks.
- Work on a feature branch — never commit directly to `main`, `uat`, or `develop`.
```

### 6d. Create `.claude/harness.json`

Compute SHA-256 hashes and write:

```bash
sha256_agents=$(shasum -a 256 AGENTS.md | cut -d' ' -f1)
# Every enforcement hook script is a high-value tamper target — hash each for drift detection.
# Add a seeded_files entry (origin_hash + path) for EACH line printed below, alongside the core files:
for h in .claude/hooks/*; do shasum -a 256 "$h"; done
sha256_claude=$(shasum -a 256 CLAUDE.md | cut -d' ' -f1)
sha256_settings=$(shasum -a 256 .claude/settings.json | cut -d' ' -f1)
sha256_verify=$(shasum -a 256 .claude/skills/nest-verify.md | cut -d' ' -f1)
```

**`.claude/harness.json`**:
```json
{
  "templatecentral_version": "4.5.0",
  "stack": "nestjs",
  "seeded_at": "<date>",
  "seeded_files": {
    "AGENTS.md": { "origin_hash": "<sha256_agents>", "path": "AGENTS.md" },
    "CLAUDE.md": { "origin_hash": "<sha256_claude>", "path": "CLAUDE.md" },
    ".claude/settings.json": { "origin_hash": "<sha256_settings>", "path": ".claude/settings.json" },
    ".claude/skills/nest-verify.md": { "origin_hash": "<sha256_verify>", "path": ".claude/skills/nest-verify.md" },
    ".claude/hooks/protect-files.sh": { "origin_hash": "<sha256_hook_1>", "path": ".claude/hooks/protect-files.sh" },
    ".claude/hooks/block-no-verify.sh": { "origin_hash": "<sha256_hook_2>", "path": ".claude/hooks/block-no-verify.sh" },
    ".claude/hooks/user-prompt-guard.js": { "origin_hash": "<sha256_hook_3>", "path": ".claude/hooks/user-prompt-guard.js" },
    ".claude/hooks/post-edit-typecheck.sh": { "origin_hash": "<sha256_hook_4>", "path": ".claude/hooks/post-edit-typecheck.sh" },
    ".claude/hooks/post-tool-failure.sh": { "origin_hash": "<sha256_hook_5>", "path": ".claude/hooks/post-tool-failure.sh" },
    ".claude/hooks/stop-checks.sh": { "origin_hash": "<sha256_hook_6>", "path": ".claude/hooks/stop-checks.sh" },
    ".claude/hooks/subagent-stop.sh": { "origin_hash": "<sha256_hook_7>", "path": ".claude/hooks/subagent-stop.sh" },
    ".claude/hooks/session-context.sh": { "origin_hash": "<sha256_hook_8>", "path": ".claude/hooks/session-context.sh" }
  }
}
```

Then create the cross-vendor symlink so the project works with any agent framework that resolves from `.agents/`:

```bash
ln -s .claude .agents
```

### 6e. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `nest-migrate` — DB migration with safety gate (if Drizzle/Kysely is wired up)
- `nest-module` — scaffold a new feature module (controller + service + DTO + test)

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

### 6f. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `templatecentral:build` — verify the scaffold compiles clean (`pnpm build`)
2. `templatecentral:test` — verify all scaffold tests pass (`pnpm test && pnpm test:e2e`)
3. `templatecentral:review` (update operation) — freshen any deps that have newer compatible versions
4. `templatecentral:review` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6g. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

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