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

### 3. Environment Variables

Ask the user to set these in the `.env` files (agent edits to `.env` files are hook-blocked by design); document placeholders in `.env.example`/`.env.default`.

#### Frontend `.env`

```env
# Vite + React
VITE_API_BASE_URL=/api

# Next.js (the template ships with NEXT_PUBLIC_BASE_URL only)
NEXT_PUBLIC_BACKEND_URL=/api/external
# Server-side only — never exposed to the browser
BACKEND_URL=http://localhost:8000
```

> **Security**: `NEXT_PUBLIC_BACKEND_URL` must be a **relative proxy path** (e.g., `/api/external`) — NEVER the actual backend server address (`http://...`). `NEXT_PUBLIC_*` vars are embedded in the client bundle and visible to users. Use `BACKEND_URL` (no `NEXT_PUBLIC_` prefix) for the real backend address — it stays server-side only.

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

### 5. Browser Auth: Enable Backend Cookie Mode

Backend auth (`templatecentral:add (auth)` on FastAPI/NestJS) reads only `Authorization: Bearer` by default, while the Vite auth skill sends the session cookie (`credentials: 'include'`) plus `X-CSRF-Token` and never holds a token. **When auth exists on both sides, apply the backend auth skill's "Browser Client (Cookie Mode)" section** — otherwise every guarded route returns 401 to the SPA:

| Frontend | Enable cookie mode on the backend? |
|----------|-----------------------------------|
| Vite + React | **Always** (once both sides have auth) |
| Next.js | Only if client components call the backend from the browser (`NEXT_PUBLIC_BACKEND_URL`) with the user's session. Server-side calls via `BACKEND_URL` don't need it (no browser cookie jar involved) |

Cookie mode gives the contract the Vite auth service targets: `POST /auth/session` (login → 204 + cookies), `GET /auth/me`, `POST /auth/logout`, with `X-CSRF-Token` required on every other cookie-authenticated non-GET. It sets the session cookie `HttpOnly`, `Secure` (off only in dev), `SameSite=Strict`, `Path=/`, and `__Host-` prefixed outside dev. The CSRF token is HMAC-signed and bound to the session (OWASP signed double-submit; RFC 10017 cookie rules). Bearer keeps working for non-browser clients. Then:

- **Same-origin is required, not just recommended** (RFC 10017 BFF pattern; OWASP): the SPA calls `VITE_API_BASE_URL=/api` and the Vite proxy (Step 2) / nginx (Step 6) forwards it. The backend sets `XSRF-TOKEN` as a host-only cookie on whatever host answered, so an SPA calling `api.example.com` from `app.example.com` can never read it — every non-GET 403s. Do not "fix" that with `SameSite=None`, a `Domain` attribute or credentialed CORS; route through the proxy instead
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
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        # Behind a TLS-terminating load balancer, forward its value instead: $http_x_forwarded_proto
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

nginx is now one more proxy hop in front of the backend: add its IP/CIDR to the backend's `TRUST_PROXY` (FastAPI: uvicorn forwarded-allow-ips + `X-Forwarded-Host` rewrite; NestJS: Fastify `trustProxy` — see each scaffold's `TRUST_PROXY` docs), or rate limits and logs see nginx's address for every client.

#### Next.js

The `rewrites` from Step 2 already run in production; set `BACKEND_URL` in the build environment. Any ingress (ALB, Traefik) in front stays unchanged.

## Rules

- Keep API base URLs in environment variables — never hardcode.
- NEVER put the real backend address in `NEXT_PUBLIC_*` / `VITE_*`.
- The frontend should never call the backend directly by hostname in client-side code — always go through the proxy path (e.g., `/api`).
- For Next.js server components / route handlers, you can call the backend directly using `BACKEND_URL` (server-side env var, not exposed to client).