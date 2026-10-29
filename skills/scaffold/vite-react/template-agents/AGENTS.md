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
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/vite-verify` | typecheck + lint + test in one pass |

Add new project skills here whenever you repeat a workflow more than once.

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
- Comments explain *why*, not *what* — no commented-out code, no change-narration (`// was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

(AGENTS.md tail — AI Harness / Skills Security / Git Workflow / Skill capture — is appended by harness-kit-finalize.md Step G; not embedded here to avoid duplication.)

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
