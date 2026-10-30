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
- Comments explain *why*, not *what* — no commented-out code, no change-narration (`// was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

(AGENTS.md tail — AI Harness / Skills Security / Git Workflow / Skill capture — is appended by harness-kit-finalize.md Step G; not embedded here to avoid duplication.)

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
