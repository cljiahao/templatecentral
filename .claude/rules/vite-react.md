---
paths:
  - "skills/**"
---

# Vite + React Rules

Stack: Vite 8, React ≥19.2.7 (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression), TypeScript 6, Node.js ≥24, shadcn/ui (new-york), Tailwind CSS 4, React Router 7, TanStack Query 5, React Hook Form + Zod, Vitest + Testing Library, Docker (Nginx — image pin tracked in the scaffold Dockerfile; current stable 1.30.x). Package manager: **pnpm 11** (pinned in `packageManager` field — do not use npm or yarn). Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm 11 no longer reads the `pnpm` field from `package.json`).

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
