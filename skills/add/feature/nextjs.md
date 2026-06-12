<!-- ref: add/feature/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Feature Module

Create a new self-contained feature module in a Next.js project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Inputs

- **Feature name** — The domain name (e.g., `project`, `auth`, `dashboard`)

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

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
├── schemas/                     # Zod validation schemas (see Step 4b)
├── constants.ts                 # Static data (arrays, config objects, options)
├── types.ts                     # TypeScript interfaces and types
└── index.ts                     # Barrel export
```

### 2. Create `types.ts`

Define types and interfaces first — this establishes the contract before implementation:

```ts
export interface ProjectItem {
  id: string;
  name: string;
  status: 'active' | 'archived';
}
```

### 3. Create `constants.ts`

Static data goes here — NOT in components:

```ts
export const STATUS_OPTIONS = [
  { value: 'active', label: 'Active' },
  { value: 'archived', label: 'Archived' },
] as const;
```

### 4. Create API Services (in `api/`)

Data access services consumed by React Query hooks on the client side:

```ts
// api/project-service.ts
import { APIError } from '@/integrations/error';
import type { ProjectItem } from '../types';

export const ProjectService = {
  getAll: async (): Promise<ProjectItem[]> => {
    const res = await fetch('/api/projects');
    if (!res.ok) {
      throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Failed to fetch projects' })) });
    }
    return res.json();
  },

  getById: async (id: string): Promise<ProjectItem> => {
    const res = await fetch(`/api/projects/${id}`);
    if (!res.ok) {
      throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Project not found' })) });
    }
    return res.json();
  },

  create: async (data: Omit<ProjectItem, 'id'>): Promise<ProjectItem> => {
    const res = await fetch('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) {
      throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Failed to create project' })) });
    }
    return res.json();
  },
};
```

Export from barrel: `api/index.ts`

### 4b. Create Schemas (in `schemas/`, Optional)

Create Zod schemas when the feature has form validation or needs to parse external API responses. Skip this step if the feature only consumes typed data from its own service.

```ts
// schemas/project-schemas.ts
import { z } from 'zod';

export const createProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().max(500).optional(),
  status: z.enum(['active', 'archived']),
});

export type CreateProjectInput = z.input<typeof createProjectSchema>;
```

Use these schemas in:
- **React Hook Form** — pass to `zodResolver(createProjectSchema)` for client-side form validation
- **API route handlers** — use `safeParse()` to validate request bodies (see `add-api-route` skill)
- **Service layer** — validate external API responses before returning typed data

### 5. Create Components (in `components/`)

**Before writing any UI, check the template's component library** (see `code-standards/SKILL.md` → *Component Library*). Prefer existing shadcn primitives (`button`, `card`, `dialog`, `form`, `input`, `select`, `tabs`, etc.) and widgets (`custom-card`, `custom-dialog`, `custom-form-field`, `media-card`, `pill`, etc.) over writing new ones from scratch.

Feature-specific components. Use `function` declarations:

```tsx
// components/project-card.tsx
import type { ProjectItem } from '../types';

export function ProjectCard({ project }: { project: ProjectItem }) {
  return (
    <div className="rounded-lg border p-4">
      <h3 className="font-semibold">{project.name}</h3>
      <span className="text-sm text-muted-foreground">{project.status}</span>
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

Export constants that consumers need (e.g., static data for rendering). Export types for typed props or state.

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
- If a component is used by 2+ features, promote it to `src/components/widgets/`
- NEVER import from one feature into another — promote shared code to `components/widgets/` or `lib/`
- NEVER place feature-specific components in `src/components/widgets/` until used by 2+ features
- NEVER export internal implementation details from the barrel — only the public API
- NEVER skip creating `types.ts` — define interfaces before building components

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"`  — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards
3. the test utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/test/SKILL.md"` — write and run tests