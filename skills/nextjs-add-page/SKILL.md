---
name: nextjs-add-page
description: Use when adding a new URL route, creating a public or dashboard page, or the user asks to add a page with loading/error states in a Next.js app.
---

# Add a Page

Create a new page/route in a Next.js project scaffolded from templateCentral.

## Prerequisites

Requires a project scaffolded with `templatecentral:nextjs-scaffold`. See Step 0.

## Inputs

- **Route path** — The URL path (e.g., `/settings`, `/dashboard/analytics`)
- **Route type** — Public or authenticated
- **Has data fetching** — Whether the page loads data

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Determine the Route Location

| Route type | Location |
|-----------|----------|
| Public page | `src/app/(public)/<path>/page.tsx` |
| Dashboard/authenticated page | `src/app/dashboard/<path>/page.tsx` |

> **Dashboard pages require auth.** If `src/app/dashboard/` does not exist yet, run the `nextjs-add-auth` skill first — it creates the dashboard route group along with the full auth stack.

> Dashboard pages are automatically protected by `src/proxy.ts` once auth is configured — any route not in `PUBLIC_PATHS` requires authentication. No manual auth checks needed in page components.

> For API endpoints, use the `add-api-route` skill.

Use **route groups** `(name)/` to share layouts without affecting the URL.
Use **folders** `name/` when the folder should be a URL segment.
Use **dynamic segments** `[param]/` for resource IDs.

### 2. Create the Page File

Pages should be thin — compose from features/ and components/:

```tsx
// src/app/dashboard/analytics/page.tsx
import { AnalyticsDashboard } from '@/features/analytics';

export default function AnalyticsPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <AnalyticsDashboard />
    </div>
  );
}
```

Note: `export default` is required by Next.js for pages.

### 3. Add a Loading State (Required for Data-Fetching Pages)

Always add `loading.tsx` alongside pages that fetch data. If `skeleton` is not yet installed, run `npx shadcn@latest add skeleton` first.

```tsx
// src/app/dashboard/analytics/loading.tsx
import { Skeleton } from '@/components/ui/skeleton';

export default function AnalyticsLoading() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <Skeleton className="h-9 w-48" />
      <Skeleton className="mt-4 h-64 w-full" />
    </div>
  );
}
```

### 4. Add Error Handling (Optional)

The `error` prop contains the thrown error (with an optional `digest` for server errors). The `reset` function re-renders the route segment.

```tsx
// src/app/dashboard/analytics/error.tsx
'use client';

import { Button } from '@/components/ui/button';

export default function AnalyticsError({ error, reset }: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-lg font-semibold">Something went wrong</h2>
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
```

### 5. Add Not Found (Optional, for Dynamic Routes)

```tsx
// src/app/dashboard/[id]/not-found.tsx
export default function ProjectNotFound() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center">
      <h2>Project not found</h2>
    </div>
  );
}
```

### 6. Update Routes Constant

Add the new route to `src/lib/constants/routes.ts`:

```ts
export const PAGE_ROUTES = {
  // ... existing routes
  ANALYTICS: '/dashboard/analytics',
} as const;
```

## Next.js Special Files Reference

| File | Purpose |
|------|---------|
| `layout.tsx` | Persistent UI wrapping child routes (shared across navigations) |
| `page.tsx` | Unique UI for a route segment |
| `template.tsx` | Like layout but re-mounts on navigation (for transitions) |
| `loading.tsx` | Suspense loading fallback |
| `error.tsx` | Error boundary |
| `not-found.tsx` | 404 UI |

### 7. Validate

```bash
pnpm build
```

Confirm the build succeeds with no type errors. If adding a data-fetching page, verify the loading state renders correctly in the browser.

## Rules

- Always add `loading.tsx` for data-fetching routes — omitting causes a blank screen
- One layout per concern — NEVER nest multiple layouts unless each serves a distinct purpose
- Use route groups `(name)/` for shared layouts without URL impact
- NEVER use `'use client'` in `page.tsx` components — prefer server components. Note: `error.tsx` requires `'use client'` (Next.js constraint)
- NEVER create pages outside the established route groups (`(public)/` or `dashboard/`) without reason

## Validate

```bash
pnpm build    # zero errors
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
