<!-- ref: add/pagination/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
### Vite + React (React Query)

### Step 0 — Verify context

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

Run `TC_PART=leaf TC_LEAF=add/pagination/vite-react bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/pagination/vite-react/template/` (listed in `<skill-dir>/pagination/vite-react/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**1. Pagination Hook**

Copied verbatim from `<skill-dir>/pagination/vite-react/template/src/hooks/use-pagination.ts` by the copy step; do not re-type it.

**2. Export from the hooks barrel**

```ts
// src/hooks/index.ts
export { usePagination, type Paginated } from './use-pagination';
```

**3. Schema + API Service**

The FastAPI and NestJS pagination endpoints return `{ data: { items, pagination: { page, limit, total, hasMore } } }` (non-list endpoints return bare bodies). Validate it as-is.

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

- Set `placeholderData: keepPreviousData` on paginated queries, or each page click blanks the list
- Drive loading/disabled UI off `isFetching` for page changes; `isPending` covers only the first load
- Always throw `APIError`, never a generic `Error` — never put validation details in the thrown message
- Always add the hook to the `src/hooks/index.ts` barrel
- Use the shadcn `Button` for pagination controls — never a raw `<button>`

## See Also

- `templatecentral:add` (error-handling) — unified error responses
- `templatecentral:standards` (validation-patterns) — Pagination query params validated with Zod/Pydantic
- `templatecentral:add (endpoint)` — Add pagination to new list endpoints
- Stack `code-standards` — index sort fields

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.