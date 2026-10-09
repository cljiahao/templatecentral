---
paths:
  - "skills/**"
---

# NestJS Rules

Stack: NestJS 11 (NestJS 12 available since 2026-08-27; migration deferred), Fastify adapter (≥v5 — requires `@nestjs/platform-fastify ≥11.2.4`: fixes a High path-scoped middleware bypass security advisory; below 11.1.24 also has a trailing-slash auth-bypass advisory). Fastify itself ≥5.12.5 (Nest 11.2.x bundles fastify 5.11.x, which has High security advisories fixed in 5.12.2+) — bump the direct `fastify` dep and force the transitive copy with `overrides:\n  fastify: ^5.12.5` in `pnpm-workspace.yaml` (pnpm 11 reads overrides from there, not `package.json`), Zod + nestjs-zod, Swagger, TypeScript 6, Node.js ≥24 (Node 24 enters maintenance 2026-10-20; Node 26 becomes Active LTS 2026-10-28 — no change yet), Vitest, Docker. Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.4"`). Package manager: **pnpm 11** (pinned in `packageManager` field, ≥11.11.0 for security advisory fixes; pnpm 12 is stable but errors on unknown `pnpm-workspace.yaml` keys — migration deferred). Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm 11 no longer reads the `pnpm` field from `package.json`).

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
