---
name: shared-add-test
description: Use when adding tests to any templateCentral project — FastAPI (pytest), NestJS (Vitest), Next.js (Vitest API routes), or Vite + React (Vitest + Testing Library).
---

# Add Tests

## Stack Detection

Before starting, identify the project stack:

| Signal file | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts` / `next.config.js` / `next.config.mjs` | Next.js |
| `vite.config.ts` / `vite.config.js` (no `next.config.*`) | Vite + React |

Then jump directly to the matching stack section below.

---

## FastAPI

Guide for writing tests in a FastAPI project scaffolded from templateCentral.

**Policy**: Same-change pytest for new/changed API code (root `AGENTS.md`, `code-standards/`).

### Prerequisites

Requires a project scaffolded with `templatecentral:fastapi-scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/api/routers/` contains at least one `.py` file.

If not found → ⛔ STOP. Tell the user: "No routers found. Run
`templatecentral:fastapi-add-endpoint` first, then return here."

If found → proceed to Step 1.

### Test Structure

Tests mirror `src/`:

```
test/
├── conftest.py           # Shared fixtures (TestClient) — created by scaffold
├── factories/            # Factory functions for test data
│   └── models.py
└── test_api/             # API endpoint tests
    └── test_<endpoint>.py
```

Add directories as needed: `test_services/` (business logic), `test_models/` (domain models), `test_utils/` (utilities).

### Fixtures

The scaffold generates `test/conftest.py` with a `client` fixture:

```python
"""Root conftest — shared fixtures available to all tests."""

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
    """FastAPI test client."""
    with TestClient(app) as client:
        yield client
```

Extend it for database tests by overriding dependencies:

```python
# test/conftest.py — add after the existing client fixture

@pytest.fixture()
def db_client(monkeypatch) -> Generator[TestClient, None, None]:
    """TestClient with a clean in-memory database for each test."""
    from database.session import get_db
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from database.base import Base

    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    TestSession = sessionmaker(bind=engine)
    session = TestSession()
    app.dependency_overrides[get_db] = lambda: session

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()
    session.close()
```

### Test File Layout

1. Module docstring
2. Imports (stdlib → third-party → local)
3. File-local fixtures
4. Test functions

### Naming

- Functions: `test_<subject>_<scenario>`
- Always provide a one-line docstring describing expected behavior.

```python
@pytest.mark.unit
def test_example_rejects_invalid_payload(client: TestClient) -> None:
    """POST /example with missing required field returns 422."""
    response = client.post("/example", json={})
    assert response.status_code == 422
    errors = response.json()["detail"]
    assert any("name" in str(e) for e in errors)
```

### Factories

Create factory functions in `test/factories/` with sensible defaults:

```python
def create_example_request(
    name: str = "World",
    repeat_count: int = 1,
) -> dict:
    """Create an example request payload with camelCase keys (matching API contract)."""
    return {"name": name, "repeatCount": repeat_count}
```

> **Why camelCase keys**: `BaseSchema` uses `alias_generator=to_camel`, so the API expects camelCase JSON. Factory return values must use camelCase keys (e.g., `"repeatCount"`) even though Python params use snake_case.

Rules:
- Sensible defaults; composable; use real constants where appropriate.
- Create new factories when objects have many fields or are reused with variations.
- Always use **camelCase keys** in factory dicts — they represent the API's JSON contract.

### Assertions

- One main concept per test.
- Assert before and after when testing mutations.
- Use `pytest.raises(..., match="...")` for exceptions — always include `match`.

### Parametrize

Use for tests that differ only by input/output:

```python
@pytest.mark.parametrize(
    "age, expected",
    [(54, False), (55, True), (65, True)],
    ids=["below-55", "at-55", "at-65"],
)
def test_is_eligible(age: int, expected: bool) -> None:
    """Eligibility check based on age."""
    assert is_eligible(age) == expected
```

### Mocking

- **Prefer real objects** via factories.
- Use `monkeypatch` over `unittest.mock.patch`.
- Mock only for uncontrollable side effects (network, filesystem, time).

### Running Tests

```bash
pytest test/                    # All tests
pytest test/ -m unit            # Unit tests only
pytest test/ -m end_to_end      # E2E tests only
pytest test/test_api/           # API tests only
```

### Independence

- No shared mutable state; each test constructs its own data.
- Tests should pass in any order or in isolation.

### Rules

- NEVER share mutable state between tests — each test constructs its own data
- NEVER use `unittest.mock.patch` when `monkeypatch` is available — prefer pytest idioms
- NEVER mock what you own — use real objects via factories; mock only external side effects
- NEVER depend on test execution order — tests must pass in any order or in isolation

---

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

If found → proceed to Step 1.

### Unit Tests

Unit tests go in `test/modules/<name>.controller.spec.ts` or `test/modules/<name>.service.spec.ts`.

#### Controller Test

```typescript
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
import { vi } from 'vitest';
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

