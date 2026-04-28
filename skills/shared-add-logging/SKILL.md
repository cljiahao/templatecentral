---
name: shared-add-logging
description: Use to wire structured, JSON-formatted logging into any templateCentral project — covers three cumulative tiers (base, standard, verbose), per-stack wiring locations, and a hardcoded prohibition list for sensitive data.
---

# Add Structured Logging

Wire structured JSON logging into your project at the right level of detail. All stacks emit machine-readable logs with consistent field names. Sensitive data is never logged, regardless of tier.

## When to Use

- Setting up logging from scratch after scaffolding a new project
- Upgrading from `console.log` / `print` statements to structured logging
- Adding auth event tracking, outbound HTTP observability, or slow-query detection
- Reviewing logging coverage before a production deployment

## First: One Question

Before writing any code, ask the user:

> **What logging tier do you need?**
> - **Tier 1 — Base**: Endpoint request/response, unhandled exceptions, app startup/shutdown
> - **Tier 2 — Standard** *(default)*: Tier 1 + auth events, outbound HTTP calls, key domain events
> - **Tier 3 — Verbose**: Tier 1 + 2 + slow DB queries (>500 ms), sanitized request context, cache hits/misses
>
> Press Enter to accept Tier 2, or type 1 or 3.

Do not ask any other questions. Implement the chosen tier (and all lower tiers, since tiers are cumulative).

## Hardcoded Prohibitions — Never Log These

Regardless of tier, environment, or log level, these fields **must never appear** in log output:

- **Passwords** — in any form (plain, hashed, bcrypt)
- **Tokens** — access tokens, refresh tokens, JWTs, session tokens, CSRF tokens
- **API keys and secrets** — third-party credentials, signing keys, webhook secrets
- **PII (raw)** — email address, full name, phone number, postal address
- **Full request or response bodies** — log field names and counts at most, never raw content
- **Credit card numbers or financial identifiers** — PAN, CVV, bank account numbers
- **SQL query text** — log only the query name or label, never the SQL string or bound parameters
- **Authorization header value** — log `auth_present: true/false` only; never the header value

## Tiers (Cumulative)

Each tier adds to all lower tiers. Implementing Tier 3 means implementing Tier 1 + Tier 2 + Tier 3.

### Tier 1 — Base (always included)

| Event | Required fields |
|-------|----------------|
| Endpoint request/response | `method`, `path`, `status_code`, `duration_ms` |
| Unhandled exception | `path`, `error` (message only), full stack trace (server-side only) |
| App startup | `port`, `environment` |
| App shutdown | `environment` |

### Tier 2 — Standard (default; includes Tier 1)

| Event | Required fields |
|-------|----------------|
| Login success | `user_id`, `method` (e.g. `"password"`, `"oauth"`) |
| Login failure | `reason`, `ip` — **no password** |
| Logout | `user_id` |
| Token refresh | `user_id` |
| Access denied | `user_id`, `path`, `required_role` |
| Outbound HTTP call | `method`, `url` (sanitized — strip query secrets), `status_code`, `duration_ms` |
| Key domain events | One log call per service method that causes a significant state change |

### Tier 3 — Verbose (includes Tier 1 + Tier 2)

| Event | Required fields |
|-------|----------------|
| Slow DB query (>500 ms) | `query_name`, `duration_ms` — **no SQL text** |
| Sanitized request context | `method`, `path`, headers presence only (`auth_present: true/false`) |
| Cache hit/miss | `cache_key`, `hit` (boolean) |

## Environment Variable

Log level is configured per stack:

- **NestJS**: reads `LOG_LEVEL` env var (default: `info`). Valid values: `trace`, `debug`, `info`, `warn`, `error`, `fatal`. Set in `.env`: `LOG_LEVEL=info`
- **Next.js**: reads `LOG_LEVEL` env var (default: `info`). Valid values: `trace`, `debug`, `info`, `warn`, `error`, `fatal`. Set in `.env.local`: `LOG_LEVEL=info`
- **FastAPI**: log level is configured per-environment in `src/core/json/logging.json` (`dev`=DEBUG, `uat`/`prod`=INFO). No `LOG_LEVEL` env var — the `ENVIRONMENT` variable selects the log level profile.

---

## Implementation

### Next.js

**What already exists in the template:**
- `pino` in `package.json` dependencies
- `src/lib/logger.ts` — singleton pino logger
- `src/lib/utils/with-logging.ts` — `withLogging` HOF
- `src/lib/errors/error-log-handler.ts` — `logError` using pino

#### Tier 1 — Base

Wrap every route handler with `withLogging`. It logs `method`, `path`, `status_code`, `duration_ms` (one argument — the handler function), and catches unhandled exceptions automatically.

