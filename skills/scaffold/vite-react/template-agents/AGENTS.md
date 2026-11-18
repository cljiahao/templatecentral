<!-- templateCentral: vite-react@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
Vite 8 · React 19 · TypeScript strict · shadcn/ui · Tailwind CSS 4 · React Router 8 · TanStack Query 5 · React Hook Form + Zod · Vitest · pnpm · Node ≥24. Client-side SPA: no SSR, no API handlers.

## Commands
`pnpm dev` · `pnpm build` (tsc -b && vite build) · `pnpm test` · `pnpm check` (format + lint + typecheck)

## Layout
- `src/features/<name>/` (api/, components/, hooks/, types.ts); `src/router.tsx` route definitions
- `src/components/widgets/` shared components; shadcn primitives in src/components/ui (see `.claude/rules/vite-react.md`)
- `src/lib/constants/env.ts` centralizes `VITE_*` access. Path-specific guidance: `.claude/rules/`
- Binding invariants (win on conflict): `docs/CONSTITUTION.md`

## Rules
- `VITE_*` ships to the browser: no keys, tokens or secrets in it or in code; sensitive calls go through a server-side proxy
- Zod-validate all user input and API responses at every boundary
- Named exports only (except tooling configs); `function` declarations for components
- Comments: default none; at most one short why-line above the code
- Tests: one per behaviour, parametrize siblings, none for constants, types or framework behaviour
- New-code gate: 0 new issues, coverage ≥80%, duplication ≤3%, cognitive complexity ≤15, every security hotspot reviewed; fix the code, never exclude or suppress

## Skills
Plugin: `templatecentral:add` (feature, page, form, auth), `templatecentral:standards`. Project: `/vite-verify`.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
