---
name: nestjs-code-standards
description: Use when writing or reviewing TypeScript code in a NestJS project — covers naming, decorators, module structure, Zod DTOs, and dependency rules.
disable-model-invocation: true
---

# NestJS / TypeScript Code Standards

## Code Quality (enforce before marking any task done)

- **YAGNI** — only what the task requires; no speculative helpers or files
- **DRY** — extract at second repetition; inline if only one callsite
- **SRP** — one responsibility per file/function; controllers handle HTTP, services handle logic
- **SoC** — HTTP separate from business logic; DTO validation separate from domain logic
- **No premature abstractions** — wait for the third callsite
- **No dead code** — no commented-out code, unused imports, or TODO stubs
- **Validate at boundaries** — Zod (`createZodDto`) for all DTOs, API responses, and env vars
- **Fail loudly** — no empty catch blocks; log with context; return meaningful HTTP status codes
- **Least privilege** — return only needed fields; never expose internal IDs without auth checks
- **No secrets** — no hardcoded tokens or keys; env vars only; document in `.env.example`

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `PascalCase` | `ExampleService` |
| Interfaces | `PascalCase` | `ExampleItem` |
| Functions / Methods | `camelCase` | `findById` |
| Variables | `camelCase` | `createdAt` |
| Constants | `UPPER_SNAKE_CASE` | `HTTP_STATUS_MESSAGES` |
| Files | `kebab-case` (dot-separated) | `example.controller.ts` |
| Directories | `kebab-case` | `common/` |
| DTOs | `PascalCase` + `Dto` suffix | `CreateExampleDto` |
| Modules | `PascalCase` + `Module` suffix | `ExampleModule` |
| Controllers | `PascalCase` + `Controller` suffix | `ExampleController` |
| Services | `PascalCase` + `Service` suffix | `ExampleService` |
| Repositories | `PascalCase` + `Repository` suffix | `ExampleRepository` |
| Tests | `<name>.spec.ts` / `<name>.e2e-spec.ts` | `example.controller.spec.ts` |

## Module Structure

Each feature is a self-contained module under `src/modules/<name>/`:

```
<name>/
├── <name>.module.ts       # @Module declaration
├── <name>.controller.ts   # HTTP endpoints (thin)
├── <name>.service.ts      # Business logic
├── <name>.repository.ts   # Data access (optional — extract when query logic grows complex)
├── <name>.dto.ts          # Zod DTOs
├── <name>.types.ts        # TypeScript interfaces
└── services/              # (optional) Sub-services for complex domains
    └── <sub>.ts
```

## Dependency Injection

- Use constructor injection — NestJS resolves dependencies automatically.
- Mark all injectables with `@Injectable()`.
- Export services from modules if they need to be consumed by other modules.
- Use `@Module({ exports: [MyService] })` to make services available.

## DTOs and Validation

- Use `nestjs-zod` with `createZodDto` for all DTOs.
- Define Zod schemas as `const` above the DTO class.
- Use `.partial()` for update DTOs.
- The global `ZodValidationPipe` validates all incoming requests automatically.

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateItemSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

const UpdateItemSchema = CreateItemSchema.partial();

export class CreateItemDto extends createZodDto(CreateItemSchema) {}
export class UpdateItemDto extends createZodDto(UpdateItemSchema) {}
```

## Controllers

- Keep controllers thin — accept request, delegate to service, return response.
- Use `@ApiTags()` and `@ApiOperation()` for Swagger documentation.
- Use `@HttpCode()` when the default status code is not appropriate.
- Use `@Param()`, `@Body()`, `@Query()` for extracting request data.

## Services

- Services contain business logic and orchestrate between repositories.
- One service per module (split into sub-services if complexity warrants).
- Use `crypto.randomUUID()` for generating IDs (Node.js built-in).
- Return typed objects, not raw database results.

## Error Handling

- Use NestJS built-in exceptions: `NotFoundException`, `BadRequestException`, etc.
- Provide descriptive error messages.
- The global `HttpExceptionFilter` catches and formats all HTTP exceptions.
- For domain-specific errors, create custom exceptions extending `HttpException`.

## Imports

- Use relative imports within a module.
- Use path-relative imports from `src/` root for cross-module imports.
- Barrel exports (`index.ts`) at the `modules/` level.
- Order: NestJS/framework → third-party → local (separated by blank lines).

## Swagger

- Every controller gets `@ApiTags()`.
- Every endpoint gets `@ApiOperation({ summary: '...' })`.
- Use `@ApiParam()` and `@ApiBody()` for parameter documentation.
- DTOs from `nestjs-zod` generate Swagger schemas automatically.

## Type Annotations

- Annotate all public method parameters and return types.
- Use `type` imports for interfaces: `import type { ExampleItem } from './example.types'`.
- Prefer interfaces for object shapes, types for unions/aliases.

## Tooling

- **ESLint 9** — flat config with typescript-eslint + prettier.
- **Prettier** — single quotes, trailing commas.
- **Vitest** — testing framework.
- **Fastify `app.inject()`** — HTTP assertions for e2e tests (NEVER use Supertest with Fastify).

## Backend testing (mandatory)

Same-change Vitest for controllers, services, repositories, HTTP guards/pipes (`test/modules/*.spec.ts`; e2e per `add-module` / `add-test`). Run `pnpm test` and `pnpm test:e2e` when request flows change.

## Security

### Environment & Secrets
- All config via `src/config/env.config.ts` — access env vars through the centralized config object, not `process.env` scattered across services or controllers
- Secrets (`JWT_SECRET`, `DATABASE_URL`) must be set in `.env` — NEVER hardcode fallback secrets like `'change-me'` in production code
- Use `.env.example` for documentation only; keep actual secrets out of version control

### Request Validation
- Global `ZodValidationPipe` validates all incoming DTOs automatically — NEVER skip DTO typing on `@Body()` or `@Query()`
- Use `z.string().min(1)` and similar constraints — NEVER accept unbounded strings without length limits

### Security Headers
- `helmet` is configured in `security.setup.ts` — NEVER remove or weaken CSP, HSTS, or frame-ancestors directives
- Cache-Control headers are set to `no-cache, no-store, must-revalidate, private` — appropriate for API responses with sensitive data

### CORS
- Origins are restricted to `CLIENT_URL` — NEVER use `origin: '*'` in production
- Only specific methods and headers are allowed — NEVER use `'*'` for methods or headers

### Auth
- Guard-based authentication (Passport.js + JWT) — apply guards at controller or route level, not globally (allows health checks)
- NEVER return password hashes, JWT secrets, or sensitive internal fields in API responses — public resource IDs are acceptable
- Use short-lived JWTs with refresh tokens for session management

### Least Privilege
- Controllers return DTOs, not raw entities — NEVER expose database models directly in responses
- Repository results should be mapped through services before reaching controllers
- NEVER log tokens, passwords, or PII in any environment

