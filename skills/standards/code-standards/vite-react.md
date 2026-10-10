<!-- ref: standards/code-standards/vite-react.md
     loaded-by: standards/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Vite + React

### File Naming

All files use **kebab-case**. No exceptions (unlike Next.js, Vite has no special file conventions).

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
| `export function Foo() {}` | Default — most components |
| `export const Foo = memo(function Foo() {})` | Components needing memoization (`import { memo } from 'react'` — this scaffold uses named React imports, there is no default `React` import anywhere) |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

- Keep components thin — delegate logic to hooks/services.
- Extract when there's a second consumer — don't prematurely extract.
- Add shadcn/ui primitives via the CLI (`npx shadcn@latest add <name>`) — NEVER install `@radix-ui/*` manually or recreate primitives.
- Prefer composition (children) over boolean flag props for variants.

Stack-specific component library:

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

Centralized in `src/lib/constants/env.ts` — read that file for the authoritative shape of `ENV` and `getApiBaseUrl()`. It is not restated here: a second copy drifts from the real one the moment a key is added.

- Every `import.meta.env.VITE_*` read goes in that file and nowhere else — NEVER `import.meta.env` inline in a component or service, and NEVER `process.env` (it does not exist in the browser).
- Use `getApiBaseUrl()` in services — NEVER `ENV.API_BASE_URL ?? ''`, which turns a missing-config error into a silent request to the wrong origin.
- Call `getApiBaseUrl()` **inside** each request function, never at module top level — it throws when the var is unset, and a module-scope throw aborts bundle evaluation before `createRoot()` runs, producing a blank page no ErrorBoundary can catch.
- `ENV` and `getApiBaseUrl` are both re-exported from `@/lib/constants` — import from the barrel.
- NEVER put secrets in `VITE_*` — they are embedded in the client bundle.

### Testing

- **Vitest** — NEVER use Jest in Vite projects.
- **Testing Library** (`@testing-library/react`) for component tests.
- Co-locate tests next to source: `example-service.test.ts`, `example-card.test.tsx`.
- Globals enabled — `describe`, `it`, `expect` available without imports.

### Comments

- Follow the shared comment doctrine in `code-standards/comments.md` (why-not-what, no commented-out code, no change-narration).
- JSDoc on exported functions/components describes the contract (props, return, behavior) — not the implementation.
- The comment gate is seeded as a hard gate (`error`, not a warning) in `eslint.config.mjs`: `no-inline-comments: 'error'` (with an `ignorePattern` for `eslint-`/`@ts-`/`prettier-`/coverage directives) enforces own-line comments, and `sonarjs/no-commented-code: 'error'` blocks commented-out code. Directive hygiene is gated too: `linterOptions.reportUnusedDisableDirectives`/`reportUnusedInlineConfigs: 'error'`, `@eslint-community/eslint-comments` (`recommended` + `require-description`), and typescript-eslint's `ban-ts-comment` (via `recommended`) — every suppression must be scoped, used, and carry a `-- reason`. `sonarjs/todo-tag`/`fixme-tag` are downgraded to `warn` — TODO/FIXME with context is allowed. See `comments.md` → Enforcement.

### Static Analysis (`eslint-plugin-sonarjs`)

`eslint.config.mjs` extends `sonarjs.configs.recommended` (~230 of the plugin's 295 rules at the pinned 4.2.2, at `error`) covering bugs, code smells, test hygiene, and React/JSX rules (`jsx-no-leaked-render`, `no-uniq-key`, `prefer-read-only-props`). This is a client-only SPA, so the server-focused security rules (hardcoded secrets, weak crypto, insecure cookies/JWT) stay on but are inert — no server code exists here to trip them. `src/components/ui/**` (generated shadcn primitives) turns off `prefer-read-only-props`, and test files (`src/**/*.{test,spec}.{ts,tsx}`) turn off `no-hardcoded-secrets` / `no-clear-text-protocols` so fake fixtures don't false-positive.

### Security (Vite + React)

**Environment Variables**
- `VITE_*` is embedded in the client bundle — NEVER put API keys, tokens, or secrets there
- Proxy through the backend for APIs requiring auth

**Input Validation**
- Validate all form inputs with Zod via React Hook Form
- Validate API response shapes with Zod in the service layer, before the data reaches a component. Default to `.parse()` — the thrown `ZodError` propagates to React Query's `error` state and the global handlers, which is the behavior every service in this template relies on. Reach for `safeParse()` only where the call site genuinely handles the failure itself (logging field errors, throwing a domain `APIError`, falling back) — never as a way to ignore it

**Auth & Route Protection**
- Protected routes wrapped with `<ProtectedRoute />` in `src/router.tsx`
- NEVER store tokens in `localStorage` — use `httpOnly` cookies from the backend
- NEVER make authorization decisions in the SPA

**Least Privilege**
- NEVER store sensitive data in React state, URL params, or `sessionStorage`
- NEVER log tokens, credentials, or PII to the browser console