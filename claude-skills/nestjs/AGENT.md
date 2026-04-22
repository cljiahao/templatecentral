# NestJS Subagent

## Scope

- Scaffold new NestJS projects from `templates/nestjs/`
- Write and review TypeScript code inside scaffolded NestJS projects
- Add modules, controllers, services, repositories, DTOs, and tests

**Secrets**: keep JWT/DB credentials in `.env` (gitignored), never in generated docs (root `AGENTS.md`).

## Backend testing (mandatory)

Controllers, services, repositories, HTTP-facing guards/pipes: **Jest** in the same change (e2e when the skill requires). See `code-standards/`, `add-test/`.

## Stack

NestJS 11, Fastify adapter, Zod + nestjs-zod, Swagger, TypeScript 6, Jest, Docker.

## Skills Available

| Skill | When to use |
|-------|-------------|
| `scaffold/` | User wants to create a new NestJS project |
| `code-standards/` | Before writing or reviewing any TypeScript code |
| `add-module/` | Adding a new feature module with CRUD |
| `add-test/` | Adding unit or e2e tests |
| `add-auth/` | Adding JWT authentication with Passport.js |
| `add-database/` | Adding a database — Prisma (SQL), Kysely (SQL), or Mongoose (MongoDB), with optional AWS IAM auth |
| `add-integration/` | Connecting to an external API (@nestjs/axios + Zod schemas) |

## Shared Skills

Cross-stack skills in `claude-skills/shared/` — use these instead of inventing patterns:

| Skill | When to use |
|-------|-------------|
| `shared/validation-patterns/` | Endpoint input validation needing OWASP/CWE compliance |
| `shared/add-error-handling/` | Consistent error responses and security boundaries across controllers |
| `shared/full-stack-pairing/` | Wiring a frontend client to this NestJS backend (CORS, auth headers) |
| `shared/task-management/` | Complex multi-step features — opt-in via project `AGENTS.md` |
| `shared/remove-example/` | Removing template placeholder code after scaffold |
| `shared/add-pagination/` | Adding offset or cursor-based pagination to endpoints |

## Architecture & Code Standards

See `.claude/rules/nestjs.md` for boundaries, architecture, and code standards that are automatically loaded when working with NestJS files.
