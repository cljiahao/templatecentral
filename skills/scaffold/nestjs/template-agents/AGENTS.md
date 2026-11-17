<!-- templateCentral: nestjs@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
NestJS 12 · Fastify · Zod + nestjs-zod · Swagger · TypeScript strict · Vitest · pnpm · Node ≥24.15

## Commands
```bash
pnpm start:dev    # dev server with hot reload
pnpm build        # compile TypeScript
pnpm test         # run unit tests
pnpm test:e2e     # run e2e tests
pnpm check        # format + lint + typecheck
```

## Architecture
- `src/modules/<name>/` — one module per feature (controller → service → optional repository)
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes/filters in `app.module.ts`; auth guards at controller level
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/nest-verify` | typecheck + lint + test in one pass |

Add new project skills here whenever you repeat a workflow more than once.

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (endpoint)` | new route + DTO + service method (NestJS modules — alias: module) |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod (`createZodDto`) at every boundary
- kebab-case filenames, PascalCase classes, camelCase methods; named exports only
- No secrets in code — use env vars; document in `.env.example`
- Comments: default none; at most one short line above the code giving the non-obvious reason; cite an ADR by id only (`// ADR-0049`); fix the cause before suppressing. Full policy: `templatecentral:standards (code-standards)` → `comments.md`
- Tests: one per distinct behaviour; parametrize sibling cases; extend an existing test before adding one; no tests for constants, types or framework behaviour.
- Quality gate: Sonar way on new code — 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%; cognitive complexity <= 15. Meet it by fixing code, not by excluding or suppressing.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
