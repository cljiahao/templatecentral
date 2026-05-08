## Next.js — Structured Logging

**What already exists in the template:**
- `pino` in `package.json` dependencies
- `src/lib/logger.ts` — singleton pino logger
- `src/lib/utils/with-logging.ts` — `withLogging` HOF
- `src/lib/errors/error-log-handler.ts` — `logError` using pino

#### Tier 1 — Base

Wrap every route handler with `withLogging`. It logs `method`, `path`, `status`, `duration_ms`, and `requestId` per request, and catches unhandled exceptions automatically.

```ts
// Apply this pattern to every route handler in src/app/api/
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

**Auth events** — wrap the auth API route handler to log sign-in and sign-out events:

```ts
// src/app/api/auth/[...all]/route.ts
import { auth } from '@/lib/auth';
import { logger } from '@/lib/logger';
import { toNextJsHandler } from 'better-auth/next-js';

const { GET: _GET, POST: _POST } = toNextJsHandler(auth);

export { GET: _GET as GET };

export async function POST(req: Request) {
  const url = new URL(req.url);
  const path = url.pathname.replace('/api/auth', '');

  const response = await _POST(req.clone() as Request);

  if (path.startsWith('/sign-in') && response.status === 200) {
    logger.info({ event: 'auth.login_success', path }, 'Login success');
  } else if (path.startsWith('/sign-in') && response.status !== 200) {
    logger.warn(
      { event: 'auth.login_failure', path, status: response.status },
      'Login failure'
    );
  } else if (path.startsWith('/sign-out')) {
    logger.info({ event: 'auth.logout' }, 'Logout');
  }

  return response;
}
```

For access denied, log in `proxy.ts` (route protection middleware):

```ts
// src/proxy.ts — inside proxy(), after session check
if (!session) {
  if (isApiRoute(pathname)) {
    logger.warn({ event: 'auth.access_denied', path: pathname }, 'Unauthenticated API request');
    return new Response(null, { status: 401 });
  }
  logger.info({ event: 'auth.redirect_to_login', path: pathname }, 'Redirecting to login');
  return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
}
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

**Slow DB queries** — add a timing wrapper in `src/lib/utils/with-slow-query-log.ts`:

```ts
// src/lib/utils/with-slow-query-log.ts
import { logger } from '@/lib/logger';

export async function withSlowQueryLog<T>(
  name: string,
  fn: () => Promise<T>,
): Promise<T> {
  const start = Date.now();
  const result = await fn();
  const duration = Date.now() - start;
  if (duration > 500) {
    logger.warn({ event: 'db.slow_query', name, duration_ms: duration });
    // NEVER log query params — may contain PII or sensitive data
  }
  return result;
}
```

Usage in API routes or Server Components:

```ts
import { withSlowQueryLog } from '@/lib/utils/with-slow-query-log';
import { db, projects } from '@/integrations/database';

const rows = await withSlowQueryLog('projects.findAll', () =>
  db.select().from(projects)
);
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

## Verification

```bash
# Tier 1
pnpm dev
curl http://localhost:3000/api/health
# Expect JSON log line: { method: "GET", path: "/api/health", status_code: 200, duration_ms: <n> }

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
