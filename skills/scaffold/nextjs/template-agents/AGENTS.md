<!-- templateCentral: nextjs@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

> Next.js 16 breaking changes: `cookies()`, `headers()`, `params`, `searchParams` are
> all async. `middleware.ts` is replaced by `proxy.ts`. Verify before writing route handlers.

## Stack
Next.js 16 · App Router · TypeScript strict · shadcn/ui · TanStack Query v5
React Hook Form · Zod v4 · Vitest · pnpm 12 · Node ≥24

## Commands
```bash
pnpm dev          # dev server — http://localhost:3000
pnpm build        # production build
pnpm test         # run test suite
pnpm check        # format + lint + typecheck
```

## File Layout
src/app/                — app router (pages, layouts, route handlers)
src/app/api/            — API route handlers
src/features/<name>/    — feature modules: api/, components/, hooks/, types.ts
src/components/ui/      — shadcn primitives (CLI-managed, do not edit directly)
src/components/widgets/ — reusable composed components (project-owned)
src/proxy.ts            — frame protection (APPCENTRAL_PORTAL_ORIGIN); auth route protection after `templatecentral:add (auth)`
src/lib/auth.ts         — auth layer (after `templatecentral:add (auth)`)
src/integrations/database/ — database layer (after `templatecentral:add (database)`)
src/lib/constants/env.ts — environment constants

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/next-verify` | typecheck + lint + test in one pass |
| `/next-migrate` | Drizzle push/migrate with safety gate (once database is wired up) |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (feature)` | full feature: page + API route + hooks (includes components) |
| `templatecentral:add (endpoint)` | API route with auth guard |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod at every boundary
- DB writes via repository layer only
- `z.input<typeof Schema>` for form types; `z.infer` for post-parse output
- No secrets in `NEXT_PUBLIC_*` variables
- Comments: default none; at most one short line above the code giving the non-obvious reason; cite an ADR by id only (`// ADR-0049`); fix the cause before suppressing. Full policy: `templatecentral:standards (code-standards)` → `comments.md`
- Tests: one per distinct behaviour; parametrize sibling cases; extend an existing test before adding one; no tests for constants, types or framework behaviour.
- Quality gate: Sonar way on new code — 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%; cognitive complexity <= 15. Meet it by fixing code, not by excluding or suppressing.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
