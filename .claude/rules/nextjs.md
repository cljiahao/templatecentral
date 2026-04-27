---
paths:
  - "templates/nextjs/**"
  - "claude-skills/nextjs/**"
---

# Next.js Rules

Stack: Next.js 16, React 19, TypeScript 6, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `nextjs-add-auth` skill (Auth.js/NextAuth). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).

## Boundaries

- App Router only — NEVER use `pages/` router
- Source lives under `src/` — App Router entry is `src/app/`, NOT a bare `app/` at the root
- NEVER put secrets or API keys in `NEXT_PUBLIC_*` — exposed to every browser
- Server components by default — add `'use client'` only for interactivity
- Use `npx shadcn@latest add` for UI primitives — NEVER install manually
- Pages compose from features — NEVER put data-fetching in page components
- `proxy.ts` (route protection, exists only after `nextjs-add-auth`): NEVER return JSON for unauthorized requests — use `new Response(null, { status: 401 })`. JSON responses from proxy create information-disclosure vectors

## Architecture

- App Router: `src/app/` (layouts, pages, API routes)
- Features: `src/features/<name>/` (api/, components/, hooks/, schemas/, types.ts, constants.ts, index.ts)
- Auth (optional, added via `nextjs-add-auth`): `auth.ts` (config) + `proxy.ts` (route protection) + `features/auth/` (UI)
- Integrations: `src/integrations/` (clients/base/, schemas/, services/, factories.ts)
- Shared: `src/lib/` (constants/, errors/, utils/) + `src/components/` (layout/, ui/, widgets/)

## Standards

- **API tests**: same-change Vitest under `test/api/` for `src/app/api/**` (not React UI) — root `AGENTS.md`, `claude-skills/nextjs/code-standards/SKILL.md`.
- Naming, exports, components: `code-standards/SKILL.md`.
