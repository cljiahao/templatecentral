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

// Fastify trustProxy: "*" → trust every hop (closed networks only — the leftmost, client-supplied
// X-Forwarded-For entry wins); otherwise comma-separated IPs/CIDRs that must cover EVERY proxy in
// the chain (one-hop ALB → App: ALB CIDR; two-hop ALB → Traefik → App: Traefik's AND the ALB's
// CIDRs). Numeric hop counts were removed in fastify 5.12.1 (security advisory): they
// cannot validate the connecting peer, so they now trust nothing.
function resolveTrustProxy(value: string | undefined): boolean | string | undefined {
  return value === '*' ? true : value;
}

async function bootstrap(): Promise<void> {
  const trustProxy = resolveTrustProxy(appConfig.TRUST_PROXY);
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    // Fastify assigns req.id before pino-http runs, so the UUID generator must live here; a
    // pino-http genReqId is ignored and logs show Fastify's sequential req-1, req-2.
    new FastifyAdapter({
      genReqId: () => crypto.randomUUID(),
      ...(trustProxy ? { trustProxy } : {}),
    }),
    { bufferLogs: true },
  );
  const logger = app.get(Logger);
  app.useLogger(logger);

  await setupSecurity(app);
  logger.log('Security middleware configured');

  setupCors(app);
  logger.log('CORS configured');

  const docsEnabled = setupSwagger(app);

  await app.init();
  logger.log('Application initialized');

  const port = appConfig.PORT;
  await app.listen(port, '0.0.0.0');

  logger.log(`${appConfig.PROJECT_NAME} running on: http://localhost:${port}`);
  if (docsEnabled) {
    logger.log(`Swagger docs available at: http://localhost:${port}/docs`);
  }
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
        level: appConfig.LOG_LEVEL,
        // pino-http's default serializer logs the whole headers object at info level.
        // Without this, every request writes its bearer JWT and session cookies to the log.
        redact: {
          paths: [
            'req.headers.authorization',
            'req.headers.cookie',
            'res.headers["set-cookie"]',
          ],
          remove: true,
        },
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
import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { ZodSerializationException } from 'nestjs-zod';
import { ZodError } from 'zod';
import { HTTP_STATUS_MESSAGES } from '../constants';

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost): void {
    if (exception instanceof ZodSerializationException) {
      const zodError: unknown = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
    }

    const ctx = host.switchToHttp();
    const reply = ctx.getResponse<FastifyReply>();
    const status = exception.getStatus();
    // A 5xx message is server-side detail (e.g. `new InternalServerErrorException(err.message)`)
    // — log it, return the generic text, matching FastAPI's catch-all handler.
    const isServerError = status >= 500;
    if (isServerError) {
      this.logger.error(exception.message, exception.stack);
    }
    reply.status(status).send({
      statusCode: status,
      message: isServerError ? HTTP_STATUS_MESSAGES.INTERNAL_ERROR : exception.message,
    });
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
import { z } from 'zod';

const envSchema = z.object({
  PROJECT_NAME: z.string().min(1).default('My Project'),
  PROJECT_DESCRIPTION: z
    .string()
    .min(1)
    .default('API built with [NestJS](https://nestjs.com/) + Fastify'),
  PROJECT_VERSION: z.string().min(1).default('0.1.0'),
  ENVIRONMENT: z.enum(['dev', 'uat', 'prod']).default('dev'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  CLIENT_URL: z.string().min(1).default('http://localhost:3000'),
  // Reverse proxy trust: comma-separated IPs/CIDRs, or "*" — see main.ts's resolveTrustProxy().
  TRUST_PROXY: z.string().optional(),
  LOG_LEVEL: z
    .enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal', 'silent'])
    .default('info'),
});

// An empty value in `.env` means "not set" — drop it so the schema default applies.
const rawEnv = Object.fromEntries(
  Object.entries(process.env).filter(([, value]) => value !== ''),
);

const parsed = envSchema.safeParse(rawEnv);

// Fail at import time. A `!` assertion is erased at compile time and would surface a
// missing variable as an obscure runtime failure on the first request instead.
if (!parsed.success) {
  throw new Error(
    `Invalid environment configuration:\n${z.prettifyError(parsed.error)}`,
  );
}

const env = parsed.data;

export const appConfig = {
  PROJECT_NAME: env.PROJECT_NAME,
  PROJECT_DESCRIPTION: env.PROJECT_DESCRIPTION,
  PROJECT_VERSION: env.PROJECT_VERSION,
  ENVIRONMENT: env.ENVIRONMENT,
  PORT: env.PORT,
  TRUST_PROXY: env.TRUST_PROXY,
  LOG_LEVEL: env.LOG_LEVEL,
};

export const serviceConfig = {
  CLIENT_URL: env.CLIENT_URL.split(',').map((url) => url.trim()),
};
```

> **Extending this schema**: when a `templatecentral:add` capability introduces a new
> environment variable (`DATABASE_URL`, `JWT_SECRET`, …), prefer adding the field to
> `envSchema` and reading it off `env` over a bare `process.env.X!`. The `!` is erased at
> compile time and never throws, so validation belongs here where boot fails loudly.

### `src/config/index.ts`

```typescript
export * from './env.config';
export * from './setups/swagger.setup';
export * from './setups/security.setup';
```

> Files under `config/setups/` import from `'../env.config'` directly, never from this
> barrel — going through `index.ts` would form a cycle (`index` → `setups/*` → `index`)
> that only resolves by accident of re-export ordering.

### `src/config/setups/security.setup.ts`

```typescript
import fastifyHelmet from '@fastify/helmet';
import type { INestApplication } from '@nestjs/common';
import type { FastifyInstance } from 'fastify';
import { appConfig, serviceConfig } from '../env.config';

export async function setupSecurity(app: INestApplication): Promise<void> {
  const fastify = app.getHttpAdapter().getInstance() as FastifyInstance;

  // Anti-clickjacking (frame-ancestors, X-Frame-Options) is skipped in dev — Swagger UI at
  // /docs is otherwise blocked from rendering in IDE-embedded preview panes (most render via
  // <iframe>, and browsers enforce these headers even for localhost). Full protection still
  // applies in every deployed environment (prod, uat).
  const isDev = appConfig.ENVIRONMENT === 'dev';

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
        // null omits the directive from the emitted header — an empty array does not:
        // Helmet's own default for an unset frame-ancestors is 'self', which would still
        // block a cross-origin IDE-preview iframe.
        'frame-ancestors': isDev ? null : ["'none'"],
      },
    },
    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    // frameguard sets X-Frame-Options (xFrameOptions is an equivalent alias). action must be
    // lowercase — 'deny' | 'sameorigin', not 'DENY' — per @fastify/helmet's actual type.
    frameguard: isDev ? false : { action: 'deny' },
  });

  fastify.addHook('onSend', async (_request, reply, payload) => {
    void reply.header(
      'Cache-Control',
      'no-cache, no-store, must-revalidate, private',
    );
    void reply.header(
      'Permissions-Policy',
      'camera=(), microphone=(), geolocation=()',
    );
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
import { appConfig } from '../env.config';

/** Mounts Swagger UI at /docs outside prod/uat. Returns whether it was mounted. */
export function setupSwagger(app: INestApplication): boolean {
  if (appConfig.ENVIRONMENT === 'prod' || appConfig.ENVIRONMENT === 'uat') {
    return false;
  }

  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, cleanupOpenApiDoc(document));
  return true;
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
  update(@Param('id') id: string, @Body() dto: UpdateExampleDto): ExampleItem {
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
    const updated = {
      ...existing,
      ...data,
      updatedAt: new Date().toISOString(),
    };
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

    // Mirror main.ts's adapter options so request IDs (and anything keyed off them, e.g. log
    // correlation) behave the same under test as in the running app.
    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter({ genReqId: () => crypto.randomUUID() }),
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET / should return "Hello World!"', () => {
    return app.inject({ method: 'GET', url: '/' }).then((result) => {
      expect(result.statusCode).toBe(200);
      expect(result.payload).toBe('Hello World!');
    });
  });

  it('GET /health should return OK', () => {
    return app.inject({ method: 'GET', url: '/health' }).then((result) => {
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

- All **Part B** config files verbatim
- All **Part C** source files verbatim
- Create two empty files: `src/common/types/.gitkeep` and `src/database/.gitkeep`
- Write `package.json` verbatim from `config-files.md`, substituting the project `"name"` (kebab-case)
- Write `README.md` (brief project intro + the commands from `package.json` scripts)

Make `docker-entrypoint.sh` executable:

```bash
chmod +x docker-entrypoint.sh
```

### 2. Update Project Settings

In `package.json`, set `"name"` to the project name (kebab-case).

In `src/config/env.config.ts`, update the schema defaults:

```typescript
PROJECT_NAME: z.string().min(1).default('<Project Name>'),
PROJECT_DESCRIPTION: z
  .string()
  .min(1)
  .default('API built with [NestJS](https://nestjs.com/) + Fastify'),
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

`pnpm install` triggers the `prepare` script, installing the lefthook git hooks.

### 5. Verification Gate

**Do NOT generate AGENTS.md until all four pass:**

> Run `pnpm format` once first if this is a fresh scaffold — Prettier drift on newly generated files will cause `pnpm check` to fail until formatted.

```bash
pnpm build        # zero compile errors
pnpm check        # format + lint + typecheck
pnpm test         # all unit tests pass
pnpm test:e2e     # e2e tests pass
```

If any command fails, diagnose and fix before proceeding.

### 6. Write project AGENTS.md

Create `AGENTS.md` at the project root with this exact content (fill in `[Project Name]`):

```markdown
<!-- templateCentral: nestjs@6.0.0 -->
# AGENTS.md — [Project Name]

## Stack
NestJS 12 · Fastify · Zod + nestjs-zod · Swagger · TypeScript strict · Vitest · pnpm · Node ≥24.15

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
| `templatecentral:add (endpoint)` | new route + DTO + service method (NestJS modules — alias: module) |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod (`createZodDto`) at every boundary
- kebab-case filenames, PascalCase classes, camelCase methods; named exports only
- No secrets in code — use env vars; document in `.env.example`
- Comments explain *why*, not *what* — no commented-out code, no change-narration (`// was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

(AGENTS.md tail — AI Harness / Skills Security / Git Workflow / Skill capture — is appended by harness-kit-finalize.md Step G; not embedded here to avoid duplication.)

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
```

### 6b. Seed the agent harness (shared kit)

Load the shared harness kit using the **nestjs** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit.md"
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Execute kit Steps **A through D** now (settings.json, hook scripts, FUTURE.md, CONSTITUTION.md). Then continue with step 6c below to create the verify skill. After step 6c, execute kit Steps **E through H** (harness.json requires the verify skill to exist first — Step E's prerequisites note explains this).

### 6c. Create project skill files (`.claude/skills/`)

Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Run `mkdir -p .claude/skills/nest-verify`, then create `.claude/skills/nest-verify/SKILL.md`:

```markdown
---
name: nest-verify
description: Run typecheck, lint, and tests for this NestJS project in one pass
allowed-tools: Bash(pnpm *)
---

Run all quality checks in sequence (`pnpm check` already runs `tsc --noEmit` after format + lint):

```bash
pnpm check && pnpm test
```

Report failures with the exact error output. Fix before proceeding.
```

### 6d. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `nest-migrate` — DB migration with safety gate (if Drizzle/Kysely is wired up)
- `nest-module` — scaffold a new feature module (controller + service + DTO + test)

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

Now execute kit Steps **E through H** using the **nestjs** row: harness.json (Step E — includes the `nest-verify` skill hash), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail append (Step G — always appends the shared tail fragment with the nestjs `PostToolUse` line), and plugin install (Step H).

---

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

After creating it, add a `CLAUDE.md` entry to `seeded_files` in `.claude/harness.json` with its SHA-256 hash (see harness-kit-finalize.md Step E).

### 7b. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append this to the project's `AGENTS.md`:

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`. Skip for single-file edits or quick fixes.
```

If no, skip.

### 8. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

NestJS-specific steps (the utility covers these):
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