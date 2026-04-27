---
name: add-error-handling
description: Use to add consistent error handling and response schemas across all stacks — covers unified error responses, security boundaries, logging integration, and per-stack implementation patterns.
---

# Add Error Handling & Boundaries

Implement consistent, secure error handling across your stack. All errors return a unified response schema with appropriate HTTP status codes. Errors are logged server-side with context; sensitive details are never exposed to clients in production.

## When to Use

- Adding a new API route or endpoint that needs error handling
- Enhancing existing error handling to be more consistent or secure
- Integrating logging with error responses
- Setting up error boundary components for client-side error UI

## Security Checklist

- [ ] **Stack traces never exposed** — Production responses exclude file paths, line numbers, and internal error chains
- [ ] **Sensitive fields protected** — No API keys, tokens, database URLs, or internal identifiers in error responses
- [ ] **Field-level validation errors only** — User-facing 400 errors include field names and messages, never raw query/filter values
- [ ] **SQL injection prevention** — No user input echoed in error messages; Zod/Pydantic validates before ORM parameterization
- [ ] **Path traversal prevention** — File validation errors check `../` patterns; never log raw file paths from user input
- [ ] **Auth bypass prevention** — 401/403 responses do not reveal whether resource exists; "Not found" for both missing and unauthorized resources
- [ ] **Rate limit headers included** — 429 responses include `Retry-After` header; no stack traces
- [ ] **Unhandled exceptions caught globally** — No raw exception objects returned; all errors go through unified handler
- [ ] **Logging excludes request bodies** — Never log raw `request.json()` or form data; log only status, path, duration, user ID
- [ ] **Environment-based detail levels** — Development: include stack traces; Production: generic messages only

## Unified Error Response Schema

All errors return this shape (regardless of stack):

**Success response:** (status 200, 201, etc.)
```json
{
  "data": { /* actual response */ }
}
```

**Error response:** (status 400, 401, 404, 500, etc.)
```json
{
  "error": "User-facing error message",
  "details": {
    "fieldErrors": {
      "email": ["Must be a valid email"],
      "password": ["Minimum 8 characters"]
    },
    "code": "VALIDATION_ERROR"
  }
}
```

**Schema breakdown:**
- `error` — Human-readable, user-facing message (always present)
- `details` — Optional object with:
  - `fieldErrors` — Object mapping field names to error arrays (for validation errors only)
  - `code` — Machine-readable error code (e.g., `NOT_FOUND`, `UNAUTHORIZED`, `RATE_LIMIT_EXCEEDED`)

**HTTP Status Codes:**
- **400 Bad Request** — Validation failed, malformed JSON, missing required fields
- **401 Unauthorized** — No authentication, invalid credentials, expired token
- **403 Forbidden** — Authenticated but lacks permission for this resource
- **404 Not Found** — Resource doesn't exist (also used for unauthorized resource access)
- **408 Request Timeout** — Request took too long
- **409 Conflict** — Resource already exists, state conflict, constraint violation
- **429 Too Many Requests** — Rate limited; include `Retry-After` header
- **500 Internal Server Error** — Unhandled exception, database error, external service failure
- **502/503 Bad Gateway/Service Unavailable** — External dependency down

## Rules

1. **All user input must be validated before use** — Never trust raw `request.json()`, `request.params`, or `request.query`
2. **Validation errors must be field-level** — Map Zod/Pydantic errors to field names, not raw validation paths
3. **Custom exceptions allowed** — Raise domain-specific exceptions (e.g., `NotFoundError`, `ValidationError`); catch once in global handler
4. **Rate-limit 429 errors must include Retry-After header** — Enables smart client-side backoff
5. **Errors must be logged server-side** — Include requestId, userId, method, path, statusCode, duration; exclude request bodies and sensitive fields
6. **Production never exposes stack traces** — Check `NODE_ENV`, `ENVIRONMENT`, or Python `DEBUG` setting
7. **Unhandled exceptions must be caught globally** — Every stack has a catch-all handler that logs and returns 500
8. **Client receives generic 500 messages** — Detailed error information stays in server logs only
9. **404 for both missing and unauthorized resources** — Never reveal whether a resource exists if user lacks access

## Implementation

### Next.js

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

    // Your logic here: await prisma.project.create({ data: parsed.data })
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
import { auth } from '@/auth';
import { handleApiError } from '@/lib/errors';
import { NextResponse } from 'next/server';

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const session = await auth();

    // Check project exists AND user has access
    // (In real app: const project = await prisma.project.findUnique({ where: { id } }))
    const project = { id, name: 'Sample', ownerId: 'user-1' };

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

**3. Error Boundary Component**

```tsx
// src/components/layout/error-boundary-async.tsx
'use client';

import { useEffect, useState } from 'react';

interface AsyncErrorBoundaryProps {
  children: React.ReactNode;
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

### FastAPI

**1. Global Exception Handlers (Already Present)**

The template includes `src/error_handler.py`. Enhance it to return consistent field-level errors:

```python
# src/error_handler.py
from typing import Any, Sequence

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette import status

