<!-- ref: add/error-handling/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React — Error Handling

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Error Boundary (Already Wired by the Scaffold — No Changes Required)**

The scaffold already ships `src/components/layout/error-boundary.tsx`, which imports `logError` from `@/lib/errors` and calls `logError('react.error-boundary', error)` in `componentDidCatch(error: Error)`. Do NOT rewrite it and do NOT add a second `logError` import.

Optional — dev-only component-stack logging: add `type ErrorInfo` to the existing `react` import and the `errorInfo` parameter, keeping the existing `logError` call:

```tsx
// src/components/layout/error-boundary.tsx — edit in place
import { Component, type ErrorInfo, type ReactNode } from 'react';

componentDidCatch(error: Error, errorInfo: ErrorInfo) {
  logError('react.error-boundary', error);
  if (ENV.IS_DEV) {
    console.error('Component stack:', errorInfo.componentStack);
  }
}
```

Everything else (state, fallback rendering, retry button) stays as scaffolded.

**2. Async Errors (Complete As Scaffolded — No Changes)**

Async error coverage needs no work. `src/lib/errors/global-handlers.ts` already listens for both `window.onerror` and `unhandledrejection` and already routes each through `logError`, and `registerGlobalErrorHandlers()` is already called in `main.tsx`. Leave the file and the `main.tsx` wiring alone — adding a second listener or a second bootstrap call double-logs every async error.

**3. React Query Error Handler**

> `defaultOptions` match the scaffolded `providers.tsx` client — only the cache handlers are new. This singleton replaces the one `providers.tsx` created, so tune options here only.

```ts
// src/lib/clients/query-client.ts
import { MutationCache, QueryCache, QueryClient } from '@tanstack/react-query';
import { logError } from '@/lib/errors/error-log-handler';

export const queryClient = new QueryClient({
  // Cache-level onError fires for every query/mutation; a per-hook onError would
  // override a defaultOptions handler, and v5 useQuery has no onError at all.
  queryCache: new QueryCache({
    onError: (error, query) => {
      if (error instanceof Error) {
        logError(`Query failed: ${String(query.queryKey[0])}`, error);
      }
    },
  }),
  mutationCache: new MutationCache({
    onError: (error) => {
      if (error instanceof Error) {
        logError('Mutation failed', error);
      }
    },
  }),
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000,
      refetchOnWindowFocus: false,
    },
  },
});
```

Then update `src/components/layout/providers.tsx` to use this singleton instead of creating its own:

```tsx
import { queryClient } from '@/lib/clients/query-client';
import { AuthProvider } from '@/features/auth';
import { QueryClientProvider } from '@tanstack/react-query';
import { type ReactNode } from 'react';
import { Toaster } from 'sonner';

interface ProvidersProps {
  children: ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  return (
    <AuthProvider>
      <QueryClientProvider client={queryClient}>
        {children}
        <Toaster position="top-right" />
      </QueryClientProvider>
    </AuthProvider>
  );
}
```

## Validate

```bash
pnpm test
pnpm build
```

## See Also

- `templatecentral:add` (logging) — Integrate structured logging with error handlers
- `templatecentral:standards` (validation-patterns) — Zod/Pydantic schemas for validation errors
- Stack-specific `code-standards` — Security and error handling guidance
- `templatecentral:add (endpoint)` — Use error handling in new routes

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards