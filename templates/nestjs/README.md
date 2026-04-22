# NestJS Template

Production-ready NestJS API template with Fastify, Zod validation, Swagger docs, and Docker.

## Stack

| Layer | Technology |
|-------|-----------|
| Framework | NestJS 11 |
| HTTP Adapter | Fastify |
| Validation | Zod + nestjs-zod |
| API Docs | Swagger (@nestjs/swagger) |
| Security | Helmet, CORS |
| Testing | Jest |
| Linting | ESLint 9 (flat config), Prettier |
| Language | TypeScript 6, ES2023 |
| Docker | Multi-stage (dev / stage / prod) |

## Getting Started

```bash
# Install dependencies
pnpm install

# Copy environment file
cp .env.example .env

# Start dev server
pnpm start:dev

# Run tests
pnpm test

# Run e2e tests
pnpm test:e2e
```

API runs at `http://localhost:3000`, Swagger docs at `http://localhost:3000/docs`.

## Folder Structure

```
├── src/
│   ├── main.ts                    # Entry point (dotenv, Fastify bootstrap)
│   ├── app.module.ts              # Root module (global pipes, filters)
│   ├── config/
│   │   ├── env.config.ts          # Typed env config objects
│   │   ├── index.ts               # Barrel export
│   │   └── setups/
│   │       ├── security.setup.ts  # Helmet, CORS, cache headers
│   │       └── swagger.setup.ts   # Swagger / OpenAPI setup
│   ├── common/
│   │   ├── constants/             # Shared constants
│   │   ├── filters/               # Exception filters
│   │   ├── types/                 # Custom type declarations (.d.ts)
│   │   └── utils/                 # Reusable utility functions
│   ├── database/                  # Database connection (add Prisma, TypeORM, etc.)
│   └── modules/
│       ├── index.ts               # Barrel export for all modules
│       ├── base/                  # Health check / root endpoints
│       │   ├── base.module.ts
│       │   ├── base.controller.ts
│       │   └── base.service.ts
│       └── example/               # Full CRUD example module
│           ├── example.module.ts
│           ├── example.controller.ts
│           ├── example.service.ts
│           ├── example.repository.ts
│           ├── example.dto.ts     # Zod DTOs via nestjs-zod
│           └── example.types.ts   # TypeScript interfaces
├── test/
│   ├── jest-e2e.json
│   ├── app.e2e-spec.ts            # E2E tests
│   └── modules/                   # Unit tests per module
├── .env.example
├── Dockerfile                     # Multi-stage Docker build
├── docker-entrypoint.sh
└── .dockerignore
```

## Architecture

### Module Pattern

Each feature is a self-contained NestJS module:

```
modules/<name>/
├── <name>.module.ts       # Module definition (imports, providers, exports)
├── <name>.controller.ts   # HTTP endpoints (thin — delegates to service)
├── <name>.service.ts      # Business logic orchestration
├── <name>.repository.ts   # Data access (database queries)
├── <name>.dto.ts          # Zod schemas → DTOs via createZodDto
└── <name>.types.ts        # TypeScript interfaces
```

### Dependency Flow

```
Controller  →  Service  →  Repository
                  ↓
              Types / DTOs
```

- Controllers are thin — accept request, call service, return response
- Services contain business logic and orchestrate between repositories
- Repositories handle data persistence
- DTOs validate input via Zod schemas

### Validation with Zod

DTOs use `nestjs-zod` for runtime validation with automatic Swagger schema generation:

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateItemSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

export class CreateItemDto extends createZodDto(CreateItemSchema) {}
```

## Customization

| File | What to Change |
|------|----------------|
| `src/config/env.config.ts` | Add typed env variables |
| `.env.example` | Add environment variable defaults |
| `src/app.module.ts` | Register new modules, global providers |
| `src/modules/index.ts` | Export new modules |
| `src/common/constants/` | Add shared constants |
| `src/database/` | Add Prisma, TypeORM, or MongoDB |

## Docker

```bash
# Development
docker build --target dev -t my-api:dev .
docker run -p 3000:3000 my-api:dev

# Production
docker build --target prod -t my-api:prod .
docker run -p 3000:3000 my-api:prod
```
