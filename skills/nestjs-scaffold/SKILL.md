---
name: nestjs-scaffold
description: Use when the user wants to start a new NestJS backend project, create a new API, or scaffold a project with modular architecture and Docker support.
version: "1.0.0"
---

# Scaffold NestJS Project

## Inputs

- **Project name** — The name for the new project (e.g., `my-api`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-api`). If not provided, default to `./<project-name>` and confirm with the user.

---

## Part A — Rules

### Dependencies

Install runtime dependencies (no version pins):

```bash
pnpm add @nestjs/common @nestjs/core @nestjs/platform-fastify @nestjs/swagger \
  @fastify/helmet dotenv nestjs-pino nestjs-zod pino pino-http reflect-metadata rxjs zod

pnpm add -D @eslint/js @nestjs/cli @nestjs/testing @types/jest @types/node \
  eslint eslint-config-prettier eslint-plugin-prettier globals husky \
  jest pino-pretty prettier ts-jest ts-node typescript typescript-eslint
```

Then initialize husky:

```bash
git init
pnpm install   # activates husky via prepare script
```

### Directory Structure

```
<project-name>/
├── Dockerfile                          [verbatim — Part B]
├── docker-entrypoint.sh                [verbatim — Part B]
├── .dockerignore                       [verbatim — Part B]
├── .gitignore                          [verbatim — Part B]
├── .env.example                        [verbatim — Part B]
├── .prettierrc                         [verbatim — Part B]
├── eslint.config.mjs                   [verbatim — Part B]
├── nest-cli.json                       [verbatim — Part B]
├── tsconfig.json                       [verbatim — Part B]
├── tsconfig.build.json                 [verbatim — Part B]
├── .husky/
│   ├── pre-commit                      [verbatim — Part B]
│   └── pre-push                        [verbatim — Part B]
├── package.json                        [generate]
├── README.md                           [generate]
├── AGENTS.md                           [generate — after verification gate]
├── src/
│   ├── main.ts                         [verbatim — Part C]
│   ├── app.module.ts                   [verbatim — Part C]
│   ├── common/
│   │   ├── constants/
│   │   │   ├── http.constants.ts       [verbatim — Part C]
│   │   │   └── index.ts                [verbatim — Part C]
│   │   ├── filters/
│   │   │   └── http-exception.filter.ts [verbatim — Part C]
│   │   ├── types/
│   │   │   └── .gitkeep               [verbatim — empty]
│   │   └── utils/
│   │       ├── date.utils.ts           [verbatim — Part C]
│   │       └── string.utils.ts         [verbatim — Part C]
│   ├── config/
│   │   ├── env.config.ts               [verbatim — Part C]
│   │   ├── index.ts                    [verbatim — Part C]
│   │   └── setups/
│   │       ├── security.setup.ts       [verbatim — Part C]
│   │       └── swagger.setup.ts        [verbatim — Part C]
│   ├── database/
│   │   └── .gitkeep                    [verbatim — empty]
│   └── modules/
│       ├── index.ts                    [verbatim — Part C]
│       ├── base/
│       │   ├── base.controller.ts      [verbatim — Part C]
│       │   ├── base.module.ts          [verbatim — Part C]
│       │   └── base.service.ts         [verbatim — Part C]
│       └── example/
│           ├── example.controller.ts   [verbatim — Part C]
│           ├── example.dto.ts          [verbatim — Part C]
│           ├── example.module.ts       [verbatim — Part C]
│           ├── example.repository.ts   [verbatim — Part C]
│           ├── example.service.ts      [verbatim — Part C]
│           └── example.types.ts        [verbatim — Part C]
└── test/
    ├── app.e2e-spec.ts                 [verbatim — Part C]
    ├── jest-e2e.json                   [verbatim — Part C]
    └── modules/
        ├── base.controller.spec.ts     [verbatim — Part C]
        └── example.controller.spec.ts  [verbatim — Part C]
```

### Generation Conventions

**`package.json`** — Generate with the project name substituted into `"name"`. Use the scripts, jest config, and dependency list exactly matching the template structure. No version pins on deps (pnpm resolves latest compatible).

**`README.md`** — Generate a brief project README: project name as heading, one-line description, stack badge line (NestJS, Fastify, TypeScript, Zod), and quick-start commands (`pnpm install`, `pnpm start:dev`, `pnpm build`, `pnpm test`).

**`AGENTS.md`** — Generated only after the verification gate passes (Step 5). Write `<!-- templateCentral: nestjs@1.0.0 -->` on line 1. See Step 6 for full template.

---

## Part B — Verbatim Config Files

### `Dockerfile`

```dockerfile
# ---- Global build arguments ----
# NODE:           Production Node.js image (pinned for reproducible builds).
#                 Override with a hardened image via --build-arg NODE=dhi.io/...
# NODE_BUILD:     Build-stage Node.js image. Always Alpine (needs shell for
#                 apk, adduser, etc.). Not overridden by CI.
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the NestJS server listens on
ARG NODE=node:24.14-alpine3.23
ARG NODE_BUILD=node:24.14-alpine3.23
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
# Alpine foundation for deps/builder/dev stages (uses NODE_BUILD).
# OS packages (tzdata, dumb-init, ca-certificates) and the non-root user are
# created here, then COPY'd into the prod stage which may be distroless.
FROM ${NODE_BUILD} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

WORKDIR ${APP_DIR}

RUN apk add --no-cache tzdata dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && cp /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}

# ---- Dependencies ----
# Installs ALL dependencies (including devDependencies like TypeScript, jest, etc.)
# Used by the builder (needs TypeScript, build tools) and the dev stage.
FROM base AS deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  elif [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Prod Dependencies ----
# Installs production-only dependencies. These node_modules ship in the final
# prod image alongside the compiled dist/. No devDependencies in production.
FROM base AS prod-deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile --prod; \
  elif [ -f yarn.lock ]; then yarn --frozen-lockfile --production; \
  elif [ -f package-lock.json ]; then npm ci --omit=dev; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Builder ----
# Copies source code and compiles TypeScript to dist/. Uses all deps (including
# devDependencies) since TypeScript compiler and build tools are needed.
FROM deps AS builder
ENV NODE_OPTIONS=--max-old-space-size=4096
COPY ./ ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm run build; \
  elif [ -f yarn.lock ]; then yarn run build; \
  elif [ -f package-lock.json ]; then npm run build; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Development ----
# Full Node environment with all deps + source for local dev (hot reload).
# Uses docker-entrypoint.sh to auto-detect the package manager and run "dev".
FROM deps AS dev
ENV NODE_ENV="development"
COPY ./ ./
RUN apk add --no-cache curl
RUN chmod +x docker-entrypoint.sh
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["dev"]

# ---- Production ----
# Uses NODE (hardened/distroless when CI overrides, Alpine otherwise).
# No RUN commands — all setup via COPY from base/prod-deps/builder stages.
#
# dumb-init (PID 1) forwards SIGTERM for graceful shutdown of Fastify and
# database connections (Prisma, Mongoose, Kysely/pg pools).
# read-only compatible with ECS readonlyRootFilesystem: true.
FROM ${NODE} AS prod
ARG APP_UID
ARG APP_GID
ARG APP_DIR
ARG PORT

ENV NODE_ENV="production" \
    NODE_OPTIONS=--max-old-space-size=384 \
    PORT=${PORT}

WORKDIR ${APP_DIR}

# OS-level setup from the Alpine base stage (user, timezone, certs, dumb-init)
COPY --from=base /etc/passwd /etc/passwd
COPY --from=base /etc/group /etc/group
COPY --from=base /etc/localtime /etc/localtime
COPY --from=base /etc/timezone /etc/timezone
COPY --from=base /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=base /etc/ssl/certs/ /etc/ssl/certs/

COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/package.json ./
COPY --chown=${APP_UID}:${APP_GID} --from=prod-deps ${APP_DIR}/node_modules ./node_modules
COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/dist ./dist

EXPOSE ${PORT}
USER ${APP_UID}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://localhost:' + process.env.PORT + '/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/main.js"]
```

### `docker-entrypoint.sh`

```sh
#!/bin/sh

MODE="${1:-prod}"

# Detect package manager
if [ -f "yarn.lock" ]; then
  PM="yarn"
elif [ -f "pnpm-lock.yaml" ]; then
  corepack enable pnpm
  PM="pnpm"
else
  PM="npm"
fi

case "$MODE" in
  dev)
    exec $PM run start:dev
    ;;
  start|prod)
    exec node dist/main.js
    ;;
  *)
    exec "$@"
    ;;
esac
```

### `.dockerignore`

```
# ==============================================================================
# NESTJS DOCKER IGNORE - Production Optimized
# ==============================================================================

# Version Control
.git
.gitignore
.gitattributes
.gitmodules

# Dependencies (will be installed in container)
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
.pnpm-store/

# NestJS Build Outputs & Cache
dist/
build/
.build/
.swc/

# Environment Variables (security)
.env
.env.*
!.env.example
!.env.local.example

