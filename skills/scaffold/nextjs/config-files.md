<!-- ref: scaffold/nextjs/config-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Verbatim Config Files

Write these files exactly as shown.

### `package.json`

> Set `"name"` to the project name (kebab-case) before `pnpm install`. Dependency versions use caret floors aligned with `.claude/rules/nextjs.md` and the current stable; `pnpm install` resolves the newest compatible. shadcn/ui Radix primitives and `@testing-library/*` are intentionally omitted — they are added by `npx shadcn@latest add` (Step 4) and `templatecentral:add (test)` respectively. Run the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`) post-scaffold to freshen pins.
>
> **ESLint pinned at `^9`** — `eslint-plugin-react-hooks` 7.x peer-supports only `^9`; bumping to ESLint 10 breaks `pnpm install` under strict peer enforcement until the plugin ships ESLint 10 support. Do not upgrade eslint past `^9` without verifying `eslint-plugin-react-hooks` peer compatibility.

```json
{
  "name": "PROJECT_NAME_PLACEHOLDER",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@11.5.2",
  "engines": {
    "node": ">=24"
  },
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "eslint .",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "typecheck": "tsc --noEmit",
    "check:logging": "node scripts/check-route-logging.mjs",
    "check": "prettier --check . && eslint . && tsc --noEmit && node scripts/check-route-logging.mjs",
    "test": "vitest run",
    "test:ci": "vitest run --coverage",
    "prepare": "lefthook install"
  },
  "dependencies": {
    "@tanstack/react-query": "^5.101.0",
    "axios": "^1.17.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "lucide-react": "^1.17.0",
    "next": "^16.2.6",
    "next-themes": "^0.4.6",
    "pino": "^10.3.1",
    "react": "^19.2.7",
    "react-dom": "^19.2.7",
    "react-hook-form": "^7.77.0",
    "@hookform/resolvers": "^5.1.0",
    "sonner": "^2.0.7",
    "tailwind-merge": "^3.0.0",
    "zod": "^4.4.3"
  },
  "devDependencies": {
    "@tailwindcss/postcss": "^4.3.0",
    "@tailwindcss/typography": "^0.5.16",
    "@types/node": "^25.9.1",
    "@types/react": "^19.2.0",
    "@types/react-dom": "^19.2.0",
    "@vitest/coverage-v8": "^4.1.8",
    "eslint": "^9.0.0",
    "eslint-config-next": "^16.2.6",
    "eslint-plugin-react-hooks": "^7.0.0",
    "lefthook": "^2.1.9",
    "pino-pretty": "^13.0.0",
    "prettier": "^3.8.3",
    "prettier-plugin-organize-imports": "^4.1.0",
    "prettier-plugin-tailwindcss": "^0.6.11",
    "tailwindcss": "^4.3.0",
    "tw-animate-css": "^1.3.0",
    "typescript": "^6.0.3",
    "vitest": "^4.1.8"
  }
}
```

### `scripts/check-route-logging.mjs`

> Next.js App Router has no global request-logging layer, so coverage can't be automatic like NestJS (pino-http) or FastAPI (ASGI middleware). This dependency-free check fails the build if any API handler ships unwrapped — wired into `pnpm check`, so it runs locally, in lefthook, and in CI. See `add/logging/nextjs.md`.

```js
// Fail the build if any App Router API handler is not wrapped in withLogging().
// Enforces the "every route is logged" rule the base scaffold models on its own handlers.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = 'src/app/api';
const METHODS = 'GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS';
const ROUTE_FILE = /^route\.m?[jt]sx?$/; // route.ts|tsx|js|jsx|mjs|mts

// Match on comment-stripped, whole-file text (not line-by-line) so commented-out handlers
// don't false-positive and prettier-wrapped `export const POST =\n  withLogging(...)` still passes.
const bareFn = new RegExp(`export\\s+(?:async\\s+)?function\\s+(?:${METHODS})\\b`, 'g');
// Whitespace lives INSIDE the lookahead so it can't backtrack to zero and false-pass `= withLogging`.
const unwrapped = new RegExp(`export\\s+const\\s+(?:${METHODS})\\b\\s*=(?!\\s*withLogging\\b)`, 'g');

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (ROUTE_FILE.test(entry)) out.push(p);
  }
  return out;
}

// Blank out comments while preserving newlines so reported line numbers stay accurate.
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
}

const lineOf = (src, index) => src.slice(0, index).split('\n').length;

const files = existsSync(ROOT) ? walk(ROOT) : [];
const violations = [];
for (const file of files) {
  const src = stripComments(readFileSync(file, 'utf8'));
  for (const m of src.matchAll(bareFn)) {
    violations.push(`${file}:${lineOf(src, m.index)} — bare handler export; wrap it in withLogging()`);
  }
  for (const m of src.matchAll(unwrapped)) {
    violations.push(`${file}:${lineOf(src, m.index)} — handler not wrapped in withLogging()`);
  }
}

if (violations.length > 0) {
  console.error('Route logging check failed — every API handler must be wrapped in withLogging():');
  for (const v of violations) console.error('  ' + v);
  process.exit(1);
}
console.log(`Route logging check passed (${files.length} route file(s)).`);
```

### `eslint.config.mjs`

> Next.js 16 ships `eslint-config-next` as native flat configs — `FlatCompat` causes circular JSON crashes. Import the flat config objects directly and spread them. `pnpm check` runs `eslint .`, so this file must exist.

```javascript
import coreWebVitals from 'eslint-config-next/core-web-vitals';
import typescript from 'eslint-config-next/typescript';

const config = [
  ...coreWebVitals,
  ...typescript,
  {
    rules: {
      // Honour the `_`-prefix convention for intentionally-unused args/vars.
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
    },
  },
  { ignores: ['.next/**', 'node_modules/**', 'next-env.d.ts', '.claude/**'] },
];

export default config;
```

### `.prettierignore`

```
node_modules
.next
dist
build
coverage
pnpm-lock.yaml
.claude

# Enforcement-layer config — human-reviewed, never auto-formatted.
# Prettier would otherwise rewrite these (yaml quoting/whitespace), drifting them from the
# harness-integrity baseline and failing verify-harness.sh on the first push / in CI.
lefthook.yml
.github/
.gitleaks.toml
```

### `.prettierrc`

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "es5",
  "tabWidth": 2,
  "printWidth": 100,
  "plugins": ["prettier-plugin-organize-imports", "prettier-plugin-tailwindcss"]
}
```

### `next.config.ts`

```ts
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: 'standalone',
  reactStrictMode: true,
  poweredByHeader: false,

  // Uncomment and add domains when using next/image with external URLs:
  // images: {
  //   remotePatterns: [{ protocol: 'https', hostname: 'example.com' }],
  // },

  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
          { key: 'X-XSS-Protection', value: '0' },
          // HSTS — browsers ignore HSTS received over HTTP, so this is only effective over HTTPS.
          { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
          // CSP baseline — tighten after auth/analytics are wired. frame-ancestors replaces X-Frame-Options for CSP2+ browsers.
          { key: 'Content-Security-Policy', value: "frame-ancestors 'none'; base-uri 'self'; object-src 'none'" },
        ],
      },
    ];
  },
};

export default nextConfig;
```

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "react-jsx",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] },
    "types": ["node"]
  },
  "include": [
    "next-env.d.ts",
    "**/*.ts",
    "**/*.tsx",
    ".next/types/**/*.ts",
    ".next/dev/types/**/*.ts"
  ],
  "exclude": ["node_modules"]
}
```

### `components.json`

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "new-york",
  "rsc": true,
  "tsx": true,
  "tailwind": {
    "config": "",
    "css": "src/app/globals.css",
    "baseColor": "neutral",
    "cssVariables": true,
    "prefix": ""
  },
  "aliases": {
    "components": "@/components",
    "ui": "@/components/ui",
    "utils": "@/lib/utils",
    "lib": "@/lib",
    "hooks": "@/hooks"
  },
  "iconLibrary": "lucide"
}
```

### `Dockerfile`

```dockerfile
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

FROM ${NODE_BUILD} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

ENV NEXT_TELEMETRY_DISABLED=1
# TZ defaults to UTC — override via TZ env var in your deploy config if needed

WORKDIR ${APP_DIR}

RUN apk add --no-cache dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}

FROM base AS deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* pnpm-workspace.yaml* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  elif [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else echo "Lockfile not found." && exit 1; \
  fi

FROM deps AS builder
ENV NODE_OPTIONS=--max-old-space-size=4096
COPY ./ ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm run build; \
  elif [ -f yarn.lock ]; then yarn run build; \
  elif [ -f package-lock.json ]; then npm run build; \
  else echo "Lockfile not found." && exit 1; \
  fi

FROM deps AS dev
ENV NODE_ENV="development"
COPY ./ ./
RUN apk add --no-cache curl
RUN chmod +x docker-entrypoint.sh
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["dev"]

FROM base AS prod-prep
ARG APP_UID
ARG APP_GID
RUN mkdir -p /tmp/.next/cache && chown -R ${APP_UID}:${APP_GID} /tmp/.next

FROM ${NODE} AS prod
ARG APP_UID
ARG APP_GID
ARG APP_DIR
ARG PORT

ENV NODE_ENV="production" \
    NODE_OPTIONS=--max-old-space-size=384 \
    PORT=${PORT} \
    HOSTNAME="0.0.0.0"

WORKDIR ${APP_DIR}

COPY --from=base /etc/passwd /etc/passwd
COPY --from=base /etc/group /etc/group
COPY --from=base /usr/bin/dumb-init /usr/bin/dumb-init
COPY --from=base /etc/ssl/certs/ /etc/ssl/certs/

COPY --from=prod-prep /tmp/.next /tmp/.next

COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/public ./public
COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/.next/standalone ./
COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/.next/static ./.next/static

EXPOSE ${PORT}
USER ${APP_UID}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://localhost:' + process.env.PORT + '/api/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"]

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
```

### `docker-entrypoint.sh`

```sh
#!/bin/sh

# Check for Yarn lock file
if [ -f "yarn.lock" ]; then
  exec yarn "$@"
# Check for pnpm lock file
elif [ -f "pnpm-lock.yaml" ]; then
  exec sh -c 'corepack enable pnpm && exec pnpm "$@"' -- "$@"
# Default to npm
else
  exec npm "$@"
fi
```

### `.dockerignore`

```
# Dependencies
node_modules/
.pnpm-store/

# Build outputs
.next/
out/
dist/
build/
.vercel/
.swc/
.turbo/

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
test-results/

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
!next.config.*
!tailwind.config.*
!postcss.config.*
!tsconfig*.json
```

### `.env.example`

```
# App
NEXT_PUBLIC_BASE_URL=http://localhost:3000

# Reverse proxy trust — set to the number of trusted proxy hops (1 = ALB → App, 2 = ALB → Traefik → App); leave empty/unset when there is no proxy (headers not trusted), e.g. local dev
TRUST_PROXY=

# Database (if using Drizzle — added by templatecentral:add (database))
# DATABASE_URL=

# Third-party API tokens
# API_KEY=
```

### `.gitignore`

```
# See https://help.github.com/articles/ignoring-files/ for more about ignoring files.

# dependencies
/node_modules
/.pnp
.pnp.*
.yarn/*
!.yarn/patches
!.yarn/plugins
!.yarn/releases
!.yarn/versions

# testing
/coverage

# next.js
/.next/
/out/

# production
/build

# misc
.DS_Store
*.pem

# debug
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*

# env files (can opt-in for committing if needed)
.env*
!.env.example

# vercel
.vercel

# typescript
*.tsbuildinfo
next-env.d.ts
# Local agent symlink (.agents -> .claude) — NEVER track it: a git-tracked
# symlink breaks Windows CI build agents (e.g. "Unable to load symbolic/hard
# linked file" on Azure DevOps hosted runners). Recreate it per machine.
.agents
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
allowBuilds:
  sharp: true          # Next.js image optimisation
  unrs-resolver: true  # required by eslint-config-next resolver
  lefthook: false      # git-hook installer; binary ships via optional deps — no build needed, but pnpm 11 still requires an explicit decision or it blocks `pnpm <script>` runs
```

### `vitest.config.ts`

```ts
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(rootDir, 'src'),
    },
  },
  test: {
    globals: false,
    environment: 'node',
    passWithNoTests: true,
    include: ['test/**/*.{test,spec}.{ts,tsx}', 'src/**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura'],
      include: ['src/**/*.ts', 'src/**/*.tsx'],
      exclude: ['**/*.test.ts', '**/*.d.ts', '**/index.ts'],
    },
  },
});
```

### `postcss.config.mjs`

```mjs
const config = {
  plugins: {
    '@tailwindcss/postcss': {},
  },
};

export default config;
```

---