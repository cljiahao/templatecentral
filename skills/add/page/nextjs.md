<!-- ref: add/page/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->

# Add a Page

## Inputs

- **Route path** — The URL path (e.g., `/settings`, `/dashboard/analytics`)
- **Route type** — Public or authenticated
- **Has data fetching** — Whether the page loads data

## Steps

### Step 0 — Verify context

Need `<!-- templateCentral: nextjs@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

### 1. Determine the Route Location

| Route type | Location |
|-----------|----------|
| Public page | `src/app/(public)/<path>/page.tsx` |
| Dashboard/authenticated page | `src/app/dashboard/<path>/page.tsx` |

> **Public pages with auth installed:** `src/proxy.ts` redirects every path not in `PUBLIC_PATHS` to `/login`, route group or not. Add the new `PAGE_ROUTES` constant (Step 6) to `PUBLIC_PATHS` there, or the "public" page is login-gated.

> **Dashboard pages require auth.** No `src/app/dashboard/` yet → run `templatecentral:add` (auth) first; it creates the route group.

> `proxy.ts` only gates routing on cookie presence — it is NOT the authoritative check. Every protected route group must additionally `await auth.api.getSession({ headers: await headers() })` in its `layout.tsx` and `redirect()` when null — see `templatecentral:add (auth)` Step 8.

> For API endpoints, use `templatecentral:add (endpoint)`.

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

`export default` is required by Next.js for route files (`page`, `layout`, `loading`, `error`, `not-found`).

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

```tsx
// src/app/dashboard/analytics/error.tsx
'use client';

import { useEffect } from 'react';

import { Button } from '@/components/ui/button';
import { logError } from '@/lib/errors/error-log-handler';

export default function AnalyticsError({ error, reset }: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    logError('dashboard.analytics.error-boundary', error);
  }, [error]);

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-lg font-semibold">Something went wrong</h2>
      {/* digest is the only handle on the server-side stack trace, which Next.js
          strips from production error objects — surface it so users can report it */}
      {error.digest && (
        <p className="text-muted-foreground text-sm">Reference: {error.digest}</p>
      )}
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
```

### 5. Add Not Found (Optional, for Dynamic Routes)

Rendered when the page (or its feature) calls `notFound()` from `next/navigation` for a missing ID.

```tsx
// src/app/dashboard/projects/[id]/not-found.tsx
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

### 7. Validate

```bash
pnpm build
```

Build passes; for a data-fetching page, the loading state renders in the browser.

## Rules

- Add `loading.tsx` to data-fetching routes
- One layout per concern
- Use route groups `(name)/` for shared layouts without URL impact
- NEVER use `'use client'` in `page.tsx` components — prefer server components. Note: `error.tsx` requires `'use client'` (Next.js constraint)
- Keep pages in the `(public)/` or `dashboard/` route groups

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.