# IDE and Editor Files
.vscode/
.idea/
*.swp
*.swo
*~
.project
.classpath
.settings/
.vscode-test
.history/

# OS Generated Files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
desktop.ini

# Logs
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
lerna-debug.log*
pnpm-debug.log*

# Runtime Data
pids/
*.pid
*.seed
*.pid.lock

# Testing & Coverage
coverage/
*.lcov
.nyc_output/
.jest/
test/
test-results/
e2e/
*.spec.ts
*.test.ts
*.e2e-spec.ts
**/__tests__/
**/__mocks__/
test-results.xml
junit.xml

# Cache Directories
.npm/
.yarn/
.pnpm/
.eslintcache
.cache/
.parcel-cache/
.turbo/

# Microbundle & Build Tool Cache
.rpt2_cache/
.rts2_cache_cjs/
.rts2_cache_es/
.rts2_cache_umd/

# Temporary Files
tmp/
temp/
*.tmp
*.temp
*.bak
*.backup

# Docker Related (don't copy into image)
.dockerignore
Dockerfile*
docker-compose*.yml
docker-compose*.yaml
.docker/

# CI/CD Configuration
.github/
.gitlab-ci.yml
.travis.yml
.circleci/
.azuredevops/
.buildkite/
bitbucket-pipelines.yml
jenkins/
Jenkinsfile*

# Documentation
README*.md
CHANGELOG*.md
CONTRIBUTING*.md
LICENSE*
SECURITY*.md
CODE_OF_CONDUCT*.md
docs/
.docs/

# Security & Certificates
*.pem
*.key
*.crt
*.cer
*.p12
*.pfx
.secrets/
secret.txt
key.txt

# TypeScript
*.tsbuildinfo
.tscache/

# Analysis & Profiling
.analyze/
bundle-analyzer/
lighthouse/
.bundle-analyzer/

# Monitoring & Analytics
.sentry/
newrelic.js

# Database
*.db
*.sqlite
*.sqlite3
.db/

# Terraform
*.tfstate
*.tfstate.*
.terraform/

# Kubernetes
*.kubeconfig
k8s/
kubernetes/

# AWS
.aws/
.serverless/

# Sentry
.sentryclirc

# Development Tools (not needed for build)
.eslintrc.js
.prettierrc
.prettierignore
.editorconfig

# Other Projects/Versions
v1/

# ==============================================================================
# EXCEPTIONS - Files to include despite patterns above
# ==============================================================================

# Package manager lock files (needed for reproducible builds)
!package-lock.json
!yarn.lock
!pnpm-lock.yaml
!bun.lockb

# Essential NestJS config files
!nest-cli.json
!tsconfig.json
!tsconfig.build.json

# Essential config files
!.eslintrc.js
!.prettierrc*
!.npmrc
```

### `.gitignore`

```
# Compiled output
/dist
/node_modules
/build
*.js.map

# Logs
logs
*.log
npm-debug.log*
pnpm-debug.log*
yarn-debug.log*
yarn-error.log*
lerna-debug.log*

# OS
.DS_Store
Thumbs.db

# Tests
/coverage
/.nyc_output
*.spec.ts.snap

# IDEs and editors
/.idea
.project
.classpath
.c9/
*.launch
.settings/
*.sublime-workspace
*.sublime-project
*.swp
*.swo
*~

# IDE - VSCode
.vscode/*
!.vscode/settings.json
!.vscode/tasks.json
!.vscode/launch.json
!.vscode/extensions.json

# Environment variables
.env
.env.development.local
.env.test.local
.env.production.local
.env.local
.env.*.local

# Secrets and certificates
*.key
*.pem
*.crt
*.cer
*.p12
*.pfx
secret.txt
key.txt

# Temporary files
.temp
.tmp
tmp/
temp/

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Diagnostic reports
report.[0-9]*.[0-9]*.[0-9]*.[0-9]*.json

# Dependency directories
jspm_packages/

# Optional npm cache directory
.npm

# Optional eslint cache
.eslintcache

# Optional stylelint cache
.stylelintcache

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn
.yarn-integrity
.yarn/cache
.yarn/unplugged
.yarn/build-state.yml
.yarn/install-state.gz
.pnp.*

# Package manager lock files (optional, uncomment if needed)
# package-lock.json
# yarn.lock
# pnpm-lock.yaml

# Build files
*.tsbuildinfo

# macOS
.AppleDouble
.LSOverride

# Backup files
*.bak
*.backup
*~
```

### `.env.example`

```env
# General
PROJECT_NAME=my-nestjs-api
PROJECT_DESCRIPTION=
PROJECT_VERSION=0.1.0
ENVIRONMENT=dev

# Port
PORT=3000

# CORS
CLIENT_URL=http://localhost:3000
```

### `.prettierrc`

```json
{
  "singleQuote": true,
  "trailingComma": "all"
}
```

### `eslint.config.mjs`

```js
// @ts-check
import eslint from '@eslint/js';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['eslint.config.mjs'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  eslintPluginPrettierRecommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.jest,
      },
      sourceType: 'commonjs',
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-floating-promises': 'warn',
      '@typescript-eslint/no-unsafe-argument': 'warn',
      '@typescript-eslint/no-unsafe-call': 'off',
    },
  },
);
```

### `nest-cli.json`

```json
{
  "$schema": "https://json.schemastore.org/nest-cli",
  "collection": "@nestjs/schematics",
  "sourceRoot": "src",
  "compilerOptions": {
    "deleteOutDir": true
  }
}
```

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "resolvePackageJsonExports": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "declaration": true,
    "removeComments": true,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "allowSyntheticDefaultImports": true,
    "target": "ES2023",
    "sourceMap": true,
    "rootDir": "./",
    "outDir": "./dist",
    "baseUrl": "./",
    "ignoreDeprecations": "6.0",
    "incremental": true,
    "skipLibCheck": true,
    "strictNullChecks": true,
    "forceConsistentCasingInFileNames": true,
    "noImplicitAny": false,
    "typeRoots": [
      "./node_modules/@types",
      "./src/common/types"
    ]
  },
  "include": [
    "src/**/*",
    "src/common/types/**/*.d.ts"
  ]
}
```

### `tsconfig.build.json`

```json
{
  "extends": "./tsconfig.json",
  "exclude": ["node_modules", "test", "dist", "**/*spec.ts"]
}
```

### `.husky/pre-commit`

```sh
#!/bin/sh
# Ensure lock file matches package.json
pnpm install --frozen-lockfile > /dev/null 2>&1 || {
  echo "❌ Lock file is out of sync with package.json"
  echo "Run: pnpm install"
  exit 1
}

# Fast checks (format, lint, typecheck)
pnpm run check || {
  echo "❌ Check failed (format/lint/typecheck)"
  exit 1
}
```

### `.husky/pre-push`

```sh
#!/bin/sh
pnpm build && pnpm run check && pnpm run test:ci
```

---

## Part C — Verbatim Source Files

### `src/main.ts`

```typescript
import { config } from 'dotenv';

config();

import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { Logger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { appConfig, setupCors, setupSecurity, setupSwagger } from './config';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter(),
    { bufferLogs: true },
  );
  const logger = app.get(Logger);
  app.useLogger(logger);

  await setupSecurity(app);
  logger.log('Security middleware configured');

  setupCors(app);
  logger.log('CORS configured');

  setupSwagger(app);
  logger.log('Swagger documentation configured');

  await app.init();
  logger.log('Application initialized');

  const port = appConfig.PORT;
  await app.listen(port, '0.0.0.0');

  logger.log(`${appConfig.PROJECT_NAME} running on: http://localhost:${port}`);
  logger.log(`Swagger docs available at: http://localhost:${port}/docs`);
}

bootstrap().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

### `src/app.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { APP_FILTER, APP_PIPE } from '@nestjs/core';
import { ZodValidationPipe } from 'nestjs-zod';
import { LoggerModule } from 'nestjs-pino';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { BaseModule, ExampleModule } from './modules';
import { appConfig } from './config';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL ?? 'info',
        transport:
          appConfig.ENVIRONMENT !== 'prod' && appConfig.ENVIRONMENT !== 'uat'
            ? { target: 'pino-pretty', options: { singleLine: true } }
            : undefined,
      },
    }),
    BaseModule,
    ExampleModule,
  ],
  providers: [
    {
      provide: APP_PIPE,
      useClass: ZodValidationPipe,
    },
    {
      provide: APP_FILTER,
      useClass: HttpExceptionFilter,
    },
  ],
})
export class AppModule {}
```

### `src/common/constants/http.constants.ts`

```typescript
export const HTTP_STATUS_MESSAGES = {
  BAD_REQUEST: 'Bad request',
  UNAUTHORIZED: 'Unauthorized access',
  FORBIDDEN: 'Forbidden resource',
  NOT_FOUND: 'Resource not found',
  METHOD_NOT_ALLOWED: 'Method not allowed',
  CONFLICT: 'Resource conflict',
  TOO_MANY_REQUESTS: 'Too many requests',
  INTERNAL_ERROR: 'Internal server error',
} as const;
```

### `src/common/constants/index.ts`

```typescript
export * from './http.constants';
```

### `src/common/filters/http-exception.filter.ts`

```typescript
import { Logger, Catch, ArgumentsHost, HttpException } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { ZodSerializationException } from 'nestjs-zod';
import { ZodError } from 'zod';

@Catch(HttpException)
export class HttpExceptionFilter extends BaseExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: HttpException, host: ArgumentsHost) {
    if (exception instanceof ZodSerializationException) {
      const zodError: unknown = exception.getZodError();
      if (zodError instanceof ZodError) {
        this.logger.error(`ZodSerializationException: ${zodError.message}`);
      }
    }

    super.catch(exception, host);
  }
}
```

### `src/common/utils/date.utils.ts`

```typescript
export function toISOString(date: Date = new Date()): string {
  return date.toISOString();
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

export function isExpired(expiresAt: Date): boolean {
  return new Date() > expiresAt;
}
```

### `src/common/utils/string.utils.ts`

```typescript
export function convertStrToList(
  value: string | undefined,
  delimiter: string,
): string[] | undefined {
  if (!value) return undefined;
  return value
    .split(delimiter)
    .map((s) => s.trim())
    .filter(Boolean);
}
```

### `src/config/env.config.ts`

```typescript
export const appConfig = {
  PROJECT_NAME: process.env.PROJECT_NAME || 'My Project',
  PROJECT_DESCRIPTION:
    process.env.PROJECT_DESCRIPTION ||
    'API built with [NestJS](https://nestjs.com/) + Fastify',
  PROJECT_VERSION: process.env.PROJECT_VERSION || '0.1.0',
  ENVIRONMENT: process.env.ENVIRONMENT || 'dev',
  PORT: Number.isFinite(parseInt(process.env.PORT ?? '', 10))
    ? parseInt(process.env.PORT!, 10)
    : 3000,
};

export const serviceConfig = {
  CLIENT_URL: (process.env.CLIENT_URL || 'http://localhost:3000').split(','),
};
```

### `src/config/index.ts`

```typescript
export * from './env.config';
export * from './setups/swagger.setup';
export * from './setups/security.setup';
```

### `src/config/setups/security.setup.ts`

```typescript
import fastifyHelmet from '@fastify/helmet';
import type { INestApplication } from '@nestjs/common';
import type { FastifyInstance } from 'fastify';

export async function setupSecurity(app: INestApplication): Promise<void> {
  const fastify = app.getHttpAdapter().getInstance() as FastifyInstance;

  await fastify.register(fastifyHelmet, {
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    contentSecurityPolicy: {
      directives: {
        'base-uri': ["'none'"],
        'frame-ancestors': ["'none'"],
      },
    },
    strictTransportSecurity: { maxAge: 31536000 },
    xFrameOptions: { action: 'deny' },
  });

  fastify.addHook('onSend', async (_request, reply, payload) => {
    void reply.header('Cache-Control', 'no-cache, no-store, must-revalidate, private');
    void reply.header('Pragma', 'no-cache');
    void reply.header('Expires', '0');
    return payload;
  });
}

export function setupCors(app: INestApplication): void {
  app.enableCors({
    origin: serviceConfig.CLIENT_URL,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    credentials: true,
    allowedHeaders: ['Content-Type', 'Authorization'],
  });
}
```

### `src/config/setups/swagger.setup.ts`

```typescript
import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { cleanupOpenApiDoc } from 'nestjs-zod';
import { appConfig } from '..';

export function setupSwagger(app: INestApplication): void {
  const options = new DocumentBuilder()
    .setTitle(appConfig.PROJECT_NAME)
    .setDescription(appConfig.PROJECT_DESCRIPTION)
    .setVersion(appConfig.PROJECT_VERSION)
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, cleanupOpenApiDoc(document));
}
```

### `src/modules/index.ts`

```typescript
export * from './base/base.module';
export * from './example/example.module';
```

### `src/modules/base/base.controller.ts`

```typescript
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Controller, Get, HttpCode, HttpStatus } from '@nestjs/common';
import { BaseService } from './base.service';

@ApiTags('Base')
@Controller()
export class BaseController {
  constructor(private readonly baseService: BaseService) {}

  @Get()
  @ApiOperation({ summary: 'Root endpoint' })
  getHello(): string {
    return this.baseService.getHello();
  }

  @Get('health')
  @ApiOperation({ summary: 'Health check' })
  @HttpCode(HttpStatus.OK)
  checkHealth(): { status: string } {
    return this.baseService.getHealth();
  }
}
```

### `src/modules/base/base.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { BaseController } from './base.controller';
import { BaseService } from './base.service';

