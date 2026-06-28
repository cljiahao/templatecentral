---
paths:
  - "skills/**"
---

# NestJS Rules

Stack: NestJS 11, Fastify adapter (≥v5 — requires `@nestjs/platform-fastify ≥11.1.27`; below 11.1.24 has a trailing-slash auth-bypass advisory), Zod + nestjs-zod, Swagger, TypeScript 6, Node.js ≥24, Vitest, Docker. Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.4"`). Package manager: **pnpm 11** (pinned in `packageManager` field). Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm 11 no longer reads the `pnpm` field from `package.json`).

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
