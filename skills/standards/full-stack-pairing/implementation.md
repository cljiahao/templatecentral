<!-- ref: standards/full-stack-pairing/implementation.md
     loaded-by: standards/SKILL.md
     prereq: Multi-stack pairing workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->

# Full-Stack Pairing Guide

Connect a templateCentral frontend to a templateCentral backend.

## Inputs

Locate both projects by scanning the current directory and its immediate subdirectories for an `AGENTS.md` whose line 1 is a `<!-- templateCentral: <stack>@` marker. The stack in each marker tells you which is frontend and which is backend. Ask only if this finds zero or more than one candidate for either side.

## Supported Pairings

| Frontend | Backend | Proxy Method |
|----------|---------|-------------|
| Vite + React | FastAPI | Vite `server.proxy` |
| Vite + React | NestJS | Vite `server.proxy` |
| Next.js | FastAPI | Next.js `rewrites` in `next.config.ts` |
| Next.js | NestJS | Next.js `rewrites` in `next.config.ts` |

## Steps

### Step 0 — Verify context

Confirm both `AGENTS.md` files found under **Inputs** carry the line-1 `<!-- templateCentral: <stack>@` marker.

If found → proceed to Step 1.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Backend CORS — Not Needed for the Paired Frontend

Every pairing below is **same-origin**: the browser only ever calls its own origin (`/api` or `/api/external`), and the proxy (Step 2 in dev, Step 6 in production) forwards to the backend server-side. Same-origin requests never preflight, so the frontend's origin does **not** go into the backend's CORS list. Cookie auth (Step 5) *requires* this layout. Leave `CORS_ORIGINS` (FastAPI, `src/.env`) / `CLIENT_URL` (NestJS, `.env`) as they are — they only matter for other browser origins that call the API directly with Bearer tokens.

### 2. Configure Frontend Proxy (Development)

#### Vite + React (`vite.config.ts`)

```typescript
export default defineConfig({
  server: {
    proxy: {
      '/api': {
        // FastAPI :8000; NestJS — whatever PORT you moved it to (see Port alignment)
        target: 'http://localhost:8000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
});
```

> Backend scaffolds serve routes at root; if you add a global `/api` prefix to the backend, drop the rewrite. Cookies the backend sets through the proxy carry no `Domain`, so the browser stores them for the SPA's own origin (`localhost:3000`) — where `csrfHeader()` can read `XSRF-TOKEN`.

#### Next.js (`next.config.ts`)

```typescript
const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/external/:path*',
        // Read at build time (rewrites are baked into the build output) — set BACKEND_URL
        // in the build environment, not only at runtime.
        destination: `${process.env.BACKEND_URL ?? 'http://localhost:8000'}/:path*`,
      },
    ];
  },
};
```

> Backend scaffolds serve routes at root; if you add a global `/api` prefix to the backend, append `/api` before `/:path*` in the destination.

Add the browser path to `src/lib/constants/routes.ts` — a fixed same-origin path, so it is a constant, not a `NEXT_PUBLIC_*` variable:

```typescript
export const API_ROUTES = {
  HEALTH: '/api/health',
  BACKEND: '/api/external', // rewritten to ${BACKEND_URL} by next.config.ts
} as const;
```

What the rewrite does (observed on Next 16.4 with `next build && next start` against a stub backend):

- **`proxy.ts` runs first.** Next checks `headers` → `redirects` → `proxy.ts` → rewrites, so the auth proxy gates `/api/external/*` before anything is forwarded: its `isApiRoute` branch returns 401 when there's no session cookie, and the backend never sees the request. Add the backend's unauthenticated endpoints to `proxy.ts` as **exact paths** (`/api/external/auth/session`, `/api/external/health`), not as `PUBLIC_API_PREFIXES` entries. A prefix like `/api/external/auth/session` also matches `/api/external/auth/sessionX` and `…/auth/session/..%2Fx`. The backend's own check is still the one that counts
- **Passed through unchanged:** the request's `Cookie`, `Authorization`, `X-CSRF-Token` and body, plus the response status and `Set-Cookie`. The backend sets no `Domain`, so the browser keeps the cookies for the Next origin, and `document.cookie` there can read `XSRF-TOKEN`. Every cookie on the Next origin goes to the backend, so only rewrite to a backend you own
- **Rewritten:** `Host` is set to the backend's host. `X-Forwarded-Host` becomes Next's own host (anything the client sent is dropped), and `X-Forwarded-Proto`/`-Port` are set. `X-Forwarded-For` is a problem: if the client sends one, Next forwards it **as-is**; if not, Next fills in the socket address. So list Next in the backend's `TRUST_PROXY` only when an ingress in front of Next overwrites `X-Forwarded-For`. Otherwise any client can pick its own rate-limit key
- **Not applied:** `headers()` in `next.config.ts` (the security headers) does not reach proxied responses. The browser gets the backend's own headers instead (FastAPI `SecurityHeadersMiddleware`, NestJS `@fastify/helmet`), so leave those on
- **Fixed at build time:** if you change `BACKEND_URL` at `next start`, the rewrite target stays the same

### 3. Environment Variables

Ask the user to set these in the `.env` files (agent edits to `.env` files are hook-blocked by design); document placeholders in `.env.example`/`.env.default`.

#### Frontend `.env`

```env
# Vite + React
VITE_API_BASE_URL=/api

# Next.js — server-side only, never exposed to the browser. Also needed at build time (rewrites).
BACKEND_URL=http://localhost:8000
```

> **Security**: Next.js has **no** `NEXT_PUBLIC_*` backend variable. The browser uses the fixed same-origin path `API_ROUTES.BACKEND` (`/api/external`). The real backend address goes only in `BACKEND_URL`, which the rewrite and server code read and the client bundle never contains.

> **Port alignment**: FastAPI defaults to `8000`; NestJS, Vite (template-configured), and Next.js all default to `3000`. When pairing NestJS with either frontend, move NestJS (`PORT=3001`) and point the proxy target at it.

### 4. Frontend HTTP Client

Both templates ship an abstract `FetchClient` whose `request()` is `protected` — subclass it and expose one typed public method per backend endpoint (`getHealth()` below hits the `/health` route both backend scaffolds ship).

#### Vite + React

`ApiClient` is the **one** backend client class in the SPA — this is its only definition. Feature services extend it with their own typed endpoint methods (`templatecentral:add (feature)`) instead of piling every endpoint into this file. `templatecentral:add (auth)` adds two members to it (cookie `credentials` + `X-CSRF-Token` on non-GET), so every subclass inherits browser auth.

```typescript
// src/lib/clients/api-client.ts
import { FetchClient } from './fetch-client';
import { getApiBaseUrl } from '@/lib/constants/env';

export class ApiClient extends FetchClient {
  constructor() {
    // getApiBaseUrl() throws if VITE_API_BASE_URL is missing — so construct clients
    // lazily, never at module scope (a module-scope throw blanks the page).
    super(getApiBaseUrl(), {});
  }

  getHealth(): Promise<{ status: string }> {
    return this.request('health');
  }
}
```

#### Next.js

Server-side only (route handlers, server components). Reach for `createAxiosClient` only for mTLS / pinning / interceptor chains, per `src/integrations/factories.ts`.

```typescript
// src/integrations/clients/backend-client.ts
import { FetchClient } from './base/fetch-client';

class BackendClient extends FetchClient {
  getHealth(): Promise<{ status: string }> {
    return this.request('health');
  }
}

let client: BackendClient | undefined;

// Resolved on first use, not at import — `next build` evaluates route modules, and a
// module-scope throw would fail builds where BACKEND_URL is only set at runtime.
// A relative fallback has no origin to resolve against server-side, so fail loudly.
export function getBackendClient(): BackendClient {
  const backendUrl = process.env.BACKEND_URL;
  if (!backendUrl) {
    throw new Error('BACKEND_URL is not set — required for server-side backend calls');
  }
  client ??= new BackendClient(backendUrl, {});
  return client;
}
```

**Server calls on behalf of the signed-in user.** Server code has no cookie jar of its own, so forward the browser's cookies yourself. The backend answers 401 to an anonymous call, and it requires `X-CSRF-Token` on a cookie-authenticated non-GET, which you can fill by echoing the `XSRF-TOKEN` cookie:

```typescript
// src/lib/session.ts — server-only (server components, layouts, route handlers)
import 'server-only';
import { cookies } from 'next/headers';

export async function getCurrentUser(): Promise<{ id: string | number; email: string } | null> {
  const backendUrl = process.env.BACKEND_URL;
  if (!backendUrl) throw new Error('BACKEND_URL is not set — required for server-side backend calls');
  const res = await fetch(`${backendUrl}/auth/me`, {
    headers: { cookie: (await cookies()).toString() },
    cache: 'no-store',
    signal: AbortSignal.timeout(10_000),
  });
  return res.ok ? res.json() : null;
}
```

**Client components** call the same-origin path. `FetchClient` builds its URLs with `new URL()` and is meant for server use, so browser code gets this small helper instead. `fetch` defaults to `credentials: 'same-origin'`, so the session cookie rides along without extra options:

```typescript
// src/lib/clients/backend-browser.ts — 'use client' callers only
import { API_ROUTES } from '@/lib/constants/routes';

function csrfHeader(): Record<string, string> {
  const token = document.cookie
    .split('; ')
    .find((c) => c.startsWith('XSRF-TOKEN='))
    ?.slice('XSRF-TOKEN='.length);
  return token ? { 'X-CSRF-Token': decodeURIComponent(token) } : {};
}

export function backendFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const method = (init.method ?? 'GET').toUpperCase();
  const headers = new Headers(init.headers);
  if (method !== 'GET' && method !== 'HEAD') {
    for (const [k, v] of Object.entries(csrfHeader())) headers.set(k, v);
  }
  return fetch(`${API_ROUTES.BACKEND}/${path}`, { ...init, method, headers });
}
```

### 5. Browser Auth: Enable Backend Cookie Mode

Backend auth (`templatecentral:add (auth)` on FastAPI/NestJS) reads only `Authorization: Bearer` by default, while the Vite auth skill sends the session cookie (`credentials: 'include'`) plus `X-CSRF-Token` and never holds a token. **When auth exists on both sides, apply the backend auth skill's "Browser Client (Cookie Mode)" section** — otherwise every guarded route returns 401 to the SPA:

| Frontend | Enable cookie mode on the backend? |
|----------|-----------------------------------|
| Vite + React | **Always** (once both sides have auth) |
| Next.js | When the backend owns the user session: client components then call it with that session through `API_ROUTES.BACKEND` (`backendFetch`, Step 4), and server code forwards the same cookies (`getCurrentUser`). Not needed if Next keeps its own auth and makes only service-to-service calls to `BACKEND_URL` |

Cookie mode gives the contract the Vite auth service targets: `POST /auth/session` (login → 204 + cookies), `GET /auth/me`, `POST /auth/logout`, with `X-CSRF-Token` required on every other cookie-authenticated non-GET. It sets the session cookie `HttpOnly`, `Secure` (off only in dev), `SameSite=Strict`, `Path=/`, and `__Host-` prefixed outside dev. The CSRF token is HMAC-signed and bound to the session (OWASP signed double-submit; RFC 10017 cookie rules). Bearer keeps working for non-browser clients. Then:

- **Same-origin is required, not just recommended** (RFC 10017 BFF pattern; OWASP): the SPA calls `VITE_API_BASE_URL=/api` and the Vite proxy (Step 2) / nginx (Step 6) forwards it; a Next.js app calls `/api/external`, and its rewrite (Step 2) forwards it. The backend sets `XSRF-TOKEN` as a host-only cookie on whatever host answered, so an SPA calling `api.example.com` from `app.example.com` can never read it — every non-GET 403s. Do not "fix" that with `SameSite=None`, a `Domain` attribute or credentialed CORS; route through the proxy instead
- Every SPA call goes through `ApiClient` (Step 4); the Vite auth skill makes it send `credentials: 'include'` and, on every non-GET, `X-CSRF-Token` from `csrfHeader()`. A raw `fetch` that bypasses it gets 401/403

### 6. Production Deployment

Dev proxies don't exist in production: route `/api` to the backend from the frontend's own origin.

#### Vite + React — `nginx.conf.template`

Add inside the `server` block, next to `location /` (the scaffold marks the spot). The template runs through the nginx image's `envsubst`, which only replaces variables defined in the container environment — set `BACKEND_URL` (e.g. `http://api:8000`, no trailing slash) on the frontend container; nginx refuses to start if it is missing:

```nginx
    # Same-origin API (required by cookie auth): /api/x → ${BACKEND_URL}/x.
    # No add_header here — a location-level add_header drops the server's security headers.
    location /api/ {
        proxy_pass ${BACKEND_URL}/;
        proxy_http_version 1.1;
        # $http_host, not $host: $host drops the port, so on a published port (localhost:3000)
        # backend-built absolute URLs (FastAPI's trailing-slash 307 Location) would lose it.
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        # Behind a TLS-terminating load balancer, forward its value instead: $http_x_forwarded_proto
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

nginx is now one more proxy hop in front of the backend: add its IP/CIDR to the backend's `TRUST_PROXY` (FastAPI: uvicorn forwarded-allow-ips + `X-Forwarded-Host` rewrite; NestJS: Fastify `trustProxy` — see each scaffold's `TRUST_PROXY` docs), or rate limits and logs see nginx's address for every client.

#### Next.js

The `rewrites` from Step 2 already run in production; set `BACKEND_URL` in the build environment. Any ingress (ALB, Traefik) in front stays unchanged. For `TRUST_PROXY` with Next as a hop, see the `X-Forwarded-For` caveat in Step 2.

## Rules

- Keep the backend address in environment variables (`BACKEND_URL`) — never hardcode it.
- NEVER put the backend address in `NEXT_PUBLIC_*` / `VITE_*` — Next.js needs no public backend variable at all.
- Client-side code never calls the backend by hostname — always the same-origin proxy path (`/api` on Vite, `/api/external` on Next.js).
- Next.js server components / route handlers call `BACKEND_URL` directly (server-only), forwarding the user's cookies when acting for them.