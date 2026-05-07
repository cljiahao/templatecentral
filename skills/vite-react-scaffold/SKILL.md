---
name: vite-react-scaffold
description: Use when scaffolding a new Vite + React SPA (no SSR) — sets up TypeScript, React Router, TanStack Query, shadcn/ui, and Docker (auth added separately via vite-react-add-auth).
version: "1.0.0"
---

# Scaffold Vite + React Project

## Inputs

- **Project name** — The name for the new project (e.g., `my-app`). If not provided, ask the user.
- **Target directory** — Where to create the project (e.g., `~/projects/my-app`). If not provided, default to `./<project-name>` and confirm with the user.

---

## Part A — Rules

### Dependencies

Install runtime and dev dependencies (no version pins — `shared-update-agent` freshens them after scaffold):

```bash
pnpm add react react-dom react-router @tanstack/react-query \
  class-variance-authority clsx tailwind-merge lucide-react \
  @hookform/resolvers react-hook-form zod sonner motion

pnpm add -D vite @vitejs/plugin-react typescript \
  @types/react @types/react-dom \
  tailwindcss @tailwindcss/postcss @tailwindcss/typography tw-animate-css \
  eslint @eslint/js eslint-plugin-react-hooks globals typescript-eslint prettier \
  prettier-plugin-organize-imports prettier-plugin-tailwindcss \
  vitest @vitest/coverage-v8 @testing-library/react @testing-library/dom @testing-library/jest-dom \
  @testing-library/user-event jsdom husky postcss
```

Then initialize git before installing (husky requires a git repo):

```bash
git init
pnpm install    # activates husky via prepare script
```

Install shadcn components:

```bash
npx shadcn@latest add accordion avatar button card checkbox dialog dropdown-menu form input label select separator skeleton sonner tabs textarea
```

Note: Custom UI components (`field.tsx`, `button-group.tsx`, `input-group.tsx`) are written as verbatim Part C blocks — NOT installed by shadcn.

### Directory Structure

```
<project-name>/
├── Dockerfile                              [verbatim]
├── docker-entrypoint.sh                    [verbatim]
├── .dockerignore                           [verbatim]
├── .gitignore                              [verbatim]
├── .npmrc                                  [verbatim]
├── pnpm-workspace.yaml                     [verbatim]
├── .env.example                            [verbatim]
├── .env                                    [copy from .env.example]
├── .prettierrc                             [verbatim]
├── eslint.config.mjs                       [verbatim]
├── nginx.conf.template                     [verbatim]
├── index.html                              [verbatim, update <title>]
├── vite.config.ts                          [verbatim]
├── vite-env.d.ts                           [verbatim]
├── tsconfig.json                           [verbatim]
├── components.json                         [verbatim]
├── postcss.config.mjs                      [verbatim]
├── package.json                            [generate — set name from user input]
├── README.md                               [generate]
├── AGENTS.md                               [generate — after verification gate]
├── .husky/
│   ├── pre-commit                          [verbatim]
│   └── pre-push                            [verbatim]
└── src/
    ├── main.tsx                            [verbatim]
    ├── app.tsx                             [verbatim]
    ├── router.tsx                          [verbatim]
    ├── styles/
    │   └── globals.css                     [verbatim]
    ├── test/
    │   └── setup.ts                        [verbatim]
    ├── hooks/
    │   └── index.ts                        [verbatim]
    ├── pages/
    │   ├── index.ts                        [verbatim]
    │   ├── home.tsx                        [verbatim, update branding]
    │   ├── login.tsx                       [verbatim]
    │   ├── dashboard.tsx                   [verbatim]
    │   └── not-found.tsx                   [verbatim]
    ├── features/
    │   ├── auth/
    │   │   ├── index.ts                    [verbatim]
    │   │   ├── types.ts                    [verbatim]
    │   │   ├── components/
    │   │   │   ├── index.ts                [verbatim]
    │   │   │   ├── auth-provider.tsx       [verbatim]
    │   │   │   ├── login-card.tsx          [verbatim]
    │   │   │   └── protected-route.tsx     [verbatim]
    │   │   └── hooks/
    │   │       ├── index.ts                [verbatim]
    │   │       └── use-auth.ts             [verbatim]
    │   └── example/
    │       ├── index.ts                    [verbatim]
    │       ├── types.ts                    [verbatim]
    │       ├── constants.ts                [verbatim]
    │       ├── api/
    │       │   ├── index.ts                [verbatim]
    │       │   ├── example-service.ts      [verbatim]
    │       │   └── example-service.test.ts [verbatim]
    │       ├── components/
    │       │   ├── index.ts                [verbatim]
    │       │   ├── example-card.tsx        [verbatim]
    │       │   ├── example-card.test.tsx   [verbatim]
    │       │   └── example-list.tsx        [verbatim]
    │       ├── hooks/
    │       │   ├── index.ts                [verbatim]
    │       │   └── use-example-items.query.ts [verbatim]
    │       └── schemas/
    │           └── index.ts                [verbatim — empty]
    ├── components/
    │   ├── layout/
    │   │   ├── index.ts                    [verbatim]
    │   │   ├── error-boundary.tsx          [verbatim]
    │   │   ├── navbar.tsx                  [verbatim, update brand text]
    │   │   ├── providers.tsx               [verbatim]
    │   │   ├── root-layout.tsx             [verbatim]
    │   │   └── site-footer.tsx             [verbatim, update credit text]
    │   ├── ui/                             [shadcn-managed + custom verbatim]
    │   │   ├── accordion.tsx               [shadcn]
    │   │   ├── avatar.tsx                  [shadcn]
    │   │   ├── button.tsx                  [shadcn]
    │   │   ├── button-group.tsx            [verbatim]
    │   │   ├── card.tsx                    [shadcn]
    │   │   ├── checkbox.tsx                [shadcn]
    │   │   ├── dialog.tsx                  [shadcn]
    │   │   ├── dropdown-menu.tsx           [shadcn]
    │   │   ├── field.tsx                   [verbatim]
    │   │   ├── form.tsx                    [shadcn]
    │   │   ├── input-group.tsx             [verbatim]
    │   │   ├── input.tsx                   [shadcn]
    │   │   ├── label.tsx                   [shadcn]
    │   │   ├── select.tsx                  [shadcn]
    │   │   ├── separator.tsx               [shadcn]
    │   │   ├── skeleton.tsx                [shadcn]
    │   │   ├── sonner.tsx                  [shadcn]
    │   │   ├── tabs.tsx                    [shadcn]
    │   │   └── textarea.tsx                [shadcn]
    │   └── widgets/
    │       ├── index.ts                    [verbatim]
    │       ├── brand-text.tsx              [verbatim]
    │       ├── custom-card.tsx             [verbatim]
    │       ├── custom-dialog.tsx           [verbatim]
    │       ├── custom-form-field.tsx       [verbatim]
    │       ├── link-list.tsx               [verbatim]
    │       ├── media-card.tsx              [verbatim]
    │       └── pill.tsx                    [verbatim]
    └── lib/
        ├── clients/
        │   └── fetch-client.ts             [verbatim]
        ├── constants/
        │   ├── index.ts                    [verbatim]
        │   ├── env.ts                      [verbatim — VITE_* only, never process.env]
        │   └── routes.ts                   [verbatim]
        ├── errors/
        │   ├── index.ts                    [verbatim]
        │   ├── api-error.ts                [verbatim]
        │   └── error-log-handler.ts        [verbatim]
        └── utils/
            └── index.ts                    [verbatim]
```

### Generation Conventions

**`package.json`** — generated file; use project name (lowercase kebab-case) as `"name"`. Use the dependency list above and the scripts block below. Set `"packageManager"` to the current pnpm version (`pnpm --version`).

> **`@vitejs/plugin-react` v6**: Uses Oxc for React Refresh transforms — no Babel config or `@babel/core` needed. To use the React Compiler, add `@rolldown/plugin-babel` with `reactCompilerPreset` instead of configuring Babel directly.

**Engines field to include in package.json** (use the Node version from `.claude/rules/vite-react.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```

**Scripts to include in `package.json`:**
```json
{
  "dev": "vite",
  "build": "tsc -b && vite build",
  "preview": "vite preview",
  "prepare": "husky",
  "format": "prettier --write .",
  "format:check": "prettier --check .",
  "lint": "eslint .",
  "lint:fix": "eslint . --fix",
  "typecheck": "tsc --noEmit",
  "check": "pnpm format:check && pnpm lint && pnpm typecheck",
  "test": "vitest run",
  "test:watch": "vitest",
  "test:ci": "vitest run --reporter=verbose",
  "test:coverage": "vitest run --coverage"
}
```

**`README.md`** — generated; short description of the project, list of key commands (`pnpm dev`, `pnpm build`, `pnpm test`, `pnpm check`).

**`AGENTS.md`** — generated only after the verification gate passes. Must start with `<!-- templateCentral: vite-react@1.0.0 -->` on line 1. See Scaffold Steps § Generate AGENTS.md for the content template.

---

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

## Part C — Verbatim Source Files

### `src/main.tsx`

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from '@/app';
import '@/styles/globals.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

### `src/app.tsx`

```tsx
import { ErrorBoundary, Providers } from '@/components/layout';
import { AppRouter } from '@/router';

export function App() {
  return (
    <ErrorBoundary>
      <Providers>
        <AppRouter />
      </Providers>
    </ErrorBoundary>
  );
}
```

### `src/router.tsx`

```tsx
import { RootLayout } from '@/components/layout';
import { ProtectedRoute } from '@/features/auth';
import { DashboardPage } from '@/pages/dashboard';
import { HomePage } from '@/pages/home';
import { LoginPage } from '@/pages/login';
import { NotFoundPage } from '@/pages/not-found';
import { BrowserRouter, Route, Routes } from 'react-router';

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<RootLayout />}>
          {/* Public routes */}
          <Route index element={<HomePage />} />
          <Route path="login" element={<LoginPage />} />

          {/* Protected routes */}
          <Route element={<ProtectedRoute />}>
            <Route path="dashboard" element={<DashboardPage />} />
          </Route>

          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
```

### `src/styles/globals.css`

```css
@import 'tailwindcss';
@plugin '@tailwindcss/typography';
@import 'tw-animate-css';

@theme inline {
  /* Fonts & radius */
  --font-sans: 'Inter', ui-sans-serif, system-ui, sans-serif;
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);

  /* App colors */
  --color-black: var(--black);
  --color-white: var(--white);

  /* Surface */
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-popover: var(--popover);
  --color-popover-foreground: var(--popover-foreground);

  /* Actions */
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-primary-hover: var(--primary-hover);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-secondary-hover: var(--secondary-hover);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-accent-hover: var(--accent-hover);

  /* Feedback */
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-destructive: var(--destructive);
  --color-destructive-foreground: var(--destructive-foreground);

  /* Borders & inputs */
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);

  /* Max content width */
  --max-w-site: 1280px;
}

:root {
  --radius: 0.625rem;

  /* Core palette — neutral */
  --black: oklch(0 0 0);
  --white: oklch(1 0 0);

  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);

  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --primary-hover: oklch(0.3 0 0);

  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --secondary-hover: oklch(0.92 0 0);

  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --accent-hover: oklch(0.92 0 0);

  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);

  --destructive: oklch(0.577 0.245 27.325);
  --destructive-foreground: oklch(0.577 0.245 27.325);

  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
}

* {
  border-color: var(--border);
}

body {
  background-color: var(--background);
  color: var(--foreground);
  font-family: var(--font-sans);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

/* Utility classes */
@utility max-w-site {
  max-width: var(--max-w-site);
}

@utility max-w-content {
  max-width: 1000px;
}

@utility flex-center {
  display: flex;
  align-items: center;
  justify-content: center;
}

@utility flex-between {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

@utility flex-start {
  display: flex;
  align-items: flex-start;
  justify-content: flex-start;
}

@utility flex-end {
  display: flex;
  justify-content: flex-end;
}

@utility hw-full {
  height: 100%;
  width: 100%;
}

@utility bg-brand-gradient {
  background-image: linear-gradient(to right, var(--primary), var(--primary), var(--primary));
}

@utility text-brand-gradient {
  background-image: linear-gradient(to right, var(--primary), var(--primary), var(--primary));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* Scrollbar */
.no-scrollbar::-webkit-scrollbar {
  display: none;
}

.no-scrollbar {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
```

### `src/test/setup.ts`

```ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

### `src/hooks/index.ts`

```ts
// Shared hooks (used by shadcn/ui components that auto-generate hook dependencies).
// Feature-specific hooks live in src/features/<name>/hooks/.
```

### `src/pages/index.ts`

```ts
export { DashboardPage } from './dashboard';
export { HomePage } from './home';
export { LoginPage } from './login';
export { NotFoundPage } from './not-found';
```

### `src/pages/home.tsx`

Update `"Vite + React Template"` to the project name during scaffolding.

```tsx
import { Link } from 'react-router';
import { PAGE_ROUTES } from '@/lib/constants/routes';

export function HomePage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-16">
      <div className="flex flex-col items-center gap-6 text-center">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">Vite + React Template</h1>
        <p className="max-w-xl text-lg text-muted-foreground">
          A production-ready starter with React Router, TanStack Query, Tailwind CSS, and a
          feature-driven folder structure.
        </p>
        <Link
          to={PAGE_ROUTES.DASHBOARD}
          className="rounded-lg bg-primary px-6 py-3 font-semibold text-primary-foreground transition-colors hover:bg-primary-hover"
        >
          Go to Dashboard
        </Link>
      </div>
    </div>
  );
}
```

### `src/pages/login.tsx`

```tsx
import { LoginCard } from '@/features/auth';

export function LoginPage() {
  return (
    <div className="flex-center min-h-screen">
      <LoginCard />
    </div>
  );
}
```

### `src/pages/dashboard.tsx`

```tsx
import { ExampleList } from '@/features/example';

export function DashboardPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-muted-foreground">
        This page demonstrates the feature module pattern with TanStack Query.
      </p>

      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
```

### `src/pages/not-found.tsx`

```tsx
import { Link } from 'react-router';
import { PAGE_ROUTES } from '@/lib/constants/routes';

export function NotFoundPage() {
  return (
    <div className="flex-center min-h-[60vh] flex-col gap-4">
      <h1 className="text-6xl font-bold">404</h1>
      <p className="text-lg text-muted-foreground">Page not found</p>
      <Link
        to={PAGE_ROUTES.HOME}
        className="mt-2 text-sm font-medium text-primary underline underline-offset-4 hover:text-primary-hover"
      >
        Go back home
      </Link>
    </div>
  );
}
```

### `src/features/auth/index.ts`

```ts
export { AuthProvider, LoginCard, ProtectedRoute } from './components';
export { useAuth } from './hooks';
export type { AuthState, AuthUser } from './types';
```

### `src/features/auth/types.ts`

```ts
export interface AuthUser {
  id: string;
  name: string;
  email: string;
  image?: string | null;
}

export interface AuthState {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}
```

### `src/features/auth/components/index.ts`

```ts
export { AuthProvider } from './auth-provider';
export { LoginCard } from './login-card';
export { ProtectedRoute } from './protected-route';
```

### `src/features/auth/components/auth-provider.tsx`

```tsx
import { ENV } from '@/lib/constants/env';
import { createContext, useCallback, useMemo, useState, type ReactNode } from 'react';
import type { AuthUser } from '../types';

const DEV_USER: AuthUser = {
  id: 'dev',
  name: 'Dev User',
  email: 'dev@local',
};

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (user: AuthUser) => void;
  logout: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<AuthUser | null>(
    // Dev bypass: in development, skip the API call and use a mock user.
    // Remove this block before going to production.
    ENV.IS_DEV ? DEV_USER : null
  );
  const [isLoading] = useState(false);

  const login = useCallback((authUser: AuthUser) => {
    setUser(authUser);
  }, []);

  const logout = useCallback(async () => {
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({
      user,
      isAuthenticated: !!user,
      isLoading,
      login,
      logout,
    }),
    [user, isLoading, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

### `src/features/auth/components/login-card.tsx`

```tsx
import { CustomCard } from '@/components/widgets';
import { ENV } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useNavigate } from 'react-router';
import { useAuth } from '../hooks/use-auth';

export function LoginCard() {
  const { login } = useAuth();
  const navigate = useNavigate();

  const handleDevLogin = () => {
    login({ id: 'dev', name: 'Dev User', email: 'dev@local' });
    navigate(PAGE_ROUTES.DASHBOARD);
  };

  return (
    <CustomCard
      header="Sign In"
      description="Choose a sign-in method to continue."
      className="w-full max-w-md shadow-lg"
    >
      <div className="flex flex-col gap-4">
        {/* Add your SSO / OAuth login button here */}
        {ENV.IS_DEV && (
          <button
            type="button"
            className="rounded-md border-2 bg-white px-4 py-3 text-sm text-gray-500 hover:bg-gray-100"
            onClick={handleDevLogin}
          >
            Dev login (bypass auth)
          </button>
        )}
      </div>
    </CustomCard>
  );
}
```

### `src/features/auth/components/protected-route.tsx`

```tsx
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { Navigate, Outlet } from 'react-router';
import { useAuth } from '../hooks/use-auth';

export function ProtectedRoute() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex-center min-h-screen">
        <p className="text-muted-foreground">Loading...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to={PAGE_ROUTES.LOGIN} replace />;
  }

  return <Outlet />;
}
```

### `src/features/auth/hooks/index.ts`

```ts
export { useAuth } from './use-auth';
```

### `src/features/auth/hooks/use-auth.ts`

```ts
import { useContext } from 'react';
import { AuthContext } from '../components/auth-provider';

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
```

### `src/features/example/index.ts`

```ts
export * from './components';
export * from './hooks';
export * from './constants';
export type { ExampleItem } from './types';
```

### `src/features/example/types.ts`

```ts
export interface ExampleItem {
  id: string;
  title: string;
  description: string;
}
```

### `src/features/example/constants.ts`

```ts
export const EXAMPLE_ITEMS = [
  { id: 'item-1', title: 'First Item', description: 'Description for the first item' },
  { id: 'item-2', title: 'Second Item', description: 'Description for the second item' },
  { id: 'item-3', title: 'Third Item', description: 'Description for the third item' },
] as const;
```

### `src/features/example/api/index.ts`

```ts
export { ExampleService } from './example-service';
```

### `src/features/example/api/example-service.ts`

```ts
import { EXAMPLE_ITEMS } from '../constants';
import type { ExampleItem } from '../types';

export const ExampleService = {
  getAll: (): ExampleItem[] => {
    return [...EXAMPLE_ITEMS];
  },

  getById: (id: string): ExampleItem | undefined => {
    return EXAMPLE_ITEMS.find((item) => item.id === id);
  },
};
```

### `src/features/example/api/example-service.test.ts`

```ts
import { describe, expect, it } from 'vitest';
import { ExampleService } from './example-service';

describe('ExampleService', () => {
  it('returns all example items', () => {
    const items = ExampleService.getAll();
    expect(items).toHaveLength(3);
    expect(items[0]).toHaveProperty('id');
    expect(items[0]).toHaveProperty('title');
  });

  it('returns a copy, not the original array', () => {
    const a = ExampleService.getAll();
    const b = ExampleService.getAll();
    expect(a).not.toBe(b);
    expect(a).toEqual(b);
  });

  it('finds an item by id', () => {
    const item = ExampleService.getById('item-1');
    expect(item).toBeDefined();
    expect(item?.title).toBe('First Item');
  });

  it('returns undefined for unknown id', () => {
    const item = ExampleService.getById('nonexistent');
    expect(item).toBeUndefined();
  });
});
```

### `src/features/example/components/index.ts`

```ts
export { ExampleCard } from './example-card';
export { ExampleList } from './example-list';
```

### `src/features/example/components/example-card.tsx`

```tsx
import { CustomCard } from '@/components/widgets';
import type { ExampleItem } from '../types';

interface ExampleCardProps {
  item: ExampleItem;
}

export function ExampleCard({ item }: ExampleCardProps) {
  return <CustomCard header={item.title} description={item.description} />;
}
```

### `src/features/example/components/example-card.test.tsx`

```tsx
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ExampleCard } from './example-card';

describe('ExampleCard', () => {
  const mockItem = {
    id: 'test-1',
    title: 'Test Title',
    description: 'Test description text',
  };

  it('renders the item title and description', () => {
    render(<ExampleCard item={mockItem} />);
    expect(screen.getByText('Test Title')).toBeInTheDocument();
    expect(screen.getByText('Test description text')).toBeInTheDocument();
  });
});
```

### `src/features/example/components/example-list.tsx`

```tsx
import { useExampleItems } from '../hooks';
import { ExampleCard } from './example-card';

export function ExampleList() {
  const { data: items, isPending, error } = useExampleItems();

  if (isPending) {
    return <p className="text-muted-foreground">Loading...</p>;
  }

  if (error) {
    return <p className="text-destructive">Failed to load items.</p>;
  }

  if (!items?.length) {
    return <p className="text-muted-foreground">No items found.</p>;
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <ExampleCard key={item.id} item={item} />
      ))}
    </div>
  );
}
```

### `src/features/example/hooks/index.ts`

```ts
export { useExampleItems } from './use-example-items.query';
```

### `src/features/example/hooks/use-example-items.query.ts`

```ts
import { useQuery } from '@tanstack/react-query';
import { ExampleService } from '../api';

export const useExampleItems = () => {
  return useQuery({
    queryKey: ['example-items'],
    queryFn: () => ExampleService.getAll(),
  });
};
```

### `src/features/example/schemas/index.ts`

Empty file — placeholder for Zod schemas added by the `vite-react-add-feature` skill.

### `src/components/layout/index.ts`

```ts
export { Navbar } from './navbar';
export { Providers } from './providers';
export { RootLayout } from './root-layout';
export { SiteFooter } from './site-footer';
export { ErrorBoundary } from './error-boundary';
```

### `src/components/layout/error-boundary.tsx`

```tsx
import { Component, type ErrorInfo, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-2xl font-bold">Something went wrong</h1>
          <p className="text-muted-foreground max-w-md text-sm">
            {this.state.error?.message || 'An unexpected error occurred.'}
          </p>
          <button
            type="button"
            onClick={this.handleRetry}
            className="bg-primary text-primary-foreground hover:bg-primary/90 rounded-md px-4 py-2 text-sm font-medium transition-colors"
          >
            Try again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

### `src/components/layout/navbar.tsx`

Replace `templateCentral` with the project name during scaffolding.

```tsx
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';
import { Link, useLocation } from 'react-router';

const NAV_LINKS = [
  { label: 'Home', href: PAGE_ROUTES.HOME },
  { label: 'Dashboard', href: PAGE_ROUTES.DASHBOARD },
] as const;

export function Navbar() {
  const { pathname } = useLocation();

  return (
    <nav className="sticky top-0 z-50 w-full border-b bg-white">
      <div className="max-w-site flex-between mx-auto px-6 py-4">
        <Link to={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          templateCentral
        </Link>

        <div className="flex gap-6">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              to={link.href}
              className={cn(
                'text-sm font-medium transition-colors hover:text-primary',
                pathname === link.href ? 'text-primary' : 'text-muted-foreground'
              )}
            >
              {link.label}
            </Link>
          ))}
        </div>
      </div>
    </nav>
  );
}
```

### `src/components/layout/providers.tsx`

```tsx
import { AuthProvider } from '@/features/auth';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { Toaster } from 'sonner';

interface ProvidersProps {
  children: ReactNode;
}

export function Providers({ children }: ProvidersProps) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            refetchOnWindowFocus: false,
          },
        },
      })
  );

  return (
    <AuthProvider>
      <QueryClientProvider client={queryClient}>
        {children}
        <Toaster position="top-right" />
      </QueryClientProvider>
    </AuthProvider>
  );
}
```

### `src/components/layout/root-layout.tsx`

```tsx
import { Outlet } from 'react-router';
import { Navbar } from './navbar';
import { SiteFooter } from './site-footer';

export function RootLayout() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        <Outlet />
      </main>
      <SiteFooter />
    </div>
  );
}
```

### `src/components/layout/site-footer.tsx`

Update `creditText` default to project name during scaffolding.

```tsx
interface SiteFooterProps {
  creditText?: string;
}

export function SiteFooter({ creditText = 'Built with templateCentral' }: SiteFooterProps) {
  return (
    <footer className="w-full border-t bg-black">
      <div className="max-w-site mx-auto px-6 py-6">
        <p className="text-sm text-white">{creditText}</p>
      </div>
    </footer>
  );
}
```

### `src/components/widgets/index.ts`

```ts
export { BrandText } from './brand-text';
export { CustomCard } from './custom-card';
export { CustomDialog } from './custom-dialog';
export { CustomFormField } from './custom-form-field';
export { LinkList, type LinkItem } from './link-list';
export { MediaCard } from './media-card';
export { Pill } from './pill';
```

### `src/components/widgets/brand-text.tsx`

```tsx
import { cn } from '@/lib/utils';

interface BrandTextProps {
  className?: string;
}

export function BrandText({ className }: BrandTextProps) {
  return (
    <>
      <span className="text-brand-gradient">template</span>
      <span className={cn('text-white', className)}>Central</span>
    </>
  );
}
```

### `src/components/widgets/custom-card.tsx`

```tsx
import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';

interface CustomCardProps {
  header: string;
  description?: string;
  children?: ReactNode;
  className?: string;
}

export function CustomCard({ header, description, children, className }: CustomCardProps) {
  return (
    <div className={cn('rounded-lg border bg-white p-6 shadow-xs', className)}>
      <h3 className="text-lg font-semibold">{header}</h3>
      {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}
```

### `src/components/widgets/custom-dialog.tsx`

```tsx
import type { ComponentProps, ReactNode } from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';

interface CustomDialogProps extends Omit<
  ComponentProps<typeof Dialog>,
  'children'
> {
  className?: string;
  children: ReactNode;
  trigger?: ReactNode;
  title?: ReactNode;
  description?: ReactNode;
}

export function CustomDialog({
  className,
  trigger,
  title,
  description,
  children,
  ...dialogProps
}: CustomDialogProps) {
  return (
    <Dialog {...dialogProps}>
      {trigger && <DialogTrigger asChild>{trigger}</DialogTrigger>}
      <DialogContent className={cn('flex h-full w-full flex-col', className)}>
        <DialogHeader>
          {title ? (
            <DialogTitle>{title}</DialogTitle>
          ) : (
            <DialogTitle className="sr-only">Dialog</DialogTitle>
          )}
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        {children}
      </DialogContent>
    </Dialog>
  );
}
```

### `src/components/widgets/custom-form-field.tsx`

```tsx
import { cloneElement, type ReactElement } from 'react';
import { Controller, useFormContext } from 'react-hook-form';

import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
} from '@/components/ui/field';

interface CustomFormFieldProps {
  name: string;
  label: string;
  description?: string;
  children: ReactElement<Record<string, unknown>>;
}

export function CustomFormField({
  name,
  label,
  description,
  children,
}: CustomFormFieldProps) {
  const { control } = useFormContext();

  return (
    <Controller
      name={name}
      control={control}
      render={({ field: { ref, ...field }, fieldState }) => (
        <Field data-invalid={fieldState.invalid}>
          <FieldLabel
            htmlFor={name}
            className="text-foreground text-lg leading-tight font-semibold tracking-tight"
          >
            {label}
          </FieldLabel>
          {cloneElement(children, {
            id: name,
            ref,
            'aria-invalid': fieldState.invalid,
            ...field,
          })}
          {description && <FieldDescription>{description}</FieldDescription>}
          {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
        </Field>
      )}
    />
  );
}
```

### `src/components/widgets/link-list.tsx`

```tsx
import { cn } from '@/lib/utils';

export interface LinkItem {
  label: string;
  href: string;
  target?: string;
}

interface LinkListProps {
  links: LinkItem[];
  className?: string;
}

export function LinkList({ links, className }: LinkListProps) {
  return (
    <div className="flex items-center gap-6">
      {links.map((link) => (
        <a
          key={link.label}
          href={link.href}
          target={link.target}
          rel={link.target === '_blank' ? 'noopener noreferrer' : undefined}
          className={cn(
            'hover:text-primary font-semibold transition-colors',
            className
          )}
        >
          {link.label}
        </a>
      ))}
    </div>
  );
}
```

### `src/components/widgets/media-card.tsx`

```tsx
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';

type MediaPosition = 'top' | 'bottom' | 'left' | 'right';

interface MediaCardProps {
  className?: string;
  children?: ReactNode;
  title: string;
  description?: string;
  descClassName?: string;
  /** Where the media (children) is placed relative to the text. @default "top" */
  mediaPosition?: MediaPosition;
}

interface LayoutStyles {
  card: string;
  content: string;
  header: string;
  text: string;
}

const VERTICAL: Omit<LayoutStyles, 'card'> = {
  content: 'hw-full',
  header: 'flex-center hw-full',
  text: 'text-center',
};

const HORIZONTAL: Omit<LayoutStyles, 'card'> = {
  content: 'flex-1',
  header: 'flex-1',
  text: 'text-left',
};

const LAYOUT: Record<MediaPosition, LayoutStyles> = {
  top: { card: 'flex-col', ...VERTICAL },
  bottom: { card: 'flex-col-reverse', ...VERTICAL },
  left: { card: 'flex-row items-center gap-8', ...HORIZONTAL },
  right: { card: 'flex-row-reverse items-center gap-8', ...HORIZONTAL },
};

export function MediaCard({
  className,
  children,
  title,
  description,
  descClassName,
  mediaPosition = 'top',
}: MediaCardProps) {
  const { card, content, header, text } = LAYOUT[mediaPosition];

  return (
    <div className="bg-brand-gradient rounded-lg p-px">
      <Card className={cn('flex h-full w-full p-2', card, className)}>
        {children && (
          <CardContent className={cn('flex-center', content)}>
            {children}
          </CardContent>
        )}
        <CardHeader
          className={cn('flex-col gap-3', header, !children && 'flex-center')}
        >
          <CardTitle className={text}>{title}</CardTitle>
          {description && (
            <CardDescription className={cn('text-wrap', text, descClassName)}>
              {description}
            </CardDescription>
          )}
        </CardHeader>
      </Card>
    </div>
  );
}
```

### `src/components/widgets/pill.tsx`

```tsx
import type { ReactNode } from 'react';

import { cn } from '@/lib/utils';

interface PillProps {
  children: ReactNode;
  variant?: 'outline' | 'solid';
}

export function Pill({ children, variant = 'outline' }: PillProps) {
  return (
    <div className="bg-brand-gradient inline-block rounded-full p-px">
      <span
        className={cn(
          'inline-block rounded-full px-4 py-1.5 text-sm font-medium',
          variant === 'solid'
            ? 'text-background'
            : 'bg-card text-muted-foreground'
        )}
      >
        {children}
      </span>
    </div>
  );
}
```

### `src/components/ui/button-group.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import type { ComponentProps } from 'react';

import { cva, type VariantProps } from 'class-variance-authority';
import { Slot } from '@radix-ui/react-slot';

import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils/index';

const buttonGroupVariants = cva(
  "flex w-fit items-stretch [&>*]:focus-visible:z-10 [&>*]:focus-visible:relative [&>[data-slot=select-trigger]:not([class*='w-'])]:w-fit [&>input]:flex-1 has-[select[aria-hidden=true]:last-child]:[&>[data-slot=select-trigger]:last-of-type]:rounded-r-md has-[>[data-slot=button-group]]:gap-2",
  {
    variants: {
      orientation: {
        horizontal:
          '[&>*:not(:first-child)]:rounded-l-none [&>*:not(:first-child)]:border-l-0 [&>*:not(:last-child)]:rounded-r-none',
        vertical:
          'flex-col [&>*:not(:first-child)]:rounded-t-none [&>*:not(:first-child)]:border-t-0 [&>*:not(:last-child)]:rounded-b-none',
      },
    },
    defaultVariants: {
      orientation: 'horizontal',
    },
  }
);

function ButtonGroup({
  className,
  orientation,
  ...props
}: ComponentProps<'div'> & VariantProps<typeof buttonGroupVariants>) {
  return (
    <div
      role="group"
      data-slot="button-group"
      data-orientation={orientation}
      className={cn(buttonGroupVariants({ orientation }), className)}
      {...props}
    />
  );
}

function ButtonGroupText({
  className,
  asChild = false,
  ...props
}: ComponentProps<'div'> & {
  asChild?: boolean;
}) {
  const Comp = asChild ? Slot.Root : 'div';

  return (
    <Comp
      className={cn(
        "bg-muted flex items-center gap-2 rounded-md border px-4 text-sm font-medium shadow-xs [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    />
  );
}

function ButtonGroupSeparator({
  className,
  orientation = 'vertical',
  ...props
}: ComponentProps<typeof Separator>) {
  return (
    <Separator
      data-slot="button-group-separator"
      orientation={orientation}
      className={cn(
        'bg-input relative !m-0 self-stretch data-[orientation=vertical]:h-auto',
        className
      )}
      {...props}
    />
  );
}

export {
  ButtonGroup,
  ButtonGroupSeparator,
  ButtonGroupText,
  buttonGroupVariants,
};
```

### `src/components/ui/field.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import type { ComponentProps, ReactNode } from 'react';
import { useMemo } from 'react';

import { cva, type VariantProps } from 'class-variance-authority';

import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/utils';

function FieldSet({ className, ...props }: ComponentProps<'fieldset'>) {
  return (
    <fieldset
      data-slot="field-set"
      className={cn(
        'flex flex-col gap-6',
        'has-[>[data-slot=checkbox-group]]:gap-3 has-[>[data-slot=radio-group]]:gap-3',
        className
      )}
      {...props}
    />
  );
}

function FieldLegend({
  className,
  variant = 'legend',
  ...props
}: ComponentProps<'legend'> & { variant?: 'legend' | 'label' }) {
  return (
    <legend
      data-slot="field-legend"
      data-variant={variant}
      className={cn(
        'mb-3 font-medium',
        'data-[variant=legend]:text-base',
        'data-[variant=label]:text-sm',
        className
      )}
      {...props}
    />
  );
}

function FieldGroup({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-group"
      className={cn(
        'group/field-group @container/field-group flex w-full flex-col gap-7 data-[slot=checkbox-group]:gap-3 [&>[data-slot=field-group]]:gap-4',
        className
      )}
      {...props}
    />
  );
}

const fieldVariants = cva(
  'group/field flex w-full gap-3 data-[invalid=true]:text-destructive',
  {
    variants: {
      orientation: {
        vertical: ['flex-col [&>*]:w-full [&>.sr-only]:w-auto'],
        horizontal: [
          'flex-row items-center',
          '[&>[data-slot=field-label]]:flex-auto',
          'has-[>[data-slot=field-content]]:items-start has-[>[data-slot=field-content]]:[&>[role=checkbox],[role=radio]]:mt-px',
        ],
        responsive: [
          'flex-col [&>*]:w-full [&>.sr-only]:w-auto @md/field-group:flex-row @md/field-group:items-center @md/field-group:[&>*]:w-auto',
          '@md/field-group:[&>[data-slot=field-label]]:flex-auto',
          '@md/field-group:has-[>[data-slot=field-content]]:items-start @md/field-group:has-[>[data-slot=field-content]]:[&>[role=checkbox],[role=radio]]:mt-px',
        ],
      },
    },
    defaultVariants: {
      orientation: 'vertical',
    },
  }
);

function Field({
  className,
  orientation = 'vertical',
  ...props
}: ComponentProps<'div'> & VariantProps<typeof fieldVariants>) {
  return (
    <div
      role="group"
      data-slot="field"
      data-orientation={orientation}
      className={cn(fieldVariants({ orientation }), className)}
      {...props}
    />
  );
}

function FieldContent({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-content"
      className={cn(
        'group/field-content flex flex-1 flex-col gap-1.5 leading-snug',
        className
      )}
      {...props}
    />
  );
}

function FieldLabel({
  className,
  ...props
}: ComponentProps<typeof Label>) {
  return (
    <Label
      data-slot="field-label"
      className={cn(
        'group/field-label peer/field-label flex w-fit gap-2 leading-snug group-data-[disabled=true]/field:opacity-50',
        'has-[>[data-slot=field]]:w-full has-[>[data-slot=field]]:flex-col has-[>[data-slot=field]]:rounded-md has-[>[data-slot=field]]:border [&>*]:data-[slot=field]:p-4',
        'has-data-[state=checked]:bg-primary/5 has-data-[state=checked]:border-primary',
        className
      )}
      {...props}
    />
  );
}

function FieldTitle({ className, ...props }: ComponentProps<'div'>) {
  return (
    <div
      data-slot="field-label"
      className={cn(
        'flex w-fit items-center gap-2 text-sm leading-snug font-medium group-data-[disabled=true]/field:opacity-50',
        className
      )}
      {...props}
    />
  );
}

function FieldDescription({ className, ...props }: ComponentProps<'p'>) {
  return (
    <p
      data-slot="field-description"
      className={cn(
        'text-muted-foreground text-sm leading-normal font-normal group-has-[[data-orientation=horizontal]]/field:text-balance',
        'last:mt-0 nth-last-2:-mt-1 [[data-variant=legend]+&]:-mt-1.5',
        '[&>a:hover]:text-primary [&>a]:underline [&>a]:underline-offset-4',
        className
      )}
      {...props}
    />
  );
}

function FieldSeparator({
  children,
  className,
  ...props
}: ComponentProps<'div'> & {
  children?: ReactNode;
}) {
  return (
    <div
      data-slot="field-separator"
      data-content={!!children}
      className={cn(
        'relative -my-2 h-5 text-sm group-data-[variant=outline]/field-group:-mb-2',
        className
      )}
      {...props}
    >
      <Separator className="absolute inset-0 top-1/2" />
      {children && (
        <span
          className="bg-background text-muted-foreground relative mx-auto block w-fit px-2"
          data-slot="field-separator-content"
        >
          {children}
        </span>
      )}
    </div>
  );
}

function FieldError({
  className,
  children,
  errors,
  ...props
}: ComponentProps<'div'> & {
  errors?: Array<{ message?: string } | undefined>;
}) {
  const content = useMemo(() => {
    if (children) {
      return children;
    }

    if (!errors?.length) {
      return null;
    }

    if (errors?.length == 1) {
      return errors[0]?.message;
    }

    return (
      <ul className="ml-4 flex list-disc flex-col gap-1">
        {errors.map(
          (error, index) =>
            error?.message && <li key={index}>{error.message}</li>
        )}
      </ul>
    );
  }, [children, errors]);

  if (!content) {
    return null;
  }

  return (
    <div
      role="alert"
      data-slot="field-error"
      className={cn('text-destructive text-sm font-normal', className)}
      {...props}
    >
      {content}
    </div>
  );
}

export {
  Field,
  FieldContent,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldLegend,
  FieldSeparator,
  FieldSet,
  FieldTitle,
};
```

### `src/components/ui/input-group.tsx`

Custom component (not managed by shadcn CLI):

```tsx
import { cva, type VariantProps } from 'class-variance-authority';
import * as React from 'react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils/index';

function InputGroup({ className, ...props }: React.ComponentProps<'div'>) {
  return (
    <div
      data-slot="input-group"
      role="group"
      className={cn(
        'group/input-group border-input relative flex w-full items-center rounded-md border shadow-xs transition-[color,box-shadow] outline-hidden',
        'h-9 min-w-0 has-[>textarea]:h-auto',
        'has-[>[data-align=inline-start]]:[&>input]:pl-2',
        'has-[>[data-align=inline-end]]:[&>input]:pr-2',
        'has-[>[data-align=block-start]]:h-auto has-[>[data-align=block-start]]:flex-col has-[>[data-align=block-start]]:[&>input]:pb-3',
        'has-[>[data-align=block-end]]:h-auto has-[>[data-align=block-end]]:flex-col has-[>[data-align=block-end]]:[&>input]:pt-3',
        'has-[[data-slot=input-group-control]:focus-visible]:border-ring has-[[data-slot=input-group-control]:focus-visible]:ring-ring/50 has-[[data-slot=input-group-control]:focus-visible]:ring-[3px]',
        'has-[[data-slot][aria-invalid=true]]:ring-destructive/20 has-[[data-slot][aria-invalid=true]]:border-destructive',
        className
      )}
      {...props}
    />
  );
}

const inputGroupAddonVariants = cva(
  "text-muted-foreground flex h-auto cursor-text items-center justify-center gap-2 py-1.5 text-sm font-medium select-none [&>svg:not([class*='size-'])]:size-4 [&>kbd]:rounded-[calc(var(--radius)-5px)] group-data-[disabled=true]/input-group:opacity-50",
  {
    variants: {
      align: {
        'inline-start':
          'order-first pl-3 has-[>button]:ml-[-0.45rem] has-[>kbd]:ml-[-0.35rem]',
        'inline-end':
          'order-last pr-3 has-[>button]:mr-[-0.45rem] has-[>kbd]:mr-[-0.35rem]',
        'block-start':
          'order-first w-full justify-start px-3 pt-3 [.border-b]:pb-3 group-has-[>input]/input-group:pt-2.5',
        'block-end':
          'order-last w-full justify-start px-3 pb-3 [.border-t]:pt-3 group-has-[>input]/input-group:pb-2.5',
      },
    },
    defaultVariants: {
      align: 'inline-start',
    },
  }
);

function InputGroupAddon({
  className,
  align = 'inline-start',
  ...props
}: React.ComponentProps<'div'> & VariantProps<typeof inputGroupAddonVariants>) {
  return (
    <div
      role="group"
      data-slot="input-group-addon"
      data-align={align}
      className={cn(inputGroupAddonVariants({ align }), className)}
      onClick={(e) => {
        if ((e.target as HTMLElement).closest('button')) {
          return;
        }
        e.currentTarget.parentElement?.querySelector('input')?.focus();
      }}
      {...props}
    />
  );
}

const inputGroupButtonVariants = cva(
  'text-sm shadow-none flex gap-2 items-center',
  {
    variants: {
      size: {
        xs: "h-6 gap-1 px-2 rounded-[calc(var(--radius)-5px)] [&>svg:not([class*='size-'])]:size-3.5 has-[>svg]:px-2",
        sm: 'h-8 px-2.5 gap-1.5 rounded-md has-[>svg]:px-2.5',
        'icon-xs':
          'size-6 rounded-[calc(var(--radius)-5px)] p-0 has-[>svg]:p-0',
        'icon-sm': 'size-8 p-0 has-[>svg]:p-0',
      },
    },
    defaultVariants: {
      size: 'xs',
    },
  }
);

function InputGroupButton({
  className,
  type = 'button',
  variant = 'ghost',
  size = 'xs',
  ...props
}: Omit<React.ComponentProps<typeof Button>, 'size'> &
  VariantProps<typeof inputGroupButtonVariants>) {
  return (
    <Button
      type={type}
      data-size={size}
      variant={variant}
      className={cn(inputGroupButtonVariants({ size }), className)}
      {...props}
    />
  );
}

function InputGroupText({ className, ...props }: React.ComponentProps<'span'>) {
  return (
    <span
      className={cn(
        "text-muted-foreground flex items-center gap-2 text-sm [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    />
  );
}

function InputGroupInput({
  className,
  ...props
}: React.ComponentProps<'input'>) {
  return (
    <Input
      data-slot="input-group-control"
      className={cn(
        'flex-1 rounded-none border-0 bg-transparent shadow-none focus-visible:ring-0',
        className
      )}
      {...props}
    />
  );
}

function InputGroupTextarea({
  className,
  ...props
}: React.ComponentProps<'textarea'>) {
  return (
    <Textarea
      data-slot="input-group-control"
      className={cn(
        'flex-1 resize-none rounded-none border-0 bg-transparent py-3 shadow-none focus-visible:ring-0',
        className
      )}
      {...props}
    />
  );
}

export {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput,
  InputGroupText,
  InputGroupTextarea,
};
```

### `src/lib/clients/fetch-client.ts`

```ts
import { APIError } from '@/lib/errors';

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';

const BINARY_CONTENT_TYPES = [
  'application/zip',
  'application/octet-stream',
  'application/gzip',
  'application/pdf',
  'image/',
  'video/',
  'audio/',
];

const TEXT_CONTENT_TYPES = [
  'text/plain',
  'text/html',
  'text/csv',
  'text/xml',
  'application/xml',
];

export abstract class FetchClient {
  constructor(
    protected baseUrl: string,
    protected headers: Record<string, string>
  ) {}

  // ── Core Request ──────────────────────────────────────────────────

  protected async request<T>(
    path: string,
    method: HttpMethod = 'GET',
    body?: unknown,
    query: Record<string, string | number | boolean | undefined> = {}
  ): Promise<T> {
    const url = new URL(`${this.baseUrl}/${path}`, window.location.origin);

    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined) url.searchParams.set(k, String(v));
    }

    const headers: Record<string, string> = { ...this.headers };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    const res = await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (!res.ok) {
      const data = await this.parseErrorBody(res);
      console.error(`${res.status} ${res.statusText}:`, data);
      throw new APIError({ statusCode: res.status, data });
    }

    return this.parseResponse<T>(res);
  }

  // ── Response Parsing ──────────────────────────────────────────────

  private async parseResponse<T>(res: Response): Promise<T> {
    if (res.status === 204) return undefined as T;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('application/json'))
      return (await res.json()) as T;
    if (this.matchesContentType(contentType, BINARY_CONTENT_TYPES))
      return (await res.arrayBuffer()) as T;
    if (this.matchesContentType(contentType, TEXT_CONTENT_TYPES))
      return (await res.text()) as T;
    if (contentType.includes('multipart/form-data'))
      return (await res.formData()) as T;

    return this.fallbackParse<T>(res);
  }

  private async parseErrorBody(res: Response): Promise<unknown> {
    if (res.status === 204) return undefined;

    const contentType = res.headers.get('Content-Type') ?? '';

    if (contentType.includes('json') || contentType.includes('+json')) {
      try {
        return await res.json();
      } catch {
        /* not valid JSON — fall through */
      }
    }

    const text = await res.text().catch(() => '');
    if (!text) return { message: res.statusText };

    try {
      return JSON.parse(text);
    } catch {
      if (
        contentType.includes('text/html') ||
        text.trimStart().startsWith('<')
      ) {
        console.error(
          `[HTTP ${res.status}] Received HTML error response from ${res.url}`
        );
        return { message: res.statusText };
      }
      return { message: text };
    }
  }

  private async fallbackParse<T>(res: Response): Promise<T> {
    try {
      return (await res.json()) as T;
    } catch {
      return (await res.text()) as T;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  private matchesContentType(contentType: string, patterns: string[]): boolean {
    return patterns.some((p) => contentType.includes(p));
  }
}
```

### `src/lib/constants/env.ts`

IMPORTANT: All env vars use `import.meta.env.VITE_*` — NEVER `process.env`.

```ts
export const ENV = {
  API_BASE_URL: import.meta.env.VITE_API_BASE_URL as string | undefined,
  IS_DEV: import.meta.env.DEV,
  IS_PROD: import.meta.env.PROD,
} as const;

export const getApiBaseUrl = (): string => {
  if (!ENV.API_BASE_URL) throw new Error('VITE_API_BASE_URL is not set');
  return ENV.API_BASE_URL;
};
```

### `src/lib/constants/index.ts`

```ts
export { API_ROUTES, PAGE_ROUTES } from './routes';
export { ENV } from './env';
```

### `src/lib/constants/routes.ts`

```ts
export const PAGE_ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  DASHBOARD: '/dashboard',
} as const;

export const API_ROUTES = {
  HEALTH: '/api/health',
} as const;
```

### `src/lib/errors/index.ts`

```ts
export { APIError } from './api-error';
export { logError } from './error-log-handler';
```

### `src/lib/errors/api-error.ts`

```ts
const isRecord = (x: unknown): x is Record<string, unknown> =>
  typeof x === 'object' && x !== null;

function safeStringify(x: unknown): string {
  try {
    return JSON.stringify(x);
  } catch {
    return '[unserializable]';
  }
}

function extractMessage(data: unknown): string {
  if (typeof data === 'string') {
    const trimmed = data.trim();
    if (trimmed) return trimmed;
  }

  if (data instanceof Error) return data.message;

  if (isRecord(data)) {
    for (const key of ['message', 'error'] as const) {
      const val = data[key];
      if (typeof val === 'string') {
        const trimmed = val.trim();
        if (trimmed) return trimmed;
      }
    }

    return safeStringify(data);
  }

  return String(data);
}

export interface ApiErrorResponse {
  statusCode?: number;
  data?: unknown;
}

export class APIError extends Error {
  public readonly name = 'APIError' as const;
  public readonly statusCode: number;
  public readonly data: unknown;

  constructor({ statusCode = 500, data }: ApiErrorResponse = {}) {
    const message = extractMessage(data);
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);

    this.statusCode = statusCode;
    this.data = data;

    if (Error.captureStackTrace) Error.captureStackTrace(this, APIError);
  }
}
```

### `src/lib/errors/error-log-handler.ts`

```ts
import { APIError } from './api-error';

export const logError = (label: string, error: unknown): void => {
  if (error instanceof APIError) {
    console.error(`${label}:`, {
      message: error.message,
      statusCode: error.statusCode,
      data: error.data,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  if (error instanceof Error) {
    console.error(`${label}:`, {
      message: error.message,
      timestamp: new Date().toISOString(),
    });
    return;
  }

  console.error(`${label}:`, {
    message: String(error),
    timestamp: new Date().toISOString(),
  });
};
```

### `src/lib/utils/index.ts`

```ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function mergeHandlers<Args extends readonly unknown[]>(
  ...handlers: (((...args: Args) => void) | undefined)[]
): (...args: Args) => void {
  return (...args: Args) => {
    handlers.forEach((fn) => fn?.(...args));
  };
}
```

---

## Scaffold Steps

### 1. Create directory and write all files

Create the target directory, then write all Part B and Part C files verbatim. Write `package.json` using the generated template (copy scripts/deps from template, replace name).

### 2. Update project name and branding

- `package.json`: set `"name"` to the project name (lowercase kebab-case)
- `index.html`: update `<title>` to the project name
- `src/components/layout/navbar.tsx`: replace `templateCentral` with the project name
- `src/components/layout/site-footer.tsx`: replace `'Built with templateCentral'` default with project-appropriate text
- `src/pages/home.tsx`: replace `"Vite + React Template"` heading with the project name

### 3. Copy `.env.example` to `.env`

```bash
cp .env.example .env
```

### 4. Initialize git and install dependencies

```bash
git init
pnpm install
```

`pnpm install` automatically runs `prepare: husky`, activating pre-commit and pre-push hooks. Verify installation completed without errors.

### 5. Install shadcn components

```bash
npx shadcn@latest add accordion avatar button card checkbox dialog dropdown-menu form input label select separator skeleton sonner tabs textarea
```

After shadcn installs, write the custom UI components verbatim (they are NOT managed by shadcn CLI):
- `src/components/ui/button-group.tsx`
- `src/components/ui/field.tsx`
- `src/components/ui/input-group.tsx`

### 6. Verification gate

Do NOT generate `AGENTS.md` until ALL of these pass:

```bash
pnpm build        # zero errors
pnpm check        # format + lint + typecheck — zero errors
pnpm test         # all tests pass
```

If any check fails, diagnose and fix before proceeding.

### 7. Generate `AGENTS.md`

Only after the verification gate passes. Line 1 must be the templateCentral marker comment:

```markdown
<!-- templateCentral: vite-react@1.0.0 -->
# <Project Name>

## Identity
- **Stack**: Vite 8, React 19, TypeScript, shadcn/ui, Tailwind CSS 4, React Router 7, TanStack React Query 5, React Hook Form + Zod, AuthProvider
- **Scaffolded from**: templateCentral vite-react-scaffold skill
- **Created**: <date>
- **Type**: Client-side SPA (no SSR, no API route handlers)

## Architecture Decisions
- Routes defined in `src/router.tsx`, not by filesystem convention
- Auth via `AuthProvider` context + `ProtectedRoute` guard; dev bypass when `ENV.IS_DEV`
- Feature modules under `src/features/<name>/`
- Barrel exports (`index.ts`) for all shared folders
- shadcn/ui primitives in `src/components/ui/` (managed by CLI, `components.json` with `rsc: false`)
- Reusable composed widgets in `src/components/widgets/`
- Env vars via `import.meta.env.VITE_*`, centralized in `src/lib/constants/env.ts`

## Key Conventions
- Named exports only (default exports allowed in tooling configs: `vite.config.ts`, `eslint.config.mjs`)
- `function` declarations for components; `const` arrows for hooks/utilities
- kebab-case filenames, PascalCase exports
- Static data in `constants.ts`, never inline in components
- Pages are thin — compose from `features/` and `components/`
- **Env**: `VITE_*` is shipped to the browser — never API keys, tokens, or secrets (use server-side or proxy for those)

## Commands
- `pnpm dev` — development server
- `pnpm build` — production build (`tsc -b && vite build`)
- `pnpm test` — run tests
- `pnpm check` — format + lint + typecheck

## Code Quality

Every agent writing or modifying code must follow these before marking a task done:

- **YAGNI** — Write only what the current task requires. No speculative helpers, abstractions, or files.
- **DRY** — Don't duplicate logic; extract at the second repetition. Don't extract from a single callsite.
- **SRP** — One responsibility per file and function. Pages compose; features fetch; components render. Never mix.
- **SoC** — UI from data-fetching, validation from business logic, env config from components — keep them separate.
- **No premature abstractions** — Wait for the third callsite before extracting a shared helper.
- **No dead code** — No commented-out blocks, unused imports, unused variables, or TODO stubs.
- **No tech debt shortcuts** — No `// fix later`, `// temp`, or workarounds that degrade the codebase.
- **Validate at every boundary** — Form inputs, API responses, env vars: always validate with Zod. Never trust external data.
- **Fail loudly** — No empty catch blocks. Surface errors to the user or log with context; never swallow silently.
- **Least privilege** — Request only the data the view needs. Strip unused fields from API responses before storing.
- **No secrets in code** — No tokens, passwords, or keys in `VITE_*` or any client file. Use server-side or proxy.
- **Secrets in production**: Backend secrets must use a secrets manager appropriate to your cloud platform. Never put backend secrets in `VITE_*` env vars or any client-side code.

## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

Update Identity with actual project name and creation date. Add any user-specified customizations under "Project-Specific Notes".

### 7b. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean (`pnpm build && pnpm check`)
2. `shared-test-agent` — verify all scaffold tests pass (`pnpm test`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions
4. `shared-review-agent` — run the first full code review; writes `.claude/review-baseline.md` so future reviews only check files changed since this point

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

**If any agent reports failures:** Stop immediately — do NOT run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

### 7c. Install Claude Code plugins

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

### 8. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code.

Write a short `CLAUDE.md` referencing `AGENTS.md` for full detail. Include:
- **Build & Dev**: `pnpm dev`, `pnpm build`, `pnpm test`, `pnpm lint`, `pnpm format`, `pnpm check` (format + lint + typecheck)
- **templateCentral skills**: `vite-react-scaffold` (done), `vite-react-code-standards`, `vite-react-add-page`, `vite-react-add-feature`, `vite-react-add-component`, `vite-react-add-form`, `vite-react-add-auth`, `vite-react-add-integration`, `vite-react-add-test`
- **Workflow**: simple/medium → templateCentral skills; complex → Superpowers — root `AGENTS.md`
- NEVER put secrets in `CLAUDE.md`

### 9. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append Option A or Option B from "Scaffold: optional Task Management" in repository root `AGENTS.md`. If no, skip.

### 10. Optional: Remove example code

Once the project is verified and the user confirms it runs, optionally remove example code:

- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/pages/dashboard.tsx`
- Update `src/pages/index.ts` if needed

Or invoke the `shared-remove-example` skill.

---

## Rules

- Always update `package.json` name before installing dependencies
- Always copy `.env.example` to `.env` before first run — NEVER commit `.env` or paste secrets into `AGENTS.md` / `CLAUDE.md`
- Always update `index.html` title — it is the browser tab name (NEVER skip)
- Routes are defined in `src/router.tsx`, not by filesystem convention
- NEVER use `process.env` — all env access goes through `import.meta.env.VITE_*` in `src/lib/constants/env.ts`
- Verify `pnpm build`, `pnpm typecheck`, and `pnpm test` all pass before generating `AGENTS.md`
- Remove example code only after the user confirms the project runs
- NEVER copy `node_modules/` or `dist/` when scaffolding
- NEVER consider scaffolding complete without a project `AGENTS.md` — verify it exists before handing off
