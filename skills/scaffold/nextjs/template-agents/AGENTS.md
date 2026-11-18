<!-- templateCentral: nextjs@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

> Next.js 16: `cookies()`, `headers()`, `params`, `searchParams` are async; `middleware.ts` is now `proxy.ts`.

## Stack
Next.js 16 App Router · TypeScript strict · shadcn/ui · TanStack Query v5 · React Hook Form · Zod v4 · Vitest · pnpm 12 · Node ≥24

## Commands
`pnpm dev` (localhost:3000) · `pnpm build` · `pnpm test` · `pnpm check` (format + lint + typecheck)

## Layout
- `src/app/` routes and API handlers; `src/features/<name>/` (api/, components/, hooks/, types.ts)
- `src/components/widgets/` shared components; shadcn primitives in src/components/ui (see `.claude/rules/nextjs.md`)
- `src/lib/constants/env.ts` env access. Path-specific guidance: `.claude/rules/`
- Binding invariants (win on conflict): `docs/CONSTITUTION.md`

## Rules
- No `any`, no `@ts-ignore`; Zod-validate all input at every boundary; DB writes only through the repository layer
- No secrets in `NEXT_PUBLIC_*`
- Comments: default none; at most one short why-line above the code
- Tests: one per behaviour, parametrize siblings, none for constants, types or framework behaviour
- New-code gate: 0 new issues, coverage ≥80%, duplication ≤3%, cognitive complexity ≤15, every security hotspot reviewed; fix the code, never exclude or suppress

## Skills
Plugin: `templatecentral:add` (auth, database, feature, endpoint), `templatecentral:migrate`, `templatecentral:standards`. Project: `/next-verify`, `/next-migrate`.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
