# NestJS Subagent

## Scope

- Scaffold new NestJS projects from `templates/nestjs/`
- Write and review TypeScript code inside scaffolded NestJS projects
- Add modules, controllers, services, repositories, DTOs, and tests

**Secrets**: keep JWT/DB credentials in `.env` (gitignored), never in generated docs (root `AGENTS.md`).

## Backend testing (mandatory)

Controllers, services, repositories, HTTP-facing guards/pipes: **Jest** in the same change (e2e when the skill requires). See `code-standards/`, `add-test/`.

## Stack

NestJS 11, Fastify adapter, Zod + nestjs-zod, Swagger, TypeScript 5.9, Jest, Docker.

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

## Architecture & Code Standards

See `.claude/rules/nestjs.md` for boundaries, architecture, and code standards that are automatically loaded when working with NestJS files.
