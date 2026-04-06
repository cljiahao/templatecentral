---
paths:
  - "templates/nextjs/**"
  - "claude-skills/nextjs/**"
---

# Next.js Rules

Stack: Next.js 16, React 19, TypeScript 5.9, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, NextAuth (Auth.js), React Hook Form + Zod.

## Boundaries

- App Router only — NEVER use `pages/` router
- Server components by default — add `'use client'` only for interactivity
- Use `npx shadcn@latest add` for UI primitives — NEVER install manually
- Pages compose from features — NEVER put data-fetching in page components

## Architecture

- Features: `src/features/<name>/` (api/, components/, hooks/, schemas/, types.ts, constants.ts, index.ts)
- Auth: `auth.ts` (config) + `proxy.ts` (route protection) + `features/auth/` (UI)
- Integrations: `src/integrations/` (clients/base/, schemas/, services/, factories.ts)
- Shared: `src/lib/` (constants/, errors/, utils/) + `src/components/` (layout/, ui/, widgets/)

## Standards

Read `code-standards/SKILL.md` for naming, exports, component patterns, and performance rules.
