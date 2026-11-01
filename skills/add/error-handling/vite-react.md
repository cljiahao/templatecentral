<!-- ref: add/error-handling/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React — Error Handling

### Step 0 — Verify context

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

**1. Error Boundary (Already Wired by the Scaffold — No Changes Required)**

The scaffold already ships `src/components/layout/error-boundary.tsx`, which imports `logError` from `@/lib/errors` and calls `logError('react.error-boundary', error)` in `componentDidCatch(error: Error)`. Do not rewrite it, and do not add a second `logError` import.

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

Async errors are already covered: `src/lib/errors/global-handlers.ts` routes `window.onerror` and `unhandledrejection` through `logError`, registered in `main.tsx`. Leave both alone — a second listener or bootstrap call double-logs every async error.

**3. React Query Error Handler**

> `defaultOptions` match `providers.tsx`; only the cache handlers are new. This singleton replaces that client, so tune options here only.

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

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.