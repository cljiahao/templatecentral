<!-- ref: add/pagination/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### Vite + React (TypeScript + React Query)

**1. Pagination Hook**

```ts
// src/lib/utils/use-pagination.ts
import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';

interface UsePaginationOptions {
  initialPage?: number;
  pageSize?: number;
  enabled?: boolean;
}

export function usePagination<T>(
  queryKey: string[],
  fetchFn: (page: number, limit: number) => Promise<{
    items: T[];
    pagination: { page: number; limit: number; total: number; hasMore: boolean };
  }>,
  options: UsePaginationOptions = {}
) {
  const { initialPage = 1, pageSize = 10, enabled = true } = options;
  const [page, setPage] = useState(initialPage);

  const { data, isPending, error, isFetching } = useQuery({
    queryKey: [...queryKey, page],
    queryFn: () => fetchFn(page, pageSize),
    enabled,
  });

  const goToPage = useCallback((newPage: number) => {
    setPage(Math.max(1, newPage));
  }, []);

  const nextPage = useCallback(() => {
    if (data?.pagination?.hasMore) {
      setPage((p) => p + 1);
    }
  }, [data]);

  const prevPage = useCallback(() => {
    setPage((p) => Math.max(1, p - 1));
  }, []);

  return {
    data: data?.items || [],
    pagination: data?.pagination,
    page,
    pageSize,
    isPending,
    isFetching,
    error,
    goToPage,
    nextPage,
    prevPage,
  };
}
```

**2. Projects List Component**

```tsx
// src/features/projects/components/projects-list.tsx
import { usePagination } from '@/lib/utils/use-pagination';
import { fetchProjects, type ProjectItem } from '@/features/projects/api/projects';

export function ProjectsList() {
  const { data, pagination, page, isPending, error, nextPage, prevPage } =
    usePagination<ProjectItem>(['projects'], fetchProjects);

  if (isPending) return <div>Loading...</div>;
  if (error) return <div>Error: {error instanceof Error ? error.message : 'An error occurred'}</div>;

  return (
    <div className="space-y-4">
      <ul className="space-y-2">
        {data.map((project: ProjectItem) => (
          <li key={project.id} className="border p-2 rounded">
            <h3 className="font-bold">{project.name}</h3>
            {project.description && (
              <p className="text-sm text-gray-600">{project.description}</p>
            )}
          </li>
        ))}
      </ul>

      {pagination && (
        <div className="space-y-2">
          <div className="flex gap-2 justify-between items-center">
            <button
              disabled={page === 1}
              onClick={prevPage}
              className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
            >
              Previous
            </button>

            <span>
              Page {pagination.page} of{' '}
              {Math.ceil(pagination.total / pagination.limit)}
            </span>

            <button
              disabled={!pagination.hasMore}
              onClick={nextPage}
              className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
            >
              Next
            </button>
          </div>

          <div className="text-sm text-gray-600">
            Showing {(page - 1) * pagination.limit + 1} to{' '}
            {Math.min(page * pagination.limit, pagination.total)} of{' '}
            {pagination.total} results
          </div>
        </div>
      )}
    </div>
  );
}
```

**3. API Client**

```ts
// src/features/projects/api/projects.ts
import { z } from 'zod';
import { APIError } from '@/lib/errors';
import { getApiBaseUrl } from '@/lib/constants/env';

// Matches Phase 1 unified response schema
const projectItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
});

export type ProjectItem = z.infer<typeof projectItemSchema>;

const paginatedProjectSchema = z.object({
  items: z.array(projectItemSchema),
  pagination: z.object({
    page: z.number(),
    limit: z.number(),
    total: z.number(),
    hasMore: z.boolean(),
  }),
});

export async function fetchProjects(
  page: number = 1,
  limit: number = 10
): Promise<z.infer<typeof paginatedProjectSchema>> {
  const response = await fetch(
    `${getApiBaseUrl()}/api/projects?page=${page}&limit=${limit}&sort=asc_name`
  );

  if (!response.ok) {
    throw new APIError({ statusCode: response.status, data: await response.json().catch(() => ({ message: 'Failed to fetch projects' })) });
  }

  const json = await response.json();

  // API returns: { data: { items: [...], pagination: {...} } }
  // Extract from Phase 1 wrapper
  const data = json.data;

  // Validate response shape
  const parsed = paginatedProjectSchema.safeParse(data);
  if (!parsed.success) {
    throw new Error(`Invalid API response: ${JSON.stringify(z.flattenError(parsed.error).fieldErrors)}`);
  }

  return parsed.data;
}
```

## Testing / Verification

```bash
pnpm dev

# Component renders paginated list with prev/next controls
# Clicking next fetches page 2
# Previous button disabled on page 1
# hasMore correctly controls Next button state

pnpm test
```

## See Also

- `templatecentral:add` (error-handling) — Pagination errors use unified error response schema
- `templatecentral:standards` (validation-patterns) — Pagination query params validated with Zod/Pydantic
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Add pagination to new list endpoints
- Stack-specific `code-standards` — Database indexing best practices for sort fields

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards