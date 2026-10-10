<!-- ref: add/logging/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as Vite+React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React — Client-Side Logging

**What already exists in the scaffold:**
- `src/lib/errors/error-log-handler.ts` — `logError(label, error)` (console-JSON output, typed for `APIError` / `Error` / unknown)
- `src/lib/errors/api-error.ts` — `APIError` with `statusCode` and `data`
- `src/components/layout/error-boundary.tsx` — class component with `componentDidCatch` (render-phase errors)
- `src/lib/errors/global-handlers.ts` — `registerGlobalErrorHandlers()` wiring `window.onerror` + `unhandledrejection`, registered in `main.tsx`. Together with the ErrorBoundary this is full client-side error coverage: render-phase (boundary) + async/event/promise (global handlers).
- `src/lib/errors/index.ts` — barrel re-exporting `logError` and `registerGlobalErrorHandlers`

> **Coverage rule (the client analogue of "wrap every route"):** every uncaught error must reach `logError`, and every API call should flow through one logged client (`src/lib/clients/`) rather than a raw `fetch`. The ErrorBoundary + global handlers cover the first; the second is `FetchClient`: backend calls go through `ApiClient` subclasses (`templatecentral:add (feature)`, `(pagination)`, `standards (validation-patterns)`, the batcher below) and external APIs through `FetchClient` subclasses (`templatecentral:add (integration)`). The one deliberate raw-`fetch` exception is the auth service's three session calls (`templatecentral:add (auth)`).

> **Production upgrade path:** the homegrown console-JSON + batcher below is vendor-free and right for a scaffold default. For production error tracking, the community standard is **Sentry** (`@sentry/react`) — it auto-installs the ErrorBoundary wrapper + `window.onerror` + `unhandledrejection`, and adds source-map symbolication, breadcrumbs, release tracking, and PII scrubbing (`beforeSend`). Adopt it when you have a DSN; it supersedes the manual handlers above. OpenTelemetry's browser SDK is still experimental — not a client error-tracking replacement yet.

This skill extends `logError` with a `logEvent` companion, adds a breadcrumb buffer, and wires batched delivery to a backend `/logs` endpoint (or console-JSON fallback in dev).

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

> **Step order matters.** `error-log-handler.ts` imports from `@/lib/logging/breadcrumbs`, so the breadcrumb module (Step 1) must exist before the handler is extended (Step 2). Executing these out of order leaves a broken import and a failing `pnpm build`.

### 1. Create `src/lib/logging/breadcrumbs.ts`

An in-memory ring buffer (last 20 entries) attached to every error report. Labels are **scrubbed on the way in**, not on the way out — a breadcrumb is written once and read on every subsequent error report, so redacting at the entry point is the only place the guarantee holds:

```ts
// src/lib/logging/breadcrumbs.ts
const MAX_BREADCRUMBS = 20;
const buffer: Array<{ type: string; label: string; ts: string }> = [];

// Navigation labels are URL paths, and paths routinely carry the exact values that
// must never leave the browser: /reset-password/<one-time-token>, /users/<uuid>,
// /invite/<code>. Collapse any segment that is not a plain word to a placeholder so
// the route shape survives for debugging but the value does not.
const SAFE_SEGMENT = /^[a-z][a-z0-9-]*$/i;

export function redactLabel(label: string): string {
  if (!label.startsWith('/')) return label;
  return label
    .split('/')
    .map((segment) => (segment === '' || SAFE_SEGMENT.test(segment) ? segment : ':redacted'))
    .join('/');
}

export function addBreadcrumb(crumb: { type: string; label: string }): void {
  if (buffer.length >= MAX_BREADCRUMBS) buffer.shift();
  buffer.push({ type: crumb.type, label: redactLabel(crumb.label), ts: new Date().toISOString() });
}

export function getBreadcrumbs(): typeof buffer {
  return [...buffer];
}
```

### 2. Extend `src/lib/errors/error-log-handler.ts`

Add `logEvent` alongside the existing `logError`. Do not replace `logError` — only add:

```ts
// src/lib/errors/error-log-handler.ts  (extend existing file — add below logError)
import { addBreadcrumb } from '@/lib/logging/breadcrumbs';

// --- existing logError stays unchanged ---

export const logEvent = (name: string, data?: Record<string, unknown>): void => {
  const entry = { event: name, timestamp: new Date().toISOString(), ...data };
  console.info(JSON.stringify(entry));
  addBreadcrumb({ type: 'event', label: name });
};
```

