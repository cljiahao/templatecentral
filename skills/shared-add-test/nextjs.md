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

If found → proceed to the sections below.

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
