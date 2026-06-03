<!-- ref: scaffold/nextjs/config-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Verbatim Config Files

Write these files exactly as shown.

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
          // HSTS — only active over HTTPS; Next.js strips this header over HTTP automatically.
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
  exec sh -c "corepack enable pnpm && pnpm \"$@\""
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

# Reverse proxy trust — set to VPC CIDR (e.g. 10.0.0.0/8) or * when behind ALB → Traefik; leave empty for local dev
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
.env
.env.local

# vercel
.vercel

# typescript
*.tsbuildinfo
next-env.d.ts
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
# allowBuilds:
#   esbuild: true
#   sharp: true
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
      reporter: ['text', 'lcov'],
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