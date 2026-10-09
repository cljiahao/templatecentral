---
paths:
  - "skills/**"
---

# NestJS Rules

Stack: NestJS 12 (`@nestjs/common`/`core`/`platform-fastify`/`testing` ≥12.1.2, `@nestjs/swagger` ≥12.0.2, `@nestjs/cli` ≥12.0.8, `@nestjs/schematics` ≥12.0.6; ecosystem on 12-compatible majors: `@nestjs/jwt` 12, `@nestjs/passport` 12, `@nestjs/mongoose` 12, `@nestjs/axios` 12, `@nestjs/throttler` ≥6.7, nestjs-pino ≥5.3.1), Fastify adapter (`@nestjs/platform-fastify` ≥12.0.2 fixes a High path-scoped middleware bypass security advisory; NestJS 11 needed ≥11.2.4). Fastify itself ≥5.12.5 (High security advisories fixed in 5.12.2+) — Nest 12.1.2 bundles fastify 5.12.5, so keep the direct `fastify` floor; the old `overrides: fastify` in `pnpm-workspace.yaml` is no longer needed. Nest 12 packages are ESM; projects stay CommonJS via Node `require(esm)` (no `"type": "module"`, no `.js` import suffixes). Nest 12 breaking changes to respect: `@Optional()` is not inherited (a subclass needs its own constructor re-declaring it); custom pipes use the generic `ArgumentMetadata`; `@nestjs/config` validates via Standard Schema (library options under `validationOptions.libraryOptions`); Terminus removed `HealthIndicator`/`HealthCheckError` (use `HealthIndicatorService`); CLI `--webpack` → `--builder rspack`. Zod + nestjs-zod (keep `createZodDto` — nestjs-zod 5.5 still declares Nest ≤11 peers, so `pnpm install` warns; verified working on Nest 12.1 — do NOT switch to Nest 12's native `@Body({ schema })`/`StandardSchemaValidationPipe`), Swagger, TypeScript 6, Node.js `^24.15.0 || >=26` (runtime needs ≥20.19/≥22.12, but the Nest 12 schematics require ≥24.15 on the 24 line; Node 24 enters maintenance 2026-10-20; Node 26 becomes Active LTS 2026-10-28 — no change yet), Vitest, Docker. Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.4"`). Package manager: **pnpm 12** (pinned exactly in `packageManager`, e.g. `pnpm@12.10.1`; never below 11.11.0 (security advisory fixes)). pnpm 12 errors with `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` on any unknown/misspelled `pnpm-workspace.yaml` key, and CI needs `pnpm/action-setup` ≥v6.1.0. Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm ≥11 no longer reads the `pnpm` field from `package.json`).

## Boundaries

- NEVER use `class-validator` or `class-transformer` — use `nestjs-zod` with `createZodDto`
- NEVER put business logic in controllers — delegate to services only
- For simple CRUD, services may use Drizzle/Kysely/Mongoose directly; extract a repository layer when query logic grows complex
- NEVER skip Swagger docs — every endpoint needs `@ApiTags()` + `@ApiOperation()`
- NEVER use Express APIs — this uses Fastify; use `app.inject()` for e2e tests

## Architecture

- Modular: `src/modules/<feature>/` (module, controller, service, repository, dto, types)
- Shared: `src/common/` (constants/, filters/, types/, utils/), `src/config/` (env, setups/)
- Dependency flow: Controller -> Service (-> Repository for complex queries); never reversed

## Standards

- **Backend tests**: same-change Vitest for API code (`test/`) — root `AGENTS.md`, `templatecentral:standards`.
- Naming, DTOs, Swagger, DI: `templatecentral:standards`.
