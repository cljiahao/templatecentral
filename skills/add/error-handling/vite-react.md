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

**1. Error Boundary (Already Present — Wire in `logError`)**

The scaffold already ships `src/components/layout/error-boundary.tsx`. Do NOT rewrite it — apply this small delta so caught errors go through the central error logger:

The scaffolded file already imports `ErrorInfo` and defines `componentDidCatch` — only the `logError` import is new.

```tsx
// src/components/layout/error-boundary.tsx
import { logError } from '@/lib/errors/error-log-handler';    // new import

// Replace the existing componentDidCatch with:
componentDidCatch(error: Error, errorInfo: ErrorInfo) {
  logError('ErrorBoundary caught an error', error);
  if (import.meta.env.DEV) {
    console.error('Component stack:', errorInfo.componentStack);
  }
}
```

Everything else (state, fallback rendering, retry button) stays as scaffolded.

**2. Async Error Handler**

```ts
// src/lib/errors/async-error-handler.ts
import { logError } from './error-log-handler';

export function setupAsyncErrorHandler() {
  window.addEventListener('unhandledrejection', (event) => {
    const error = event.reason;
    logError('Unhandled promise rejection', error instanceof Error ? error : new Error(String(error)));
  });
}

// src/main.tsx
import { setupAsyncErrorHandler } from '@/lib/errors/async-error-handler';
setupAsyncErrorHandler();
```

**3. React Query Error Handler**

```ts
// src/lib/clients/query-client.ts
import { MutationCache, QueryClient } from '@tanstack/react-query';
import { logError } from '@/lib/errors/error-log-handler';

export const queryClient = new QueryClient({
  // MutationCache onError always fires — a per-mutation onError would silently
  // replace a handler placed in defaultOptions.mutations.onError.
  mutationCache: new MutationCache({
    onError: (error) => {
      if (error instanceof Error) {
        logError('Mutation failed', error);
      }
    },
  }),
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 1000 * 60 * 5,
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

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards