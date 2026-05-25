<!-- ref: add/error-handling/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js — Error Handling

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
    fieldErrors?: Record<string, string[]>;
    code?: string;
  };
}

export const handleApiError = (
  label: string,
  error: unknown,
  fieldErrors?: Record<string, string[]>
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
    const fieldErrors = z.flattenError(error).fieldErrors as Record<string, string[]>;
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
import { NextResponse } from 'next/server';
import { z } from 'zod';

const CreateProjectSchema = z.object({
  name: z.string().min(1, 'Name is required').max(100, 'Name must be under 100 characters'),
  description: z.string().max(500).optional(),
});

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const parsed = CreateProjectSchema.safeParse(body);

    if (!parsed.success) {
      return handleApiError(
        'Failed to create project',
        parsed.error,
        z.flattenError(parsed.error).fieldErrors as Record<string, string[]>
      );
    }

    // Your logic here: const [project] = await db.insert(projects).values(parsed.data).returning()
    const project = { id: '1', ...parsed.data };

    return NextResponse.json({ data: project }, { status: 201 });
  } catch (error) {
    return handleApiError('Failed to create project', error);
  }
}
```

**2b. Dynamic Route with Unauthorized Access (404 Pattern)**

Rule #9: Return 404 for both missing resources AND unauthorized access (never reveal whether resource exists):

```ts
// src/app/api/projects/[id]/route.ts
import { auth } from '@/lib/auth';
import { handleApiError } from '@/lib/errors';
import { NextResponse } from 'next/server';

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const session = await auth.api.getSession({ headers: _request.headers });

    // Check project exists AND user has access
    const project = { id, name: 'Sample', ownerId: 'user-1' }; // replace with real DB lookup

    // Return 404 for BOTH missing AND unauthorized (same response)
    // Never say "you don't have access" — could reveal resource exists
    if (!project || project.ownerId !== session?.user?.id) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 });
    }

    return NextResponse.json({ data: project });
  } catch (error) {
    return handleApiError('Failed to fetch project', error);
  }
}
```

**3. Error Boundary Components**

Class-based `ErrorBoundary` for catching synchronous React render errors:

```tsx
// src/components/layout/error-boundary.tsx
'use client';

import { Component, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
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

  render() {
    if (this.state.error) {
      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-2xl font-bold">Something went wrong</h1>
          <p className="text-muted-foreground max-w-md text-sm">
            {process.env.NODE_ENV === 'development'
              ? this.state.error.message
              : 'An unexpected error occurred. Please try again later.'}
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-4 py-2 text-sm font-medium transition-colors"
          >
            Reload page
          </button>
        </div>
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

interface AsyncErrorBoundaryProps {
  children: ReactNode;
}

export function AsyncErrorBoundary({ children }: AsyncErrorBoundaryProps) {
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      setError(new Error(event.reason?.message || 'An error occurred'));
    };

    window.addEventListener('unhandledrejection', handleUnhandledRejection);
    return () => window.removeEventListener('unhandledrejection', handleUnhandledRejection);
  }, []);

  if (error) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
        <h1 className="text-2xl font-bold">Something went wrong</h1>
        <p className="text-muted-foreground max-w-md text-sm">
          {process.env.NODE_ENV === 'development'
            ? error.message
            : 'An unexpected error occurred. Please try again later.'}
        </p>
        <button
          type="button"
          onClick={() => window.location.reload()}
          className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-4 py-2 text-sm font-medium transition-colors"
        >
          Reload page
        </button>
      </div>
    );
  }

  return <>{children}</>;
}
```

## Testing / Verification

```bash
# Test API route with validation error
curl -X POST http://localhost:3000/api/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'

# Expected 400 response:
# {
#   "error": "Validation failed",
#   "details": {
#     "fieldErrors": {
#       "name": ["Name is required"]
#     },
#     "code": "VALIDATION_ERROR"
#   }
# }

pnpm test
pnpm build

# Test error boundary (client-side)
pnpm dev
# Trigger unhandled error in browser console, verify error boundary displays
```

### Next.js Error Boundary Tests

```typescript
// test/error-boundary.test.tsx
// Requires: pnpm add -D @testing-library/react @testing-library/jest-dom jsdom
// Add to vitest.config.ts: environment: 'jsdom' (or use @vitest-environment jsdom comment below)
// @vitest-environment jsdom
import '@testing-library/jest-dom';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from '@/components/layout/error-boundary';

describe('ErrorBoundary', () => {
  it('displays fallback UI when render error occurs', () => {
    const ThrowComponent = () => {
      throw new Error('Test error');
      return null;
    };

    render(
      <ErrorBoundary>
        <ThrowComponent />
      </ErrorBoundary>
    );

    // In development, error message is shown
    if (process.env.NODE_ENV === 'development') {
      expect(screen.getByText(/Test error/)).toBeInTheDocument();
    } else {
      // In production, generic message is shown
      expect(screen.getByText(/unexpected error/i)).toBeInTheDocument();
    }
  });

  it('shows reload button', () => {
    const ThrowComponent = () => {
      throw new Error('Test');
      return null;
    };

    render(
      <ErrorBoundary>
        <ThrowComponent />
      </ErrorBoundary>
    );

    expect(screen.getByRole('button', { name: /reload/i })).toBeInTheDocument();
  });
});
```

## After Writing Code

Dispatch in order:
1. `templatecentral:build` — validate compilation
2. `templatecentral:review` — check code standards