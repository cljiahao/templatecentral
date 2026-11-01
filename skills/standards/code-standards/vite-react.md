<!-- ref: standards/code-standards/vite-react.md
     loaded-by: standards/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Vite + React

### File Naming

All files use **kebab-case**, no exceptions.

### Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `DashboardHeader`, `APIError` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `STATUS_OPTIONS`, `API_ROUTES` |
| Types/interfaces | PascalCase | `ProjectItem`, `ExampleCardProps` |

**Always use named exports.** Never `export default` in application code. Exception: build/tooling config files.

### Function vs Const

| Pattern | When to use |
|---------|-------------|
| `export function Foo() {}` | Default |
| `export const Foo = memo(function Foo() {})` | Components needing memoization (`import { memo } from 'react'` — named React imports only) |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

- Keep components thin — delegate logic to hooks/services. Extract on the second consumer.
- Add shadcn/ui primitives via the CLI (`npx shadcn@latest add <name>`) ; do not install `@radix-ui/*` by hand or recreate primitives.
- Prefer composition (children) over boolean flag props for variants.

**Widgets** (`src/components/widgets/`): `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill`

**Layout** (`src/components/layout/`): `root-layout` · `navbar` · `site-footer` · `providers` · `error-boundary`

**Component Placement**

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` |
| App shell | `src/components/layout/` |

### Environment Variables

Centralized in `src/lib/constants/env.ts` — read it for the shape of `ENV` and `getApiBaseUrl()`.

- Every `import.meta.env.VITE_*` read lives there ; nothing else reads `import.meta.env`, and `process.env` does not exist in the browser.
- Use `getApiBaseUrl()` in services , not `ENV.API_BASE_URL ?? ''` (a silent request to the wrong origin).
- Call `getApiBaseUrl()` **inside** each request function, never at module top level — it throws when unset, and a module-scope throw blanks the page before any ErrorBoundary mounts.
- `ENV` and `getApiBaseUrl` are both re-exported from `@/lib/constants` — import from the barrel.
- Do not put secrets in `VITE_*`; they are embedded in the client bundle.

### Testing

- **Vitest** — not Jest; Vitest shares the Vite config.
- **Testing Library** (`@testing-library/react`) for component tests.
- Co-locate tests next to source: `example-service.test.ts`, `example-card.test.tsx`.
- Globals enabled — `describe`, `it`, `expect` available without imports.

### Comments

- Follow `code-standards/comments.md`.
- JSDoc on exported functions/components describes the contract (props, return, behavior) — not the implementation.
- `eslint.config.mjs` gates comments and directives at `error`; every suppression must be scoped, used, and carry a `-- reason` (rule list: `comments.md` → Enforcement).

### Static Analysis (`eslint-plugin-sonarjs`)

`eslint.config.mjs` extends `sonarjs.configs.recommended` at `error` (bugs, code smells, tests, React/JSX). Overrides: `src/components/ui/**` (generated shadcn) turns off `prefer-read-only-props`; test files (`src/**/*.{test,spec}.{ts,tsx}`) turn off `no-hardcoded-secrets` / `no-clear-text-protocols`.

### Security (Vite + React)

**Environment Variables**
- `VITE_*` is embedded in the client bundle, so API keys, tokens and secrets do not go there
- Proxy through the backend for APIs requiring auth

**Input Validation**
- Validate all form inputs with Zod via React Hook Form
- Validate API response shapes with Zod in the service layer, before the data reaches a component. Default to `.parse()` — the thrown `ZodError` propagates to React Query's `error` state and the global handlers, which is the behavior every service in this template relies on. Reach for `safeParse()` only where the call site genuinely handles the failure itself (logging field errors, throwing a domain `APIError`, falling back) — never as a way to ignore it

**Auth & Route Protection**
- Protected routes wrapped with `<ProtectedRoute />` in `src/router.tsx`
- Do not store tokens in `localStorage` (any script can read it); use `httpOnly` cookies from the backend
- Make authorization decisions on the backend, not in the SPA (the client can be modified)

**Least Privilege**
- Do not keep sensitive data in React state, URL params or `sessionStorage`
- Do not log tokens, credentials or PII to the browser console