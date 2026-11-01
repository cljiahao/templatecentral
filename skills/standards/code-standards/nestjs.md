<!-- ref: standards/code-standards/nestjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## NestJS / TypeScript

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `PascalCase` | `ExampleService` |
| Interfaces | `PascalCase` | `ExampleItem` |
| Functions / Methods | `camelCase` | `findById` |
| Variables | `camelCase` | `createdAt` |
| Constants | `UPPER_SNAKE_CASE` | `HTTP_STATUS_MESSAGES` |
| Files | `kebab-case` (dot-separated) | `example.controller.ts` |
| Directories | `kebab-case` | `common/` |
| DTOs, modules, controllers, services, repositories | `PascalCase` + role suffix | `CreateExampleDto`, `ExampleModule`, `ExampleRepository` |
| Tests | `<name>.spec.ts` / `<name>.e2e-spec.ts` | `example.controller.spec.ts` |

### Module Structure

Each feature is a self-contained module under `src/modules/<name>/`:

```
<name>/
├── <name>.module.ts
├── <name>.controller.ts
├── <name>.service.ts
├── <name>.repository.ts   # optional — extract when query logic grows complex
├── <name>.dto.ts
├── <name>.types.ts
└── services/              # optional sub-services
```

### Dependency Injection

- Constructor injection; mark injectables `@Injectable()`; share via `@Module({ exports: [MyService] })`.

### DTOs and Validation

- `nestjs-zod` `createZodDto` for all DTOs (the global `ZodValidationPipe` validates them); `.partial()` for update DTOs.

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateItemSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

export class CreateItemDto extends createZodDto(CreateItemSchema) {}
export class UpdateItemDto extends createZodDto(CreateItemSchema.partial()) {}
```

### Controllers

- Thin — delegate to the service. `@HttpCode()` when the default status is wrong.

### Services

- Services contain business logic; orchestrate between repositories.
- Use `crypto.randomUUID()` for generating IDs.
- Return typed objects, not raw database results.

### Error Handling

- Use NestJS built-in exceptions: `NotFoundException`, `BadRequestException`, etc.
- The global `HttpExceptionFilter` (`@Catch(HttpException)`) formats `HttpException` subclasses only; a raw `Error`, escaping `ZodError` or driver error becomes an unformatted 500. Convert those to an `HttpException` at the boundary.
- For domain-specific errors, extend `HttpException`.
- Uniqueness is enforced by the database index: catch the duplicate-key error (Postgres `23505` — on `error.cause` under Drizzle v1 — or Mongo `11000`) and throw `ConflictException`; a SELECT-then-INSERT pre-check races under concurrent requests.

### Imports

- Use relative imports within a module.
- Barrel exports (`index.ts`) at the `modules/` level.
- Order: NestJS/framework → third-party → local.

### Swagger

- `@ApiTags()` on every controller, `@ApiOperation({ summary: '...' })` on every endpoint, `@ApiParam()`/`@ApiBody()` for parameters; `nestjs-zod` DTOs generate schemas.

### Type Annotations

- Annotate all public method parameters and return types.
- Use `type` imports for interfaces: `import type { ExampleItem } from './example.types'`.
- Prefer interfaces for object shapes, types for unions/aliases.

### Tooling

- **ESLint 10** — flat config (`eslint.config.mjs`, `sourceType: 'module'`) with typescript-eslint + prettier.
- **Prettier** — single quotes, trailing commas.
- **Vitest** — testing framework.
- **Fastify `app.inject()`** — HTTP assertions for e2e tests (NEVER use Supertest with Fastify).

### Backend Testing (mandatory)

Same-change Vitest for controllers, services, repositories, HTTP guards/pipes (`test/modules/*.spec.ts`; e2e per `templatecentral:add (endpoint)` / `templatecentral:add (test)`). Run `pnpm test` and `pnpm test:e2e` when request flows change. Vitest does not load `.env`: every required `envSchema` field gets a placeholder in `test.env` of both Vitest configs, and e2e suites without a live database override the DB provider (see the `add (database)` guide).

### Comments

- Follow `code-standards/comments.md`.
- JSDoc on exported providers/controllers/DTOs describes the contract — not the implementation.
- `eslint.config.mjs` gates comments and directives at `error`; every suppression must be scoped, used, and carry a `-- reason` (rule list: `comments.md` → Enforcement).

### Static Analysis (`eslint-plugin-sonarjs`)

`eslint.config.mjs` extends `sonarjs.configs.recommended` at `error` (bugs, security, code smells). Test files (`test/**`, `**/*.spec.ts`, `**/*.e2e-spec.ts`) turn off `no-hardcoded-secrets` / `no-clear-text-protocols`.

### Security (NestJS)

**Environment & Secrets**
- All config via `src/config/env.config.ts` — NEVER scatter `process.env` calls across services
- Secrets (`JWT_SECRET`, `DATABASE_URL`) in `.env` — NEVER hardcode fallback secrets like `'change-me'`

**Request Validation**
- Global `ZodValidationPipe` validates all DTOs — NEVER skip DTO typing on `@Body()` or `@Query()`
- Use `z.string().min(1)` and length constraints — NEVER accept unbounded strings

**Security Headers**
- `helmet` in `security.setup.ts` — NEVER remove or weaken CSP, HSTS, or frame-ancestors
- `frame-ancestors` is `'none'` + `frameguard: deny` unless `portalFrameAncestor()` accepts `APPCENTRAL_PORTAL_ORIGIN` (one https origin, never `*` or a list); NEVER loosen its regex

**CORS**
- Origins restricted to `CLIENT_URL` — NEVER use `origin: '*'` in production

**Rate Limiting & Proxy Trust**
- Auth and other abuse-prone routes are rate-limited with `@nestjs/throttler`, and `TRUST_PROXY` must be set correctly whenever the app sits behind a load balancer or reverse proxy — otherwise every client shares the proxy's IP and the limiter is either useless or spoofable via `X-Forwarded-For`. Both are mandatory; see `templatecentral:add (auth)` for the configuration.

**Auth**
- Guard-based (Passport.js + JWT) — apply at controller or route level, not globally
- NEVER return password hashes, JWT secrets, or sensitive internal fields
- Use short-lived JWTs; add refresh tokens when sessions must outlive the access-token TTL

**Least Privilege**
- Controllers return DTOs, not raw entities
- NEVER log tokens, passwords, or PII