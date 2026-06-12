---
paths:
  - "skills/**"
---

# Next.js Rules

Stack: Next.js ≥16.2.6 (16.2.5 insecure for Turbopack — auth-bypass CVEs), React ≥19.2.7 (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression), TypeScript 6, Node.js ≥24, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `templatecentral:add (auth)` skill (better-auth). Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.3"`). Package manager: **pnpm 11** (pinned in `packageManager` field — do not use npm or yarn). Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm 11 no longer reads the `pnpm` field from `package.json`).

## Boundaries

- App Router only — NEVER use `pages/` router
- Source lives under `src/` — App Router entry is `src/app/`, NOT a bare `app/` at the root
- NEVER put secrets or API keys in `NEXT_PUBLIC_*` — exposed to every browser
- Server components by default — add `'use client'` only for interactivity
- Use `npx shadcn@latest add` for UI primitives — NEVER install manually
- Pages compose from features — NEVER put data-fetching in page components
- `proxy.ts` (route protection, exists only after `templatecentral:add (auth)`): NEVER return JSON for unauthorized requests — use `new Response(null, { status: 401 })`. JSON responses from proxy create information-disclosure vectors

## Architecture

- App Router: `src/app/` (layouts, pages, API routes)
- Features: `src/features/<name>/` (api/, components/, hooks/, schemas/, types.ts, constants.ts, index.ts)
- Auth (optional, added via `templatecentral:add (auth)`): `lib/auth.ts` (server config) + `lib/auth-client.ts` (client config) + `proxy.ts` (route protection) + `features/auth/` (UI)
- Integrations: `src/integrations/` (clients/base/, schemas/, services/, factories.ts)
- Shared: `src/lib/` (constants/, errors/, utils/) + `src/components/` (layout/, ui/, widgets/)

## Standards

- **API tests**: same-change Vitest under `test/api/` for `src/app/api/**` (not React UI) — root `AGENTS.md`, `templatecentral:standards`.
- Naming, exports, components: `templatecentral:standards`.
