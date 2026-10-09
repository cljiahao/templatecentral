<!-- ref: add/error-handling/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js — Error Handling

### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Global Error Handler (Already Present)**

The template includes `src/lib/errors/handle-api-error.ts`. Enhance it to include field-level details:

```ts
// src/lib/errors/handle-api-error.ts
import { APIError } from '@/integrations/error';
import { logError } from '@/lib/errors/error-log-handler';
import { NextResponse } from 'next/server';
import { z, ZodError } from 'zod';

const STATUS_MESSAGES: Record<number, string> = {
  400: 'Invalid request',
  401: 'Authentication required',
  403: 'Access denied',
  404: 'Resource not found',
  408: 'Request timed out',
  409: 'Conflict',
  429: 'Too many requests',
  500: 'Internal server error',
  502: 'Service temporarily unavailable',
  503: 'Service temporarily unavailable',
};

interface ErrorResponseBody {
  error: string;
  details?: {
    fieldErrors?: Record<string, string[] | undefined>;
    code?: string;
  };
}

export const handleApiError = (
  label: string,
  error: unknown,
  fieldErrors?: Record<string, string[] | undefined>
): NextResponse<ErrorResponseBody> => {
  logError(label, error);

  if (error instanceof APIError) {
    const status = error.statusCode;
    const message = STATUS_MESSAGES[status] ?? label;
    const response: ErrorResponseBody = { error: message };

    if (fieldErrors) {
      response.details = { fieldErrors };
    }

    return NextResponse.json(response, { status });
  }

  if (error instanceof ZodError) {
    const fieldErrors = z.flattenError(error).fieldErrors;
    return NextResponse.json(
      {
        error: 'Validation failed',
        details: { fieldErrors, code: 'VALIDATION_ERROR' },
      },
      { status: 400 }
    );
  }

  return NextResponse.json(
    { error: label },
    { status: 500 }
  );
};
```

**2. API Route Example with Validation**

```ts
// src/app/api/projects/route.ts
import { handleApiError } from '@/lib/errors';
import { withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';
import { z } from 'zod';

const CreateProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name must be under 100 characters'),
  description: z.string().max(500).optional(),
});

export const POST = withLogging(async (request) => {
  try {
    // Malformed JSON parses to null so it fails validation (400) instead of hitting the 500 path.
    const body: unknown = await request.json().catch(() => null);
    const parsed = CreateProjectSchema.safeParse(body);
    if (!parsed.success) {
      return handleApiError('Failed to create project', parsed.error);
    }

    // Placeholder — replace with the data layer from `templatecentral:add (database)`.
    const project = { id: crypto.randomUUID(), ...parsed.data };

    return NextResponse.json({ data: project }, { status: 201 });
  } catch (error) {
    return handleApiError('Failed to create project', error);
  }
});
```

**2b. Dynamic Route with Unauthorized Access (404 Pattern)**

No session → 401. Missing resource **and** someone else's resource → the same 404, so the response never confirms the ID exists:

```ts
// src/app/api/projects/[id]/route.ts
// Your data-layer lookup; must return the row or null.
import { findProjectById } from '@/integrations/database/queries/find-project';
import { auth } from '@/lib/auth';
import { handleApiError } from '@/lib/errors';
import { type RouteContext, withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';

export const GET = withLogging<RouteContext<{ id: string }>>(async (request, { params }) => {
  try {
    const session = await auth.api.getSession({ headers: request.headers });
    if (!session) return new Response(null, { status: 401 });

    const { id } = await params;
    const project = await findProjectById(id);

    if (!project || project.ownerId !== session.user.id) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }

    return NextResponse.json({ data: project });
  } catch (error) {
    return handleApiError('Failed to fetch project', error);
  }
});
```

**3. Error Boundary Components**

Route-segment render errors are already handled by `src/app/error.tsx` (scaffold) and per-route `error.tsx` (`templatecentral:add (page)`). Add the boundaries below only for component-level isolation inside a page or for unhandled promise rejections. Both share one fallback:

```tsx
// src/components/layout/error-fallback.tsx
'use client';

import { Button } from '@/components/ui/button';

interface ErrorFallbackProps {
  error: Error;
  onReset: () => void;
}

export function ErrorFallback({ error, onReset }: ErrorFallbackProps) {
  return (
    <div
      role="alert"
      className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center"
    >
      <h1 className="text-2xl font-bold">Something went wrong</h1>
      <p className="text-muted-foreground max-w-md text-sm">
        {process.env.NODE_ENV === 'development'
          ? error.message
          : 'An unexpected error occurred. Please try again later.'}
      </p>
      <Button type="button" onClick={onReset}>
        Reload page
      </Button>
    </div>
  );
}
```

Class-based `ErrorBoundary` for catching synchronous React render errors:

```tsx
// src/components/layout/error-boundary.tsx
'use client';

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { logError } from '@/lib/errors/error-log-handler';
import { ErrorFallback } from './error-fallback';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  // getDerivedStateFromError only updates state — reporting belongs here, or every
  // caught render error is swallowed and never reaches the logger.
  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    logError('ErrorBoundary caught an error', error);
    if (process.env.NODE_ENV === 'development') {
      console.error('Component stack:', errorInfo.componentStack);
    }
  }

  render() {
    if (this.state.error) {
      if (this.props.fallback) return this.props.fallback;

      return (
        <ErrorFallback error={this.state.error} onReset={() => window.location.reload()} />
      );
    }

    return this.props.children;
  }
}
```

Functional `AsyncErrorBoundary` for catching unhandled promise rejections:

```tsx
// src/components/layout/error-boundary-async.tsx
'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { ErrorFallback } from './error-fallback';

interface AsyncErrorBoundaryProps {
  children: ReactNode;
}

export function AsyncErrorBoundary({ children }: AsyncErrorBoundaryProps) {
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      const reason: unknown = event.reason;
      setError(reason instanceof Error ? reason : new Error('An error occurred'));
    };

    window.addEventListener('unhandledrejection', handleUnhandledRejection);
    return () => window.removeEventListener('unhandledrejection', handleUnhandledRejection);
  }, []);

  if (error) {
    return <ErrorFallback error={error} onReset={() => window.location.reload()} />;
  }

  return <>{children}</>;
}
```

## Validate

```bash
# Expect 400 {"error":"Validation failed","details":{"fieldErrors":{"name":["Name is required"]},"code":"VALIDATION_ERROR"}}
curl -X POST http://localhost:3000/api/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'
pnpm test
pnpm build
```

### Next.js Error Boundary Tests

> **Deps not in scaffold**: run `pnpm add -D @testing-library/react @testing-library/jest-dom jsdom` (or `templatecentral:add (test)`). The `@vitest-environment jsdom` docblock keeps the scaffold's `node` default for API tests.

```typescript
// test/error-boundary.test.tsx
// @vitest-environment jsdom
import '@testing-library/jest-dom';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from '@/components/layout/error-boundary';

const Thrower = () => {
  throw new Error('internal detail');
};

describe('ErrorBoundary', () => {
  // Vitest runs with NODE_ENV=test, so the production (generic) message path is exercised.
  it('renders the generic fallback without leaking the error message', () => {
    render(
      <ErrorBoundary>
        <Thrower />
      </ErrorBoundary>
    );

    expect(screen.getByText(/unexpected error/i)).toBeInTheDocument();
    expect(screen.queryByText(/internal detail/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /reload/i })).toBeInTheDocument();
  });
});
```

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards