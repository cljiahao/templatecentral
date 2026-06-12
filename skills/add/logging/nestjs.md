<!-- ref: add/logging/nestjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## NestJS — Structured Logging

### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

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
    customProps: (req: import('fastify').FastifyRequest & { user?: { id: string } }) => ({
      user_id: req.user?.id ?? null,
    }),
    level: process.env.LOG_LEVEL ?? 'info',
  },
}),
```

Unhandled exceptions — do NOT re-copy the `HttpExceptionFilter` here; extend the filter from `templatecentral:add` (error-handling). If your copy lacks the status-logging block, add only these lines inside `catch()`, just before the final `reply.status(status).send(...)`:

```ts
// src/common/filters/http-exception.filter.ts — added lines only
if (status >= 500) {
  this.logger.error(`HTTP ${status}: ${exception.message}`);
} else {
  this.logger.warn(`HTTP ${status}: ${exception.message}`);
}
```

App startup/shutdown — use NestJS lifecycle hooks:

```ts
// Excerpt — integrate ONLY the logger wiring into your existing src/main.ts bootstrap.
// The scaffold already handles trustProxy, CORS, and app.listen — do NOT copy those here.
import { Logger } from 'nestjs-pino';

// Inside existing bootstrap(), after NestFactory.create():
const logger = app.get(Logger);
app.useLogger(logger);
// ...rest of existing bootstrap continues unchanged...
// Note: nestjs-pino's Logger has Nest's (message, context) signature — a second string
// argument becomes the Nest context, not a pino message. Interpolate instead:
logger.log(`App started on port ${port} (${process.env.NODE_ENV})`);
```

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — log in your auth guard or Passport strategy. Inject `PinoLogger` (not `Logger`) for structured fields — `PinoLogger` keeps pino's `(obj, msg)` signature, whereas `Logger.log(obj, 'msg')` would treat the string as a Nest context:

```ts
// src/modules/auth/jwt-auth.guard.ts  (path per templatecentral:add (auth))
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import { Injectable, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { FastifyRequest } from 'fastify';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(
    @InjectPinoLogger(JwtAuthGuard.name) private readonly logger: PinoLogger,
  ) {
    super();
  }

  handleRequest<TUser = { id: string; email: string }>(
    err: unknown,
    user: TUser | false,
    _info: unknown,
    context: ExecutionContext,
  ): TUser {
    const req = context.switchToHttp().getRequest<FastifyRequest>();
    if (err || !user) {
      this.logger.warn(
        { path: req.url, required_role: 'authenticated' },
        'Access denied'
      );
      if (err instanceof Error) throw err;
      throw new UnauthorizedException();
    }
    return user;
  }
}
```

For login/logout events, log in your auth service:

```ts
// src/modules/auth/auth.service.ts  (excerpt — logging calls added to your existing service)
import { Injectable } from '@nestjs/common';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';
import * as argon2 from 'argon2';

import type { User } from '../../database/schema';

@Injectable()
export class AuthService {
  constructor(
    @InjectPinoLogger(AuthService.name) private readonly logger: PinoLogger,
    private readonly usersService: UsersService, // existing collaborator — keep your project's user lookup service and its import
    // ...existing collaborators (JwtService, etc.)
  ) {}

  async login(user: User, method: string) {
    this.logger.info({ user_id: user.id, method }, 'Login success');
    return this.createToken(user); // createToken: your existing token helper
  }

  async logout(userId: string) {
    this.logger.info({ user_id: userId }, 'Logout');
  }

  async refreshToken(userId: string) {
    this.logger.info({ user_id: userId }, 'Token refresh');
    // ... return new token
  }

  async validateUser(email: string, password: string) {
    const user = await this.usersService.findByEmail(email);
    if (!user || !(await argon2.verify(user.hashedPassword, password))) {
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

**Key domain events** — log in service methods for state changes (`this.logger` is an injected `PinoLogger`, as in the auth examples above):

```ts
// src/modules/projects/projects.service.ts  (example — adapt to your domain)
async createProject(dto: CreateProjectDto, userId: string): Promise<Project> {
  const [project] = await this.drizzle.db
    .insert(projects)
    .values({ ...dto, userId })
    .returning();
  this.logger.info({ user_id: userId, project_id: project.id }, 'Project created');
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

## Validate

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
# Expect: { name: "...", duration_ms: <n> } warn log

# Confirm no prohibited fields
grep -i "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" <log-output>
```

## See Also

- `add/error-handling/nestjs` — Unified error response schema; `logError` integration
- `standards/validation-patterns/nestjs` — Zod/Pydantic validation before any log call
- Stack-specific `code-standards` — Logging rules within each stack's security guidelines
- Stack-specific `add-api-route`, `add-endpoint`, `add-module` — Apply logging when adding new routes

## Production Requirement

Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only is not sufficient; production log storage must be isolated from the application host.

## Validate

Run the stack's build and test commands (see `AGENTS.md` → Scaffold verification).

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/review/SKILL.md"` — check code standards