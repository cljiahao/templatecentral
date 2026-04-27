---
name: code-standards
description: Use when writing or reviewing any code in a Vite + React project — covers file naming, export style, function vs const, component placement, and performance rules.
---

# Vite + React Code Standards

## File Naming

All files use **kebab-case** (lowercase, hyphen-separated). No exceptions — unlike Next.js, Vite has no special file naming conventions.

## Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `DashboardHeader`, `APIError` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `STATUS_OPTIONS`, `API_ROUTES` |
| Types/interfaces | PascalCase | `ProjectItem`, `ExampleCardProps` |

**Always use named exports.** Never use `export default` in application code. Exception: build/tooling config files (`vite.config.ts`, `eslint.config.mjs`) that require a default export.

## Function vs Const

| Pattern | When to use |
|---------|-------------|
| `export function Foo() {}` | Default — most components |
| `export const Foo = React.memo(function Foo() {})` | Components that need memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Components — use `function` declarations
```tsx
export function CustomCard({ children }: Props) {
  return <div className="rounded-lg border p-6">{children}</div>;
}
```

### Hooks, utilities, helpers — use `const` with arrow functions
```ts
const formatDate = (date: Date) => date.toISOString();

const useUploadForm = () => {
  // ...
};
```

## Component Best Practices

- **Keep components thin** — focus on rendering, delegate logic to hooks/services
- **Extract when there's a second consumer** — don't prematurely extract
- **Props: prefer composition over configuration** — split instead of adding boolean flags

### Component Library — Check Before Building

**Always check existing components before creating a new one.** The template ships with:

**shadcn/ui primitives** (`src/components/ui/`) — use directly, never recreate:
`accordion` · `avatar` · `button` · `card` · `checkbox` · `dialog` · `dropdown-menu` · `form` · `input` · `label` · `select` · `separator` · `skeleton` · `sonner` · `tabs` · `textarea`

**Extended UI** (`src/components/ui/`) — built on shadcn primitives:
- `button-group` — groups of related action buttons
- `field` — form field wrapper with label + error message
- `input-group` — input with prefix/suffix addon

**Widgets** (`src/components/widgets/`) — cross-feature, import via barrel:
- `brand-text` — branded typography element
- `custom-card` — card with preset layout
- `custom-dialog` — dialog with preset header/body layout
- `custom-form-field` — field + Zod validation display
- `link-list` — list of navigation/action links
- `media-card` — card with image + content
- `pill` — inline badge/tag

**Layout** (`src/components/layout/`) — app shell only:
`navbar` · `site-footer` · `providers` · `error-boundary`

To add a **new** shadcn primitive: `npx shadcn@latest add <name>` — NEVER install `@radix-ui/*` manually.

### Component Placement Decision Guide

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` (use `npx shadcn@latest add`) |
| App shell (nav, footer, layout) | `src/components/layout/` |

## Performance

**Do NOT use React.memo, useCallback, useMemo by default** — only after profiling confirms a problem. They must be used as a chain to be effective; any single one in isolation adds overhead for zero gain.

**Exception**: Context providers must stabilize objects/functions passed as `value` with `useMemo`/`useCallback`.

## Data & Rendering Separation

Static data → `constants.ts`. Components only render. Never inline arrays, config objects, or option lists in components.

## Environment Variables

Access environment variables via `import.meta.env.VITE_*`, centralized in `src/lib/constants/env.ts`:

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

- Use `getApiBaseUrl()` in services — it throws at startup if `VITE_API_BASE_URL` is missing, preventing silent runtime failures. NEVER use `ENV.API_BASE_URL ?? ''` as a fallback.
- NEVER put secrets (API keys, tokens) in `VITE_*` variables — they are embedded in the client bundle and visible to users
- Secrets belong on the backend; the SPA calls authenticated backend endpoints

## Utility Classes

The template provides these shared utilities:

- **`cn()`** — Class merging utility (`clsx` + `tailwind-merge`) in `src/lib/utils/index.ts`. Use for conditional class composition
- **`flex-center`** — Custom CSS utility (defined in `globals.css`) for `display: flex; align-items: center; justify-content: center`
- **`flex-between`** — Custom CSS utility for `display: flex; align-items: center; justify-content: space-between`
- **`max-w-site`** — Custom max-width utility for consistent page-width containers

## Barrel Exports

- Each feature and shared folder has an `index.ts` re-exporting the public API
- **Prefer**: `import { ProjectService } from '@/features/project'`
- **Avoid**: `import { ProjectService } from '@/features/project/api/project-service'`
- Direct imports are OK within the same feature

## Testing

- **Vitest** for all tests — NEVER use Jest in Vite projects
- **Testing Library** (`@testing-library/react`) for component tests
- Co-locate test files next to source: `example-service.test.ts`, `example-card.test.tsx`
- Use `.test.ts` suffix for unit tests, `.test.tsx` for component tests
- Globals enabled (`describe`, `it`, `expect` available without imports, but explicit imports are fine)

## Security

### Environment Variables
- `VITE_*` is embedded in the client bundle — NEVER put API keys, tokens, or secrets there
- For APIs requiring auth, proxy through the backend; the SPA never holds credentials

### Input Validation
- Validate all form inputs with Zod via React Hook Form — NEVER trust raw user input
- Validate API response shapes with Zod `safeParse()` before rendering
- For complex validation (file uploads, OWASP/CWE compliance): use `shared/validation-patterns/SKILL.md`

### Auth & Route Protection
- Protected routes wrapped with `<ProtectedRoute />` in `src/router.tsx` — NEVER rely on hiding nav links as security
- NEVER store tokens in `localStorage` — use `httpOnly` cookies from the backend
- NEVER make authorization decisions in the SPA — backend enforces all access control

### Least Privilege
- NEVER store sensitive data in React state, URL params, or `sessionStorage`
- NEVER log tokens, credentials, or PII to the browser console