Then attach breadcrumbs to error logs. `error.data` is the **raw, unfiltered response body** from the backend — it can contain the submitted payload, a session identifier, or an internal stack trace, and none of that should be shipped off-device. Keep it in the dev console only; send just `statusCode` + `message` onward:

```ts
import { addBreadcrumb, getBreadcrumbs } from '@/lib/logging/breadcrumbs';

// At the top of every logError branch (before console.error):
addBreadcrumb({ type: 'error', label });

// APIError branch — raw data stays behind the DEV guard, never in the shipped payload:
console.error(`${label}:`, {
  message: error.message,
  statusCode: error.statusCode,
  ...(import.meta.env.DEV ? { data: error.data } : {}),
  timestamp: new Date().toISOString(),
  breadcrumbs: getBreadcrumbs(),
});
```

### 3. Create `src/lib/logging/log-batcher.ts`

Batched delivery to a backend `/logs` endpoint with console-JSON fallback in dev. The POST goes through `ApiClient` (`src/lib/clients/api-client.ts`, from `templatecentral:standards (full-stack-pairing)`), so it carries the session cookie and `X-CSRF-Token` once `templatecentral:add (auth)` is applied. **No paired backend** (no `api-client.ts`): drop `LogClient` and the `try` block in `flush()` and keep only the console line — logs stay local.

The backend `/logs` endpoint receives attacker-controllable input: validate it with a strict schema (bounded array length and string sizes), rate-limit it, and log entries as structured fields — never interpolate them into a message string, or a crafted `label` with newlines forges log lines.

```ts
// src/lib/logging/log-batcher.ts
import { ApiClient } from '@/lib/clients/api-client';

// Omit<LogEntry, 'timestamp'> would NOT work here: a `[k: string]: unknown` index signature
// collapses `keyof LogEntry` to `string`, so Omit silently drops the requirement that
// level/label be present. Split the index-signature part out instead.
type LogFields = { level: string; label: string; [k: string]: unknown };
type LogEntry = LogFields & { timestamp: string };

const queue: LogEntry[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

const BATCH_MS = 5_000;
const MAX_BATCH = 50;

// FetchClient reports failures with console.error, never logError — so a failing /logs
// POST cannot re-enqueue itself into a loop.
class LogClient extends ApiClient {
  // keepalive lets the request complete even if the tab closes
  protected override keepalive = true;

  send(batch: LogEntry[]): Promise<void> {
    return this.request('logs', 'POST', batch);
  }
}

let client: LogClient | undefined;

function flush(): void {
  if (queue.length === 0) return;
  const batch = queue.splice(0, MAX_BATCH);

  if (import.meta.env.DEV) {
    // Console-JSON fallback in dev — no network call
    console.info('[log-batcher]', JSON.stringify(batch));
    return;
  }

  try {
    client ??= new LogClient();
    client.send(batch).catch(() => {
      // Silently discard — logging must never throw
    });
  } catch {
    // ApiClient's constructor throws if VITE_API_BASE_URL is absent; fall back silently
    console.info('[log-batcher]', JSON.stringify(batch));
  }
  // Trade-off: if queue.length > MAX_BATCH after splice, remainder entries flush on
  // the next enqueueLog call (size gate) or next visibilitychange — never silently dropped.
}

export function enqueueLog(entry: LogFields): void {
  queue.push({ ...entry, timestamp: new Date().toISOString() });
  if (flushTimer === null) {
    flushTimer = setTimeout(() => {
      flushTimer = null;
      flush();
    }, BATCH_MS);
  }
  if (queue.length >= MAX_BATCH) {
    if (flushTimer !== null) clearTimeout(flushTimer);
    flushTimer = null;
    flush();
  }
}

// On unload, drain the entire queue (flush() only sends one MAX_BATCH slice)
function flushAll(): void {
  while (queue.length > 0) flush();
}

// Flush on page unload so buffered logs are not lost.
// pagehide fires on bfcache/navigation where visibilitychange may not — register both.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') flushAll();
});
window.addEventListener('pagehide', () => {
  flushAll();
});
```

Wire `enqueueLog` into `logError` and `logEvent`:

