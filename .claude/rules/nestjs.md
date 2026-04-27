---
paths:
  - "skills/nestjs-*/**"
---

# NestJS Rules

Stack: NestJS 11, Fastify adapter, Zod + nestjs-zod, Swagger, TypeScript 6, Jest, Docker.

## Boundaries

- NEVER use `class-validator` or `class-transformer` — use `nestjs-zod` with `createZodDto`
- NEVER put business logic in controllers — delegate to services only
- For simple CRUD, services may use Prisma/Mongoose directly; extract a repository layer when query logic grows complex
- NEVER skip Swagger docs — every endpoint needs `@ApiTags()` + `@ApiOperation()`
- NEVER use Express APIs — this uses Fastify; use `app.inject()` for e2e tests

## Architecture

- Modular: `src/modules/<feature>/` (module, controller, service, repository, dto, types)
- Shared: `src/common/` (constants/, filters/, types/, utils/), `src/config/` (env, setups/)
- Dependency flow: Controller -> Service (-> Repository for complex queries); never reversed

## Standards

- **Backend tests**: same-change Jest for API code (`test/`) — root `AGENTS.md`, `nestjs-code-standards` skill.
- Naming, DTOs, Swagger, DI: `code-standards/SKILL.md`.
