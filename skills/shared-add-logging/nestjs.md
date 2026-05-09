<!-- ref: shared-add-logging/nestjs.md
     loaded-by: shared-add-logging/SKILL.md
     prereq: Stack = NestJS. Do not invoke this file directly — it is loaded at runtime by the shared-add-logging skill. -->
## NestJS — Structured Logging

**What already exists in the template:**
- `nestjs-pino` wired in `app.module.ts` via `LoggerModule.forRoot()`
- `Logger` from `nestjs-pino` injected via DI
- pino-http auto-logs every request/response (Tier 1 request logging is automatic)
- `new Logger('X')` pattern works throughout

#### Tier 1 — Base

pino-http handles request/response logging automatically (method, path, status_code, duration_ms). Add `user_id` to request logs by extending `customProps` in `LoggerModule`:

```ts
// src/app.module.ts  (extend existing LoggerModule.forRoot config)
import { LoggerModule } from 'nestjs-pino';

LoggerModule.forRoot({
  pinoHttp: {
    customProps: (req) => ({
      user_id: (req as any).user?.id ?? null,
    }),
    level: process.env.LOG_LEVEL ?? 'info',
  },
}),
```

Unhandled exceptions — update your `HttpExceptionFilter` (from `shared-add-error-handling`) to add 5xx logging. Replace the existing file:

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
    const reply = ctx.getResponse<FastifyReply>();
    const status = exception.getStatus();

    let errorResponse: ErrorResponse = {
      error: exception.message || 'An error occurred',
    };

    if (exception instanceof ZodSerializationException) {
      const zodError = exception.getZodError();
      if (zodError instanceof ZodError) {
        const fieldErrors = z.flattenError(zodError).fieldErrors as Record<string, string[]>;
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
      void reply.header('Retry-After', '60');
    }

    if (status >= 500) {
      this.logger.error(`HTTP ${status}: ${exception.message}`);
    }

    void reply.status(status).send(errorResponse);
  }
}
```

App startup/shutdown — use NestJS lifecycle hooks:

```ts
// src/main.ts
import { Logger } from 'nestjs-pino';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const logger = app.get(Logger);
  app.useLogger(logger);

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
  logger.log({ port, environment: process.env.NODE_ENV }, 'App started');
}
bootstrap();
```

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — log in your auth guard or Passport strategy:

```ts
// src/common/guards/jwt-auth.guard.ts  (or passport local strategy)
import { Logger } from 'nestjs-pino';
import { Injectable, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly logger: Logger) {
    super();
  }

  handleRequest(err: any, user: any, info: any, context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    if (err || !user) {
      this.logger.warn(
        { path: req.url, required_role: 'authenticated' },
        'Access denied'
      );
      throw err || new UnauthorizedException();
    }
    return user;
  }
}
```

For login/logout events, log in your auth service:

```ts
// src/modules/auth/auth.service.ts
import { Injectable } from '@nestjs/common';
import { Logger } from 'nestjs-pino';
import * as argon2 from 'argon2';

@Injectable()
export class AuthService {
  constructor(private readonly logger: Logger) {}

  async login(user: User, method: string) {
    this.logger.log({ user_id: user.id, method }, 'Login success');
    return this.createToken(user);
  }

  async logout(userId: string) {
    this.logger.log({ user_id: userId }, 'Logout');
  }

  async refreshToken(userId: string) {
    this.logger.log({ user_id: userId }, 'Token refresh');
    // ... return new token
  }

  async validateUser(email: string, password: string) {
    const user = await this.usersService.findByEmail(email);
    if (!user || !(await argon2.verify(user.passwordHash, password))) {
      this.logger.warn(
        { reason: 'invalid_credentials' },
        'Login failure'
        // Never log: email (PII), password
      );
      return null;
    }
    return user;
  }
}
```

**Outbound HTTP calls** — create an interceptor that wraps the outbound handler:

```ts
// src/common/interceptors/outbound-http-logging.interceptor.ts
import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { Observable, tap } from 'rxjs';

@Injectable()
export class OutboundHttpLoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('OutboundHttp');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const start = Date.now();
    return next.handle().pipe(
      tap(() => {
        // Log after the observable completes (response returned from HttpService call)
        this.logger.log({
          event: 'http.outbound',
          duration_ms: Date.now() - start,
        });
      }),
    );
  }
}
```

> **Note**: For more detailed logging (url, status_code), wrap `HttpService.get/post` directly in a service method and time the call there — interceptors do not have access to the outbound URL or response status.

**Key domain events** — log in service methods for state changes:

```ts
// src/modules/projects/projects.service.ts  (example — adapt to your domain)
async createProject(dto: CreateProjectDto, userId: string): Promise<Project> {
  const [project] = await this.drizzle.db
    .insert(projects)
    .values({ ...dto, userId })
    .returning();
  this.logger.log({ user_id: userId, project_id: project.id }, 'Project created');
  return project;
}
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — add a timing wrapper method to `DrizzleService` in `src/database/drizzle.service.ts`:

```ts
// src/database/drizzle.service.ts  (extend existing DrizzleService)
// Add this method to the class body:

async timedQuery<T>(name: string, fn: () => Promise<T>): Promise<T> {
  const start = Date.now();
  const result = await fn();
  const duration = Date.now() - start;
  if (duration > 500) {
    this.logger.warn({ event: 'db.slow_query', name, duration_ms: duration });
    // NEVER log query params — may contain PII or sensitive data
  }
  return result;
}
```

Usage in service methods:

```ts
// src/modules/projects/projects.service.ts
const rows = await this.drizzle.timedQuery('projects.findAll', () =>
  this.drizzle.db.select().from(projects)
);
```

**Sanitized request context** — extend `LoggerModule` `customProps`:

```ts
// src/app.module.ts  (extend pinoHttp customProps)
customProps: (req) => ({
  user_id: (req as any).user?.id ?? null,
  auth_present: !!req.headers['authorization'],
  // Never log: req.headers['authorization'] value
}),
```

**Cache hits/misses** — log in your cache service:

```ts
// src/common/cache/cache.service.ts
async get<T>(key: string): Promise<T | null> {
  const value = await this.redis.get(key);
  this.logger.debug({ cache_key: key, hit: value !== null }, 'Cache lookup');
  return value ? JSON.parse(value) : null;
}
```

---

## Verification

```bash
# Tier 1
pnpm start:dev
curl http://localhost:3000/health
# Expect pino-http JSON log: { req: { method: "GET" }, res: { statusCode: 200 }, responseTime: <n> }

# Tier 2
# Attempt login with wrong credentials — expect login failure log
# Attempt login with correct credentials — expect login success log
# Hit a protected route without a token — expect access denied log

# Tier 3
# Trigger a slow DB query (or lower threshold temporarily to 0 for testing)
# Expect: { query_name: "...", duration_ms: <n> } warn log

# Confirm no prohibited fields
grep -i "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" <log-output>
```

## See Also

- `shared-add-error-handling` — Unified error response schema; `logError` integration
- `shared-validation-patterns` — Zod/Pydantic validation before any log call
- Stack-specific `code-standards` — Logging rules within each stack's security guidelines
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Apply logging when adding new routes

## Production Requirement

Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only is not sufficient; production log storage must be isolated from the application host.

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards
