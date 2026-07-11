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
├── route.ts                        # GET /api (health check)
├── <resource>/
│   ├── route.ts                    # GET, POST /api/<resource>
│   └── [id]/
│       └── route.ts               # GET, PUT, DELETE /api/<resource>/:id
```

### 2. Implement the Route Handler

Keep route handlers thin — delegate to server-side data access:

> **Important**: Route handlers run on the server. They access data via `integrations/` (clients, services, factories) — NOT through the feature's `api/` services, which use `fetch('/api/...')` and would cause the route to call itself recursively. Feature `api/` services are for client-side React Query hooks only. See the `templatecentral:add (integration)` skill for external APIs.
>
> **Note**: The data access imports below are **placeholders** — `factories.ts` starts empty. Replace them with your actual data layer: Drizzle/Mongoose via the `templatecentral:add (database)` skill, or external API clients via the `templatecentral:add (integration)` skill.

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
    const rows = [];
    return NextResponse.json(rows);
  } catch (error) {
    return handleApiError('Failed to fetch projects', error);
  }
});

export const POST = withLogging(async (request) => {
  try {
    const body = await request.json();
    const parsed = CreateProjectSchema.safeParse(body);

    if (!parsed.success) {
      return NextResponse.json(
        { error: 'Validation failed', details: z.flattenError(parsed.error) },
        { status: 400 },
      );
    }

    // ← Replace: e.g. await db.insert(projects).values(parsed.data).returning()
    const project = parsed.data;
    return NextResponse.json(project, { status: 201 });
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
    const { id } = await params;
    // ← Replace: e.g. await db.select().from(projects).where(eq(projects.id, id)).then(r => r[0] ?? null)
    const project = null;
    if (!project) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }
    return NextResponse.json(project);
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
import { GET, POST } from '@/app/api/projects/route';
import { describe, expect, it } from 'vitest';

describe('GET /api/projects', () => {
  it('returns 200 and a list', async () => {
    const response = await GET();
    expect(response.status).toBe(200);
  });
});

describe('POST /api/projects', () => {
  it('returns 400 on invalid body', async () => {
    const request = new Request('http://localhost/api/projects', {
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

- **Success**: Return data with appropriate status code (200, 201)
- **Error**: Use `handleApiError()` which logs and returns consistent JSON error response
- **Not Found**: Return `{ error: 'Not found' }` with status 404
- **Validation**: Parse with Zod's `safeParse()` and return 400 with `z.flattenError(error)` on failure

## Rules

- **Tests are mandatory** — never add or change `src/app/api/**` without new or updated tests under `test/api/` in the same change.
- Keep route handlers thin — delegate to services. NEVER put business logic in route handlers
- Always use `handleApiError()` for error responses — NEVER return raw error objects or stack traces
- Use `NextResponse.json()` for all responses
- Use dynamic segments `[id]` for resource IDs
- If `src/proxy.ts` exists (i.e. `templatecentral:add` (auth) has been run), unauthenticated requests to non-public paths are rejected automatically. Add route-level `auth()` checks only for role-based or resource-level authorization beyond authentication. If auth has not been added yet, all API routes are unprotected — run `templatecentral:add` (auth) first
- NEVER use `request.json()` without validation — parse with Zod and return 400 on failure
- NEVER expose internal error details in responses — rely on `handleApiError()` for generic messages
- NEVER skip the routes constant — always add new API routes to `src/lib/constants/routes.ts`

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards