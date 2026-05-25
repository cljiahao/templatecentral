<!-- ref: add/test/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = NestJS. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS

Guide for adding unit tests and e2e tests to a NestJS project scaffolded from templateCentral.

**Policy**: Same-change Vitest for new/changed controllers, services, repositories (root `AGENTS.md`, `code-standards/`).

### Prerequisites

Requires a project scaffolded with `templatecentral:nestjs-scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/modules/` exists and contains at least one subdirectory.

If not found → ⛔ STOP. Tell the user: "No modules found. Run
`templatecentral:nestjs-add-module` first, then return here."

If found → proceed to the sections below.

### Unit Tests

Unit tests go in `test/modules/<name>.controller.spec.ts` or `test/modules/<name>.service.spec.ts`.

#### Controller Test

```typescript
import { beforeEach, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { MyController } from '../../src/modules/my/my.controller';
import { MyService } from '../../src/modules/my/my.service';
import { MyRepository } from '../../src/modules/my/my.repository';

describe('MyController', () => {
  let controller: MyController;
  let service: MyService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [MyController],
      providers: [MyService, MyRepository],
    }).compile();

    controller = module.get<MyController>(MyController);
    service = module.get<MyService>(MyService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('should return all items', () => {
    const result = controller.findAll();
    expect(Array.isArray(result)).toBe(true);
  });
});
```

#### Service Test with Mocked Repository

```typescript
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { MyService } from '../../src/modules/my/my.service';
import { MyRepository } from '../../src/modules/my/my.repository';
import { NotFoundException } from '@nestjs/common';

describe('MyService', () => {
  let service: MyService;
  let repository: MyRepository;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MyService,
        {
          provide: MyRepository,
          useValue: {
            findAll: vi.fn().mockReturnValue([]),
            findById: vi.fn(),
            create: vi.fn(),
            update: vi.fn(),
            remove: vi.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<MyService>(MyService);
    repository = module.get<MyRepository>(MyRepository);
  });

  it('should return all items', () => {
    expect(service.findAll()).toEqual([]);
    expect(repository.findAll).toHaveBeenCalled();
  });

  it('should throw NotFoundException for missing item', () => {
    vi.spyOn(repository, 'findById').mockImplementation(() => {
      throw new NotFoundException();
    });
    expect(() => service.findOne('nonexistent')).toThrow(NotFoundException);
  });
});
```

### E2E Tests

E2E tests go in `test/app.e2e-spec.ts` or `test/<name>.e2e-spec.ts`.

> **Placeholder names**: All examples use `My*`, `/my-items`, etc. Replace these with your actual module name and route path (e.g., for a `task` module with `@Controller('tasks')`: `TaskController`, `/tasks`).

```typescript
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Test, TestingModule } from '@nestjs/testing';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';

describe('My Feature (e2e)', () => {
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

  it('POST /my-items should create an item', async () => {
    const result = await app.inject({
      method: 'POST',
      url: '/my-items',
      payload: { name: 'Test Item' },
    });

    expect(result.statusCode).toBe(201);
    const body = JSON.parse(result.payload);
    expect(body.name).toBe('Test Item');
    expect(body.id).toBeDefined();
  });

  it('GET /my-items should return items', async () => {
    const result = await app.inject({
      method: 'GET',
      url: '/my-items',
    });

    expect(result.statusCode).toBe(200);
    const body = JSON.parse(result.payload);
    expect(Array.isArray(body)).toBe(true);
  });
});
```

### Test Organization

```
test/
├── vitest.config.e2e.ts       # E2E Vitest config
├── app.e2e-spec.ts            # Root app e2e tests
├── <feature>.e2e-spec.ts      # Feature-specific e2e tests
└── modules/
    ├── <name>.controller.spec.ts  # Controller unit tests
    └── <name>.service.spec.ts     # Service unit tests (with mocks)
```

### Running Tests

```bash
# Unit tests
pnpm test

# Unit tests (watch mode)
pnpm test:watch

# Coverage report
pnpm test:cov

# E2E tests
pnpm test:e2e
```

### Rules

- One concept per test — test a single behavior in each `it()` block
- Descriptive names — `it('should throw NotFoundException for missing item')`
- Mock at boundaries — mock repositories in service tests, not internals
- Use NestJS testing module — `Test.createTestingModule()` for proper DI
- E2E tests use Fastify — `app.inject()` for HTTP assertions; NEVER use `supertest` with Fastify
- NEVER test implementation details — test behavior and outcomes
- NEVER share mutable state between tests — each `beforeEach` creates a fresh module
- NEVER mock the service in controller tests unless testing error handling paths
- NEVER skip `afterAll(() => app.close())` in e2e tests — Fastify connections must be closed
- NEVER write tests that depend on execution order — each test must be independent

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards