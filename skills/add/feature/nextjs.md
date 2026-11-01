<!-- ref: add/feature/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Feature Module

## Inputs

- **Feature name** — The domain name (e.g., `project`, `auth`, `dashboard`)

## Steps

### Step 0 — Verify context

Need `<!-- templateCentral: nextjs@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

### 1. Create the Feature Directory Structure

```
src/features/<feature-name>/
├── api/                         # Data access services (HTTP calls to /api/* routes)
│   ├── <name>-service.ts        # Service with fetch calls to /api/*
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
// Mirrors the projects table (id, name, description) used across templateCentral backends.
export interface ProjectItem {
  id: string;
  name: string;
  description?: string | null;
}
```

### 3. Create `constants.ts`

Static data goes here, not in components:

```ts
// Values use the API `sort` format (`asc_<field>` / `desc_<field>`).
export const SORT_OPTIONS = [
  { value: 'asc_name', label: 'Name (A-Z)' },
  { value: 'desc_createdAt', label: 'Newest first' },
] as const;
```

### 4. Create API Services (in `api/`)

Client services for React Query hooks. Validate every response with Zod so types are checked at runtime, not asserted:

```ts
// schemas/project.schema.ts
import { z } from 'zod';

// One canonical project schema — templatecentral:add (pagination) extends this same file.
// Extra row fields (createdAt, updatedAt) are stripped by z.object().
export const projectItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullish(),
});
```

Export from barrel: `schemas/index.ts`

Then create the service:

```ts
// api/project-service.ts
import { z } from 'zod';

import { APIError } from '@/integrations/error';
import { projectItemSchema } from '../schemas';
import type { ProjectItem } from '../types';

// Route handlers wrap every success body as `{ data }` (see templatecentral:add (endpoint)).
const envelope = <T extends z.ZodType>(schema: T) => z.object({ data: schema });

// `message` is the fallback only when the error body is not JSON.
async function assertOk(res: Response, message: string): Promise<void> {
  if (res.ok) return;
  throw new APIError({
    statusCode: res.status,
    data: await res.json().catch(() => ({ message })),
  });
}

export const ProjectService = {
  getAll: async (): Promise<ProjectItem[]> => {
    const res = await fetch('/api/projects');
    await assertOk(res, 'Failed to fetch projects');
    return envelope(projectItemSchema.array()).parse(await res.json()).data;
  },

  getById: async (id: string): Promise<ProjectItem> => {
    // Encoding stops a crafted id from rewriting the path (`../admin`).
    const res = await fetch(`/api/projects/${encodeURIComponent(id)}`);
    await assertOk(res, 'Project not found');
    return envelope(projectItemSchema).parse(await res.json()).data;
  },

  create: async (data: Omit<ProjectItem, 'id'>): Promise<ProjectItem> => {
    const res = await fetch('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    await assertOk(res, 'Failed to create project');
    return envelope(projectItemSchema).parse(await res.json()).data;
  },
};
```

`getAll` assumes an unpaginated `GET /api/projects` returning `{ data: ProjectItem[] }`. Once `templatecentral:add (pagination)` is applied, that route returns `{ data: { items, pagination } }`; update the service then, never keep both shapes.

Export from barrel: `api/index.ts`

### 4b. Add Form Schemas (in `schemas/`)

When the feature has a form, add an input schema next to the response schema:

```ts
// schemas/project.schema.ts (same file as the response schema)
import { z } from 'zod';

export const createProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().max(500).optional(),
});

export type CreateProjectInput = z.input<typeof createProjectSchema>;
```

Use these schemas in:
- **React Hook Form** — pass to `zodResolver(createProjectSchema)` for client-side form validation
- **API route handlers** — use `safeParse()` to validate request bodies (see `templatecentral:add (endpoint)`)
- **Service layer** — validate external API responses before returning typed data

### 5. Create Components (in `components/`)

**Check the component library before writing UI** (`templatecentral:standards` → `code-standards/nextjs.md` → *Component Best Practices*). Prefer existing shadcn primitives and widgets (`custom-card`, `custom-dialog`, `custom-form-field`, `media-card`, `pill`, …) over new ones.

Feature-specific components. Use `function` declarations:

```tsx
// components/project-card.tsx
import type { ProjectItem } from '../types';

export function ProjectCard({ project }: { project: ProjectItem }) {
  return (
    <div className="rounded-lg border p-4">
      <h3 className="font-semibold">{project.name}</h3>
      {project.description && (
        <p className="text-sm text-muted-foreground">{project.description}</p>
      )}
    </div>
  );
}
```

Export from barrel: `components/index.ts`

### 6. Create Hooks (in `hooks/`)

Follow naming convention:

| Suffix | Purpose |
|--------|---------|
| `.query.ts` | React Query `useQuery` — fetches from `/api/*` |
| `.mutation.ts` | React Query `useMutation` — writes to `/api/*` |
| (no suffix) | Local state, form logic, other hooks |

```ts
// hooks/use-projects.query.ts
import { useQuery } from '@tanstack/react-query';
import { ProjectService } from '../api';

export const useProjects = () => {
  return useQuery({
    queryKey: ['projects'],
    queryFn: () => ProjectService.getAll(),
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

Export constants and types consumers need.

If the feature has client-side data access services (hooks that call `/api/*`), also export the API layer:

```ts
export * from './api';
```

Only export what consumers outside the feature need.

### 8. Validate

After creating all files:
1. Run `pnpm build` — confirm no TypeScript errors
2. Verify imports resolve: `import { X } from '@/features/<name>'` works from outside the feature
3. If hooks use React Query, verify the query key is unique across the project

## Rules

- **Direct imports** OK within the same feature
- Do not import across features; promote shared code (used by 2+) to `components/widgets/` or `lib/`
- The barrel exports only the public API
- Write `types.ts` before components

## Standalone Components

For a component not tied to a feature module.

First determine where it belongs:

| Scenario | Location | Example |
|----------|----------|---------|
| Used by one feature only | `src/features/<name>/components/` | `ProjectCard` in `features/project` |
| Used by 2+ features | `src/components/widgets/` | `StatusBadge` used by project + dashboard |
| Low-level primitive | `src/components/ui/` (use shadcn CLI) | `Button`, `Input`, `Dialog` |
| App shell | `src/components/layout/` | `Navbar`, `SiteFooter` |

For low-level UI primitives, always use the shadcn CLI — never hand-install:

```bash
npx shadcn@latest add <component-name>
```

It installs into `src/components/ui/`; never hand-create primitives there.

Rules:
- Prefer composition with children over boolean flag props for variants
- Add exports to the folder's `index.ts` barrel

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"` (check code standards), then `cat "<skill-dir>/../test/SKILL.md"` (write and run tests).