```ts
// src/app/api/health/route.ts  (already done in template — follow this pattern)
import { withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';

export const GET = withLogging(async () => {
  return NextResponse.json({ status: 'ok' });
});
```

App startup is logged in `src/app/api/health/route.ts`; add an explicit startup log in `src/instrumentation.ts` (Next.js instrumentation hook):

```ts
// src/instrumentation.ts
import { logger } from '@/lib/logger';

export async function register() {
  logger.info(
    { port: process.env.PORT ?? 3000, environment: process.env.NODE_ENV },
    'App starting'
  );
}
```

Unhandled exceptions are already captured by `logError` in `src/lib/errors/error-log-handler.ts`. No extra wiring needed for Tier 1.

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — add logging inside `src/auth.ts` callbacks:

```ts
// src/auth.ts  (extend existing NextAuth config)
import { logger } from '@/lib/logger';

export const { handlers, auth, signIn, signOut } = NextAuth({
  // ...existing config...
  callbacks: {
    async jwt({ token, trigger }) {
      // Only log token refresh when explicitly triggered — NOT on every auth() call
      // WARNING: session callback fires on EVERY auth() call; do NOT log token refresh there
      if (trigger === 'update') {
        logger.info({ event: 'auth.token_refresh', user_id: token?.sub }, 'Token refresh');
      }
      return token;
    },
    async signIn({ user, account }) {
      logger.info(
        { user_id: user.id, method: account?.provider ?? 'credentials' },
        'Login success'
      );
      return true;
    },
  },
  events: {
    async signOut({ token }) {
      logger.info({ user_id: token?.sub }, 'Logout');
    },
  },
});
```

For login failures, add in the `authorize` callback (credentials provider):

```ts
// inside CredentialsProvider authorize()
if (!user) {
  logger.warn({ reason: 'invalid_credentials', ip: req?.headers?.['x-forwarded-for'] ?? 'unknown' }, 'Login failure');
  return null;
}
```

For access denied, log in auth middleware / route guard:

```ts
// src/app/api/admin/route.ts — example protected route
import { auth } from '@/auth';
import { logger } from '@/lib/logger';
import { NextResponse } from 'next/server';

export const GET = withLogging(async (req) => {
  const session = await auth();
  if (!session?.user) {
    logger.warn({ user_id: session?.user?.id, path: '/api/admin', required_role: 'admin' }, 'Access denied');
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
  // ...
});
```

**Outbound HTTP calls** — create a fetch wrapper in `src/integrations/clients/`:

```ts
// src/integrations/clients/http-client.ts
import { logger } from '@/lib/logger';

function sanitizeUrl(url: string): string {
  try {
    const u = new URL(url);
    // Remove query params that might contain secrets
    u.search = '';
    return u.toString();
  } catch {
    return url.split('?')[0];
  }
}

export async function httpGet(url: string, options?: RequestInit): Promise<Response> {
  const start = Date.now();
  const safeUrl = sanitizeUrl(url);
  try {
    const res = await fetch(url, options);
    logger.info(
      { method: 'GET', url: safeUrl, status_code: res.status, duration_ms: Date.now() - start },
      'Outbound HTTP'
    );
    return res;
  } catch (err) {
    logger.error(
      { method: 'GET', url: safeUrl, duration_ms: Date.now() - start, error: (err as Error).message },
      'Outbound HTTP error'
    );
    throw err;
  }
}
```

**Key domain events** — log inside service functions for state changes:

```ts
// src/app/api/projects/route.ts  (example — adapt to your domain)
import { logger } from '@/lib/logger';

// After successful create:
logger.info({ user_id: session.user.id, project_id: project.id }, 'Project created');
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — add Prisma 5 `$extends` in `src/lib/db.ts`:

```ts
// src/lib/db.ts
import { logger } from '@/lib/logger';
import { PrismaClient } from '@prisma/client';

const prismaBase = new PrismaClient();

// Prisma 5+ slow query logging (replaces deprecated $use)
const prisma = prismaBase.$extends({
  query: {
    $allModels: {
      async $allOperations({ model, operation, args, query }) {
        const start = Date.now();
        const result = await query(args);
        const duration = Date.now() - start;
        if (duration > 500) {
          logger.warn({
            event: 'db.slow_query',
            model,
            operation,
            duration_ms: duration,
            // NEVER log: args (may contain PII or sensitive data)
          });
        }
        return result;
      },
    },
  },
});

export { prisma };
```

**Sanitized request context** — extend `withLogging` or add inline at the top of route handlers:

```ts
// src/lib/utils/with-logging.ts  (extend existing HOF)
// Add header-presence logging before calling handler:
logger.debug(
  {
    method: req.method,
    path: new URL(req.url).pathname,
    auth_present: req.headers.has('authorization'),
  },
  'Request context'
);
```

**Cache hits/misses** — log inside cache utility functions:

```ts
// wherever you call your cache (e.g. Redis, in-memory)
logger.debug({ cache_key: key, hit: value !== null }, 'Cache lookup');
```

---

### FastAPI

**What already exists in the template:**
- `python-json-logger>=3.3.0` in `requirements.txt`
- `src/core/logging.py` — full logging setup
- `src/core/json/logging.json` — JSON formatter config
- Import via `from core.logging import logger`

#### Tier 1 — Base

Add an HTTP middleware in `src/app.py` for request/response logging:

```python
# src/app.py  (add after existing middleware)
import time
from fastapi import Request
from core.logging import logger

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.monotonic()
    response = await call_next(request)
    duration_ms = round((time.monotonic() - start) * 1000)
    user_id = getattr(request.state, "user_id", None)
    logger.info(
        "Request",
        extra={
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "user_id": user_id,
        },
    )
    return response
```

App startup/shutdown — add lifespan events in `src/app.py`:

```python
# src/app.py
from contextlib import asynccontextmanager
from core.logging import logger
from core.config import api_settings

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("App starting", extra={"port": api_settings.API_PORT, "environment": api_settings.ENVIRONMENT})
    yield
    logger.info("App shutdown", extra={"environment": api_settings.ENVIRONMENT})

app = FastAPI(lifespan=lifespan, ...)
```

Unhandled exceptions are already logged via the `Exception` handler in `src/error_handler.py` (`logger.exception`). No extra wiring for Tier 1.

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — log inside auth routers in `src/api/routers/`:

```python
# src/api/routers/auth.py
from core.logging import logger

@router.post("/login")
async def login(credentials: LoginRequest, request: Request):
    user = await authenticate(credentials)
    if not user:
        logger.warning(
            "Login failure",
            extra={
                "reason": "invalid_credentials",
                "ip": request.client.host,
                # Never log: credentials.password
            },
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")

    logger.info(
        "Login success",
        extra={"user_id": str(user.id), "method": "password"},
    )
    return create_token_response(user)

@router.post("/logout")
async def logout(current_user: User = Depends(get_current_user)):
    logger.info("Logout", extra={"user_id": str(current_user.id)})
    return {"status": "ok"}

@router.post("/token/refresh")
async def refresh(current_user: User = Depends(get_current_user)):
    logger.info("Token refresh", extra={"user_id": str(current_user.id)})
    return create_token_response(current_user)
```

Access denied — log in your auth dependency:

```python
# src/core/auth.py  (dependency used by protected routes)
from core.logging import logger

async def require_role(required_role: str, request: Request, current_user: User = Depends(get_current_user)):
    if required_role not in current_user.roles:
        logger.warning(
            "Access denied",
            extra={
                "user_id": str(current_user.id),
                "path": request.url.path,
                "required_role": required_role,
            },
        )
        raise HTTPException(status_code=404, detail="Not found")
    return current_user
```

**Outbound HTTP calls** — create a wrapper in `src/utils/http_client.py`:

```python
# src/utils/http_client.py
import time
from urllib.parse import urlparse, urlunparse
import httpx
from core.logging import logger


def _sanitize_url(url: str) -> str:
    """Strip query string to avoid logging secrets in query params."""
    parsed = urlparse(url)
    return urlunparse(parsed._replace(query=""))


async def http_get(url: str, **kwargs) -> httpx.Response:
    safe_url = _sanitize_url(url)
    start = time.monotonic()
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, **kwargs)
        duration_ms = round((time.monotonic() - start) * 1000)
        logger.info(
            "Outbound HTTP",
            extra={"method": "GET", "url": safe_url, "status_code": response.status_code, "duration_ms": duration_ms},
        )
        return response
    except Exception as exc:
        duration_ms = round((time.monotonic() - start) * 1000)
        logger.error(
            "Outbound HTTP error",
            extra={"method": "GET", "url": safe_url, "duration_ms": duration_ms, "error": str(exc)},
        )
        raise
```

**Key domain events** — log inside service-layer functions:

```python
# src/services/projects.py  (example — adapt to your domain)
from core.logging import logger

async def create_project(data: CreateProjectRequest, user_id: str) -> Project:
    project = await db.projects.insert(data)
    logger.info("Project created", extra={"user_id": user_id, "project_id": str(project.id)})
    return project
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — add a SQLAlchemy event listener:

```python
# src/core/db.py  (add after engine creation)
import time
from sqlalchemy import event
from core.logging import logger

@event.listens_for(engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    conn.info.setdefault("query_start_time", []).append(time.monotonic())

@event.listens_for(engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    total_ms = round((time.monotonic() - conn.info["query_start_time"].pop()) * 1000)
    if total_ms > 500:
        # Use operation class name as a label — never log SQL text or bound parameters
        query_name = str(context.statement.__class__.__name__) if hasattr(context, "statement") else "unknown"
        logger.warning(
            "Slow DB query",
            extra={"query_name": query_name, "duration_ms": total_ms},
            # Never log: statement (full SQL text), parameters (bound values)
        )
```

If using Prisma (Python client), add middleware at the client level instead.

**Sanitized request context** — extend the HTTP middleware in `src/app.py`:

```python
# Inside log_requests middleware — add before call_next
auth_present = "authorization" in request.headers
logger.debug(
    "Request context",
    extra={
        "method": request.method,
        "path": request.url.path,
        "auth_present": auth_present,
        # Never log: request.headers.get("authorization")
    },
)
```

**Cache hits/misses** — log inside your cache utility:

```python
# src/utils/cache.py
from core.logging import logger

async def cache_get(key: str):
    value = await redis.get(key)
    logger.debug("Cache lookup", extra={"cache_key": key, "hit": value is not None})
    return value
```

---

### NestJS

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

Unhandled exceptions — update your `HttpExceptionFilter` to extend `BaseExceptionFilter` and log 5xx errors:

```ts
// src/common/filters/http-exception.filter.ts
import { Logger, Catch, ArgumentsHost, HttpException } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { ZodSerializationException } from 'nestjs-zod';
import { ZodError } from 'zod';

@Catch(HttpException)
export class HttpExceptionFilter extends BaseExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost) {
    const status = exception.getStatus();

    if (exception instanceof ZodSerializationException) {
      const zodError: unknown = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
    } else if (status >= 500) {
      this.logger.error(`HTTP ${status}: ${exception.message}`);
    }

    super.catch(exception, host);
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
import { Injectable, ExecutionContext } from '@nestjs/common';
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
import { Logger } from 'nestjs-pino';
import { Injectable } from '@nestjs/common';

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
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
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
  const project = await this.prisma.project.create({ data: { ...dto, userId } });
  this.logger.log({ user_id: userId, project_id: project.id }, 'Project created');
  return project;
}
```

#### Tier 3 — Verbose (+ Tier 1 + Tier 2)

**Slow DB queries** — use Prisma 5 `$extends` in your `PrismaService`:

```ts
// src/common/prisma/prisma.service.ts  (extend existing PrismaService)
import { Injectable, OnModuleInit, Logger } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  private readonly logger = new Logger(PrismaService.name);

  async onModuleInit() {
    await this.$connect();
  }

  // Prisma 5+ slow query logging (replaces deprecated $use)
  withSlowQueryLogging() {
    return this.$extends({
      query: {
        $allModels: {
          async $allOperations({ model, operation, args, query }) {
            const start = Date.now();
            const result = await query(args);
            const duration = Date.now() - start;
            if (duration > 500) {
              this.logger.warn({
                event: 'db.slow_query',
                model,
                operation,
                duration_ms: duration,
                // NEVER log: args (may contain PII or sensitive data)
              });
            }
            return result;
          },
        },
      },
    });
  }
}
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

After wiring, verify each tier produces the expected log output.

### Tier 1 Check

```bash
# Next.js
pnpm dev
curl http://localhost:3000/api/health
# Expect JSON log line: { method: "GET", path: "/api/health", status_code: 200, duration_ms: <n> }

# FastAPI
uvicorn src.app:app --reload
curl http://localhost:8000/health
# Expect JSON log line: { method: "GET", path: "/health", status_code: 200, duration_ms: <n> }

# NestJS
pnpm start:dev
curl http://localhost:3000/health
# Expect pino-http JSON log: { req: { method: "GET" }, res: { statusCode: 200 }, responseTime: <n> }
```

### Tier 2 Check

```bash
# Attempt login with wrong credentials — expect login failure log
# Attempt login with correct credentials — expect login success log
# Hit a protected route without a token — expect access denied log

# Outbound HTTP — wrap an external fetch call and check log output
```

### Tier 3 Check

```bash
# Trigger a slow DB query (or lower threshold temporarily to 0 for testing)
# Expect: { query_name: "...", duration_ms: <n> } warn log

# Redis / in-memory cache — check hit/miss logs appear on repeated calls
```

### Confirm No Prohibited Fields

```bash
# Grep logs for prohibited fields — none of these should appear:
grep -i "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" <log-output>
```

---

## See Also

- `shared/add-error-handling` — Unified error response schema; `logError` integration
- `shared/validation-patterns` — Zod/Pydantic validation before any log call
- Stack-specific `code-standards` — Logging rules within each stack's security guidelines
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Apply logging when adding new routes
