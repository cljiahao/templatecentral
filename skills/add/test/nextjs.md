<!-- ref: add/test/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = Next.js. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js

Guide for writing tests for API route handlers in a Next.js project scaffolded from templateCentral. Tests cover server-side API logic only — not frontend components.

**Policy**: Same-change Vitest tests under `test/api/` for `src/app/api/**` (see root `AGENTS.md`, `code-standards/`). Frontend out of scope.

### Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

### Steps

#### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/app/api/` contains at least one `.ts` route handler file.

If not found → ⛔ STOP. Tell the user: "No API routes found. Run
`templatecentral:add` (api-route) first, then return here."

If found → proceed to the sections below.

### Test Structure

Tests live in `test/api/` mirroring `src/app/api/`:

```
test/
└── api/
    ├── health.test.ts              # GET /api/health (Docker probe path)
    ├── <resource>/
    │   ├── route.test.ts           # GET, POST /api/<resource>
    │   └── [id]/
    │       └── route.test.ts       # GET, PUT, DELETE /api/<resource>/:id
```

### Testing Approach

The Next.js template uses `globals: false` in Vitest — always import `describe`, `it`, `expect`, `vi`, `beforeEach`, `afterEach` explicitly from `'vitest'`.

Import route handler functions directly and call them with `NextRequest` objects — no HTTP server needed.

> **`proxy.ts` is not exercised.** Calling a handler directly bypasses the proxy, so session checks enforced there are untested here. Any auth check inside the handler itself (e.g. `auth.api.getSession`) must get its own 401 test.

> **Always pass a `NextRequest`, never a plain `Request`.** `withLogging`-wrapped handlers are typed against `NextRequest` (it adds `nextUrl` and `cookies`), so a plain `Request` — or a zero-argument `GET()` call — fails `pnpm check` with a type error even though it would run fine at runtime.

> **Note**: `ProjectService` in the examples below is a **placeholder** — the template's `src/integrations/factories.ts` starts empty. Replace it with whatever data access layer you've added via the `templatecentral:add (database)` or `templatecentral:add (integration)` skill. The mock pattern shown (module-level `vi.mock`, `vi.mocked` for type-safety) applies to any service you create.

#### 1. Create the Test File

Place tests in `test/api/` matching the route path:

| Route | Test file |
|-------|-----------|
| `src/app/api/health/route.ts` | `test/api/health.test.ts` (template tests the Docker probe path) |
| `src/app/api/projects/route.ts` | `test/api/projects/route.test.ts` |
| `src/app/api/projects/[id]/route.ts` | `test/api/projects/[id]/route.test.ts` |

#### 2. Test GET Endpoints

```ts
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { GET } from '@/app/api/projects/route';

// Mock your data access layer — replace path and export with your actual service.
// Route handlers consume integration-layer services (never feature api/ services).
vi.mock('@/integrations/services/project-service', () => ({
  ProjectService: { getAll: vi.fn() },
}));

import { ProjectService } from '@/integrations/services/project-service';

describe('GET /api/projects', () => {
  afterEach(() => {
    vi.resetAllMocks();
  });

  it('should return projects with status 200', async () => {
    const mockProjects = [{ id: '1', name: 'Alpha' }];
    vi.mocked(ProjectService.getAll).mockResolvedValue(mockProjects);

    const response = await GET(new NextRequest('http://localhost/api/projects'));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toEqual({ data: mockProjects });
  });

  it('should return 500 when service throws', async () => {
    vi.mocked(ProjectService.getAll).mockRejectedValue(new Error('DB down'));

    const response = await GET(new NextRequest('http://localhost/api/projects'));

    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain('DB down');
  });
});
```

#### 3. Test POST Endpoints with Validation

```ts
import { afterEach, describe, expect, it, vi } from 'vitest';

import { POST } from '@/app/api/projects/route';

vi.mock('@/integrations/services/project-service', () => ({
  ProjectService: { create: vi.fn() },
}));

import { ProjectService } from '@/integrations/services/project-service';
// jsonRequest: see Helper Patterns → Request Factory below

describe('POST /api/projects', () => {
  afterEach(() => {
    vi.resetAllMocks();
  });

  it('should create a project and return 201', async () => {
    const input = { name: 'New Project' };
    const created = { id: '1', ...input };
    vi.mocked(ProjectService.create).mockResolvedValue(created);

    const response = await POST(jsonRequest('http://localhost/api/projects', input));
    const data = await response.json();

    expect(response.status).toBe(201);
    expect(data).toEqual({ data: created });
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
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { GET } from '@/app/api/projects/[id]/route';

vi.mock('@/integrations/services/project-service', () => ({
  ProjectService: { getById: vi.fn() },
}));

import { ProjectService } from '@/integrations/services/project-service';
// makeParams: see Helper Patterns → Params Factory below

describe('GET /api/projects/[id]', () => {
  afterEach(() => {
    vi.resetAllMocks();
  });

  it('should return a project by ID', async () => {
    const project = { id: '1', name: 'Alpha' };
    vi.mocked(ProjectService.getById).mockResolvedValue(project);

    const request = new NextRequest('http://localhost/api/projects/1');
    const response = await GET(request, makeParams({ id: '1' }));
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toEqual({ data: project });
  });

  it('should return 404 when project not found', async () => {
    vi.mocked(ProjectService.getById).mockResolvedValue(null);

    const request = new NextRequest('http://localhost/api/projects/999');
    const response = await GET(request, makeParams({ id: '999' }));

    expect(response.status).toBe(404);
  });
});
```

#### 4b. Routes That Check the Session

Importing a handler that imports `@/lib/auth` throws without `BETTER_AUTH_SECRET` and would need a live session store — mock the module and drive `getSession` per test:

```ts
vi.mock('@/lib/auth', () => ({ auth: { api: { getSession: vi.fn() } } }));

import { auth } from '@/lib/auth';

it('should return 401 without a session', async () => {
  vi.mocked(auth.api.getSession).mockResolvedValue(null);
  const response = await GET(new NextRequest('http://localhost/api/projects/1'), makeParams({ id: '1' }));
  expect(response.status).toBe(401);
});
```

#### 5. Run Tests

```bash
pnpm test                  # Run all tests once (vitest run — not watch mode)
pnpm exec vitest           # Watch mode (re-runs on change)
pnpm test:ci               # Run once with coverage report
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

Create a helper for building `NextRequest` objects with JSON bodies:

```ts
import { NextRequest } from 'next/server';

function jsonRequest(url: string, body: unknown, method = 'POST'): NextRequest {
  return new NextRequest(url, {
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
- Mock at boundaries — mock integration-layer services/clients (`src/integrations/`), not internal utilities
- Use `vi.mock()` at module level and `vi.mocked()` for type-safe mock access
- Always call `vi.resetAllMocks()` in `afterEach` — prevent mock leakage between tests. `vi.restoreAllMocks()` is not enough: it only restores `vi.spyOn` spies, so a `mockResolvedValue` queued on a `vi.fn()` from a `vi.mock` factory (the pattern used above) survives into the next test. Setting `mockReset: true` in `vitest.config.ts` achieves the same thing globally.
- Use descriptive test names — `it('should return 404 when project not found')`
- NEVER test implementation details — test the HTTP status and response body, not how the handler calls services internally
- NEVER share mutable state between tests — each test sets up its own mocks
- NEVER skip error path tests — always test what happens when services throw, and assert the 500 body does not echo the internal error message
- NEVER hardcode URLs in assertions — test the response shape and status code

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards