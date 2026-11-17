<!-- templateCentral: vite-react@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
Vite 8 · React 19 · TypeScript strict · shadcn/ui · Tailwind CSS 4 · React Router 8
TanStack React Query 5 · React Hook Form + Zod · Vitest · pnpm · Node ≥24
Client-side SPA — no SSR, no API route handlers.

## Commands
```bash
pnpm dev          # dev server
pnpm build        # production build (tsc -b && vite build)
pnpm test         # run tests
pnpm check        # format + lint + typecheck
```

## File Layout
src/features/<name>/    — feature modules (api/, components/, hooks/, types.ts)
src/components/ui/      — shadcn primitives (CLI-managed, do not edit directly)
src/components/widgets/ — reusable composed components (project-owned)
src/router.tsx          — route definitions (not filesystem convention)
src/lib/constants/env.ts — centralized VITE_* env access

## Skills
### Project skills — check here first
| Skill | What it does |
|-------|-------------|
| `/vite-verify` | typecheck + lint + test in one pass |

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (feature)` | full feature: page + query hook + components (includes components) |
| `templatecentral:add (page)` | new route + page component |
| `templatecentral:add (form)` | React Hook Form + Zod form |
| `templatecentral:add (auth)` | auth flow integration |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- `VITE_*` env vars are shipped to the browser — never API keys, tokens, or secrets
- All user input / API responses validated with Zod at every boundary
- Named exports only (except tooling configs); `function` declarations for components
- No secrets in code or `VITE_*` vars — use server-side proxy for sensitive calls
- Comments: default none; names carry meaning. When needed, one short line above the code stating the non-obvious reason, never trailing or in brackets, never change history; cite an ADR by id only (`// ADR-0049`).
- Docstrings/JSDoc only on public APIs unclear from signature and types: one summary line. No commented-out code.
- Fix the cause; suppress (`eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`) only a confirmed false positive or third-party constraint, one line, one rule, with the reason. No `NOSONAR`, no file-level disables, no coverage/Sonar exclusions.
- Tests: one per distinct behaviour; parametrize sibling cases; extend an existing test before adding one; no tests for constants, types or framework behaviour.
- Quality gate: SonarQube default (cognitive complexity 15, duplication 3% and coverage 80% on new code). Meet it by fixing code, not by excluding or suppressing.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
