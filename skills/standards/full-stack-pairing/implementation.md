<!-- ref: standards/full-stack-pairing/implementation.md
     loaded-by: standards/SKILL.md
     prereq: Multi-stack pairing workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->

# Full-Stack Pairing Guide

Cross-stack guidance for connecting a templateCentral frontend to a templateCentral backend.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## Inputs

- **Frontend project path** — current directory if running from inside the frontend
  project, or ask if running from a mono repo root. The agent should scan immediate
  subdirectories for a `<!-- templateCentral:` marker to identify the frontend path
  automatically before asking.
- **Backend project path** — ask the user. The agent should scan immediate
  subdirectories for a second `<!-- templateCentral:` marker to suggest the backend
  path.

## Supported Pairings

| Frontend | Backend | Proxy Method |
|----------|---------|-------------|
| Vite + React | FastAPI | Vite `server.proxy` |
| Vite + React | NestJS | Vite `server.proxy` |
| Next.js | FastAPI | Next.js `rewrites` in `next.config.ts` |
| Next.js | NestJS | Next.js `rewrites` in `next.config.ts` |

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.

### 1. Set Up the Backend CORS

#### FastAPI

The template already has `configure_cors()` in `src/app.py` using `api_settings.ALLOWED_CORS`. Production origins are driven by `CORS_ORIGINS` in `APISettings` (comma-separated). Update `src/.env`:

```env
CORS_ORIGINS=http://localhost:3000
```

> The templateCentral Vite template defaults to port `3000` (same as Next.js). For multiple origins: `CORS_ORIGINS=http://localhost:3000,http://localhost:3001`.

No code changes needed — `_compute_allowed_cors()` already reads `CORS_ORIGINS` and splits by comma for non-dev environments. In dev, common localhost origins (`localhost:3000`, `localhost:5173`, `127.0.0.1` variants) are allowed automatically.

#### NestJS (`src/config/setups/security.setup.ts`)

The template already configures CORS via `serviceConfig.CLIENT_URL` (from `src/config/env.config.ts`). Update `CLIENT_URL` in `.env`:

```env
CLIENT_URL=http://localhost:3000
```

> **Port note**: The templateCentral Vite template defaults to port `3000` (same as NestJS and Next.js). When pairing Vite or Next.js with NestJS, change one port to avoid conflict (e.g., set NestJS to `3001`).

The template's `setupCors()` reads this automatically — no code changes needed unless you need multiple origins (comma-separated: `CLIENT_URL=http://localhost:3000,http://localhost:3001`).

### 2. Configure Frontend Proxy (Development)

#### Vite + React (`vite.config.ts`)

```typescript
export default defineConfig({
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8000', // FastAPI or NestJS
        changeOrigin: true,
      },
    },
  },
});
```

#### Next.js (`next.config.ts`)

```typescript
const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/external/:path*',
        destination: 'http://localhost:8000/api/:path*',
      },
    ];
  },
};
```

### 3. Environment Variables

#### Frontend `.env`

```env
# Vite + React
VITE_API_BASE_URL=/api

# Next.js (add these — the template ships with NEXT_PUBLIC_BASE_URL only)
NEXT_PUBLIC_BACKEND_URL=/api/external
BACKEND_URL=http://localhost:8000  # server-side direct calls
```

> **Security**: `NEXT_PUBLIC_BACKEND_URL` must be a **relative proxy path** (e.g., `/api/external`) — NEVER the actual backend server address (`http://...`). `NEXT_PUBLIC_*` vars are embedded in the client bundle and visible to users. Use `BACKEND_URL` (no `NEXT_PUBLIC_` prefix) for the real backend address — it stays server-side only.

#### Backend `.env`

```env
# FastAPI — update CORS_ORIGINS in src/.env
CORS_ORIGINS=http://localhost:3000

# NestJS — already in .env.example
CLIENT_URL=http://localhost:3000
```

> **Port alignment**: FastAPI defaults to `8000`, NestJS defaults to `3000`, Vite defaults to `3000`, Next.js defaults to `3000`. Ensure your proxy target port matches the backend. When pairing NestJS with Vite or Next.js, change one port to avoid conflict.

### 4. Frontend HTTP Client

Both templates have a base HTTP client. Configure it with the API base URL:

#### Vite + React

`FetchClient` is abstract — create a concrete subclass for your backend API:

```typescript
// src/lib/clients/api-client.ts
import { FetchClient } from './fetch-client';

export class ApiClient extends FetchClient {
  constructor() {
    super(import.meta.env.VITE_API_BASE_URL, {});
  }
}
```

#### Next.js

Use `createAxiosClient` from the template's base client:

```typescript
// src/integrations/clients/backend-client.ts
import { createAxiosClient } from './base/axios-client';

export const backendClient = createAxiosClient({
  baseURL: process.env.BACKEND_URL || '/api/external',
});
```

### 5. Cookie Forwarding (Auth)

If using cookie-based auth (e.g., session tokens), ensure:

- Backend sets `SameSite=Lax` (or `None` + `Secure` for cross-origin)
- Frontend proxy preserves cookies (both Vite proxy and Next.js rewrites do this by default)
- `credentials: 'include'` on fetch calls, or `withCredentials: true` on Axios

### 6. Production Deployment

In production, you typically:
- Deploy frontend and backend separately
- Use a reverse proxy (Nginx, Caddy) or API gateway to route `/api` to the backend
- Set absolute URLs in environment variables instead of relying on dev proxy

## Rules

- Dev proxies (`server.proxy`, `rewrites`) are for development only — do not rely on them in production.
- Always set `allow_credentials=True` / `credentials: true` in CORS if using cookies.
- Keep API base URLs in environment variables — never hardcode.
- The frontend should never call the backend directly by hostname in client-side code — always go through the proxy path (e.g., `/api`).
- For Next.js server components / route handlers, you can call the backend directly using `BACKEND_URL` (server-side env var, not exposed to client).