---
name: code-standards
description: Use when writing or reviewing any code in a Next.js project — covers file naming, export style, function vs const, component placement, and performance rules.
---

# Next.js Code Standards

## File Naming

All files use **kebab-case** (lowercase, hyphen-separated).

### Exceptions (Next.js special files)
- `layout.tsx`, `page.tsx`, `route.ts`, `not-found.tsx`, `loading.tsx`, `error.tsx`, `template.tsx`
- Dynamic route segments: `[id]`, `[...slug]`

## Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `UploadService`, `DashboardHeader` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `FRAMEWORK_OPTIONS`, `AVATAR_COLOR_MAP` |
| Types/interfaces | PascalCase | `ProjectFormSchema`, `UploadMode` |

**Always use named exports.** Never use `export default` except where required by Next.js (pages, layouts, config files).

## Function vs Const

| Pattern | When to use |
|---------|-------------|
| `export function Foo() {}` | Default — most components |
| `export const Foo = React.memo(function Foo() {})` | Components that need memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Components — use `function` declarations
```tsx
export function CustomCard({ children }: Props) {
  return <Card>{children}</Card>;
}
```

### Memoized components — use `const` with named function inside
```tsx
export const FrameworkSelector = React.memo(
  function FrameworkSelector({ ... }: Props) {
    return (...);
  }
);
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

### Component Placement Decision Guide

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` (via shadcn CLI) |
| App shell (nav, footer, theme) | `src/components/layout/` |

## Performance

**Do NOT use React.memo, useCallback, useMemo by default.** Only after profiling confirms a problem.

They form a **chain** — must be used together to be effective:
1. Parent stabilizes handlers with `useCallback`
2. Child wrapped with `React.memo`
3. Using any of them in isolation adds overhead for zero gain

**Exception**: Context providers that pass objects/functions as `value` should stabilize with `useMemo`/`useCallback` to prevent all consumers from re-rendering on every provider render.

## Data & Rendering Separation

- Static data belongs in `constants.ts`
- Components only handle rendering
- Static arrays, configuration objects, option lists → feature's `constants.ts`

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

## Backend testing (mandatory for API code)

- Vitest tests under `test/api/` (mirror `src/app/api/`) in the **same change** as new or changed route handlers — see `add-api-route`, `add-test`.
- No mandatory tests for React UI under `src/features/**` or pages.
- Run `pnpm test` (and `pnpm build` if types might drift) before handing off API work.

## Security

### Environment Variables
- Server-only secrets (`AUTH_SECRET`, `DATABASE_URL`, API keys) use `process.env.SECRET_NAME` — NEVER prefix with `NEXT_PUBLIC_`
- Client-safe values use `NEXT_PUBLIC_` prefix — assume anything with this prefix is visible to users; NEVER put API keys or tokens in `NEXT_PUBLIC_*`
- Generate `AUTH_SECRET` with `npx auth secret` — NEVER commit it or use a hardcoded placeholder in production

### Input Validation
- Validate all request bodies in API route handlers with Zod `safeParse()` — return 400 on failure, NEVER trust raw `request.json()`
- Validate URL params and search params before use — they are user-controlled input

### Auth & Route Protection
- `proxy.ts` uses `export const proxy = auth(...)` (Next.js 16 convention) to enforce auth for all routes not in `PUBLIC_PATHS` — NEVER duplicate auth checks in page components. Page components are protected by the proxy redirect; API routes should independently verify the session for defense-in-depth
- API routes that need auth should check `auth()` from `@/auth` and return 401 if no session
- NEVER expose user IDs or internal identifiers in client-side code without authorization checks

### Least Privilege
- API route handlers should only return the fields the client needs — NEVER send full database records to the browser
- Use `select` or explicit field picking when querying data
- NEVER log sensitive data (tokens, passwords, full request bodies with PII)

