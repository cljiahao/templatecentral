<!-- ref: add/pagination/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### Vite + React (React Query)

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Pagination Hook**

```ts
// src/hooks/use-pagination.ts
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { useState } from 'react';

export interface Paginated<T> {
  items: T[];
  pagination: { page: number; limit: number; total: number; hasMore: boolean };
}

interface UsePaginationOptions {
  initialPage?: number;
  pageSize?: number;
  enabled?: boolean;
}

export function usePagination<T>(
  queryKey: readonly unknown[],
  fetchFn: (page: number, limit: number, signal: AbortSignal) => Promise<Paginated<T>>,
  { initialPage = 1, pageSize = 10, enabled = true }: UsePaginationOptions = {}
) {
  const [page, setPage] = useState(initialPage);

  const { data, isPending, isFetching, error } = useQuery({
    // pageSize is in the key so two lists with different sizes never share a cache entry.
    queryKey: [...queryKey, { page, pageSize }],
    queryFn: ({ signal }) => fetchFn(page, pageSize, signal),
    enabled,
    // Keeps the previous page on screen (isFetching) instead of unmounting to isPending.
    placeholderData: keepPreviousData,
  });

  return {
    items: data?.items ?? [],
    pagination: data?.pagination,
    page,
    isPending,
    isFetching,
    error,
    nextPage: () => {
      if (data?.pagination.hasMore) setPage((p) => p + 1);
    },
    prevPage: () => setPage((p) => Math.max(1, p - 1)),
  };
}
```

**2. Export from the hooks barrel**

```ts
// src/hooks/index.ts
export { usePagination, type Paginated } from './use-pagination';
```

**3. Schema + API Service**

The FastAPI and NestJS pagination endpoints (`templatecentral:add (pagination)` on the backend) both return `{ data: { items, pagination: { page, limit, total, hasMore } } }` — the one wrapped shape; their non-list endpoints return bare bodies. Validate it as-is.

**Update, don't overwrite**: if `templatecentral:add (feature)` already created `project.schema.ts`, keep its `projectItemSchema` and add only `paginatedProjectsSchema`; if `types.ts` already declares `ProjectItem`, skip the `ProjectItem` export below and import the type from `../types`. Create the file as shown only when it is absent.

```ts
// src/features/project/schemas/project.schema.ts
import { z } from 'zod';

// Canonical project schema (same as add (feature)). nullish: FastAPI emits `null`, a NestJS
// DTO may omit the key; extra fields (createdAt, updatedAt) are stripped.
export const projectItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullish(),
});

export type ProjectItem = z.infer<typeof projectItemSchema>;

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

The service calls the backend through `ApiClient` (`src/lib/clients/api-client.ts`, defined in `templatecentral:standards (full-stack-pairing)` → Frontend HTTP Client; create it from there if missing), which carries the session cookie and CSRF header once `templatecentral:add (auth)` is applied. The list endpoint's shape changes from a bare array to the paginated envelope, so if `api/project-service.ts` already exists (from add (feature)), replace `ProjectClient.list` with the one below, add `fetchProjects`, and remove `ProjectService.getAll` (update its callers to `fetchProjects`) — do not overwrite the file's other methods.

```ts
// src/features/project/api/project-service.ts
import type { Paginated } from '@/hooks';
import { ApiClient } from '@/lib/clients/api-client';
import { APIError, logError } from '@/lib/errors';
import { paginatedProjectsSchema, type ProjectItem } from '../schemas/project.schema';

class ProjectClient extends ApiClient {
  // unknown: fetchProjects parses, so network data is never type-asserted.
  list(page: number, limit: number, signal?: AbortSignal): Promise<unknown> {
    return this.request('projects', 'GET', undefined, { page, limit }, signal);
  }
}

// Lazy: ApiClient's constructor throws when VITE_API_BASE_URL is unset — at module scope
// that kills bundle evaluation before createRoot().
let client: ProjectClient | undefined;
const projects = (): ProjectClient => (client ??= new ProjectClient());

export async function fetchProjects(
  page: number,
  limit: number,
  signal?: AbortSignal
): Promise<Paginated<ProjectItem>> {
  const parsed = paginatedProjectsSchema.safeParse(await projects().list(page, limit, signal));
  if (!parsed.success) {
    // Log the issue paths for debugging; the user sees only the generic APIError.
    logError('fetchProjects: response failed schema validation', parsed.error);
    throw new APIError({ statusCode: 502, data: { message: 'Unexpected response from the server.' } });
  }
  return parsed.data.data;
}
```

**4. Projects List Component**

```tsx
// src/features/project/components/projects-list.tsx
import { Button } from '@/components/ui/button';
import { usePagination } from '@/hooks';
import { fetchProjects } from '../api/project-service';
import type { ProjectItem } from '../schemas/project.schema';

export function ProjectsList() {
  const { items, pagination, page, isPending, isFetching, error, nextPage, prevPage } =
    usePagination<ProjectItem>(['projects'], fetchProjects);

  if (isPending) return <div>Loading...</div>;
  if (error) return <div role="alert">Failed to load projects.</div>;

  return (
    <div className="space-y-4">
      <ul className={isFetching ? 'space-y-2 opacity-60 transition-opacity' : 'space-y-2'}>
        {items.map((project) => (
          <li key={project.id} className="rounded border p-2">
            <h3 className="font-bold">{project.name}</h3>
            {project.description && (
              <p className="text-muted-foreground text-sm">{project.description}</p>
            )}
          </li>
        ))}
      </ul>

      {pagination && (
        <nav aria-label="Pagination" className="flex items-center justify-between gap-2">
          <Button variant="outline" onClick={prevPage} disabled={page === 1 || isFetching}>
            Previous
          </Button>
          <span aria-live="polite">
            Page {pagination.page} of {Math.max(1, Math.ceil(pagination.total / pagination.limit))} (
            {pagination.total} results)
          </span>
          <Button variant="outline" onClick={nextPage} disabled={!pagination.hasMore || isFetching}>
            Next
          </Button>
        </nav>
      )}
    </div>
  );
}
```

## Validate

Run `pnpm test`, then `pnpm dev` and confirm: Previous is disabled on page 1, Next fetches page 2 without blanking the list, and `hasMore` drives Next.

## Rules

- Always set `placeholderData: keepPreviousData` on a paginated query — without it every page click blanks the list
- Drive loading/disabled UI off `isFetching` for page changes; `isPending` covers only the first load
- Always throw `APIError`, never a generic `Error` — never put validation details in the thrown message
- Always add the hook to the `src/hooks/index.ts` barrel
- Use the shadcn `Button` for pagination controls — never a raw `<button>`

## See Also

- `templatecentral:add` (error-handling) — Pagination errors use unified error response schema
- `templatecentral:standards` (validation-patterns) — Pagination query params validated with Zod/Pydantic
- `templatecentral:add (endpoint)` — Add pagination to new list endpoints
- Stack-specific `code-standards` — Database indexing best practices for sort fields

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards