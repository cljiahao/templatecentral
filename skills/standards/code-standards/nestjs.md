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
| DTOs | `PascalCase` + `Dto` suffix | `CreateExampleDto` |
| Modules | `PascalCase` + `Module` suffix | `ExampleModule` |
| Controllers | `PascalCase` + `Controller` suffix | `ExampleController` |
| Services | `PascalCase` + `Service` suffix | `ExampleService` |
| Repositories | `PascalCase` + `Repository` suffix | `ExampleRepository` |
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

- Use constructor injection — NestJS resolves dependencies automatically.
- Mark all injectables with `@Injectable()`.
- Use `@Module({ exports: [MyService] })` to share services between modules.

### DTOs and Validation

- Use `nestjs-zod` with `createZodDto` for all DTOs. The global `ZodValidationPipe` validates all incoming requests automatically.
- Use `.partial()` for update DTOs.

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

- Keep controllers thin — delegate to service, return response.
- Use `@ApiTags()` and `@ApiOperation()` for Swagger.
- Use `@HttpCode()` when the default status code is wrong.

### Services

- Services contain business logic; orchestrate between repositories.
- Use `crypto.randomUUID()` for generating IDs.
- Return typed objects, not raw database results.

### Error Handling

- Use NestJS built-in exceptions: `NotFoundException`, `BadRequestException`, etc.
- The global `HttpExceptionFilter` catches and formats all HTTP exceptions.
- For domain-specific errors, extend `HttpException`.

### Imports

- Use relative imports within a module.
- Barrel exports (`index.ts`) at the `modules/` level.
- Order: NestJS/framework → third-party → local.

### Swagger

- Every controller gets `@ApiTags()`.
- Every endpoint gets `@ApiOperation({ summary: '...' })`.
- Use `@ApiParam()` and `@ApiBody()` for parameter documentation.
- DTOs from `nestjs-zod` generate Swagger schemas automatically.

### Type Annotations

- Annotate all public method parameters and return types.
- Use `type` imports for interfaces: `import type { ExampleItem } from './example.types'`.
- Prefer interfaces for object shapes, types for unions/aliases.

### Tooling

- **ESLint 9** — flat config with typescript-eslint + prettier.
- **Prettier** — single quotes, trailing commas.
- **Vitest** — testing framework.
- **Fastify `app.inject()`** — HTTP assertions for e2e tests (NEVER use Supertest with Fastify).

### Backend Testing (mandatory)

Same-change Vitest for controllers, services, repositories, HTTP guards/pipes (`test/modules/*.spec.ts`; e2e per `templatecentral:add (endpoint)` / `templatecentral:add (test)`). Run `pnpm test` and `pnpm test:e2e` when request flows change.

### Security (NestJS)

**Environment & Secrets**
- All config via `src/config/env.config.ts` — NEVER scatter `process.env` calls across services
- Secrets (`JWT_SECRET`, `DATABASE_URL`) in `.env` — NEVER hardcode fallback secrets like `'change-me'`

**Request Validation**
- Global `ZodValidationPipe` validates all DTOs — NEVER skip DTO typing on `@Body()` or `@Query()`
- Use `z.string().min(1)` and length constraints — NEVER accept unbounded strings

**Security Headers**
- `helmet` in `security.setup.ts` — NEVER remove or weaken CSP, HSTS, or frame-ancestors

**CORS**
- Origins restricted to `CLIENT_URL` — NEVER use `origin: '*'` in production

**Auth**
- Guard-based (Passport.js + JWT) — apply at controller or route level, not globally
- NEVER return password hashes, JWT secrets, or sensitive internal fields
- Use short-lived JWTs; add refresh tokens when sessions must outlive the access-token TTL

**Least Privilege**
- Controllers return DTOs, not raw entities
- NEVER log tokens, passwords, or PII