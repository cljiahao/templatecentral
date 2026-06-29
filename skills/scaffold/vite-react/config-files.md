<!-- ref: scaffold/vite-react/config-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Verbatim Config Files

### `package.json`

> Set `"name"` to the project name (kebab-case) before `pnpm install`. Dependency versions use caret floors aligned with `.claude/rules/vite-react.md` and the current stable; `pnpm install` resolves the newest compatible. shadcn/ui Radix primitives and `@hookform/resolvers` are intentionally omitted — they are added by `npx shadcn@latest add` (Step 4) and `npx shadcn@latest add form` respectively. `@testing-library/jest-dom` and `@testing-library/react` are included in devDependencies; only `@testing-library/user-event` is added later by `templatecentral:add (test)`. Run the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`) post-scaffold to freshen pins.
>
> **ESLint pinned at `^9`** — `eslint-plugin-react-hooks` 7.x peer-supports only `^9`; bumping to ESLint 10 breaks `pnpm install` under strict peer enforcement until the plugin ships ESLint 10 support. Do not upgrade eslint past `^9` without verifying `eslint-plugin-react-hooks` peer compatibility.

```json
{
  "name": "PROJECT_NAME_PLACEHOLDER",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "packageManager": "pnpm@11.5.2",
  "engines": {
    "node": ">=24"
  },
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest --run",
    "test:watch": "vitest",
    "test:ci": "vitest --run --coverage --reporter=dot",
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "format": "prettier --check .",
    "format:write": "prettier --write .",
    "check": "prettier --check . && eslint . && tsc --noEmit",
    "prepare": "lefthook install"
  },
  "dependencies": {
    "@radix-ui/react-slot": "^1.2.4",
    "@tanstack/react-query": "^5.101.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "lucide-react": "^1.17.0",
    "react": "^19.2.7",
    "react-dom": "^19.2.7",
    "react-hook-form": "^7.77.0",
    "react-router": "^8.0.1",
    "sonner": "^2.0.7",
    "tailwind-merge": "^3.6.0",
    "zod": "^4.4.3"
  },
  "devDependencies": {
    "@eslint/js": "^9.0.0",
    "@tailwindcss/postcss": "^4.3.0",
    "@tailwindcss/typography": "^0.5.19",
    "@testing-library/jest-dom": "^6.9.1",
    "@testing-library/react": "^16.3.2",
    "@types/node": "^25.9.1",
    "@types/react": "^19.2.0",
    "@types/react-dom": "^19.2.0",
    "@vitejs/plugin-react": "^6.0.2",
    "@vitest/coverage-v8": "^4.1.8",
    "eslint": "^9.0.0",
    "eslint-plugin-react-hooks": "^7.1.1",
    "globals": "^17.6.0",
    "lefthook": "^2.1.9",
    "jsdom": "^29.1.1",
    "prettier": "^3.8.3",
    "prettier-plugin-organize-imports": "^4.3.0",
    "prettier-plugin-tailwindcss": "^0.8.0",
    "tailwindcss": "^4.3.0",
    "tw-animate-css": "^1.4.0",
    "typescript": "^6.0.3",
    "typescript-eslint": "^8.60.1",
    "vite": "^8.0.16",
    "vitest": "^4.1.8"
  }
}
```

### `.prettierignore`

```
node_modules
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
ARG NGINX=nginx:1.30.2-alpine3.23
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
  exec sh -c 'corepack enable pnpm && exec pnpm "$@"' sh "$@"
# Default to npm
else
  exec npm "$@"
fi
```

### `.dockerignore`

```
# Version Control
.git
.gitignore
.gitattributes

# Dependencies (installed in container)
node_modules/
.pnpm-store/

# Vite build outputs & cache
dist/
build/
.vite/
vite.config.js.timestamp-*
vite.config.ts.timestamp-*

# Environment variables (security)
**/.env
**/.env.*
!**/.env.example

# Logs
*.log
logs/

# Testing & coverage
coverage/
.vitest/

# Editor / OS cruft
.vscode/
.idea/
*.swp
*.swo
.DS_Store
Thumbs.db

# TypeScript
*.tsbuildinfo

# Docker (don't copy into image)
.dockerignore
Dockerfile*
docker-compose*.yml
docker-compose*.yaml

# CI/CD & docs
.github/
README*.md
docs/

# Certificates & secrets
*.pem
*.key
*.crt
.secrets/
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
.env*
!.env.example

# IDE
.vscode/
.idea/

# typescript
*.tsbuildinfo
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
  lefthook: false      # git-hook installer; binary ships via optional deps — no build needed, but pnpm 11 still requires an explicit decision or it blocks `pnpm <script>` runs
# Add native build deps here if `pnpm install` reports ERR_PNPM_IGNORED_BUILDS, e.g.:
#   esbuild: true
#   sharp: true
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
  { ignores: ['dist', '.claude/**'] },
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
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "0" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    # CSP baseline — tighten after analytics/auth are wired. frame-ancestors replaces X-Frame-Options for CSP2+ browsers.
    add_header Content-Security-Policy "frame-ancestors 'none'; base-uri 'self'; object-src 'none'" always;

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
/// <reference types="vitest/config" />
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
    // Uncomment to proxy API calls to a backend during local dev:
    // proxy: {
    //   '/api': { target: 'http://localhost:8000', changeOrigin: true },
    // },
  },
  preview: {
    port: 3000,
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
    coverage: {
      provider: 'v8',
      reporter: ['text', 'cobertura'],
    },
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

---