---
name: vite-react-scaffold
description: Scaffold a new Vite + React SPA with React Router, TanStack Query, shadcn/ui, and Docker (auth via vite-react-add-auth)
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

Load config file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/vite-react-scaffold/config-files.md"
```
Generate each file exactly as shown.

## Part C — Verbatim Source Files

Load source file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/vite-react-scaffold/source-files.md"
```
Generate each file exactly as shown.
