<!-- templateCentral: nestjs@6.0.0 -->
# AGENTS.md — __TC_PROJECT_TITLE__

## Stack
NestJS 12 · Fastify · Zod + nestjs-zod · Swagger · TypeScript strict · Vitest · pnpm · Node ≥26.12.1

## Commands
`pnpm start:dev` · `pnpm build` · `pnpm test` · `pnpm test:e2e` · `pnpm check` (format + lint + typecheck)

## Architecture
- `src/modules/<name>/`: one module per feature (controller → service → optional repository)
- Controller, DTO and `app.module.ts` conventions: `.claude/rules/nestjs.md`
- Binding invariants (win on conflict): `docs/CONSTITUTION.md`. Path-specific guidance: `.claude/rules/`

## Rules
- No `any`, no `@ts-ignore`; Zod-validate all input (`createZodDto`) at every boundary
- kebab-case filenames, PascalCase classes, camelCase methods; named exports only
- No secrets in code: env vars, documented in `.env.example`
- Comments: default none; at most one short why-line above the code
- Tests: one per behaviour, parametrize siblings, none for constants, types or framework behaviour
- New-code gate: 0 new issues, coverage ≥80%, duplication ≤3%, cognitive complexity ≤15, every security hotspot reviewed; fix the code, never exclude or suppress

## Skills
Plugin: `templatecentral:add` (auth, database, endpoint), `templatecentral:migrate`, `templatecentral:standards`. Project: `/nest-verify`.

## Project-Specific Notes
<!-- [[post-harness]] — reserved for meta-harness integration (see FUTURE.md) -->
