---
paths:
  - "skills/**"
---

# Next.js Rules

Stack: Next.js ≥16.3.8 (current 16.4.x; 16.3.8 fixes critical unauthenticated RCE security advisories — Image Optimization AVIF, Windows hosts, `next/og` ImageResponse — plus a High SSRF and a Medium cache-poisoning advisory; there is no 16.2.x fix, so 16.2 is unsafe; LTS 15.5 line floor ≥15.5.27), React ≥19.2.7 (RSC DoS advisory fix; 19.2.6 had a Server-Actions regression; React 19.3 ships alongside Next 16.4 — fine but not forced), TypeScript 6, Node.js ≥24 (Node 24 enters maintenance 2026-10-20; Node 26 becomes Active LTS 2026-10-28 — no change yet), shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `templatecentral:add (auth)` skill (better-auth ≥1.7.7 — two critical security advisories fixed only in 1.7.7; 1.7 removed the `oidcProvider` plugin → `@better-auth/oauth-provider`, moved MCP to `@better-auth/mcp`, renamed `experimental.joins` → `advanced.database.joins` (regenerate the Drizzle schema), made `Account.issuer` required, removed `validAudiences`, and folded genericOAuth into `signIn.social` with PKCE on by default). Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.4"`). Package manager: **pnpm 12** (pinned exactly in `packageManager`, e.g. `pnpm@12.10.1`; never below 11.11.0 (security advisory fixes) — do not use npm or yarn). pnpm 12 errors with `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` on any unknown/misspelled `pnpm-workspace.yaml` key, and CI needs `pnpm/action-setup` ≥v6.1.0. Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm ≥11 no longer reads the `pnpm` field from `package.json`).

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
