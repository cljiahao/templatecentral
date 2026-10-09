<!-- ref: add/page/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Page

Create a new page/route in a Vite + React project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:scaffold`. See Step 0.

## Inputs

- **Route path** — The URL path (e.g., `/settings`, `/dashboard/analytics`)
- **Has data fetching** — Whether the page loads data via React Query

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Create the Page Component

Pages live in `src/pages/` and should be thin — compose from features:

```tsx
// src/pages/analytics.tsx
import { AnalyticsDashboard } from '@/features/analytics';

export function AnalyticsPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Analytics</h1>
      <div className="mt-8">
        <AnalyticsDashboard />
      </div>
    </div>
  );
}
```

Note: Use **named exports** — unlike Next.js, there is no `export default` requirement.

### 2. Add the Route to the Router

In `src/router.tsx`, add the route inside the `<Route element={<RootLayout />}>` wrapper.

For **public** routes, place them alongside existing public routes:

```tsx
import { AnalyticsPage } from '@/pages/analytics';

<Route path="analytics" element={<AnalyticsPage />} />
```

For **protected** routes, nest them inside the `<ProtectedRoute />` wrapper — this redirects unauthenticated users to `/login`:

```tsx
<Route element={<ProtectedRoute />}>
  <Route path="dashboard" element={<DashboardPage />} />
  <Route path="analytics" element={<AnalyticsPage />} />
</Route>
```

For nested routes:

```tsx
<Route element={<ProtectedRoute />}>
  <Route path="dashboard">
    <Route index element={<DashboardPage />} />
    <Route path="analytics" element={<AnalyticsPage />} />
  </Route>
</Route>
```

For dynamic segments:

```tsx
<Route path="projects/:id" element={<ProjectDetailPage />} />
```

Route params are user input — validate their shape with Zod before any service call; a presence check (`!id`) is not validation.

```tsx
import { ProjectDetail } from '@/features/projects';
import { NotFoundPage } from '@/pages/not-found';
import { useParams } from 'react-router';
import { z } from 'zod';

// Match the schema to the real id format — z.uuid() here, z.coerce.number().int().positive()
// for numeric ids, z.enum([...]) for a fixed set.
const paramsSchema = z.object({ id: z.uuid() });

export function ProjectDetailPage() {
  // Data hooks live in <ProjectDetail>, so this early return cannot break the Rules of Hooks.
  const parsed = paramsSchema.safeParse(useParams());
  if (!parsed.success) return <NotFoundPage />;

  return <ProjectDetail id={parsed.data.id} />;
}
```

Query-string values need the same treatment:

```tsx
import { ProjectList } from '@/features/projects';
import { useSearchParams } from 'react-router';
import { z } from 'zod';

// `.catch()` falls back to a default instead of throwing on junk input.
const searchSchema = z.object({
  page: z.coerce.number().int().min(1).catch(1),
  status: z.enum(['active', 'archived']).catch('active'),
});

export function ProjectListPage() {
  const [searchParams] = useSearchParams();
  const { page, status } = searchSchema.parse(Object.fromEntries(searchParams));
  return <ProjectList page={page} status={status} />;
}
```

### 3. Export from Barrel

Add the page to `src/pages/index.ts`:

```ts
export { AnalyticsPage } from './analytics';
```

### 4. Update Routes Constant

Add the new route to `src/lib/constants/routes.ts`:

```ts
export const PAGE_ROUTES = {
  // ... existing routes
  ANALYTICS: '/analytics',
} as const;
```

> `PAGE_ROUTES` values are **full paths** — `analytics` nested under `dashboard` is `'/dashboard/analytics'`.

### 5. Add Navigation (Optional)

Update `src/components/layout/navbar.tsx` to include the new link:

```ts
const NAV_LINKS = [
  // ... existing links
  { label: 'Analytics', href: PAGE_ROUTES.ANALYTICS },
] as const;
```

### 6. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds with no type errors and all tests pass.

## Rules

- Always add to `src/pages/index.ts` barrel export
- Always add to `src/lib/constants/routes.ts`
- Always add the `<Route>` in `src/router.tsx` — the page won't be accessible otherwise
- Protected pages MUST be nested inside `<Route element={<ProtectedRoute />}>` in `src/router.tsx`. This is UX gating only — the SPA bundle is public, so the backend must authorize every data request
- Use layout routes for shared navigation/chrome
- Always validate `useParams` / `useSearchParams` values with Zod before using them
- NEVER hardcode route paths in components — use `PAGE_ROUTES` constants
- NEVER create deeply nested route files — keep pages flat in `src/pages/`; nesting is in the router

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards