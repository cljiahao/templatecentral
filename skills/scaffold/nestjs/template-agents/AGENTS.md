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
| Skill | What it does |
|-------|-------------|
| `/nest-verify` | typecheck + lint + test in one pass |

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (endpoint)` | new route + DTO + service method (NestJS modules — alias: module) |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- TypeScript strict — no `any`
- All user input validated with Zod (`createZodDto`) at every boundary
- kebab-case filenames, PascalCase classes, camelCase methods; named exports only
- No secrets in code — use env vars; document in `.env.example`
- Comments: default none; names carry meaning. When needed, one short line above the code stating the non-obvious reason, never trailing or in brackets, never change history; cite an ADR by id only (`// ADR-0049`).
- Docstrings/JSDoc only on public APIs unclear from signature and types: one summary line. No commented-out code.
- Fix the cause; suppress (`eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`) only a confirmed false positive or third-party constraint, one line, one rule, with the reason. No `NOSONAR`, no file-level disables, no coverage/Sonar exclusions.
- Tests: one per distinct behaviour; parametrize sibling cases; extend an existing test before adding one; no tests for constants, types or framework behaviour.
- Quality gate: SonarQube default (cognitive complexity 15, duplication 3% and coverage 80% on new code). Meet it by fixing code, not by excluding or suppressing.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
