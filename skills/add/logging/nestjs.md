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
- `nestjs-pino` wired in `app.module.ts` via `LoggerModule.forRoot()` (with a header `redact` block; UUID request ids come from `genReqId` on the `FastifyAdapter` in `main.ts`)
- `main.ts` already does `app.useLogger(app.get(Logger))` with `bufferLogs: true` and logs startup — no bootstrap changes needed
- pino-http auto-logs every request/response (Tier 1 request logging is automatic)
- `new Logger('X')` pattern works throughout

#### Tier 1 — Base

pino-http handles request/response logging automatically (method, path, status_code, duration_ms). Add `user_id` to request logs by turning on `assignResponse` in `LoggerModule` and calling `PinoLogger.assign()` from the auth guard once the user is known (Tier 2 guard below):

```ts
// src/app.module.ts — add assignResponse next to the existing pinoHttp object
LoggerModule.forRoot({
  // Fields set with PinoLogger.assign() during the request also land on pino-http's
  // "request completed" line, not just on logs written after the assign() call.
  assignResponse: true,
  pinoHttp: {
    // ...keep existing level, redact, transport unchanged
  },
}),
```

> Do NOT derive `user_id` in `pinoHttp.customProps`. pino-http evaluates `customProps` when the
> request starts — before any guard runs — and again when the response finishes, so (verified on
> NestJS 11.2 + `@nestjs/platform-fastify` + nestjs-pino 4.6 / pino-http 11) every log written
> inside the handler carries `user_id: null`, and the "request completed" line carries the key
> twice (`"user_id":null,"user_id":"u-123"`) — log backends that keep the first duplicate show null.
> `assign()` adds the field once, to the in-handler logs and the completion line.

> Add the key; do not replace the config object. Replacing it wholesale silently drops the
> scaffold's `redact` block, and every request then logs its bearer JWT and cookies.

Unhandled exceptions — do NOT re-copy the `HttpExceptionFilter` here; extend the filter from `templatecentral:add` (error-handling). The scaffold's filter already logs 5xx (`if (isServerError) this.logger.error(...)`); replace that one `if` with the block below so 4xx are logged too — never add it alongside, or every 5xx logs twice. Keep the generic client message for 5xx unchanged:

```ts
// src/common/filters/http-exception.filter.ts — replaces the isServerError logging `if`
if (isServerError) {
  this.logger.error(`HTTP ${status}: ${exception.message}`);
} else {
  this.logger.warn(`HTTP ${status}: ${exception.message}`);
}
```

App startup is already logged by the scaffold's `bootstrap()`. nestjs-pino's `Logger` keeps Nest's `(message, context)` signature — a second string argument becomes the context, so interpolate values into the message.

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

  handleRequest<TUser extends { id: string } = { id: string; email: string }>(
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
    // Binds user_id to every later log in this request and (assignResponse) the completion line.
    this.logger.assign({ user_id: user.id });
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
    // existing collaborator — keep your project's user lookup service and its import
    private readonly usersService: UsersService,
    // ...existing collaborators (JwtService, etc.)
  ) {}

  async login(user: User, method: string) {
    this.logger.info({ user_id: user.id, method }, 'Login success');
    // createToken: your existing token helper
    return this.createToken(user);
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
      // No email: it is PII, and logging it on failure builds a list of probed accounts.
      this.logger.warn({ reason: 'invalid_credentials' }, 'Login failure');
      return null;
    }
    return user;
  }
}
```

**Outbound HTTP calls** — wrap `fetch` in a provider (a `NestInterceptor` only sees inbound handlers, never outbound calls):

```ts
// src/common/http/http-client.service.ts
import { Injectable } from '@nestjs/common';
import { InjectPinoLogger, PinoLogger } from 'nestjs-pino';

@Injectable()
export class HttpClientService {
  constructor(@InjectPinoLogger(HttpClientService.name) private readonly logger: PinoLogger) {}

  async request(url: string, init?: RequestInit): Promise<Response> {
    // origin + path only: userinfo, query, and fragment can all carry credentials.
    const { origin, pathname } = new URL(url);
    const safeUrl = `${origin}${pathname}`;
    const method = init?.method ?? 'GET';
    const start = Date.now();
    try {
      const res = await fetch(url, init);
      this.logger.info(
        { method, url: safeUrl, status_code: res.status, duration_ms: Date.now() - start },
        'Outbound HTTP',
      );
      return res;
    } catch (err) {
      this.logger.error(
        { method, url: safeUrl, duration_ms: Date.now() - start, error_type: (err as Error).name },
        'Outbound HTTP error',
      );
      throw err;
    }
  }
}
```

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
    // Label only — query params may contain PII.
    this.logger.warn({ name, duration_ms: duration }, 'Slow DB query');
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

**Sanitized request context** — add `customProps` to `pinoHttp` for request-start facts only (headers are fixed when the request starts; `user_id` stays on `assign()` from Tier 1/2):

```ts
// src/app.module.ts  (add to the existing pinoHttp object)
import type { IncomingMessage } from 'node:http';

customProps: (req: IncomingMessage) => ({
  auth_present: !!req.headers.authorization,
}),
```

**Cache hits/misses** — log in your cache service:

```ts
// src/common/cache/cache.service.ts
async get<T>(key: string): Promise<T | null> {
  const value = await this.redis.get(key);
  // Log a key prefix, not the full key, if keys embed user data (e.g. "session:<email>").
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
# Expect: { msg: "Slow DB query", name: "...", duration_ms: <n> } warn log

# Confirm no prohibited fields leaked.
# INVERTED CHECK: this grep must print NOTHING. Any match is a FAILURE — a prohibited
# field reached the logs. Investigate immediately and do not ship until it is silent.
# Matches JSON keys, so log messages like "Token refresh" do not false-positive.
grep -iE '"(password|secret|token|access_token|api_key|authorization|cookie|email|phone|address|credit_card)"' <log-output>
```

## See Also

- `add/error-handling/nestjs` — Unified error response schema; `logError` integration
- `standards/validation-patterns/nestjs` — Zod/Pydantic validation before any log call
- Stack-specific `code-standards` — Logging rules within each stack's security guidelines
- `templatecentral:add (endpoint)` — Apply logging when adding new routes

## Production Requirement

Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only is not sufficient; production log storage must be isolated from the application host.

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards