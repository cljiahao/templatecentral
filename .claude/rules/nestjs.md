---
paths:
  - "skills/**"
---

# NestJS Rules

Stack: NestJS 11, held on major 11 (`@nestjs/common`/`core`/`platform-fastify`/`testing` ≥11.2.11, `@nestjs/swagger` ≥11.4.8, `@nestjs/cli` ≥11.0.24, `@nestjs/schematics` ≥11.1.0; ecosystem packages on the majors whose peer ranges include Nest 11: `@nestjs/jwt`, `@nestjs/passport`, `@nestjs/mongoose`, `@nestjs/throttler` ≥6.7, nestjs-pino ≥5.3.1). Nest 11 still gets security backports (11.2.10 and 11.2.11 shipped in 2026-11); the floor is 11.2.11 because earlier 11.x releases carry High advisories (platform-fastify path-scoped middleware bypass fixed in 11.2.8 and 11.2.9, `ParseFilePipe` crash fixed in 11.2.10). Fastify adapter: `@nestjs/platform-fastify` 11.2.11 bundles fastify 5.12.8, so keep the direct `fastify` floor ≥5.12.8 (no `overrides: fastify`). Packages are CommonJS (no `"type": "module"`, no `.js` import suffixes). Zod + nestjs-zod (keep `createZodDto`; pinned exactly at 5.6.0, whose peers are `@nestjs/common` ^10||^11 and `@nestjs/swagger` ^7.4.2||^8||^11, so Nest and Swagger stay on major 11 and `pnpm install` prints no peer warning; lift the hold when a nestjs-zod release peers the next majors), Swagger, TypeScript 6, Node.js 26 (Active LTS since 2026-10-28; the template's choice, Nest 11 needs less), Vitest, Docker. Database (via `templatecentral:add (database)`): Drizzle ORM v1 (pre-release RC — pin the exact RC, e.g. `"drizzle-orm": "1.0.0-rc.4"`). Package manager: **pnpm 12** (pinned exactly in `packageManager`; never below 11.11.0 (security advisory fixes)). pnpm 12 errors with `ERR_PNPM_UNRECOGNIZED_WORKSPACE_SETTINGS` on any unknown/misspelled `pnpm-workspace.yaml` key, and CI needs `pnpm/action-setup` ≥v6.1.0. Native addons: add `allowBuilds:\n  <pkg>: true` to `pnpm-workspace.yaml` (pnpm ≥11 no longer reads the `pnpm` field from `package.json`). Advisory exceptions go in `.claude/dep-audit-allow.txt` (expiring entries); the deps gate rejects native pnpm suppressions (`audit.ignore`, `auditConfig`). If deepmerge's no-fix prototype-pollution advisory GHSA-gcqx-w48m-w2h4 starts failing the audit, allowlist it there — nestjs-zod calls deepmerge only during OpenAPI generation, never on request data; remove the entry once a nestjs-zod release drops deepmerge (upstream PR #479). The prod Dockerfile runs Node with `--disable-proto=delete`.

## Boundaries

- Use `nestjs-zod` with `createZodDto`, not `class-validator` or `class-transformer`
- Keep business logic out of controllers; delegate to services
- For simple CRUD, services may use Drizzle/Kysely/Mongoose directly; extract a repository layer when query logic grows complex
- Document every endpoint in Swagger with `@ApiTags()` + `@ApiOperation()`
- Do not use Express APIs; the app runs on Fastify, so e2e tests use `app.inject()`
- Browser SPA clients authenticate via the auth skill's cookie mode (`@fastify/cookie` 11, HttpOnly `__Host-session` + session-bound `XSRF-TOKEN`/`X-CSRF-Token`, `POST /auth/session`/`/auth/logout`) — keep Vite's auth service, `add/auth/nestjs.md`, and `standards/full-stack-pairing` aligned on these names

## Architecture

- Modular: `src/modules/<feature>/` (module, controller, service, repository, dto, types)
- Shared: `src/common/` (constants/, filters/, types/, utils/), `src/config/` (env, setups/)
- Dependency flow: Controller -> Service (-> Repository for complex queries); never reversed

## Standards

- **Backend tests**: same-change Vitest for API code (`test/`) — root `AGENTS.md`, `templatecentral:standards`.
- Naming, DTOs, Swagger, DI: `templatecentral:standards`.
