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
| `export const Foo = React.memo(function Foo() {})` | Components needing memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

Same principles as Next.js. Stack-specific component library:

**Widgets** (`src/components/widgets/`): `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill`

**Layout** (`src/components/layout/`): `navbar` · `site-footer` · `providers` · `error-boundary`

**Component Placement**

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` |
| App shell | `src/components/layout/` |

### Environment Variables

Centralized in `src/lib/constants/env.ts`:

```ts
export const ENV = {
  API_BASE_URL: import.meta.env.VITE_API_BASE_URL as string | undefined,
  IS_DEV: import.meta.env.DEV,
} as const;

export const getApiBaseUrl = (): string => {
  if (!ENV.API_BASE_URL) throw new Error('VITE_API_BASE_URL is not set');
  return ENV.API_BASE_URL;
};
```

Use `getApiBaseUrl()` in services — NEVER use `ENV.API_BASE_URL ?? ''`. NEVER put secrets in `VITE_*`.

### Testing

- **Vitest** — NEVER use Jest in Vite projects.
- **Testing Library** (`@testing-library/react`) for component tests.
- Co-locate tests next to source: `example-service.test.ts`, `example-card.test.tsx`.
- Globals enabled — `describe`, `it`, `expect` available without imports.

### Security (Vite + React)

**Environment Variables**
- `VITE_*` is embedded in the client bundle — NEVER put API keys, tokens, or secrets there
- Proxy through the backend for APIs requiring auth

**Input Validation**
- Validate all form inputs with Zod via React Hook Form
- Validate API response shapes with Zod `safeParse()` before rendering

**Auth & Route Protection**
- Protected routes wrapped with `<ProtectedRoute />` in `src/router.tsx`
- NEVER store tokens in `localStorage` — use `httpOnly` cookies from the backend
- NEVER make authorization decisions in the SPA

**Least Privilege**
- NEVER store sensitive data in React state, URL params, or `sessionStorage`
- NEVER log tokens, credentials, or PII to the browser console