---

## Next.js

Guide for writing tests for API route handlers in a Next.js project scaffolded from templateCentral. Tests cover server-side API logic only — not frontend components.

**Policy**: Same-change Vitest tests under `test/api/` for `src/app/api/**` (see root `AGENTS.md`, `code-standards/`). Frontend out of scope.

### Prerequisites

Requires a project scaffolded with `templatecentral:nextjs-scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/app/api/` contains at least one `.ts` route handler file.

If not found → ⛔ STOP. Tell the user: "No API routes found. Run
`templatecentral:nextjs-add-api-route` first, then return here."

If found → proceed to Step 1.

### Test Structure

Tests live in `test/api/` mirroring `src/app/api/`:

```
test/
└── api/
    ├── health.test.ts              # GET /api + GET /api/health (probe paths)
    ├── <resource>/
    │   ├── route.test.ts           # GET, POST /api/<resource>
    │   └── [id]/
    │       └── route.test.ts       # GET, PUT, DELETE /api/<resource>/:id
```

### Testing Approach

The Next.js template uses `globals: false` in Vitest — always import `describe`, `it`, `expect`, `vi`, `beforeEach`, `afterEach` explicitly from `'vitest'`.

Import route handler functions directly and call them with `Request` objects — no HTTP server needed:

```ts
import { GET } from '@/app/api/projects/route';
import { describe, expect, it } from 'vitest';

describe('GET /api/projects', () => {
  it('should return all projects', async () => {
    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(Array.isArray(data)).toBe(true);
  });
});
```

> **Why direct imports**: Next.js API route handlers are plain async functions that accept a `Request` and return a `Response`. Calling them directly is fast, requires no server setup, and gives full access to the response object.

> **Note**: `DataService` in the examples below is a **placeholder** — the template's `src/integrations/factories.ts` starts empty. Replace it with whatever data access layer you've added via the `add-database` or `add-integration` skill. The mock pattern shown (module-level `vi.mock`, `vi.mocked` for type-safety) applies to any service you create.

#### 1. Create the Test File

Place tests in `test/api/` matching the route path:

| Route | Test file |
|-------|-----------|
| `src/app/api/route.ts` and `src/app/api/health/route.ts` | `test/api/health.test.ts` (template tests both probe paths) |
| `src/app/api/projects/route.ts` | `test/api/projects/route.test.ts` |
| `src/app/api/projects/[id]/route.ts` | `test/api/projects/[id]/route.test.ts` |

#### 2. Test GET Endpoints

```ts
import { GET } from '@/app/api/projects/route';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Mock your data access layer — replace path and export with your actual service
vi.mock('@/features/projects/api/project-service', () => ({
  ProjectService: { getAll: vi.fn() },
}));

import { ProjectService } from '@/features/projects/api/project-service';

describe('GET /api/projects', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should return projects with status 200', async () => {
    const mockProjects = [{ id: '1', name: 'Alpha' }];
    vi.mocked(ProjectService.getAll).mockResolvedValue(mockProjects);

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toEqual(mockProjects);
  });

  it('should return 500 when service throws', async () => {
    vi.mocked(ProjectService.getAll).mockRejectedValue(new Error('DB down'));

    const response = await GET();

    expect(response.status).toBe(500);
  });
});
```

#### 3. Test POST Endpoints with Validation

```ts
import { POST } from '@/app/api/projects/route';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/features/projects/api/project-service', () => ({
  ProjectService: { create: vi.fn() },
}));

import { ProjectService } from '@/features/projects/api/project-service';

function jsonRequest(url: string, body: unknown, method = 'POST'): Request {
  return new Request(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /api/projects', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should create a project and return 201', async () => {
    const input = { name: 'New Project' };
    const created = { id: '1', ...input };
    vi.mocked(ProjectService.create).mockResolvedValue(created);

    const response = await POST(jsonRequest('http://localhost/api/projects', input));
    const data = await response.json();

    expect(response.status).toBe(201);
    expect(data).toEqual(created);
  });

  it('should return 400 for invalid body', async () => {
    const response = await POST(jsonRequest('http://localhost/api/projects', { name: '' }));

    expect(response.status).toBe(400);
    const data = await response.json();
    expect(data.error).toBe('Validation failed');
  });
});
```

#### 4. Test Dynamic Segment Routes

