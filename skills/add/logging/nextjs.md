<!-- ref: add/logging/nextjs.md
     loaded-by: add/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Next.js — Structured Logging

### Step 0 — Verify context

Need `<!-- templateCentral: nextjs@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

**What already exists in the template:**
- `pino` in `package.json` dependencies
- `src/lib/logger.ts` — pino logger with `redact` (auth/cookie/password/token) and an HMR-safe `globalThis` singleton (dev)
- `src/lib/utils/with-logging.ts` — `withLogging` HOF (already applied to the scaffold's own route handlers; the lint gate enforces coverage)
- `src/lib/errors/error-log-handler.ts` — `logError` using pino

#### Tier 1 — Base

Wrap every route handler with `withLogging` — it logs `method`, `path`, `status`, `duration_ms`, `requestId` and catches unhandled exceptions.

```ts
// Apply this pattern to every route handler in src/app/api/
import { withLogging } from '@/lib/utils/with-logging';
import { NextResponse } from 'next/server';

export const GET = withLogging(async () => {
  return NextResponse.json({ status: 'ok' });
});
```

Add an explicit startup log in `src/instrumentation.ts` (Next.js instrumentation hook):

```ts
// src/instrumentation.ts
export async function register() {
  // register() also runs in the Edge runtime, where pino cannot load — import lazily, Node only.
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;
  const { logger } = await import('@/lib/logger');
  logger.info(
    { port: process.env.PORT ?? 3000, environment: process.env.NODE_ENV },
    'App starting'
  );
}
```

Unhandled exceptions already reach `logError`; Tier 1 needs no wiring.

#### Tier 2 — Standard (+ Tier 1)

**Auth events** — the auth route from `templatecentral:add (auth)` already wraps both handlers in `withLogging`. Add `import { logger } from '@/lib/logger';` and replace its `POST` export:

```ts
// src/app/api/auth/[...all]/route.ts
export const POST = withLogging(async (req) => {
  const response = await handlers.POST(req);
  const path = req.nextUrl.pathname.replace('/api/auth', '');

  if (path.startsWith('/sign-in')) {
    // Never log the request body — it holds the email and password.
    if (response.ok) logger.info({ event: 'auth.login_success', path }, 'Login success');
    else logger.warn({ event: 'auth.login_failure', path, status: response.status }, 'Login failure');
  } else if (path.startsWith('/sign-out')) {
    logger.info({ event: 'auth.logout' }, 'Logout');
  }

  return response;
});
```

For access denied, log in `proxy.ts` (route protection middleware):

```ts
// src/proxy.ts — inside route(), after session check
if (!hasSession) {
  if (isApiRoute(pathname)) {
    logger.warn({ event: 'auth.access_denied', path: pathname }, 'Unauthenticated API request');
    return new Response(null, { status: 401 });
  }
  logger.info({ event: 'auth.redirect_to_login', path: pathname }, 'Redirecting to login');
  return NextResponse.redirect(new URL(PAGE_ROUTES.LOGIN, req.url));
}
```

Run `TC_PART=leaf TC_LEAF=add/logging/nextjs bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/logging/nextjs/template/` (listed in `<skill-dir>/logging/nextjs/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

**Outbound HTTP calls** — the fetch wrapper is `src/integrations/clients/http-client.ts` (copied above):

Copied verbatim from `<skill-dir>/logging/nextjs/template/src/integrations/clients/http-client.ts` by the copy step; do not re-type it.

**Key domain events** — log where the state change happens:

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
    // Label only — query params may contain PII.
    logger.warn({ event: 'db.slow_query', name, duration_ms: duration }, 'Slow DB query');
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
// wherever you call your cache — log a key prefix instead if keys embed user data
logger.debug({ cache_key: key, hit: value !== null }, 'Cache lookup');
```

---

## Validate

```bash
# Tier 1
pnpm dev
curl http://localhost:3000/api/health
# Expect JSON log line: { method: "GET", path: "/api/health", status: 200, duration_ms: <n> }

# Tier 2
# Attempt login with wrong credentials — expect login failure log
# Attempt login with correct credentials — expect login success log
# Hit a protected route without a token — expect access denied log

# Tier 3
# Trigger a slow DB query (or lower threshold temporarily to 0 for testing)
# Expect: { name: "...", duration_ms: <n> } warn log

# Confirm no prohibited field reaches the log unredacted.
# The negative lookahead skips pino's own "[Redacted]" markers, so any line that
# matches is a real leak. Lookahead needs PCRE (grep -P), not -E.
pnpm dev 2>&1 | grep -P '"(password|secret|token|api_key|authorization|cookie|email|phone|address|credit_card)":\s*"(?!\[Redacted\])'
```

Expect zero matches. On macOS, BSD `grep` has no `-P` — use `rg` instead (same pattern, PCRE is
available via `rg -P`), or drop the lookahead and confirm by eye that every sensitive key printed
has `"[Redacted]"` as its value.

## After Writing Code

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.