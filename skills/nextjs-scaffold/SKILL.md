---
name: nextjs-scaffold
description: Use when scaffolding a new Next.js project following templateCentral conventions with App Router, shadcn/ui, TanStack Query, and Docker support (auth added separately via nextjs-add-auth)
version: "1.0.0"
---

# Scaffold Next.js Project

## Inputs

- **Project name** — kebab-case (e.g. `my-dashboard`). Ask if not provided.
- **Target directory** — defaults to `./<project-name>`. Confirm with user.

---

## Part A — Rules (generate these files fresh)

### Dependencies

Install these with `pnpm`. Claude resolves latest compatible versions at scaffold time. The `shared-update-agent` will freshen them immediately after scaffold.

**Runtime:**
`@hookform/resolvers`, `@tanstack/react-query`, `axios`, `class-variance-authority`, `clsx`, `lucide-react`, `motion`, `next`, `next-themes`, `pino`, `pino-http`, `react`, `react-dom`, `react-hook-form`, `sonner`, `tailwind-merge`, `zod`

**Dev:**
`@tailwindcss/postcss`, `@tailwindcss/typography`, `@types/node`, `@types/react`, `@types/react-dom`, `@vitest/coverage-v8`, `eslint`, `eslint-config-next`, `eslint-config-prettier`, `husky`, `pino-pretty`, `prettier`, `prettier-plugin-organize-imports`, `prettier-plugin-tailwindcss`, `tailwindcss`, `tw-animate-css`, `typescript`, `vitest`

**Scripts to include in package.json:**
```json
{
  "dev": "next dev",
  "build": "next build",
  "start": "next start",
  "prepare": "husky",
  "format": "prettier --write .",
  "format:check": "prettier --check .",
  "lint": "eslint .",
  "lint:fix": "eslint . --fix",
  "typecheck": "tsc --noEmit",
  "check": "pnpm format:check && pnpm lint && pnpm typecheck",
  "test": "vitest run",
  "test:watch": "vitest",
  "test:ci": "vitest run",
  "test:coverage": "vitest run --coverage"
}
```

**Engines field to include in package.json** (use the Node version from `.claude/rules/nextjs.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```

### Directory Structure

Generate this structure. Files marked `[generate]` are written by Claude from conventions. Files marked `[verbatim]` are written exactly from Part B or Part C below.

```
<project-name>/
├── Dockerfile                          [verbatim — Part B]
├── docker-entrypoint.sh                [verbatim — Part B]
├── .dockerignore                       [verbatim — Part B]
├── next.config.ts                      [verbatim — Part B]
├── tsconfig.json                       [verbatim — Part B]
├── components.json                     [verbatim — Part B]
├── .env.example                        [verbatim — Part B]
├── .env.local                          [copy from .env.example]
├── package.json                        [generate — use dep list above]
├── postcss.config.mjs                  [verbatim — Part B]
├── eslint.config.mjs                   [generate — extends next/core-web-vitals + prettier]
├── prettier.config.mjs                 [generate — with organize-imports + tailwindcss plugins]
├── vitest.config.ts                    [verbatim — Part B]
├── .gitignore                          [verbatim — Part B]
├── .npmrc                              [verbatim — Part B]
├── pnpm-workspace.yaml                 [verbatim — Part B]
├── .husky/
│   ├── pre-commit                      [generate — pnpm format:check && pnpm lint]
│   └── pre-push                        [generate — pnpm test]
├── public/
│   └── image_assets/
│       ├── logo.svg                    [generate — simple placeholder SVG]
│       └── default-square.svg          [generate — simple placeholder SVG]
├── test/
│   └── api/
│       └── health.test.ts              [verbatim — Part C]
└── src/
    ├── app/
    │   ├── globals.css                 [verbatim — Part C]
    │   ├── layout.tsx                  [verbatim — Part C]
    │   ├── (public)/
    │   │   ├── layout.tsx              [verbatim — Part C]
    │   │   └── page.tsx                [verbatim — Part C, update branding in Step 2]
    │   ├── dashboard/
    │   │   ├── layout.tsx              [verbatim — Part C]
    │   │   └── (overview)/
    │   │       └── page.tsx            [verbatim — Part C]
    │   ├── api/
    │   │   ├── route.ts                [verbatim — Part C]
    │   │   └── health/
    │   │       └── route.ts            [verbatim — Part C]
    ├── components/
    │   ├── layout/
    │   │   ├── navbar.tsx              [verbatim — Part C, update branding in Step 2]
    │   │   ├── site-footer.tsx         [verbatim — Part C, update branding in Step 2]
    │   │   ├── providers.tsx           [verbatim — Part C]
    │   │   ├── theme-provider.tsx      [verbatim — Part C]
    │   │   └── index.ts                [verbatim — Part C]
    │   ├── ui/
    │   │   └── field.tsx               [verbatim — Part C]
    │   └── widgets/
    │       ├── brand-logo.tsx          [verbatim — Part C]
    │       ├── brand-text.tsx          [verbatim — Part C]
    │       ├── custom-card.tsx         [verbatim — Part C]
    │       ├── custom-dialog.tsx       [verbatim — Part C]
    │       ├── custom-form-field.tsx   [verbatim — Part C]
    │       ├── floating-shape.tsx      [verbatim — Part C]
    │       ├── link-list.tsx           [verbatim — Part C]
    │       ├── media-card.tsx          [verbatim — Part C]
    │       ├── pill.tsx                [verbatim — Part C]
    │       ├── theme-toggle-button.tsx [verbatim — Part C]
    │       └── index.ts                [verbatim — Part C]
    ├── features/
    │   └── example/
    │       ├── index.ts                [verbatim — Part C]
    │       ├── types.ts                [verbatim — Part C]
    │       ├── constants.ts            [verbatim — Part C]
    │       ├── api/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   └── example-service.ts  [verbatim — Part C]
    │       ├── components/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   ├── example-card.tsx    [verbatim — Part C]
    │       │   └── example-list.tsx    [verbatim — Part C]
    │       ├── hooks/
    │       │   ├── index.ts            [verbatim — Part C]
    │       │   └── use-example-items.query.ts  [verbatim — Part C]
    │       └── schemas/
    │           └── index.ts            [verbatim — Part C]
    ├── hooks/
    │   └── index.ts                    [verbatim — Part C]
    ├── integrations/
    │   ├── factories.ts                [verbatim — Part C]
    │   ├── error.ts                    [verbatim — Part C]
    │   ├── schemas/
    │   │   └── .gitkeep                [verbatim — empty]
    │   ├── services/
    │   │   └── .gitkeep                [verbatim — empty]
    │   └── clients/
    │       └── base/
    │           ├── axios-client.ts     [verbatim — Part C]
    │           ├── fetch-client.ts     [verbatim — Part C]
    │           └── https-agent.ts      [verbatim — Part C]
    └── lib/
        ├── logger.ts                   [verbatim — Part C]
        ├── utils/
        │   ├── index.ts                [verbatim — Part C]
        │   ├── with-logging.ts         [verbatim — Part C]
        │   └── request-origin.ts       [verbatim — Part C]
        ├── constants/
        │   ├── index.ts                [verbatim — Part C]
        │   ├── env.ts                  [verbatim — Part C]
        │   └── routes.ts               [generate — PAGE_ROUTES (HOME:'/', DASHBOARD:'/dashboard') + API_ROUTES (ROOT:'/api', HEALTH:'/api/health'); nextjs-add-auth appends LOGIN:'/login' — do not add it here]
        └── errors/
            ├── index.ts                [verbatim — Part C]
            ├── handle-api-error.ts     [verbatim — Part C]
            └── error-log-handler.ts    [verbatim — Part C]
```

### Generation Conventions

- **Named exports only** — except Next.js special files (pages, layouts, route handlers which use `export default`)
- **`function` declarations** for components; **`const` arrows** for hooks and utilities
- **kebab-case** filenames, **PascalCase** named exports
- **`'use client'`** only when component needs interactivity (event handlers, hooks, browser APIs)
- **Server components by default** — no `'use client'` unless required
- **`@/*`** path alias maps to `./src/*`
- **Static data** in `constants.ts`, never inline in components
- **Pages compose** from features and widgets — no data fetching in page components
- **shadcn components**: use `npx shadcn@latest add <component>` — never install manually
- Install shadcn with `new-york` style and CSS variables
- **`src/app/globals.css`**: After Tailwind directives and CSS vars, append:
  ```css
  @keyframes float {
    0%, 100% { transform: translateY(0) rotate(0deg); }
    50% { transform: translateY(-15px) rotate(5deg); }
  }
  .animate-float {
    animation: float 10s ease-in-out infinite;
  }
  ```

---


## Part B — Verbatim Config Files

Load config file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/nextjs-scaffold/config-files.md"
```
Generate each file exactly as shown.

## Part C — Verbatim Source Files

Load source file templates:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/nextjs-scaffold/source-files.md"
```
Generate each file exactly as shown.
