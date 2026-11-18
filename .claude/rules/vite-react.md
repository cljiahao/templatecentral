---
paths:
  - "skills/**"
---

# Vite + React Rules

Stack: Vite 8, React ≥19.2.7 (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression), TypeScript 6, Node.js 26 (Active LTS since 2026-10-28; Node 24 is in maintenance), shadcn/ui (new-york), Tailwind CSS 4, React Router 8, TanStack Query 5, React Hook Form + Zod, Vitest + Testing Library, Docker (Nginx — image pin tracked in the scaffold Dockerfile). Package manager: **pnpm 12** (pinned exactly in `packageManager`; never below 11.11.0 (security advisory fixes) — do not use npm or yarn). pnpm 12 errors with `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` on any unknown/misspelled `pnpm-workspace.yaml` key, and CI needs `pnpm/action-setup` ≥v6.1.0. Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm ≥11 no longer reads the `pnpm` field from `package.json`).

## Boundaries

- Client-only SPA; do not add server-side code (SSR, RSC, API route handlers)
- Use `import.meta.env.VITE_*`, not `process.env` (centralized in `src/lib/constants/env.ts`)
- Do not put secrets, API keys or tokens in `VITE_*`; they are embedded in the client bundle
- Use named exports, not `export default`, in application code (exception: tooling configs like `vite.config.ts`, `eslint.config.mjs`)
- Keep data fetching out of components; use React Query hooks in features
- Auth targets the backend cookie mode (`POST /auth/session`, `GET /auth/me`, `POST /auth/logout`; once `templatecentral:add auth` runs, every backend call goes through `ApiClient` (a `FetchClient` subclass it adds), which sends `credentials: 'include'` and `X-CSRF-Token` from `csrfHeader()` on non-GET; the scaffold's `FetchClient` uses `AbortSignal.any`, so browsers ≥ Chrome 116 / Safari 17.4 / Firefox 124) — change these names only together with `add/auth/{fastapi,nestjs}.md`

## Architecture

- Features: `src/features/<name>/` (api/, components/, hooks/, schemas/, types.ts, constants.ts, index.ts)
- Auth: `src/features/auth/` (AuthProvider, ProtectedRoute, LoginCard) ships with the scaffold as a dev-only stub (`DEV_USER` behind `ENV.IS_DEV`); `templatecentral:add auth` wires it to the backend
- Routing: `src/router.tsx` (definitions) + `src/pages/` (page components)
- Shared: `src/lib/` (clients/, constants/, errors/, utils/) + `src/components/` (layout/, ui/, widgets/)
- Integrations: `src/integrations/` (created by `templatecentral:add (integration)` — clients, schemas, services for external APIs)

## Standards

Naming, exports, component patterns, performance: `templatecentral:standards`.