```ts
import { GET } from '@/app/api/projects/[id]/route';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/features/projects/api/project-service', () => ({
  ProjectService: { getById: vi.fn() },
}));

import { ProjectService } from '@/features/projects/api/project-service';

function makeParams<T extends Record<string, string>>(values: T) {
  return { params: Promise.resolve(values) };
}

describe('GET /api/projects/[id]', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should return a project by ID', async () => {
    const project = { id: '1', name: 'Alpha' };
    vi.mocked(ProjectService.getById).mockResolvedValue(project);

    const request = new Request('http://localhost/api/projects/1');
    const response = await GET(request, makeParams({ id: '1' }));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toEqual(project);
  });

  it('should return 404 when project not found', async () => {
    vi.mocked(ProjectService.getById).mockResolvedValue(null);

    const request = new Request('http://localhost/api/projects/999');
    const response = await GET(request, makeParams({ id: '999' }));

    expect(response.status).toBe(404);
  });
});
```

#### 5. Run Tests

```bash
pnpm test                  # Run all tests once
pnpm test:watch            # Watch mode (re-runs on change)
pnpm test:coverage         # Run with coverage report
```

#### 6. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

### Naming

- Files: `<name>.test.ts` under `test/api/`, mirroring the route path
- Describe blocks: `describe('METHOD /api/<path>', ...)` — matches the HTTP method and route
- Test names: `it('should <expected behavior>', ...)` — describes the outcome, not the implementation

### Helper Patterns

#### Request Factory

Create a helper for building `Request` objects with JSON bodies:

```ts
function jsonRequest(url: string, body: unknown, method = 'POST'): Request {
  return new Request(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}
```

#### Params Factory

For dynamic segment routes, create a params factory:

```ts
function makeParams<T extends Record<string, string>>(values: T) {
  return { params: Promise.resolve(values) };
}
```

### Rules

- Test API route handlers only — NEVER write frontend component tests in this pattern
- One concept per test — test a single behavior in each `it()` block
- Mock at boundaries — mock your data access services (feature service modules, integration clients), not internal utilities
- Use `vi.mock()` at module level and `vi.mocked()` for type-safe mock access
- Always call `vi.restoreAllMocks()` in `afterEach` — prevent mock leakage between tests
- Use descriptive test names — `it('should return 404 when project not found')`
- NEVER test implementation details — test the HTTP status and response body, not how the handler calls services internally
- NEVER share mutable state between tests — each test sets up its own mocks
- NEVER skip error path tests — always test what happens when services throw
- NEVER hardcode URLs in assertions — test the response shape and status code

---

## Vite + React

Guide for writing tests in a Vite + React project scaffolded from templateCentral.

### Prerequisites

Requires a project scaffolded with `templatecentral:vite-react-scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/features/` or `src/components/` contains at least
one `.tsx` file.

If not found → ⛔ STOP. Tell the user: "No components or features found. Add some
using `templatecentral:vite-react-add-feature` or `templatecentral:vite-react-add-component`
first, then return here."

If found → proceed to Step 1.

### Test Structure

Tests are **co-located** next to the source file they test:

```
src/features/project/
├── api/
│   ├── project-service.ts
│   └── project-service.test.ts        # Service test
├── components/
│   ├── project-card.tsx
│   └── project-card.test.tsx          # Component test
├── hooks/
│   ├── use-projects.query.ts
│   └── use-projects.query.test.tsx    # Hook test
```

| Source file | Test file |
|-------------|-----------|
| `project-service.ts` | `project-service.test.ts` |
| `project-card.tsx` | `project-card.test.tsx` |
| `use-projects.query.ts` | `use-projects.query.test.tsx` |

Use `.test.ts` for pure logic, `.test.tsx` for anything that renders React.

### Test Setup

The template has a setup file at `src/test/setup.ts` that:
- Imports `@testing-library/jest-dom/vitest` (adds DOM matchers like `toBeInTheDocument`)
- Runs `cleanup()` after each test (unmounts rendered components)

Vitest is configured with `globals: true` — `describe`, `it`, `expect` are available without imports, but explicit imports are also fine.

### Component Tests

Use Testing Library to render and assert on DOM output:

```tsx
// src/features/project/components/project-card.test.tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ProjectCard } from './project-card';

describe('ProjectCard', () => {
  const mockProject = {
    id: '1',
    name: 'Alpha',
    status: 'active' as const,
  };

  it('renders the project name', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('Alpha')).toBeInTheDocument();
  });

  it('renders the project status', () => {
    render(<ProjectCard project={mockProject} />);
    expect(screen.getByText('active')).toBeInTheDocument();
  });
});
```

### Component Tests with User Interaction

Use `@testing-library/user-event` for clicks, typing, and other interactions:

