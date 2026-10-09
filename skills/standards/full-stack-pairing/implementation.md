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

### 1. Set Up the Backend CORS

#### FastAPI

The template already has `configure_cors()` in `src/app.py` using `api_settings.ALLOWED_CORS`. Production origins are driven by `CORS_ORIGINS` in `APISettings` (comma-separated). Ask the user to update `CORS_ORIGINS` in `src/.env` (agent edits to `.env` files are hook-blocked by design); document the placeholder in `src/.env.default`:

```env
CORS_ORIGINS=http://localhost:3000
```

No code changes — `_compute_allowed_cors()` splits `CORS_ORIGINS` on commas outside dev; in dev it allows the common localhost origins (`:3000`, `:3001`, `:5173`) automatically.

#### NestJS (`src/config/setups/security.setup.ts`)

The template already configures CORS via `serviceConfig.CLIENT_URL` (from `src/config/env.config.ts`). Ask the user to update `CLIENT_URL` in `.env` (agent edits to `.env` files are hook-blocked by design); document the placeholder in `.env.example`:

```env
CLIENT_URL=http://localhost:3000
```

No code changes — `setupCors()` reads it and accepts a comma-separated list.

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

> Backend scaffolds serve routes at root; if you add a global `/api` prefix to the backend, drop the rewrite.

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

Backend: `CORS_ORIGINS` (FastAPI, `src/.env`) / `CLIENT_URL` (NestJS, `.env`) as in Step 1.

> **Port alignment**: FastAPI defaults to `8000`; NestJS, Vite (template-configured), and Next.js all default to `3000`. When pairing NestJS with either frontend, move NestJS (`PORT=3001`) and point the proxy target at it.

### 4. Frontend HTTP Client

Both templates ship an abstract `FetchClient` whose `request()` is `protected` — subclass it and expose one typed public method per backend endpoint (`getHealth()` below hits the `/health` route both backend scaffolds ship).

#### Vite + React

```typescript
// src/lib/clients/api-client.ts
import { FetchClient } from './fetch-client';
import { getApiBaseUrl } from '@/lib/constants/env';

export class ApiClient extends FetchClient {
  constructor() {
    // getApiBaseUrl() throws if VITE_API_BASE_URL is missing — never pass the raw env var
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

### 5. Cookie Forwarding (Auth)

If using cookie-based auth:

- Backend sets session cookies `HttpOnly`, `Secure` (outside localhost), and `SameSite=Lax` — `SameSite=None` only for a genuinely cross-site deployment, and then pair it with CSRF protection
- Same-origin proxy paths (Vite proxy, Next.js rewrites) forward cookies as-is
- Cross-origin calls need `credentials: 'include'` (fetch) / `withCredentials: true` (Axios) plus credentialed CORS on the backend — with an explicit origin list, never `*`

### 6. Production Deployment

Dev proxies don't exist in production: route `/api` to the backend with a reverse proxy (Nginx, Caddy) or API gateway, and set the production origins in `CORS_ORIGINS` / `CLIENT_URL`.

## Rules

- Keep API base URLs in environment variables — never hardcode.
- NEVER put the real backend address in `NEXT_PUBLIC_*` / `VITE_*`.
- The frontend should never call the backend directly by hostname in client-side code — always go through the proxy path (e.g., `/api`).
- For Next.js server components / route handlers, you can call the backend directly using `BACKEND_URL` (server-side env var, not exposed to client).