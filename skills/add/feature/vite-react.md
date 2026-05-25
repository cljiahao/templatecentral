<!-- ref: add/feature/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Feature Module

Create a new self-contained feature module in a Vite + React project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Inputs

- **Feature name** — The domain name (e.g., `project`, `auth`, `dashboard`)

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create the Feature Directory Structure

```
src/features/<feature-name>/
├── api/                         # Data access services (calls to external backend API)
│   ├── <name>-service.ts        # Service with fetch calls to backend endpoints
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

Define types and interfaces first — this establishes the contract before implementation:

```ts
export interface ProjectItem {
  id: string;
  name: string;
  status: 'active' | 'archived';
}
```

### 3. Create `constants.ts`

Put all static data here — NOT in components:

```ts
export const STATUS_OPTIONS = [
  { value: 'active', label: 'Active' },
  { value: 'archived', label: 'Archived' },
] as const;
```

### 4. Create API Services (in `api/`)

Client-side services that fetch data from the backend API.

> **`getApiBaseUrl()`** is pre-provided in `src/lib/constants/env.ts` — it throws at startup if `VITE_API_BASE_URL` is missing, preventing silent network failures at runtime. Always use it instead of `ENV.API_BASE_URL` directly.

```ts
// api/project-service.ts
import { getApiBaseUrl } from '@/lib/constants/env';
import { APIError } from '@/lib/errors';
import type { ProjectItem } from '../types';

const API_BASE = getApiBaseUrl();

export const ProjectService = {
  getAll: async (): Promise<ProjectItem[]> => {
    const res = await fetch(`${API_BASE}/projects`);
    if (!res.ok) {
      throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Failed to fetch projects' })) });
    }
    return res.json();
  },

  getById: async (id: string): Promise<ProjectItem> => {
    const res = await fetch(`${API_BASE}/projects/${id}`);
    if (!res.ok) {
      throw new APIError({ statusCode: res.status, data: await res.json().catch(() => ({ message: 'Project not found' })) });
    }
    return res.json();
  },
};
```

Export from barrel: `api/index.ts`

### 5. Create Components (in `components/`)

**Before writing any UI, check the template's component library** (see `code-standards/SKILL.md` → *Component Library*). Prefer existing shadcn primitives (`button`, `card`, `dialog`, `form`, `input`, `select`, `tabs`, etc.) and widgets (`custom-card`, `custom-dialog`, `custom-form-field`, `media-card`, `pill`, etc.) over writing new ones from scratch.

Feature-specific components. Use `function` declarations:

```tsx
// components/project-card.tsx
import { CustomCard } from '@/components/widgets';
import type { ProjectItem } from '../types';

export function ProjectCard({ project }: { project: ProjectItem }) {
  return <CustomCard header={project.name} description={project.status} />;
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

Export constants that consumers need (e.g., static data for rendering). Export types for typed props or state. Only export what consumers outside the feature need.

### 8. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds with no TypeScript errors and all tests pass. Verify imports resolve: `import { X } from '@/features/<name>'` works from outside the feature.

## Rules

- **Direct imports** OK within the same feature
- If a component is used by 2+ features, promote it to `src/components/widgets/`; NEVER place feature-specific components there until used by 2+ features
- NEVER import from one feature into another — if shared, promote to `components/widgets/` or `lib/`
- NEVER export internal implementation details from the barrel — only the public API
- NEVER skip creating `types.ts` — define interfaces before building components
- NEVER hardcode API URLs in services — use `getApiBaseUrl()` from `src/lib/constants/env.ts` (throws at startup if `VITE_API_BASE_URL` is missing)

## Validate

```bash
pnpm build    # zero errors
pnpm test     # tests pass
```

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards