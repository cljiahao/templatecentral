<!-- ref: add/error-handling/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React — Error Handling

**1. Error Boundary (Already Present, Enhanced)**

```tsx
// src/components/layout/error-boundary.tsx
import { Component, type ErrorInfo, type ReactNode } from 'react';
import { logError } from '@/lib/errors/error-log-handler';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    logError('ErrorBoundary caught an error', error);
    if (import.meta.env.DEV) {
      console.error('Component stack:', errorInfo.componentStack);
    }
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-2xl font-bold">Something went wrong</h1>
          <p className="text-muted-foreground max-w-md text-sm">
            {import.meta.env.DEV
              ? this.state.error?.message
              : 'An unexpected error occurred. Please try again later.'}
          </p>
          <button
            type="button"
            onClick={this.handleRetry}
            className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-4 py-2 text-sm font-medium transition-colors"
          >
            Try again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

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
import { QueryClient } from '@tanstack/react-query';
import { logError } from '@/lib/errors/error-log-handler';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      staleTime: 1000 * 60 * 5,
    },
    mutations: {
      onError: (error) => {
        if (error instanceof Error) {
          logError('Mutation failed', error);
        }
      },
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

## Testing / Verification

```bash
# Trigger error boundary
# Implementation included in test examples

pnpm test
pnpm build
```

## See Also

- `shared-add-logging` — Integrate structured logging with error handlers
- `shared-validation-patterns` — Zod/Pydantic schemas for validation errors
- Stack-specific `code-standards` — Security and error handling guidance
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Use error handling in new routes

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards