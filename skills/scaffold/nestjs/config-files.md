<!-- ref: scaffold/nestjs/config-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Verbatim Config Files

### `package.json`

> Set `"name"` to the project name (kebab-case) before `pnpm install`. Dependency versions use caret floors aligned with `.claude/rules/nestjs.md` and the current stable; `pnpm install` resolves the newest compatible. shadcn/ui Radix primitives and `@testing-library/*` are intentionally omitted — they are added by `npx shadcn@latest add` (Step 4) and `templatecentral:add (test)` respectively. Run `templatecentral:review` (update) post-scaffold to freshen pins.

```json
{
  "name": "PROJECT_NAME_PLACEHOLDER",
  "version": "0.1.0",
  "description": "",
  "private": true,
  "license": "UNLICENSED",
  "packageManager": "pnpm@11.5.2",
  "engines": {
    "node": ">=24"
  },
  "scripts": {
    "build": "nest build",
    "start": "nest start",
    "start:dev": "nest start --watch",
    "start:prod": "node dist/main.js",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "lint": "eslint \"{src,test}/**/*.ts\" --fix",
    "typecheck": "tsc --noEmit",
    "check": "prettier --check \"src/**/*.ts\" \"test/**/*.ts\" && eslint \"{src,test}/**/*.ts\" && tsc --noEmit",
    "test": "vitest --run",
    "test:watch": "vitest",
    "test:cov": "vitest --run --coverage",
    "test:e2e": "vitest --run --config vitest.config.e2e.ts",
    "test:ci": "vitest --run && vitest --run --config vitest.config.e2e.ts",
    "prepare": "husky"
  },
  "dependencies": {
    "@fastify/helmet": "^13.0.2",
    "@nestjs/common": "^11.1.24",
    "@nestjs/core": "^11.1.24",
    "@nestjs/platform-fastify": "^11.1.24",
    "@nestjs/swagger": "^11.4.4",
    "dotenv": "^17.4.2",
    "fastify": "^5.8.5",
    "nestjs-pino": "^4.6.1",
    "nestjs-zod": "^5.4.0",
    "pino-pretty": "^13.1.3",
    "reflect-metadata": "^0.2.2",
    "zod": "^4.4.3",
    "rxjs": "^7.8.2"
  },
  "devDependencies": {
    "@eslint/js": "^9.0.0",
    "@nestjs/cli": "^11.0.21",
    "@nestjs/schematics": "^11.1.0",
    "@nestjs/testing": "^11.1.24",
    "@types/node": "^25.9.1",
    "@vitest/coverage-v8": "^4.1.8",
    "eslint": "^9.0.0",
    "eslint-plugin-prettier": "^5.5.6",
    "globals": "^17.6.0",
    "husky": "^9.1.7",
    "prettier": "^3.8.3",
    "typescript": "^6.0.3",
    "typescript-eslint": "^8.60.1",
    "vitest": "^4.1.8"
  }
}
```

### `Dockerfile`

```dockerfile
# ---- Global build arguments ----
# NODE:           Production Node.js image. Uses a floating major tag so patch
#                 updates are picked up automatically; pin to a digest in CI
#                 for reproducible builds. Override via --build-arg NODE=...
# NODE_BUILD:     Build-stage Node.js image. Always Alpine (needs shell for
#                 apk, adduser, etc.). Not overridden by CI.
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the NestJS server listens on
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
# Alpine foundation for deps/builder/dev stages (uses NODE_BUILD).
# OS packages (dumb-init, ca-certificates) and the non-root user are
# created here, then COPY'd into the prod stage which may be distroless.
FROM ${NODE_BUILD} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

WORKDIR ${APP_DIR}

# TZ defaults to UTC — override via TZ env var in your deploy config if needed
RUN apk add --no-cache dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}

# ---- Dependencies ----
# Installs ALL dependencies (including devDependencies like TypeScript, vitest, etc.)
# Used by the builder (needs TypeScript, build tools) and the dev stage.
FROM base AS deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* pnpm-workspace.yaml* ./
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
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* pnpm-workspace.yaml* ./
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
# database connections (Mongoose, Kysely/pg pools).
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

# OS-level setup from the Alpine base stage (user, certs, dumb-init)
COPY --from=base /etc/passwd /etc/passwd
COPY --from=base /etc/group /etc/group
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
# Dependencies
node_modules/
.pnpm-store/

# Build outputs
dist/
build/
.build/
.swc/

# Environment variables — never copy secrets into image
.env
.env.*
!.env.example
!.env.local.example

# Version control
.git
.gitignore
.gitattributes

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Testing & coverage
coverage/
.nyc_output/
test/
test-results/
*.spec.ts
*.test.ts
*.e2e-spec.ts

# Cache
.npm/
.yarn/
.pnpm/
.eslintcache
.cache/

# Security — never copy certs or keys
*.pem
*.key
*.crt
*.p12
*.pfx
.secrets/

# CI/CD config (not needed in image)
.github/
.gitlab-ci.yml
.circleci/

# Docs
README*.md
docs/

# TypeScript build cache
*.tsbuildinfo

# ==============================================================================
# EXCEPTIONS
# ==============================================================================
!package-lock.json
!yarn.lock
!pnpm-lock.yaml
!pnpm-workspace.yaml
!nest-cli.json
!tsconfig.json
!tsconfig.build.json
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

# Reverse proxy trust — set to VPC CIDR (e.g. 10.0.0.0/8) or * when behind ALB → Traefik; leave empty for local dev
TRUST_PROXY=
```

### `.npmrc`

```
# Auth and registry settings only (pnpm 11+).
# All other pnpm settings live in pnpm-workspace.yaml.
```

### `pnpm-workspace.yaml`

```yaml
# pnpm-workspace.yaml — project-level pnpm 11 settings.
# Auth/registry settings belong in .npmrc; all other settings belong here.

# Block git-URL, tarball, and local-path dependencies.
# Primary mitigation against dependency confusion and supply-chain attacks.
blockExoticSubdeps: true

# Explicitly allowlist packages permitted to run install-time build scripts.
# pnpm 11 blocks all install scripts by default; add native packages here as needed.
# Run `templatecentral:add (auth)` — it adds argon2 and will prompt you to uncomment this.
# allowBuilds:
#   argon2: true   # required after `templatecentral:add (auth)`
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
      '@typescript-eslint/no-explicit-any': 'warn',
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

### `vitest.config.ts`

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    passWithNoTests: true,
    include: ['test/**/*.{spec,test}.ts', 'src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.ts'],
      exclude: ['**/*.spec.ts', '**/*.d.ts', 'src/main.ts'],
    },
  },
});
```

### `vitest.config.e2e.ts`

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    passWithNoTests: true,
    include: ['test/**/*.e2e-spec.ts'],
  },
});
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
    ],
    "types": ["node"]
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