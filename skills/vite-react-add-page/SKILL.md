---
name: vite-react-add-page
description: Use when adding a new URL route, creating a page component, or the user asks to add a page to a Vite + React SPA.
---

# Add a Page

Create a new page/route in a Vite + React project scaffolded from templateCentral.

## Inputs

- **Route path** — The URL path (e.g., `/settings`, `/dashboard/analytics`)
- **Has data fetching** — Whether the page loads data via React Query

## Steps

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

Access params in the page:

```tsx
import { useParams } from 'react-router';

export function ProjectDetailPage() {
  const { id } = useParams<{ id: string }>();
  // ...
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

> **Nested routes**: `PAGE_ROUTES` values must be the **full path**, not the relative segment. For example, if `analytics` is nested under `dashboard` in the router (`<Route path="dashboard"><Route path="analytics" /></Route>`), use `ANALYTICS: '/dashboard/analytics'`.

### 5. Add Navigation (Optional)

Update `src/components/layout/navbar.tsx` to include the new link:

```ts
const NAV_LINKS = [
  // ... existing links
  { label: 'Analytics', href: PAGE_ROUTES.ANALYTICS },
] as const;
```

## React Router Key Concepts

| Concept | Syntax | Example |
|---------|--------|---------|
| Static route | `path="analytics"` | `/analytics` |
| Dynamic segment | `path="projects/:id"` | `/projects/123` |
| Index route | `<Route index />` | Matches parent path exactly |
| Nested routes | `<Route path="parent"><Route path="child" /></Route>` | `/parent/child` |
| Catch-all | `path="*"` | 404 fallback |
| Layout route | `<Route element={<Layout />}>` | Wraps children with shared UI |

### 6. Validate

```bash
pnpm build && pnpm test
```

Confirm the build succeeds with no type errors and all tests pass.

## Rules

- Always add to `src/pages/index.ts` barrel export
- Always add to `src/lib/constants/routes.ts`
- Always add the `<Route>` in `src/router.tsx` — the page won't be accessible otherwise
- Protected pages MUST be nested inside `<Route element={<ProtectedRoute />}>` in `src/router.tsx` — otherwise unauthenticated users can access them
- Use layout routes for shared navigation/chrome
- NEVER hardcode route paths in components — use `PAGE_ROUTES` constants
- NEVER create deeply nested route files — keep pages flat in `src/pages/`; nesting is in the router
