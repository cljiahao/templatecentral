<!-- ref: add/feature/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Feature Module

## Inputs

- **Feature name** — The domain name (e.g., `project`, `auth`, `dashboard`)

## Steps

### Step 0 — Verify context

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

### 1. Create the Feature Directory Structure

```
src/features/<feature-name>/
├── api/                         # Data access services (calls to external backend API)
│   ├── <name>-service.ts        # ApiClient subclass + Zod-parsing service
│   └── index.ts
├── components/                  # Feature-specific UI
│   └── index.ts
├── hooks/                       # React hooks (queries, mutations, local state)
│   └── index.ts
├── schemas/                     # Zod validation schemas (form inputs + API response shapes)
│   └── index.ts
├── constants.ts                 # Static data (arrays, config objects, options)
├── types.ts                     # TypeScript interfaces and types
└── index.ts                     # Barrel export
```

### 2. Create `types.ts`

```ts
// Mirrors the backend Project response (FastAPI `ProjectResponse`, NestJS `ProjectDto`).
export interface ProjectItem {
  id: string;
  name: string;
  description?: string | null;
}
```

### 3. Create `constants.ts`

Put all static data here — NOT in components:

```ts
// Values use the backend `sort` format (`asc_<field>` / `desc_<field>`).
export const SORT_OPTIONS = [
  { value: 'asc_name', label: 'Name (A-Z)' },
  { value: 'desc_createdAt', label: 'Newest first' },
] as const;
```

### 4. Create Response Schemas and API Services (in `schemas/` + `api/`)

First define a Zod schema for the API response shape — every external response is validated at the boundary:

```ts
// schemas/project.schema.ts
import { z } from 'zod';

// One canonical project schema — templatecentral:add (pagination) extends this same file.
// nullish: FastAPI emits `null`; a NestJS DTO may omit the key. Extra backend fields
// (createdAt, updatedAt) are stripped by z.object().
export const projectItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullish(),
});
```

Export from barrel: `schemas/index.ts`

Then the client and service. Call the backend through `ApiClient` (`src/lib/clients/api-client.ts`; create it from `templatecentral:standards (full-stack-pairing)` → Frontend HTTP Client if missing). It owns base URL, timeout, `APIError` mapping and, with auth, the session cookie and `X-CSRF-Token` — feature code never touches `fetch`, credentials or CSRF:

```ts
// api/project-service.ts
import { ApiClient } from '@/lib/clients/api-client';
import { projectItemSchema } from '../schemas';
import type { ProjectItem } from '../types';

// The FastAPI (response_model) and NestJS (plain return) backends send bare bodies — no
// `{ data }` envelope — so parse the body directly. Only paginated list endpoints wrap
// (`{ data: { items, pagination } }`, see templatecentral:add (pagination)).
// Methods return unknown: the service parses, so network data is never type-asserted.
class ProjectClient extends ApiClient {
  list(signal?: AbortSignal): Promise<unknown> {
    return this.request('projects', 'GET', undefined, {}, signal);
  }

  get(id: string, signal?: AbortSignal): Promise<unknown> {
    // Encoding stops a crafted id from rewriting the path (`../admin`).
    return this.request(`projects/${encodeURIComponent(id)}`, 'GET', undefined, {}, signal);
  }
}

// Lazy: ApiClient's constructor throws when VITE_API_BASE_URL is unset, and a module-scope
// throw kills bundle evaluation before createRoot() — a blank page no ErrorBoundary catches.
let client: ProjectClient | undefined;
const projects = (): ProjectClient => (client ??= new ProjectClient());

export const ProjectService = {
  getAll: async (signal?: AbortSignal): Promise<ProjectItem[]> =>
    projectItemSchema.array().parse(await projects().list(signal)),

  getById: async (id: string, signal?: AbortSignal): Promise<ProjectItem> =>
    projectItemSchema.parse(await projects().get(id, signal)),
};
```

`getAll` assumes an unpaginated `GET /projects` returning a bare array. Once `templatecentral:add (pagination)` is applied to the backend, that endpoint returns `{ data: { items, pagination } }`; update the service then, never keep both shapes.

Export from barrel: `api/index.ts`

### 5. Create Components (in `components/`)

**Check the component library before writing UI** (`templatecentral:standards` → `code-standards/vite-react.md` → *Component Best Practices*). Prefer existing shadcn primitives and widgets (`custom-card`, `custom-dialog`, `custom-form-field`, `media-card`, `pill`, …) over new ones.

Feature-specific components. Use `function` declarations:

```tsx
// components/project-card.tsx
import { CustomCard } from '@/components/widgets';
import type { ProjectItem } from '../types';

export function ProjectCard({ project }: { project: ProjectItem }) {
  return <CustomCard header={project.name} description={project.description ?? undefined} />;
}
```

Export from barrel: `components/index.ts`

### 6. Create Hooks (in `hooks/`)

Follow naming convention:

| Suffix | Purpose |
|--------|---------|
| `.query.ts` | React Query `useQuery` — fetches data |
| `.mutation.ts` | React Query `useMutation` — writes data |
| (no suffix) | Local state, form logic, other hooks |

```ts
// hooks/use-projects.query.ts
import { useQuery } from '@tanstack/react-query';
import { ProjectService } from '../api';

export const useProjects = () => {
  return useQuery({
    queryKey: ['projects'],
    queryFn: ({ signal }) => ProjectService.getAll(signal),
  });
};
```

Export from barrel: `hooks/index.ts`

### 7. Create Root Barrel Export

```ts
// index.ts
export * from './components';
export * from './hooks';
export * from './constants';
export type { ProjectItem } from './types';
```

Export only what consumers outside the feature need (constants, types).

### 8. Validate

```bash
pnpm build && pnpm test
```

Build and tests pass; `import { X } from '@/features/<name>'` resolves from outside the feature.

## Rules

- **Direct imports** OK within the same feature
- NEVER import across features — promote shared code (used by 2+) to `components/widgets/` or `lib/`
- The barrel exports only the public API
- Write `types.ts` before components
- Call the backend through an `ApiClient` subclass — NEVER raw `fetch` or a hardcoded URL (it would skip the session cookie and CSRF header)

## Standalone Components

For a component not tied to a feature module.

First determine where it belongs:

| Scenario | Location | Example |
|----------|----------|---------|
| Used by one feature only | `src/features/<name>/components/` | `ProjectCard` in `features/project` |
| Used by 2+ features | `src/components/widgets/` | `StatusBadge` used by project + dashboard |
| Low-level primitive | `src/components/ui/` (use shadcn CLI) | `Button`, `Input`, `Dialog` |
| App shell | `src/components/layout/` | `Navbar`, `SiteFooter` |

For low-level UI primitives, always use the shadcn CLI — never hand-install (`components.json` is set to `rsc: false` for Vite compatibility):

```bash
npx shadcn@latest add <component-name>
```

It installs into `src/components/ui/`; never hand-create primitives there.

Rules:
- NEVER add boolean flag props to configure variants — prefer composition with children
- Always add to barrel `index.ts` when creating in shared folders — NEVER omit the barrel export

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.