@Module({
  controllers: [BaseController],
  providers: [BaseService],
})
export class BaseModule {}
```

### `src/modules/base/base.service.ts`

```typescript
import { Injectable } from '@nestjs/common';

@Injectable()
export class BaseService {
  getHello(): string {
    return 'Hello World!';
  }

  getHealth(): { status: string } {
    return { status: 'OK' };
  }
}
```

### `src/modules/example/example.controller.ts`

```typescript
import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Param,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiParam, ApiBody } from '@nestjs/swagger';
import { ExampleService } from './example.service';
import { CreateExampleDto, UpdateExampleDto } from './example.dto';
import type { ExampleItem } from './example.types';

@ApiTags('Example')
@Controller('examples')
export class ExampleController {
  constructor(private readonly exampleService: ExampleService) {}

  @Get()
  @ApiOperation({ summary: 'List all examples' })
  findAll(): ExampleItem[] {
    return this.exampleService.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get example by ID' })
  @ApiParam({ name: 'id', type: 'string' })
  findOne(@Param('id') id: string): ExampleItem {
    return this.exampleService.findOne(id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a new example' })
  @ApiBody({ type: CreateExampleDto })
  @HttpCode(HttpStatus.CREATED)
  create(@Body() dto: CreateExampleDto): ExampleItem {
    return this.exampleService.create(dto);
  }

  @Put(':id')
  @ApiOperation({ summary: 'Update an example' })
  @ApiParam({ name: 'id', type: 'string' })
  @ApiBody({ type: UpdateExampleDto })
  update(
    @Param('id') id: string,
    @Body() dto: UpdateExampleDto,
  ): ExampleItem {
    return this.exampleService.update(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete an example' })
  @ApiParam({ name: 'id', type: 'string' })
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string): void {
    this.exampleService.remove(id);
  }
}
```

### `src/modules/example/example.dto.ts`

```typescript
import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateExampleSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

const UpdateExampleSchema = CreateExampleSchema.partial();

export class CreateExampleDto extends createZodDto(CreateExampleSchema) {}
export class UpdateExampleDto extends createZodDto(UpdateExampleSchema) {}
```

### `src/modules/example/example.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { ExampleController } from './example.controller';
import { ExampleService } from './example.service';
import { ExampleRepository } from './example.repository';

@Module({
  controllers: [ExampleController],
  providers: [ExampleService, ExampleRepository],
  exports: [ExampleService],
})
export class ExampleModule {}
```

### `src/modules/example/example.repository.ts`

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import type { ExampleItem } from './example.types';

@Injectable()
export class ExampleRepository {
  private readonly items = new Map<string, ExampleItem>();

  findAll(): ExampleItem[] {
    return Array.from(this.items.values());
  }

  findById(id: string): ExampleItem {
    const item = this.items.get(id);
    if (!item) throw new NotFoundException(`Example with id "${id}" not found`);
    return item;
  }

  create(item: ExampleItem): ExampleItem {
    this.items.set(item.id, item);
    return item;
  }

  update(id: string, data: Partial<ExampleItem>): ExampleItem {
    const existing = this.findById(id);
    const updated = { ...existing, ...data, updatedAt: new Date().toISOString() };
    this.items.set(id, updated);
    return updated;
  }

  remove(id: string): void {
    if (!this.items.has(id)) {
      throw new NotFoundException(`Example with id "${id}" not found`);
    }
    this.items.delete(id);
  }
}
```

### `src/modules/example/example.service.ts`

```typescript
import { Injectable } from '@nestjs/common';
import { ExampleRepository } from './example.repository';
import type { CreateExampleDto, UpdateExampleDto } from './example.dto';
import type { ExampleItem } from './example.types';

@Injectable()
export class ExampleService {
  constructor(private readonly repository: ExampleRepository) {}

  findAll(): ExampleItem[] {
    return this.repository.findAll();
  }

  findOne(id: string): ExampleItem {
    return this.repository.findById(id);
  }

  create(dto: CreateExampleDto): ExampleItem {
    const now = new Date().toISOString();
    const item: ExampleItem = {
      id: crypto.randomUUID(),
      name: dto.name,
      description: dto.description,
      createdAt: now,
      updatedAt: now,
    };
    return this.repository.create(item);
  }

  update(id: string, dto: UpdateExampleDto): ExampleItem {
    return this.repository.update(id, dto);
  }

  remove(id: string): void {
    this.repository.remove(id);
  }
}
```

### `src/modules/example/example.types.ts`

```typescript
export interface ExampleItem {
  id: string;
  name: string;
  description?: string;
  createdAt: string;
  updatedAt: string;
}
```

### `test/app.e2e-spec.ts`

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';

describe('AppController (e2e)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    await app.init();
    await app.getHttpAdapter().getInstance().ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET / should return "Hello World!"', () => {
    return app
      .inject({ method: 'GET', url: '/' })
      .then((result) => {
        expect(result.statusCode).toBe(200);
        expect(result.payload).toBe('Hello World!');
      });
  });

  it('GET /health should return OK', () => {
    return app
      .inject({ method: 'GET', url: '/health' })
      .then((result) => {
        expect(result.statusCode).toBe(200);
        expect(JSON.parse(result.payload)).toEqual({ status: 'OK' });
      });
  });
});
```

### `test/jest-e2e.json`

```json
{
  "moduleFileExtensions": ["js", "json", "ts"],
  "rootDir": "..",
  "testEnvironment": "node",
  "testMatch": ["<rootDir>/test/**/*.e2e-spec.ts"],
  "transform": {
    "^.+\\.(t|j)s$": ["ts-jest", {
      "tsconfig": "<rootDir>/tsconfig.json",
      "diagnostics": false
    }]
  }
}
```

### `test/modules/base.controller.spec.ts`

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { BaseController } from '../../src/modules/base/base.controller';
import { BaseService } from '../../src/modules/base/base.service';

describe('BaseController', () => {
  let controller: BaseController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [BaseController],
      providers: [BaseService],
    }).compile();

    controller = module.get<BaseController>(BaseController);
  });

  it('should return "Hello World!"', () => {
    expect(controller.getHello()).toBe('Hello World!');
  });

  it('should return health status OK', () => {
    expect(controller.checkHealth()).toEqual({ status: 'OK' });
  });
});
```

### `test/modules/example.controller.spec.ts`

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { ExampleController } from '../../src/modules/example/example.controller';
import { ExampleService } from '../../src/modules/example/example.service';
import { ExampleRepository } from '../../src/modules/example/example.repository';

describe('ExampleController', () => {
  let controller: ExampleController;
  let service: ExampleService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [ExampleController],
      providers: [ExampleService, ExampleRepository],
    }).compile();

    controller = module.get<ExampleController>(ExampleController);
    service = module.get<ExampleService>(ExampleService);
  });

  it('should return an empty array initially', () => {
    expect(controller.findAll()).toEqual([]);
  });

  it('should create and retrieve an example', () => {
    const created = controller.create({ name: 'Test', description: 'Desc' });
    expect(created.name).toBe('Test');
    expect(created.id).toBeDefined();

    const found = controller.findOne(created.id);
    expect(found.name).toBe('Test');
  });

  it('should update an example', () => {
    const created = service.create({ name: 'Original' });
    const updated = controller.update(created.id, { name: 'Updated' });
    expect(updated.name).toBe('Updated');
  });

  it('should delete an example', () => {
    const created = service.create({ name: 'ToDelete' });
    controller.remove(created.id);
    expect(controller.findAll()).toEqual([]);
  });
});
```

---

## Scaffold Steps

### 1. Write All Files

Create the target directory and write all files:

- All **Part B** config files verbatim (including `.husky/pre-commit` and `.husky/pre-push`)
- All **Part C** source files verbatim
- Create two empty files: `src/common/types/.gitkeep` and `src/database/.gitkeep`
- Generate `package.json` with the project name substituted (see Generation Conventions)
- Generate `README.md` (see Generation Conventions)

Make `docker-entrypoint.sh` and both husky hooks executable:

```bash
chmod +x docker-entrypoint.sh .husky/pre-commit .husky/pre-push
```

### 2. Update Project Settings

In `package.json`, set `"name"` to the project name (kebab-case).

In `src/config/env.config.ts`, update the fallback defaults:

```typescript
PROJECT_NAME: process.env.PROJECT_NAME || '<Project Name>',
PROJECT_DESCRIPTION:
  process.env.PROJECT_DESCRIPTION ||
  'API built with [NestJS](https://nestjs.com/) + Fastify',
```

In `.env.example`, update:

```env
PROJECT_NAME=<project-name>
```

### 3. Create Environment File

```bash
cp .env.example .env
```

### 4. Install Dependencies

```bash
git init
pnpm install
```

`pnpm install` triggers the `prepare` script which activates husky.

### 5. Verification Gate

**Do NOT generate AGENTS.md until all three pass:**

```bash
pnpm build        # zero compile errors
pnpm test         # all unit tests pass
pnpm test:e2e     # e2e tests pass
```

If any command fails, diagnose and fix before proceeding.

### 6. Generate AGENTS.md (MANDATORY)

Write `<!-- templateCentral: nestjs@1.0.0 -->` on line 1, then:

```markdown
<!-- templateCentral: nestjs@1.0.0 -->
# <Project Name>

## Identity
- **Stack**: NestJS 11, Fastify, Zod + nestjs-zod, Swagger, TypeScript, Jest
- **Scaffolded from**: templateCentral nestjs-scaffold skill
- **Created**: <date>

## Architecture Decisions
- One module per feature under `src/modules/`
- Controller → Service (→ Repository for complex queries); simple CRUD may use ORM directly in services
- DTOs use `createZodDto` from `nestjs-zod` (no class-validator)
- Global pipes and filters in `app.module.ts`; auth guards at controller/route level
- Setup functions (Swagger, security) in `src/config/setups/`

## Key Conventions
- kebab-case filenames (dot-separated), PascalCase classes, camelCase methods
- Named exports only — no `export default`
- Swagger `@ApiTags()` + `@ApiOperation()` on every endpoint
- Barrel exports at `src/modules/index.ts`
- **Testing**: New or changed controllers/services/repositories must include Jest tests in the same change (`pnpm test`; e2e when appropriate)

## Code Quality

Every agent writing or modifying code must follow these before marking a task done:

- **YAGNI** — Write only what the current task requires. No speculative helpers, abstractions, or files.
- **DRY** — Don't duplicate logic; extract at the second repetition. Don't extract from a single callsite.
- **SRP** — One responsibility per file and function. Controllers handle HTTP; services handle business logic; never mix.
- **SoC** — Keep concerns separate: HTTP from business logic, DTO validation from domain logic, config from implementation.
- **No premature abstractions** — Wait for the third callsite before extracting a shared helper.
- **No dead code** — No commented-out blocks, unused imports, unused variables, or TODO stubs.
- **No tech debt shortcuts** — No `// fix later`, `// temp`, or workarounds that degrade the codebase.
- **Validate at every boundary** — User input, API responses, env vars: always validate with Zod (`createZodDto`). Never trust external data.
- **Fail loudly** — No empty catch blocks. Log with context; return meaningful HTTP status codes.
- **Least privilege** — Return only the fields the caller needs. Never expose internal IDs without auth checks.
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

Update `Identity` with the actual project name and creation date.

### 6b. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean (`pnpm build`)
2. `shared-test-agent` — verify all scaffold tests pass (`pnpm test && pnpm test:e2e`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions
4. `shared-review-agent` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 6c. Install Claude Code plugins

**Claude Code users only.** Install these plugins in the scaffolded project directory. These are **on by default** — skip only if the user explicitly opts out.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin marketplace add thedotmack/claude-mem
claude plugin install claude-mem
claude plugin marketplace add obra/superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **claude-mem** — persists decisions, file changes, and tool usage across sessions via SQLite + vector DB. Installed in the **scaffolded project**, not in templateCentral.
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**If the user asks to skip:** Accept without pushback — these improve session quality but are not required.

---

### 7. Generate CLAUDE.md (Optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Write a short `CLAUDE.md` (architecture and conventions live in `AGENTS.md` only).

Include:
- **Build & Dev** verified commands: `pnpm start:dev`, `pnpm build`, `pnpm test`, `pnpm test:e2e`, `pnpm lint`
- **templateCentral skills**: `nestjs-scaffold` (done), `nestjs-code-standards`, `nestjs-add-module`, `nestjs-add-auth`, `nestjs-add-database`, `nestjs-add-integration`, `nestjs-add-test`
- **Workflow**: simple/medium → templateCentral skills; complex → Superpowers
- NEVER put secrets in `CLAUDE.md`

### 7b. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from **Scaffold: optional Task Management** in templateCentral's root `AGENTS.md`. If no, skip.

### 8. Remove Example Code (Optional)

Once the project is verified and the user confirms it runs, use the `shared-remove-example` skill.

NestJS-specific steps (the skill covers these):
- Delete `src/modules/example/` directory
- Remove `ExampleModule` import and reference from `src/modules/index.ts`
- Remove `ExampleModule` from `imports` array in `src/app.module.ts`
- Delete `test/modules/example.controller.spec.ts`

---

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — **never** commit real secrets or paste JWT/DB credentials into `AGENTS.md` / `CLAUDE.md`
- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/`, `dist/`, or `.env` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off to the user
- NEVER remove the `base/` module — it provides the health check endpoint
- NEVER install packages globally — always use pnpm/npm within the project
- NEVER remove `test/` directory structure when cleaning up example code