```tsx
// src/features/project/components/project-form.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ProjectForm } from './project-form';

describe('ProjectForm', () => {
  it('calls onSubmit with form data', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();

    render(<ProjectForm onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText('Name'), 'New Project');
    await user.click(screen.getByRole('button', { name: /submit/i }));

    expect(onSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'New Project' }),
    );
  });
});
```

### Service Tests

Test services by calling their methods directly. The first example below is for **synchronous/in-memory services** (like the template's `ExampleService`). For **async services** that call `fetch` or an external API, see the second example with `mockFetch`:

```ts
// src/features/project/api/project-service.test.ts
import { describe, expect, it } from 'vitest';
import { ProjectService } from './project-service';

describe('ProjectService', () => {
  it('getAll returns all items', () => {
    const result = ProjectService.getAll();

    expect(Array.isArray(result)).toBe(true);
    expect(result.length).toBeGreaterThan(0);
    expect(result[0]).toHaveProperty('id');
  });

  it('getById returns matching item', () => {
    const result = ProjectService.getById('1');

    expect(result).toBeDefined();
    expect(result?.id).toBe('1');
  });

  it('getById returns undefined for unknown id', () => {
    expect(ProjectService.getById('nonexistent')).toBeUndefined();
  });
});
```

For services that call `fetch` or an external API, stub `fetch` at the boundary:

```ts
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { ProjectService } from './project-service';

const mockFetch = vi.fn();

describe('ProjectService (API-backed)', () => {
  beforeEach(() => { vi.stubGlobal('fetch', mockFetch); });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it('fetches projects from API', async () => {
    const projects = [{ id: '1', name: 'Alpha' }];
    mockFetch.mockResolvedValue(new Response(JSON.stringify(projects)));

    const result = await ProjectService.getAll();
    expect(result).toEqual(projects);
  });
});
```

### React Query Hook Tests

Wrap hooks in a `QueryClientProvider` for testing:

```tsx
// src/features/project/hooks/use-projects.query.test.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi, afterEach } from 'vitest';
import type { ReactNode } from 'react';
import { useProjects } from './use-projects.query';
import { ProjectService } from '../api';

vi.mock('../api', () => ({
  ProjectService: {
    getAll: vi.fn(),
  },
}));

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };
}

describe('useProjects', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns projects on success', async () => {
    const projects = [{ id: '1', name: 'Alpha', status: 'active' }];
    vi.mocked(ProjectService.getAll).mockResolvedValue(projects);

    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toEqual(projects);
  });

  it('returns error on failure', async () => {
    vi.mocked(ProjectService.getAll).mockRejectedValue(new Error('Failed'));

    const { result } = renderHook(() => useProjects(), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isError).toBe(true));
  });
});
```

### Integration Service Tests (External APIs)

If you've added external API integrations via the `add-integration` skill, test them by mocking the client:

```ts
// src/features/<name>/api/<name>-service.test.ts
import { describe, expect, it, vi, afterEach } from 'vitest';
import { NameService } from './<name>-service';

vi.mock('./<name>-client', () => ({
  nameClient: { getItems: vi.fn(), getItem: vi.fn() },
}));

import { nameClient } from './<name>-client';

describe('NameService', () => {
  afterEach(() => { vi.restoreAllMocks(); });

  it('fetches and returns items', async () => {
    const mockData = [{ id: '1', title: 'Item' }];
    vi.mocked(nameClient.getItems).mockResolvedValue(mockData);

    const result = await NameService.getItems();
    expect(result).toEqual(mockData);
  });
});
```

### Running Tests

```bash
pnpm test                  # Run all tests once
pnpm test:watch            # Watch mode (re-runs on change)
pnpm test:coverage         # Run with coverage report
```

### Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds and all tests pass.

### Helper Patterns

#### JSON Response Factory

```ts
function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
```

#### React Query Wrapper

```tsx
function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    );
  };
}
```

### Rules

- One concept per test — test a single behavior in each `it()` block
- Mock at boundaries — mock `fetch`, service modules, or integration clients; NEVER mock internal utilities or React internals
- Use Testing Library queries by role/text — `getByRole`, `getByText`, `getByLabelText`; NEVER use `querySelector` or test IDs unless no semantic alternative exists
- Use `userEvent` over `fireEvent` — `userEvent.setup()` simulates real user behavior
- Always call `vi.restoreAllMocks()` and `vi.unstubAllGlobals()` in `afterEach` — prevent mock leakage between tests
- Create a fresh `QueryClient` per test — NEVER share a client across tests (stale cache causes flakes)
- NEVER test implementation details — test what the user sees (components) or what the caller gets (services)
- NEVER test third-party library behavior — test YOUR code's usage of it
- NEVER share mutable state between tests — each test sets up its own data
