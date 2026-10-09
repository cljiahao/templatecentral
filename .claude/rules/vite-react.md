---
paths:
  - "skills/**"
---

# Vite + React Rules

Stack: Vite 8, React ≥19.2.7 (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression), TypeScript 6, Node.js ≥24 (Node 24 enters maintenance 2026-10-20; Node 26 becomes Active LTS 2026-10-28 — no change yet), shadcn/ui (new-york), Tailwind CSS 4, React Router 8, TanStack Query 5, React Hook Form + Zod, Vitest + Testing Library, Docker (Nginx — image pin tracked in the scaffold Dockerfile; current stable 1.30.x). Package manager: **pnpm 12** (pinned exactly in `packageManager`, e.g. `pnpm@12.10.1`; never below 11.11.0 (security advisory fixes) — do not use npm or yarn). pnpm 12 errors with `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` on any unknown/misspelled `pnpm-workspace.yaml` key, and CI needs `pnpm/action-setup` ≥v6.1.0. Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm ≥11 no longer reads the `pnpm` field from `package.json`).

## Boundaries

- Client-only SPA — NEVER add server-side code (SSR, RSC, API route handlers)
- NEVER use `process.env` — use `import.meta.env.VITE_*` (centralized in `src/lib/constants/env.ts`)
- NEVER put secrets, API keys, or tokens in `VITE_*` — they are embedded in the client bundle
- NEVER use `export default` in application code (exception: tooling configs like `vite.config.ts`, `eslint.config.mjs`)
- NEVER put data-fetching logic directly in components — use React Query hooks in features

## Architecture

- Features: `src/features/<name>/` (api/, components/, hooks/, schemas/, types.ts, constants.ts, index.ts)
- Auth: `src/features/auth/` (AuthProvider, ProtectedRoute, LoginCard)
- Routing: `src/router.tsx` (definitions) + `src/pages/` (page components)
- Shared: `src/lib/` (clients/, constants/, errors/, utils/) + `src/components/` (layout/, ui/, widgets/)
- Integrations: `src/integrations/` (created by `add-integration` skill — clients, schemas, services for external APIs)

## Standards

Naming, exports, component patterns, performance: `templatecentral:standards`.