from core.exceptions import InvalidInputError, NoResultsFound
from core.logging import logger

INTERNAL_SERVER_ERROR_DETAIL = "Internal Server Error"


def _sanitize_errors(errors: Sequence[Any]) -> dict[str, list[str]]:
    """Convert Pydantic validation errors to field-level format.
    
    Returns:
      Dict mapping field names to lists of error messages.
    """
    field_errors: dict[str, list[str]] = {}
    for err in errors:
        loc = err.get('loc', [])
        msg = err.get('msg', 'Invalid value')
        
        # loc is a tuple like ('body', 'email') or ('query', 'limit')
        # Extract the field name (skip 'body', 'query', 'path' prefixes)
        if len(loc) > 1:
            field_name = loc[-1]
        elif len(loc) == 1:
            field_name = loc[0]
        else:
            field_name = 'unknown'
        
        if field_name not in field_errors:
            field_errors[field_name] = []
        field_errors[field_name].append(msg)
    
    return field_errors


def configure_exceptions(app: FastAPI) -> None:
    """Register exception handlers so all errors are handled in one place."""

    @app.exception_handler(InvalidInputError)
    async def invalid_input_handler(
        request: Request, exc: InvalidInputError
    ) -> JSONResponse:
        logger.warning(
            "Invalid input",
            extra={"path": request.url.path, "detail": str(exc), "code": "INVALID_INPUT"},
        )
        # Allow services to attach field-level errors to the exception
        field_errors = getattr(exc, 'field_errors', {})
        content = {
            "error": str(exc),
            "details": {"code": "INVALID_INPUT"}
        }
        if field_errors:
            content["details"]["fieldErrors"] = field_errors
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=content,
        )

    @app.exception_handler(NoResultsFound)
    async def no_results_handler(
        request: Request, exc: NoResultsFound
    ) -> JSONResponse:
        logger.warning(
            "No results found",
            extra={"path": request.url.path, "detail": str(exc), "code": "NOT_FOUND"},
        )
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"error": str(exc), "details": {"code": "NOT_FOUND"}},
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": exc.detail},
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        field_errors = _sanitize_errors(exc.errors())
        logger.warning(
            "Request validation error",
            extra={"path": request.url.path, "code": "VALIDATION_ERROR"},
        )
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": "Validation failed",
                "details": {"fieldErrors": field_errors, "code": "VALIDATION_ERROR"},
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        logger.exception(
            "Unhandled exception",
            extra={"path": request.url.path, "code": "INTERNAL_ERROR"},
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": INTERNAL_SERVER_ERROR_DETAIL},
        )
```

**2. API Endpoint Example**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, status
from pydantic import BaseModel, Field

from core.exceptions import InvalidInputError
from error_handler import configure_exceptions

router = APIRouter(prefix="/projects", tags=["projects"])


class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_project(req: CreateProjectRequest) -> dict:
    """Create a new project.
    
    Pydantic automatically validates and returns 422 on invalid input.
    """
    # Your logic: project = await db.projects.insert(req.model_dump())
    project = {"id": "1", **req.model_dump()}
    return project


@router.get("/{project_id}")
async def get_project(project_id: str) -> dict:
    """Get a project by ID."""
    if not project_id:
        raise InvalidInputError("Project ID is required")
    
    # Your logic: project = await db.projects.find_by_id(project_id)
    project = {"id": project_id, "name": "Sample Project"}
    
    if not project:
        from core.exceptions import NoResultsFound
        raise NoResultsFound("Project not found")
    
    return project
```

**2b. Main App Setup (Required Integration)**

Register exception handlers in your FastAPI app:

```python
# src/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from error_handler import configure_exceptions

app = FastAPI(title="My API")

# Register all exception handlers first
configure_exceptions(app)

# Then add other middleware/routes
# CORS: never use ["*"] with allow_credentials=True — forbidden by the CORS spec.
# Use explicit origins and methods. In the FastAPI template, configure_cors() in
# src/app.py handles this correctly using api_settings.ALLOWED_CORS.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # explicit origins required with credentials
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

# Include routers
from api.projects.routes import router as projects_router
app.include_router(projects_router)

@app.get('/health')
def health():
    return {'status': 'ok'}

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)
```

### NestJS

**1. Enhanced HTTP Exception Filter**

```ts
// src/common/filters/http-exception.filter.ts
import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Response } from 'express';
import { ZodSerializationException } from 'nestjs-zod';
import { z, ZodError } from 'zod';

interface ErrorResponse {
  error: string;
  details?: {
    fieldErrors?: Record<string, string[]>;
    code?: string;
  };
}

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const status = exception.getStatus();

    let errorResponse: ErrorResponse = {
      error: exception.message || 'An error occurred',
    };

    // Handle Zod validation errors
    if (exception instanceof ZodSerializationException) {
      const zodError = exception.getZodError();
      if (zodError instanceof ZodError) {
        const fieldErrors = z.flattenError(zodError)
          .fieldErrors as Record<string, string[]>;
        errorResponse = {
          error: 'Validation failed',
          details: { fieldErrors, code: 'VALIDATION_ERROR' },
        };
        this.logger.warn(`Validation error: ${zodError.message}`);
      }
    } else if (status === HttpStatus.BAD_REQUEST) {
      errorResponse.details = { code: 'BAD_REQUEST' };
    } else if (status === HttpStatus.UNAUTHORIZED) {
      errorResponse = { error: 'Authentication required' };
    } else if (status === HttpStatus.FORBIDDEN) {
      errorResponse = { error: 'Access denied' };
    } else if (status === HttpStatus.NOT_FOUND) {
      errorResponse = { error: 'Resource not found' };
    } else if (status === HttpStatus.CONFLICT) {
      errorResponse.details = { code: 'CONFLICT' };
    } else if (status === HttpStatus.TOO_MANY_REQUESTS) {
      errorResponse = { error: 'Too many requests' };
      // Set Retry-After header for rate limit (client uses for backoff)
      response.setHeader('Retry-After', '60');
    }

    this.logger.log(
      `HTTP ${status}: ${exception.message}`,
      'HttpExceptionFilter'
    );

    response.status(status).json(errorResponse);
  }
}
```

**2. Custom Exception Example**

```ts
// src/common/exceptions/not-found.exception.ts
import { HttpException, HttpStatus } from '@nestjs/common';

export class NotFoundException extends HttpException {
  constructor(message: string = 'Resource not found') {
    super(message, HttpStatus.NOT_FOUND);
  }
}

// src/modules/projects/projects.service.ts
import { Injectable } from '@nestjs/common';
import { NotFoundException } from '@/common/exceptions/not-found.exception';

@Injectable()
export class ProjectsService {
  async getProject(id: string) {
    // const project = await this.prisma.project.findUnique({ where: { id } });
    const project = null; // Simulated
    
    if (!project) {
      throw new NotFoundException('Project not found');
    }
    
    return project;
  }
}
```

**3. API Route with Validation**

```ts
// src/modules/projects/projects.controller.ts
import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
import { ProjectsService } from './projects.service';

const CreateProjectSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

class CreateProjectDto extends createZodDto(CreateProjectSchema) {}

@ApiTags('projects')
@Controller('projects')
export class ProjectsController {
  constructor(private readonly service: ProjectsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new project' })
  @ApiResponse({ status: 201, description: 'Project created' })
  @ApiResponse({ status: 400, description: 'Validation failed' })
  async create(@Body() dto: CreateProjectDto) {
    return await this.service.createProject(dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get project by ID' })
  @ApiResponse({ status: 200, description: 'Project found' })
  @ApiResponse({ status: 404, description: 'Project not found' })
  async getById(@Param('id') id: string) {
    return await this.service.getProject(id);
  }
}
```

### Vite + React

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
    logError('ErrorBoundary caught an error', {
      message: error.message,
      stack: import.meta.env.DEV ? error.stack : undefined,
      componentStack: errorInfo.componentStack,
    });
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
    logError('Unhandled promise rejection', {
      message: error?.message || String(error),
      stack: import.meta.env.DEV ? error?.stack : undefined,
    });
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
          logError('Mutation failed', {
            message: error.message,
            stack: import.meta.env.DEV ? error.stack : undefined,
          });
        }
      },
    },
  },
});
```

## Testing / Verification

### Next.js

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
import { render, screen } from '@testing-library/react';
import { AsyncErrorBoundary } from '@/components/layout/error-boundary-async';

describe('AsyncErrorBoundary', () => {
  it('displays fallback UI when error occurs', async () => {
    // Trigger unhandled rejection
    const ThrowComponent = () => {
      throw new Error('Test error');
    };

    render(
      <AsyncErrorBoundary>
        <ThrowComponent />
      </AsyncErrorBoundary>
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
    };

    render(
      <AsyncErrorBoundary>
        <ThrowComponent />
      </AsyncErrorBoundary>
    );

    expect(screen.getByRole('button', { name: /reload/i })).toBeInTheDocument();
  });
});
```

### FastAPI

```bash
# Test endpoint with validation error
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'

# Expected 422 response includes fieldErrors mapping

pytest -v
```

### NestJS

```bash
# Test controller validation
pnpm test

# Check Swagger docs at /api/docs includes error schemas
pnpm start:dev
```

### Vite + React

```bash
# Trigger error boundary
# Implementation included in test examples

pnpm test
pnpm build
```

## See Also

- `shared/add-logging` — Integrate structured logging with error handlers
- `shared/validation-patterns` — Zod/Pydantic schemas for validation errors
- Stack-specific `code-standards` — Security and error handling guidance
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Use error handling in new routes
