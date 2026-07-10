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

> **Coverage rule (the client analogue of "wrap every route"):** every uncaught error must reach `logError`, and every API call must flow through one logged client (`src/lib/clients/`), never a raw `fetch`. The ErrorBoundary + global handlers cover the first; keep all data-fetching in the shared client for the second.

> **Production upgrade path:** the homegrown console-JSON + batcher below is vendor-free and right for a scaffold default. For production error tracking, the community standard is **Sentry** (`@sentry/react`) — it auto-installs the ErrorBoundary wrapper + `window.onerror` + `unhandledrejection`, and adds source-map symbolication, breadcrumbs, release tracking, and PII scrubbing (`beforeSend`). Adopt it when you have a DSN; it supersedes the manual handlers above. OpenTelemetry's browser SDK is still experimental — not a client error-tracking replacement yet.

This skill extends `logError` with a `logEvent` companion, adds a breadcrumb buffer, and wires batched delivery to a backend `/logs` endpoint (or console-JSON fallback in dev).

### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Extend `src/lib/errors/error-log-handler.ts`

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

### 2. Create `src/lib/logging/breadcrumbs.ts`

An in-memory ring buffer (last 20 entries) attached to every error report:

```ts
// src/lib/logging/breadcrumbs.ts
const MAX = 20;
const buffer: Array<{ type: string; label: string; ts: string }> = [];

export function addBreadcrumb(crumb: { type: string; label: string }): void {
  if (buffer.length >= MAX) buffer.shift();
  buffer.push({ ...crumb, ts: new Date().toISOString() });
}

export function getBreadcrumbs(): typeof buffer {
  return [...buffer];
}
```

Update `src/lib/errors/error-log-handler.ts` to import and attach breadcrumbs to error logs:

```ts
import { getBreadcrumbs } from '@/lib/logging/breadcrumbs';
// Inside logError, add breadcrumbs to the console.error object:
//   breadcrumbs: getBreadcrumbs()
// Example for the APIError branch:
console.error(`${label}:`, {
  message: error.message,
  statusCode: error.statusCode,
  data: error.data,
  timestamp: new Date().toISOString(),
  breadcrumbs: getBreadcrumbs(),
});
```

Also import `addBreadcrumb` in `error-log-handler.ts` and call it from `logError`:

```ts
import { addBreadcrumb, getBreadcrumbs } from '@/lib/logging/breadcrumbs';
// At the top of every logError branch (before console.error):
addBreadcrumb({ type: 'error', label: label });
```

### 3. Create `src/lib/logging/log-batcher.ts`

Batched delivery to a backend `/logs` endpoint with console-JSON fallback in dev. Cross-references the `/api` prefix proxy convention: if your project pairs a backend via `VITE_API_BASE_URL`, POST to `${getApiBaseUrl()}/logs`; otherwise logs stay local.

```ts
// src/lib/logging/log-batcher.ts
import { getApiBaseUrl } from '@/lib/constants/env';

type LogEntry = { level: string; label: string; timestamp: string; [k: string]: unknown };

const queue: LogEntry[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;

const BATCH_MS = 5_000;
const MAX_BATCH = 50;

function flush(): void {
  if (queue.length === 0) return;
  const batch = queue.splice(0, MAX_BATCH);

  if (import.meta.env.DEV) {
    // Console-JSON fallback in dev — no network call
    console.info('[log-batcher]', JSON.stringify(batch));
    return;
  }

  try {
    const base = getApiBaseUrl();
    void fetch(`${base}/logs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      // keepalive lets the request complete even if the tab closes
      keepalive: true,
      body: JSON.stringify(batch),
    }).catch(() => {
      // Silently discard — logging must never throw
    });
  } catch {
    // getApiBaseUrl() throws if VITE_API_BASE_URL is absent; fall back silently
    console.info('[log-batcher]', JSON.stringify(batch));
  }
  // Trade-off: if queue.length > MAX_BATCH after splice, remainder entries flush on
  // the next enqueueLog call (size gate) or next visibilitychange — never silently dropped.
}

export function enqueueLog(entry: Omit<LogEntry, 'timestamp'>): void {
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
if (typeof window !== 'undefined') {
  window.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') flushAll();
  });
  window.addEventListener('pagehide', () => {
    flushAll();
  });
}
```

Wire `enqueueLog` into `logError` and `logEvent`:

```ts
// src/lib/errors/error-log-handler.ts — add at the end of each branch
import { enqueueLog } from '@/lib/logging/log-batcher';
// In logError:
enqueueLog({ level: 'error', label, message: ..., breadcrumbs: getBreadcrumbs() });
// In logEvent:
enqueueLog({ level: 'info', label: name, ...data });
```

### 4. Add router navigation breadcrumbs

Wire into React Router so every navigation is recorded before an error report:

```ts
// src/router.tsx — extend existing router
import { addBreadcrumb } from '@/lib/logging/breadcrumbs';
// In your router subscribe / useEffect that watches location:
addBreadcrumb({ type: 'navigation', label: location.pathname });
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

Any match must be removed or redacted before the code ships.

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
