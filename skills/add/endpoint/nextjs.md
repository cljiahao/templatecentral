<!-- ref: add/endpoint/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as Next.js. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add an API Route

Create a new API route handler in a Next.js project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Inputs

- **Resource name** — The API resource (e.g., `projects`, `users`)
- **HTTP methods** — Which methods to support (GET, POST, PUT, DELETE, PATCH)

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create the Route File

API routes live in `src/app/api/`:

```
src/app/api/
├── health/
│   └── route.ts                    # GET /api/health (health check)
├── <resource>/
│   ├── route.ts                    # GET, POST /api/<resource>
│   └── [id]/
│       └── route.ts               # GET, PUT, DELETE /api/<resource>/:id
```

### 2. Implement the Route Handler

Keep route handlers thin — delegate to server-side data access:

> **Important**: Route handlers access data via `integrations/` (clients, services, factories) — NOT the feature's `api/` services, which `fetch('/api/...')` and would make the route call itself. Data access below is a **placeholder** — wire it via `templatecentral:add (database)` or `templatecentral:add (integration)`.

> **Wrap every handler in `withLogging`.** Next.js has no global request-logging layer, so each handler must be wrapped — and `pnpm check` fails the build on any unwrapped route (`scripts/check-route-logging.mjs`). See `add/logging/nextjs.md`.

```ts
// src/app/api/projects/route.ts
import { handleApiError } from '@/lib/errors';
import { withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';
import { z } from 'zod';
// Replace with your actual data access — e.g. (after running templatecentral:add (database)):
//   import { db, projects } from '@/integrations/database';

const CreateProjectSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

export const GET = withLogging(async () => {
  try {
    // ← Replace: e.g. await db.select().from(projects)
    const rows: unknown[] = [];
    return NextResponse.json({ data: rows });
  } catch (error) {
    return handleApiError('Failed to fetch projects', error);
  }
});

export const POST = withLogging(async (request) => {
  try {
    // Malformed JSON must be a 400, not a 500 from the catch below.
    const body: unknown = await request.json().catch(() => null);
    const parsed = CreateProjectSchema.safeParse(body);

    if (!parsed.success) {
      return NextResponse.json(
        { error: 'Validation failed', details: z.flattenError(parsed.error) },
        { status: 400 },
      );
    }

    // ← Replace: e.g. await db.insert(projects).values(parsed.data).returning()
    const project = parsed.data;
    return NextResponse.json({ data: project }, { status: 201 });
  } catch (error) {
    return handleApiError('Failed to create project', error);
  }
});
```

### 3. Dynamic Segments

For routes with resource IDs:

```ts
// src/app/api/projects/[id]/route.ts
import { handleApiError } from '@/lib/errors';
import { type RouteContext, withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';

export const GET = withLogging<RouteContext<{ id: string }>>(async (_request, { params }) => {
  try {
    const { id: _id } = await params;
    // ← Replace: e.g. await db.select().from(projects).where(eq(projects.id, _id)).then(r => r[0] ?? null)
    const project = null;
    if (!project) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }
    return NextResponse.json({ data: project });
  } catch (error) {
    return handleApiError('Failed to fetch project', error);
  }
});
```

### 4. Update Routes Constant

Add the new API route to `src/lib/constants/routes.ts`:

```ts
export const API_ROUTES = {
  // ... existing routes
  PROJECTS: '/api/projects',
  PROJECT_BY_ID: (id: string) => `/api/projects/${id}`,
} as const;
```

### 5. Add tests (mandatory)

Create Vitest files under `test/api/` mirroring the route structure. Import handlers from the route module (same pattern as `test/api/health.test.ts`).

Example for `src/app/api/projects/route.ts`:

```ts
// test/api/projects/route.test.ts
import { NextRequest } from 'next/server';
import { describe, expect, it } from 'vitest';

import { GET, POST } from '@/app/api/projects/route';

// withLogging-wrapped handlers are typed against NextRequest and always take the
// request as their first argument — a plain Request or a zero-arg call is a type error.
describe('GET /api/projects', () => {
  it('returns 200 and a list', async () => {
    const response = await GET(new NextRequest('http://localhost/api/projects'));
    expect(response.status).toBe(200);
  });
});

describe('POST /api/projects', () => {
  it('returns 400 on invalid body', async () => {
    const request = new NextRequest('http://localhost/api/projects', {
      method: 'POST',
      body: JSON.stringify({}),
      headers: { 'Content-Type': 'application/json' },
    });
    const response = await POST(request);
    expect(response.status).toBe(400);
  });
});
```

Cover success paths and validation/error paths you implemented. Run `pnpm test` before handing off.

### 6. Validate

```bash
pnpm build
pnpm test
```

Confirm the build succeeds with no type errors, all tests pass, and the route responds correctly using `curl` or the browser.

## Response Conventions

- **Success**: Return `{ data: … }` with the appropriate status (200, 201) — the envelope the feature services, pagination, and error-handling guides all parse
- **Error**: Use `handleApiError()` which logs and returns consistent JSON error response
- **Not Found**: Return `{ error: 'Not found' }` with status 404
- **Validation**: Parse with Zod's `safeParse()` and return 400 with `z.flattenError(error)` on failure

## Rules

- **Tests are mandatory** — never add or change `src/app/api/**` without new or updated tests under `test/api/` in the same change.
- Keep route handlers thin — delegate to services. NEVER put business logic in route handlers
- Always use `handleApiError()` for error responses — NEVER return raw error objects or stack traces
- Use `NextResponse.json()` for all responses
- Use dynamic segments `[id]` for resource IDs
- **Authenticate in the handler.** `src/proxy.ts` (after `templatecentral:add` (auth)) only checks session-cookie *presence* — it does not validate the session. Every non-public handler must call `const session = await auth.api.getSession({ headers: request.headers })` and return `new Response(null, { status: 401 })` when it is `null`, then enforce ownership/role checks. Without auth added, every API route is public — run `templatecentral:add` (auth) first
- NEVER use `request.json()` without validation — parse with Zod and return 400 on failure
- NEVER expose internal error details in responses — rely on `handleApiError()` for generic messages
- NEVER skip the routes constant — always add new API routes to `src/lib/constants/routes.ts`

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards