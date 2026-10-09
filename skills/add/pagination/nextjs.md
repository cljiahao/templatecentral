<!-- ref: add/pagination/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### Next.js (Drizzle + Zod)

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Reusable Pagination Schema** (canonical copy: `templatecentral:standards` → `validation-patterns/patterns.md`; reuse it if `src/lib/validation/schemas.ts` already exists)

```ts
// src/lib/validation/schemas.ts
import { z } from 'zod';

// Pass Object.fromEntries(searchParams) so missing keys are undefined and the defaults apply.
export const paginationSchema = z.object({
  // Capped: OFFSET cost grows with page, so an unbounded page is a cheap DoS lever.
  page: z.coerce.number().int().min(1, 'Page must be 1 or greater').max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(100, 'Limit must be 100 or less').default(10),
  sort: z.string().max(64).regex(/^(asc|desc)_\w+$/, 'Invalid sort format').optional(),
});

export type PaginationParams = z.infer<typeof paginationSchema>;
```

**2. Pagination Response Type**

```ts
// src/lib/types/pagination.ts
export interface PaginationMetadata {
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

export interface PaginatedResponse<T> {
  data: {
    items: T[];
    pagination: PaginationMetadata;
  };
}
```

**3. Pagination Helpers (Business Logic)**

```ts
// src/lib/pagination/pagination-service.ts
import type { PaginationMetadata } from '@/lib/types/pagination';

export function calculateOffset(page: number, limit: number): number {
  return (page - 1) * limit;
}

export function createMetadata(page: number, limit: number, total: number): PaginationMetadata {
  return {
    page,
    limit,
    total,
    hasMore: page * limit < total,
  };
}

// Returns null unless the field is allow-listed — the only gate between client input and orderBy.
export function parseSortParam(
  sort: string | undefined,
  allowedFields: string[]
): { field: string; direction: 'asc' | 'desc' } | null {
  if (!sort) return null;

  // Split on the first underscore only — field names may contain underscores.
  const separatorIndex = sort.indexOf('_');
  if (separatorIndex === -1) return null;
  const direction = sort.slice(0, separatorIndex);
  const field = sort.slice(separatorIndex + 1);
  if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
    return null;
  }

  return { field, direction: direction as 'asc' | 'desc' };
}
```

**4. Data Access + API Route**

Query building is data access — keep it out of the route handler:

```ts
// src/integrations/database/queries/list-projects.ts
import { asc, count, desc } from 'drizzle-orm';
import { db, projects } from '@/integrations/database';
import { calculateOffset, createMetadata, parseSortParam } from '@/lib/pagination/pagination-service';
import type { PaginationParams } from '@/lib/validation/schemas';

// The allow-list IS this mapping, so it cannot drift from the sortable columns.
const SORT_COLUMNS = {
  name: projects.name,
  createdAt: projects.createdAt,
  updatedAt: projects.updatedAt,
} as const;
type SortField = keyof typeof SORT_COLUMNS;
export const ALLOWED_SORT_FIELDS = Object.keys(SORT_COLUMNS) as SortField[];

export class InvalidSortError extends Error {}

export async function listProjects({ page, limit, sort }: PaginationParams) {
  const sortParam = parseSortParam(sort, ALLOWED_SORT_FIELDS);
  if (sort && !sortParam) throw new InvalidSortError();

  const column = sortParam ? SORT_COLUMNS[sortParam.field as SortField] : projects.createdAt;
  const orderBy = sortParam?.direction === 'asc' ? asc(column) : desc(column);

  const [rows, [{ total }]] = await Promise.all([
    // Explicit columns — never send full rows to the browser.
    db
      .select({ id: projects.id, name: projects.name, description: projects.description })
      .from(projects)
      .orderBy(orderBy)
      .limit(limit)
      .offset(calculateOffset(page, limit)),
    db.select({ total: count() }).from(projects),
  ]);

  return { items: rows, pagination: createMetadata(page, limit, Number(total)) };
}
```

```ts
// src/app/api/projects/route.ts
import { ALLOWED_SORT_FIELDS, InvalidSortError, listProjects } from '@/integrations/database/queries/list-projects';
import { handleApiError } from '@/lib/errors';
import { withLogging } from '@/lib/utils/with-logging';
import { paginationSchema } from '@/lib/validation/schemas';
import { NextResponse } from 'next/server';
import { z } from 'zod';

export const GET = withLogging(async (request) => {
  try {
    const parsed = paginationSchema.safeParse(Object.fromEntries(request.nextUrl.searchParams));
    if (!parsed.success) {
      return NextResponse.json(
        { error: 'Invalid query parameters', details: z.flattenError(parsed.error) },
        { status: 400 },
      );
    }

    return NextResponse.json({ data: await listProjects(parsed.data) });
  } catch (error) {
    if (error instanceof InvalidSortError) {
      return NextResponse.json(
        {
          error: 'Invalid sort field',
          details: { fieldErrors: { sort: [`Must be one of: ${ALLOWED_SORT_FIELDS.join(', ')}`] } },
        },
        { status: 400 },
      );
    }
    return handleApiError('Failed to fetch projects', error);
  }
});
```

**5. Paginated UI (feature schema → service → hook → component)**

```ts
// src/features/projects/schemas/project.schema.ts
import { z } from 'zod';

export const projectItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
});

export const paginatedProjectsSchema = z.object({
  data: z.object({
    items: z.array(projectItemSchema),
    pagination: z.object({
      page: z.number(),
      limit: z.number(),
      total: z.number(),
      hasMore: z.boolean(),
    }),
  }),
});
```

```ts
// src/features/projects/api/project-service.ts
// Not '@/lib/errors' — that barrel pulls server-only modules into the client bundle.
import { APIError } from '@/integrations/error';
import { paginatedProjectsSchema } from '../schemas/project.schema';

export async function fetchProjects(page: number, limit: number, signal?: AbortSignal) {
  const query = new URLSearchParams({ page: String(page), limit: String(limit), sort: 'asc_name' });
  const response = await fetch(`/api/projects?${query}`, { signal });

  if (!response.ok) {
    throw new APIError({
      statusCode: response.status,
      data: await response.json().catch(() => ({ message: 'Failed to fetch projects' })),
    });
  }

  const parsed = paginatedProjectsSchema.safeParse(await response.json());
  if (!parsed.success) {
    throw new APIError({ statusCode: 502, data: { message: 'Unexpected response from the server.' } });
  }
  return parsed.data.data;
}
```

```ts
// src/features/projects/hooks/use-projects.query.ts
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { fetchProjects } from '../api/project-service';

export const useProjects = (page: number, limit: number) =>
  useQuery({
    queryKey: ['projects', { page, limit }],
    queryFn: ({ signal }) => fetchProjects(page, limit, signal),
    // Keeps the previous page on screen (isFetching) instead of unmounting to isPending.
    placeholderData: keepPreviousData,
  });
```

```tsx
// src/features/projects/components/projects-list.tsx
'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { useProjects } from '../hooks/use-projects.query';

const PAGE_SIZE = 10;

export function ProjectsList() {
  const [page, setPage] = useState(1);
  const { data, isPending, isFetching, error } = useProjects(page, PAGE_SIZE);

  if (isPending) return <div>Loading...</div>;
  if (error) return <div role="alert">Failed to load projects.</div>;

  const { items: projects, pagination } = data;
  const totalPages = Math.max(1, Math.ceil(pagination.total / pagination.limit));

  return (
    <div className="space-y-4">
      <ul className={isFetching ? 'space-y-2 opacity-60 transition-opacity' : 'space-y-2'}>
        {projects.map((project) => (
          <li key={project.id} className="rounded border p-2">
            <h3 className="font-bold">{project.name}</h3>
            {project.description && (
              <p className="text-muted-foreground text-sm">{project.description}</p>
            )}
          </li>
        ))}
      </ul>

      <nav aria-label="Pagination" className="flex items-center justify-between gap-2">
        <Button
          variant="outline"
          disabled={page === 1 || isFetching}
          onClick={() => setPage((p) => Math.max(1, p - 1))}
        >
          Previous
        </Button>
        <span aria-live="polite">
          Page {pagination.page} of {totalPages} ({pagination.total} results)
        </span>
        <Button
          variant="outline"
          disabled={!pagination.hasMore || isFetching}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </Button>
      </nav>
    </div>
  );
}
```

## Validate

```bash
# Expect 200 {"data":{"items":[...],"pagination":{"page":1,"limit":10,"total":N,"hasMore":...}}}
curl 'http://localhost:3000/api/projects?page=1&limit=10'
# Each of these must be 400
curl 'http://localhost:3000/api/projects?page=0'
curl 'http://localhost:3000/api/projects?limit=200'
curl 'http://localhost:3000/api/projects?sort=asc_invalid'
pnpm test
pnpm build
```

## Rules

- Always set `placeholderData: keepPreviousData` on a paginated query — without it every page click blanks the list
- Drive loading/disabled UI off `isFetching` for page changes; `isPending` covers only the first load
- Validate the response with Zod `safeParse` and derive the row type from the schema — never re-declare the row shape
- Client code throws `APIError` from `@/integrations/error` (not `@/lib/errors`), never a generic `Error`
- Keep queries out of route handlers and fetches out of components — route → `integrations/`, component → hook → feature `api/`
- Whitelist every sortable field before it reaches the ORM's `orderBy` — `parseSortParam` returns `null` for anything outside the list
- Use the shadcn `Button` for pagination controls — never a raw `<button>`

## See Also

- `templatecentral:add` (error-handling) — Pagination errors use unified error response schema
- `templatecentral:standards` (validation-patterns) — Pagination query params validated with Zod
- `templatecentral:add (endpoint)` — Add pagination to new list endpoints
- Stack-specific `code-standards` — Database indexing best practices for sort fields

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards