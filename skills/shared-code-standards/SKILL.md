---
name: shared-code-standards
description: Use when writing or reviewing code in any templateCentral project (FastAPI, NestJS, Next.js, or Vite + React) — universal quality principles plus stack-specific naming, error handling, security, and tooling.
---

# Code Standards

## Stack Detection

Check the current project root:

| File present | Stack |
|---|---|
| `requirements.txt` containing `fastapi` | FastAPI |
| `nest-cli.json` | NestJS |
| `next.config.ts`, `next.config.js`, or `next.config.mjs` | Next.js |
| `vite.config.ts` or `vite.config.js` (no `next.config`) | Vite + React |

Apply **Universal Code Quality** first, then the matching stack section below.

---

## Universal Code Quality (all stacks)

- **YAGNI** — only what the task requires; no speculative helpers or files
- **DRY** — extract at second repetition; inline if only one callsite
- **SRP** — one responsibility per file/function
- **SoC** — routing/HTTP separate from business logic; validation separate from domain logic
- **No premature abstractions** — wait for the third callsite
- **No dead code** — no commented-out code, unused imports, or TODO stubs
- **Validate at boundaries** — Pydantic/Zod for all user input, API responses, and env vars
- **Fail loudly** — no empty catch blocks; log with context; return meaningful HTTP status codes
- **Least privilege** — return only needed fields; never expose raw DB records or internal IDs
- **No secrets** — no hardcoded tokens or keys; env vars only; document in `.env.example`

---

## FastAPI / Python

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `PascalCase` | `InterestSettings` |
| Functions | `snake_case` | `get_limits` |
| Constants | `UPPER_SNAKE_CASE` | `INTEREST_RATES` |
| Variables | `snake_case` | `age_in_months` |
| Type aliases | `PascalCase` | `DatedSchedules` |
| Private helpers | `_leading_underscore` | `_coerce_account` |
| Files | `snake_case.py` | `tiered_interest.py` |
| Directories | `snake_case` | `cpf_data/` |
| Tests | `test_<function>_<scenario>` | `test_withdrawal_raises_below_55` |

### Type Annotations

- Annotate all public function parameters and return types.
- Use Python 3.10+ union syntax: `int | None` (not `Optional[int]`).
- Use built-in generics: `list[str]`, `dict[str, int]`.
- Use `TypeAlias` for complex reusable types.

### Dataclasses

- Immutable: `@dataclass(frozen=True, slots=True)` — config, lookup data, parameters.
- Mutable: `@dataclass(slots=True)` — state that changes during processing.
- Use `__post_init__` for invariants; fail fast with clear `ValueError`.

### Function Design

- Prefer pure functions: inputs → outputs, no side effects.
- Isolate side effects; keep mutation in functions with `-> None`.
- Keep functions small and single-purpose.
- Use dict dispatch instead of long `if/elif` for key-based branching.

### Error Handling

- Use built-in exceptions with descriptive messages.
- `ValueError` for invalid values; `TypeError` for wrong types.
- Chain exceptions with `from` to preserve traceback.
- Avoid bare `except:` or broad `except Exception:` except at boundaries.
- Custom exceptions (`InvalidInputError`, `NoResultsFound`) for crossing layer boundaries.

### Imports

- Order: stdlib → third-party → local (separated by blank lines, enforced by Ruff).
- Use absolute imports only: `from models.base import BaseModel`.
- Import specific names, not modules.
- No wildcard imports (`from module import *`).
- Avoid barrel re-exports in `__init__.py` unless stable public API.

### Docstrings

- One-line for simple functions; short paragraph for complex ones.
- Focus on *what*, not *how*; inline comments explain *why*.

### Constants

- Include units when helpful (e.g. `HARD_LIMIT_CENTS`).
- Use underscores in numeric literals: `1_000_000`.
- Keep related constants grouped.

### Tooling

- **Ruff** — linting + isort (line-length 88, Python 3.12).
- **pytest** — testing framework.
- **Pydantic v2** — API schemas with `BaseSchema` (camelCase aliases, `extra="forbid"`).

### Backend Testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `add-endpoint`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `pytest` from project root before handoff.

### Dependency Rules

```
core/          (standalone — app infrastructure, config, logging)
api/           →  models/
 ├── routers/     ↑
 ├── services/    utils/
 └── schemas/
```

- `api/services/` contains business logic — called by `api/routers/`, never the reverse.
- `models/` **never** imports from `api/`.
- `core/` is standalone infrastructure — imported by `api/` but never by `models/`.
- `utils/` are pure helpers — importable by any layer.

### Security (FastAPI)

**Environment & Secrets**
- All config via Pydantic `BaseSettings` — env vars loaded by `load_dotenv()` in `src/main.py`; NEVER use `os.environ` directly
- Secrets (`SECRET_KEY`, `DATABASE_URL`, API keys) go in `src/.env` — NEVER commit or hardcode
- Use `src/.env.default` for non-sensitive defaults only; secrets must be blank or absent

**Input Validation**
- All request bodies validated by Pydantic schemas with `extra="forbid"`
- NEVER skip `response_model` — it filters outgoing data
- Validate path/query params with FastAPI's type annotations

**CORS**
- In dev, `ALLOWED_CORS` is a fixed list of localhost origins — never `["*"]` with credentials
- In production, set `CORS_ORIGINS` env var; always set explicit methods and headers

**Auth**
- Hash passwords with `bcrypt` directly — NEVER store plaintext; `passlib` is unmaintained
- JWT tokens: short expiry; use refresh tokens for long sessions
- NEVER return password hashes or internal IDs in API responses

**Least Privilege**
- Services return Pydantic `response_model` objects — NEVER return raw ORM objects
- NEVER log full request bodies that may contain passwords or PII

---

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
- DTOs from `nestjs-zod` generate Swagger schemas automatically.

### Tooling

- **ESLint 9** — flat config with typescript-eslint + prettier.
- **Jest** — testing framework with ts-jest.
- **Fastify `app.inject()`** — HTTP assertions for e2e tests (NEVER use Supertest with Fastify).

### Backend Testing (mandatory)

Same-change Jest for controllers, services, repositories (`test/modules/*.spec.ts`). Run `pnpm test` and `pnpm test:e2e` when request flows change.

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
- Use short-lived JWTs with refresh tokens

**Least Privilege**
- Controllers return DTOs, not raw entities
- NEVER log tokens, passwords, or PII

---

## Next.js

### File Naming

All files use **kebab-case**. Exceptions: Next.js special files (`layout.tsx`, `page.tsx`, `route.ts`, `not-found.tsx`, `loading.tsx`, `error.tsx`) and dynamic segments (`[id]`, `[...slug]`).

### Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `UploadService`, `DashboardHeader` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `FRAMEWORK_OPTIONS` |
| Types/interfaces | PascalCase | `ProjectFormSchema`, `UploadMode` |

**Always use named exports.** Never `export default` except where required by Next.js.

### Function vs Const

| Pattern | When to use |
|---------|-------------|
| `export function Foo() {}` | Default — most components |
| `export const Foo = React.memo(function Foo() {})` | Components needing memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

- Keep components thin — delegate logic to hooks/services.
- Extract when there's a second consumer — don't prematurely extract.

**shadcn/ui primitives** (`src/components/ui/`) — use directly, never recreate:
`accordion` · `avatar` · `button` · `card` · `checkbox` · `dialog` · `dropdown-menu` · `form` · `input` · `label` · `select` · `separator` · `skeleton` · `sonner` · `tabs` · `textarea`

**Widgets** (`src/components/widgets/`): `brand-logo` · `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill` · `theme-toggle-button` · `floating-shape`

**Layout** (`src/components/layout/`): `navbar` · `site-footer` · `providers` · `theme-provider`

To add a new shadcn primitive: `npx shadcn@latest add <name>` — NEVER install `@radix-ui/*` manually.

**Component Placement**

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` |
| App shell | `src/components/layout/` |

### Performance

Do NOT use `React.memo`, `useCallback`, `useMemo` by default — only after profiling. Exception: Context providers must stabilize `value` objects.

### Utility Classes

- `cn()` — `clsx` + `tailwind-merge` in `src/lib/utils/index.ts`
- `flex-center`, `flex-between`, `max-w-site` — custom CSS utilities in `globals.css`

### Barrel Exports

Each feature and shared folder has an `index.ts`. Prefer `import { X } from '@/features/project'` over deep imports.

### Backend Testing (mandatory for API code)

Vitest tests under `test/api/` mirroring `src/app/api/`. Run `pnpm test` and `pnpm build` before handoff.

### Security (Next.js)

**Environment Variables**
- Server secrets: `process.env.SECRET_NAME` — NEVER use `NEXT_PUBLIC_` prefix for secrets
- Client-safe values only in `NEXT_PUBLIC_*`

**Input Validation**
- Validate all request bodies with Zod `safeParse()` — return 400 on failure

**Auth & Route Protection** (after `nextjs-add-auth` is run)
- `proxy.ts`: NEVER return JSON for unauthorized requests — `new Response(null, { status: 401 })` only
- API routes independently call `auth.api.getSession()` — defense in depth

**Least Privilege**
- Return only the fields the client needs — NEVER send full DB records to the browser
- NEVER log tokens, passwords, or PII

---

## Vite + React

### File Naming

All files use **kebab-case**. No exceptions (unlike Next.js, Vite has no special file conventions).

### Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `DashboardHeader`, `APIError` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `STATUS_OPTIONS`, `API_ROUTES` |
| Types/interfaces | PascalCase | `ProjectItem`, `ExampleCardProps` |

**Always use named exports.** Never `export default` in application code. Exception: build/tooling config files.

### Function vs Const

Same as Next.js section above.

### Component Best Practices

Same principles as Next.js. Stack-specific component library:

**Widgets** (`src/components/widgets/`): `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill`

**Layout** (`src/components/layout/`): `navbar` · `site-footer` · `providers` · `error-boundary`

**Component Placement** — same table as Next.js section.

### Environment Variables

Centralized in `src/lib/constants/env.ts`:

```ts
export const ENV = {
  API_BASE_URL: import.meta.env.VITE_API_BASE_URL as string | undefined,
  IS_DEV: import.meta.env.DEV,
} as const;

export const getApiBaseUrl = (): string => {
  if (!ENV.API_BASE_URL) throw new Error('VITE_API_BASE_URL is not set');
  return ENV.API_BASE_URL;
};
```

Use `getApiBaseUrl()` in services — NEVER use `ENV.API_BASE_URL ?? ''`. NEVER put secrets in `VITE_*`.

### Testing

- **Vitest** — NEVER use Jest in Vite projects.
- **Testing Library** (`@testing-library/react`) for component tests.
- Co-locate tests next to source: `example-service.test.ts`, `example-card.test.tsx`.
- Globals enabled — `describe`, `it`, `expect` available without imports.

### Security (Vite + React)

**Environment Variables**
- `VITE_*` is embedded in the client bundle — NEVER put API keys, tokens, or secrets there
- Proxy through the backend for APIs requiring auth

**Input Validation**
- Validate all form inputs with Zod via React Hook Form
- Validate API response shapes with Zod `safeParse()` before rendering

**Auth & Route Protection**
- Protected routes wrapped with `<ProtectedRoute />` in `src/router.tsx`
- NEVER store tokens in `localStorage` — use `httpOnly` cookies from the backend
- NEVER make authorization decisions in the SPA

**Least Privilege**
- NEVER store sensitive data in React state, URL params, or `sessionStorage`
- NEVER log tokens, credentials, or PII to the browser console
