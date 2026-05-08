## Part B — Verbatim Config Files

### `Dockerfile`

```dockerfile
# ---- Global build arguments ----
# NODE:           Node.js image tag. Uses a floating major tag so patch updates
#                 are picked up automatically; pin to a digest in CI for
#                 reproducible builds. Build stages only — prod uses NGINX.
# NODE_BUILD:     Build-stage Node.js image. Always Alpine (needs shell for
#                 apk, adduser, etc.). Not overridden by CI.
# NGINX:          Nginx image for serving the static Vite build output
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the Nginx server listens on (also used in nginx.conf.template)
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG NGINX=nginx:1.28.2-alpine3.23
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
# Alpine foundation for deps/builder/dev stages (uses NODE_BUILD).
# Timezone and non-root user are created here.
FROM ${NODE_BUILD} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

WORKDIR ${APP_DIR}

# TZ defaults to UTC — override via TZ env var in your deploy config if needed
RUN apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}

# ---- Dependencies ----
# Installs ALL dependencies (including devDependencies like vite, typescript,
# postcss, etc.) for builder and dev stages.
FROM base AS deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* pnpm-workspace.yaml* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  elif [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Builder ----
# Runs the Vite build. Output lands in dist/ for the prod stage.
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
# Minimal Nginx image serving static dist/ output. No Node.js runtime needed.
FROM ${NGINX} AS prod
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME
ARG APP_DIR
ARG PORT

ENV PORT=${PORT}

RUN apk upgrade --no-cache \
    && mkdir -p /run \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME} \
    && chown -R ${APP_UID}:${APP_GID} /run /var/cache/nginx /etc/nginx \
    && chmod -R 755 /run /var/cache/nginx /etc/nginx \
    && rm /etc/nginx/conf.d/default.conf

COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/dist /usr/share/nginx/html
COPY --chown=${APP_UID}:${APP_GID} ./nginx.conf.template /etc/nginx/templates/nginx.conf.template

EXPOSE ${PORT}
USER ${APP_UID}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O/dev/null "http://localhost:${PORT:-3000}/" || exit 1

CMD ["nginx", "-g", "daemon off;"]
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
# ==============================================================================
# VITE + REACT DOCKER IGNORE - Production Optimized
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

# Vite Build Outputs & Cache
dist/
build/
.vite/
vite.config.js.timestamp-*
vite.config.ts.timestamp-*
.rollup.cache/

# Environment Variables (security)
.env
.env.*
!.env.example
!.env.local.example
!.env.production.example

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
.fleet/

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
test-results/
playwright-report/
cypress/videos/
cypress/screenshots/
cypress/downloads/
test-results.xml
junit.xml
.vitest/

# Cache Directories
.npm/
.yarn/
.pnpm/
.eslintcache
.cache/
.parcel-cache/
.turbo/

# Build Tool Cache
.rpt2_cache/
.rts2_cache_cjs/
.rts2_cache_es/
.rts2_cache_umd/

# React Development Tools
.react-dev-inspector/
.react-refresh/

# Development Tools & Storybook
.storybook-out/
.chromatic/
storybook-static/
.out/

# Temporary Files
tmp/
temp/
*.tmp
*.temp

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
*.p12
*.pfx
.secrets/

# TypeScript
*.tsbuildinfo
.tscache/

# Rust (for SWC/esbuild optimizations)
target/
Cargo.lock

# WebAssembly
*.wasm

# Analysis & Profiling
.analyze/
bundle-analyzer/
lighthouse/
.bundle-analyzer/
webpack-bundle-analyzer/
size-limit/

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

# AWS & Cloud
.aws/
.serverless/
.vercel/

# Sentry
.sentryclirc

# React Native (if applicable)
.expo/
android/
ios/

# PWA
.pwa/
sw.js
workbox-*.js

# Electron (if applicable)
electron-builder.env
out/
release/

# ==============================================================================
# EXCEPTIONS - Files to include despite patterns above
# ==============================================================================

# Package manager lock files (needed for reproducible builds)
!package-lock.json
!yarn.lock
!pnpm-lock.yaml
!pnpm-workspace.yaml
!bun.lockb

# Essential config files that might match broader patterns
!vite.config.*
!vitest.config.*
!tailwind.config.*
!postcss.config.*
!.eslintrc.*
!.prettierrc*
!tsconfig*.json
!jest.config.*
!playwright.config.*
!cypress.config.*
!rollup.config.*
```

### `.gitignore`

```
# dependencies
/node_modules
/.pnp
.pnp.*
.yarn/*
!.yarn/patches
!.yarn/plugins
!.yarn/releases
!.yarn/versions

# build output
dist/
build/

# vite
.vite/
vite.config.js.timestamp-*
vite.config.ts.timestamp-*

# testing
/coverage
.vitest/

# misc
.DS_Store
*.pem

# debug
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*

# env files
.env
.env.local

# IDE
.vscode/
.idea/

# typescript
*.tsbuildinfo
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
```

### `.env.example`

```
VITE_API_BASE_URL=http://localhost:8000
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

### `eslint.config.mjs`

```mjs
import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist'] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      'react-hooks': reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
    },
  }
);
```

### `nginx.conf.template`

```nginx
client_max_body_size 20M;
proxy_read_timeout 600s;
proxy_connect_timeout 60s;
proxy_send_timeout 60s;

server {
    listen ${PORT};
    listen [::]:${PORT};
    server_name _;
    absolute_redirect off;
    server_tokens off;
    autoindex off;

    root /usr/share/nginx/html;
    index index.html;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "0" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    location / {
        try_files $uri $uri/ /index.html;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_proxied any;
    gzip_min_length 1000;
    gzip_comp_level 5;
    gzip_disable "MSIE [1-6]\.";
    gzip_vary on;
}
```

### `index.html`

Update the `<title>` to the project name during scaffolding.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Vite React Template</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

### `vite.config.ts`

```ts
/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    open: true,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    css: true,
  },
});
```

### `vite-env.d.ts`

```ts
/// <reference types="vite/client" />
```

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "paths": {
      "@/*": ["./src/*"]
    },
    "types": [] // TypeScript 6 default; add @types/* package names here if globally-visible types are needed
  },
  "include": ["src", "vite-env.d.ts", "vite.config.ts"]
}
```

### `components.json`

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "new-york",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "",
    "css": "src/styles/globals.css",
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

### `postcss.config.mjs`

```mjs
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
};
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

