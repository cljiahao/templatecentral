<!-- ref: add/logging/vite-react.md
     loaded-by: add/SKILL.md
     prereq: Stack identified as Vite+React. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Vite + React — Client-Side Logging

**What already exists in the scaffold:**
- `src/lib/errors/error-log-handler.ts` — `logError(label, error)` (console-JSON output, typed for `APIError` / `Error` / unknown)
- `src/lib/errors/api-error.ts` — `APIError` with `statusCode` and `data`
- `src/components/layout/error-boundary.tsx` — class component with `componentDidCatch` (render-phase errors)
- `src/lib/errors/global-handlers.ts` — `registerGlobalErrorHandlers()` wiring `window.onerror` + `unhandledrejection`, registered in `main.tsx`. With the ErrorBoundary this covers render-phase and async/event/promise errors.
- `src/lib/errors/index.ts` — barrel re-exporting `logError` and `registerGlobalErrorHandlers`

> **Coverage rule (the client analogue of "wrap every route"):** every uncaught error must reach `logError`, and every API call should flow through one logged client (`src/lib/clients/`) rather than a raw `fetch`. The ErrorBoundary + global handlers cover the first; the second is `FetchClient`: backend calls go through `ApiClient` subclasses (`templatecentral:add (feature)`, `(pagination)`, `standards (validation-patterns)`, the batcher below) and external APIs through `FetchClient` subclasses (`templatecentral:add (integration)`). The one deliberate raw-`fetch` exception is the auth service's three session calls (`templatecentral:add (auth)`).

> **Production upgrade path:** the vendor-free batcher below is the default. With a DSN, adopt **Sentry** (`@sentry/react`) — it installs the boundary and global handlers and adds symbolication, breadcrumbs, releases and PII scrubbing (`beforeSend`), superseding the manual handlers. OpenTelemetry's browser SDK is still experimental.

This adds `logEvent` beside `logError`, a breadcrumb buffer, and batched delivery to a backend `/logs` endpoint (console-JSON in dev).

### Step 0 — Verify context

Need `<!-- templateCentral: vite-react@` on `AGENTS.md` line 1; if absent, run `templatecentral:migrate`, and if still absent, stop without writing files.

> **Step order matters.** `error-log-handler.ts` imports `@/lib/logging/breadcrumbs`, so Step 1 must precede Step 2 or `pnpm build` fails.

### 1. Create `src/lib/logging/breadcrumbs.ts`

Run `TC_PART=leaf TC_LEAF=add/logging/vite-react bash "<skill-dir>/../scaffold/shared/tc-copy.sh" "<target>"` now. It copies every file in `<skill-dir>/logging/vite-react/template/` (listed in `<skill-dir>/logging/vite-react/template.manifest`) into the project, and writes nothing, ending with a `STOP:` line, when a path is in the way. A later step that names one of those files only explains it.

An in-memory ring buffer (last 20 entries) attached to every error report. Labels are **scrubbed on the way in** — a breadcrumb is written once and read by every later report, so entry is the only place redaction holds:

Copied verbatim from `<skill-dir>/logging/vite-react/template/src/lib/logging/breadcrumbs.ts` by the copy step; do not re-type it.

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

Then attach breadcrumbs to error logs. `error.data` is the **raw backend response body** (payloads, session ids, stack traces) — keep it in the dev console only and send just `statusCode` + `message` onward:

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

Copied verbatim from `<skill-dir>/logging/vite-react/template/src/lib/logging/log-batcher.ts` by the copy step; do not re-type it.

Wire `enqueueLog` into `logError` and `logEvent`:

Only allowlisted fields cross this boundary — `enqueueLog` POSTs off the browser. Pass `statusCode` and `message`; never `error.data` or the error object:

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

Copied verbatim from `<skill-dir>/logging/vite-react/template/src/lib/logging/index.ts` by the copy step; do not re-type it.

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

Hits in comments and `redactLabel` are expected; remove any in a value passed to `logEvent` / `enqueueLog`.

**The grep is necessary but not sufficient** — it sees source keywords, not runtime values. The two PII carriers here contain no such keyword:

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

Then `cat "<skill-dir>/../build/SKILL.md"` (validate compilation), then `cat "<skill-dir>/../review/SKILL.md"`.
