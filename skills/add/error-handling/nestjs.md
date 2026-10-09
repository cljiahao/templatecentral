<!-- ref: add/error-handling/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS — Error Handling

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

**1. Enhanced HTTP Exception Filter**

This replaces the base scaffold's `HttpExceptionFilter` entirely — the response body shape changes from `{ statusCode, message }` to `{ error, details? }`. Update any existing client code, tests, or Swagger consumers written against the base shape; this is not an additive change.

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
import type { FastifyReply } from 'fastify';
import { ZodSerializationException, ZodValidationException } from 'nestjs-zod';
import { z, ZodError } from 'zod';

interface ErrorResponse {
  error: string;
  details?: {
    fieldErrors?: Record<string, string[]>;
    code?: string;
  };
}

// Fixed client-facing text per status: exception messages can carry internal detail.
const STATUS_ERRORS: Partial<Record<number, ErrorResponse>> = {
  [HttpStatus.BAD_REQUEST]: { error: 'Bad request', details: { code: 'BAD_REQUEST' } },
  [HttpStatus.UNAUTHORIZED]: { error: 'Authentication required' },
  [HttpStatus.FORBIDDEN]: { error: 'Access denied' },
  [HttpStatus.NOT_FOUND]: { error: 'Resource not found' },
  [HttpStatus.CONFLICT]: { error: 'Resource conflict', details: { code: 'CONFLICT' } },
  [HttpStatus.TOO_MANY_REQUESTS]: { error: 'Too many requests' },
};

// A thrower that already built an ErrorResponse (e.g. the allowed-sort-field list from
// `templatecentral:add (pagination)`) keeps it. Nest's built-in bodies also carry `error`,
// so `statusCode` tells them apart.
function isErrorResponse(body: unknown): body is ErrorResponse {
  return typeof body === 'object' && body !== null && 'error' in body && !('statusCode' in body);
}

@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost): void {
    const reply = host.switchToHttp().getResponse<FastifyReply>();
    const status = exception.getStatus();

    if (status >= 500) {
      const zodError: unknown =
        exception instanceof ZodSerializationException ? exception.getZodError() : undefined;
      const detail = zodError instanceof ZodError ? zodError.message : exception.message;
      this.logger.error(`HTTP ${status}: ${detail}`, exception.stack);
    } else {
      this.logger.warn(`HTTP ${status}: ${exception.message}`);
    }

    // ThrottlerGuard already set Retry-After to the real remaining window.
    void reply.status(status).send(this.toErrorResponse(exception, status));
  }

  private toErrorResponse(exception: HttpException, status: number): ErrorResponse {
    const zodError: unknown =
      exception instanceof ZodValidationException ? exception.getZodError() : undefined;
    if (zodError instanceof ZodError) {
      const fieldErrors = z.flattenError(zodError).fieldErrors as Record<string, string[]>;
      return { error: 'Validation failed', details: { fieldErrors, code: 'VALIDATION_ERROR' } };
    }
    // Covers ZodSerializationException: a response-schema mismatch is a server bug.
    if (status >= 500) return { error: 'Internal server error' };

    const body = exception.getResponse();
    if (status === 400 && isErrorResponse(body)) return body;
    return STATUS_ERRORS[status] ?? { error: 'An error occurred' };
  }
}
```

Non-`HttpException` errors bypass this filter and get Nest's default `{ statusCode, message: 'Internal server error' }` — no leak, but a different shape. To unify, add a second `@Catch()` filter that logs the error and sends `{ error: 'Internal server error' }` with 500.

**2. Throwing Errors from Services**

Throw Nest's built-in exceptions (`NotFoundException`, `ConflictException`, …) from services — the filter maps each status to its fixed client message, so the exception text is for logs only. A domain exception is only worth a class when several services share it:

```ts
// src/common/exceptions/app-not-found.exception.ts
// Domain prefix avoids shadowing @nestjs/common's built-in NotFoundException.
import { HttpException, HttpStatus } from '@nestjs/common';

export class AppNotFoundException extends HttpException {
  constructor(message = 'Resource not found') {
    super(message, HttpStatus.NOT_FOUND);
  }
}
```

Document the error statuses each route can return so Swagger consumers see the `{ error, details? }` shape, e.g. on a `GET :id` handler:

```ts
@ApiResponse({ status: 400, description: 'Validation failed' })
@ApiResponse({ status: 404, description: 'Resource not found' })
```

## Validate

```bash
pnpm check && pnpm build && pnpm test && pnpm test:e2e
pnpm start:dev
curl -s -X POST localhost:3000/examples -H 'content-type: application/json' -d '{"name":""}'
# Expect 400 {"error":"Validation failed","details":{"fieldErrors":{"name":[...]},"code":"VALIDATION_ERROR"}}
```

Any test asserting the old `{ statusCode, message }` body must be updated in the same change.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards