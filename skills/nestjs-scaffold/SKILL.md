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

pnpm add -D @eslint/js @nestjs/cli @nestjs/testing @types/node \
  @vitest/coverage-v8 eslint eslint-config-prettier eslint-plugin-prettier \
  globals husky pino-pretty prettier ts-node typescript typescript-eslint vitest
```

Then initialize husky:

```bash
git init
pnpm install   # activates husky via prepare script
```

> **NestJS 11 + Fastify v5**: `@nestjs/platform-fastify ≥11.1.19` is required — earlier 11.x releases shipped Fastify v4 (EOL). The floor is documented in `.claude/rules/nestjs.md`; ensure your installed version meets it.

### Directory Structure

```
<project-name>/
├── Dockerfile                          [verbatim — Part B]
├── docker-entrypoint.sh                [verbatim — Part B]
├── .dockerignore                       [verbatim — Part B]
├── .gitignore                          [verbatim — Part B]
├── .npmrc                              [verbatim — Part B]
├── .env.example                        [verbatim — Part B]
├── .prettierrc                         [verbatim — Part B]
├── eslint.config.mjs                   [verbatim — Part B]
├── nest-cli.json                       [verbatim — Part B]
├── vitest.config.ts                    [verbatim — Part B]
├── vitest.config.e2e.ts                [verbatim — Part B]
├── tsconfig.json                       [verbatim — Part B]
├── tsconfig.build.json                 [verbatim — Part B]
├── .husky/
│   ├── pre-commit                      [verbatim — Part B]
│   └── pre-push                        [verbatim — Part B]
├── package.json                        [generate]
├── pnpm-workspace.yaml                 [verbatim — Part B]
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
    └── modules/
        ├── base.controller.spec.ts     [verbatim — Part C]
        └── example.controller.spec.ts  [verbatim — Part C]
```

### Generation Conventions

**`package.json`** — Generate with the project name substituted into `"name"`. Include these exact scripts:

```json
{
  "scripts": {
    "build": "nest build",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "format:check": "prettier --check \"src/**/*.ts\" \"test/**/*.ts\"",
    "start": "node dist/main.js",
    "start:dev": "nest start --watch",
    "start:debug": "nest start --debug --watch",
    "lint": "eslint \"{src,test}/**/*.ts\" --fix",
    "lint:check": "eslint \"{src,test}/**/*.ts\"",
    "typecheck": "tsc --noEmit",
    "check": "pnpm run format:check && pnpm run lint:check && pnpm run typecheck",
    "test": "vitest run --passWithNoTests",
    "test:watch": "vitest",
    "test:ci": "vitest run --passWithNoTests",
    "test:e2e": "vitest run --config vitest.config.e2e.ts --passWithNoTests",
    "test:coverage": "vitest run --coverage"
  }
}
```

No version pins on deps — pnpm resolves latest compatible.

**Engines field to include in package.json** (use the Node version from `.claude/rules/nestjs.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```

**`README.md`** — Generate a brief project README: project name as heading, one-line description, stack badge line (NestJS, Fastify, TypeScript, Zod), and quick-start commands (`pnpm install`, `pnpm start:dev`, `pnpm build`, `pnpm test`).

**`AGENTS.md`** — Generated only after the verification gate passes (Step 5). Write `<!-- templateCentral: nestjs@1.0.0 -->` on line 1. See Step 6 for full template.

---


## Part B — Verbatim Config Files

Load config file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/nestjs-scaffold/config-files.md"
```
Generate each file exactly as shown.

## Part C — Verbatim Source Files

Load source file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/nestjs-scaffold/source-files.md"
```
Generate each file exactly as shown.