Only allowlisted fields cross this boundary — `enqueueLog` POSTs to a backend, so anything passed here leaves the browser. Pass `statusCode` and the error `message`; never `error.data`, never the caught error object itself:

```ts
// src/lib/errors/error-log-handler.ts — add at the end of each branch
import { enqueueLog } from '@/lib/logging/log-batcher';

// In logError (APIError branch):
enqueueLog({
  level: 'error',
  label,
  message: error.message,
  statusCode: error.statusCode,
  breadcrumbs: getBreadcrumbs(),
});

// In logEvent — `data` is caller-supplied, so it is the caller's job to keep it PII-free:
enqueueLog({ level: 'info', label: name, ...data });
```

### 4. Add router navigation breadcrumbs

Wire into React Router so every navigation is recorded before an error report:

`useLocation` must be called from a component rendered *inside* `<BrowserRouter>`. Add a small listener component and render it next to `<Routes>` in `src/router.tsx`:

```tsx
// src/components/layout/navigation-breadcrumbs.tsx
import { addBreadcrumb } from '@/lib/logging/breadcrumbs';
import { useEffect } from 'react';
import { useLocation } from 'react-router';

// addBreadcrumb() redacts non-word path segments, so ids and one-time tokens
// in the pathname never reach the buffer.
export function NavigationBreadcrumbs() {
  const location = useLocation();

  useEffect(() => {
    addBreadcrumb({ type: 'navigation', label: location.pathname });
  }, [location.pathname]);

  return null;
}
```

```tsx
// src/router.tsx — render it inside <BrowserRouter>, alongside the existing <Routes>
<BrowserRouter>
  <NavigationBreadcrumbs />
  <Routes>{/* existing routes unchanged */}</Routes>
</BrowserRouter>
```

### 5. Export from `src/lib/logging/index.ts`

```ts
// src/lib/logging/index.ts
export { addBreadcrumb, getBreadcrumbs } from './breadcrumbs';
export { enqueueLog } from './log-batcher';
```

Also add to `src/lib/errors/index.ts`:

```ts
export { logEvent } from './error-log-handler';
```

## No-PII Rule

NEVER log passwords, tokens, email addresses, or other personal data.

```bash
# Grep check — run before committing
grep -rn "password\|secret\|token\|api_key\|email\|phone\|address\|credit_card" src/lib/logging/ src/lib/errors/
```

Review every match: hits in comments and in `redactLabel` are expected; a hit in a value passed to `logEvent` / `enqueueLog` must be removed before the code ships.

**The grep is necessary but not sufficient.** It scans source text for literal keywords; it cannot see what a value actually holds at runtime. The two payloads that carry PII in this design contain no such keyword anywhere in the source:

| Runtime payload | Why grep misses it | Required control |
|-----------------|--------------------|------------------|
| `APIError.data` | An opaque `unknown` — the backend decides what is in it (echoed form fields, session ids, stack traces) | Never forward it to `enqueueLog`; keep it behind `import.meta.env.DEV` for the console only (Step 2) |
| Breadcrumb labels | `location.pathname` is a plain string — `/reset-password/<token>` matches nothing | `redactLabel()` at `addBreadcrumb()` entry (Step 1) collapses non-word segments. Word-shaped values (`/users/alice`) still pass — avoid usernames/emails in paths, or tighten `SAFE_SEGMENT` to an allowlist of known route words |

Before shipping, confirm both by inspection, not by grep:

1. Every `enqueueLog(...)` call site passes only allowlisted scalars (`level`, `label`, `message`, `statusCode`, `breadcrumbs`) — no spread of an error object, no `error.data`.
2. Trigger an error on a route with a dynamic segment in dev and read the emitted JSON — the breadcrumb must show `/reset-password/:redacted`, not the real value.

Anything new that reaches `enqueueLog` must be added to the allowlist deliberately, never by spreading an object of unknown shape.

## Validate

```bash
pnpm build    # zero type errors
pnpm test     # all tests pass
```

Manually verify in dev mode (`pnpm dev`):
1. Trigger an error (e.g. navigate to a non-existent route) → expect a console.error JSON line with `breadcrumbs`
2. Call `logEvent('test.event')` from the browser console → expect a `console.info` JSON line
3. Check the batch timer: wait 5 s after a log event → expect `[log-batcher]` console output in dev

## After Writing Code

Dispatch in order:
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate compilation
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards
