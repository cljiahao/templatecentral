---
name: nextjs-code-standards
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

### Component Library — Check Before Building

**Always check existing components before creating a new one.** The template ships with:

**shadcn/ui primitives** (`src/components/ui/`) — use directly, never recreate:
`accordion` · `avatar` · `button` · `card` · `checkbox` · `dialog` · `dropdown-menu` · `form` · `input` · `label` · `select` · `separator` · `skeleton` · `sonner` · `tabs` · `textarea`

**Extended UI** (`src/components/ui/`) — built on shadcn primitives:
- `button-group` — groups of related action buttons
- `field` — form field wrapper with label + error message
- `input-group` — input with prefix/suffix addon
- `dropzone` (ui/shadcn-io/) — file upload zone

**Widgets** (`src/components/widgets/`) — cross-feature, import via barrel:
- `brand-logo` · `brand-text` — branded identity elements
- `custom-card` — card with preset layout
- `custom-dialog` — dialog with preset header/body layout
- `custom-form-field` — field + Zod validation display
- `link-list` — list of navigation/action links
- `media-card` — card with image + content
- `pill` — inline badge/tag
- `theme-toggle-button` · `floating-shape` — UI chrome

**Layout** (`src/components/layout/`) — app shell only:
`navbar` · `site-footer` · `providers` · `theme-provider`

To add a **new** shadcn primitive: `npx shadcn@latest add <name>` — NEVER install `@radix-ui/*` manually.

### Component Placement Decision Guide

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` (via shadcn CLI) |
| App shell (nav, footer, theme) | `src/components/layout/` |

## Performance

**Do NOT use React.memo, useCallback, useMemo by default** — only after profiling confirms a problem. They must be used as a chain to be effective; any single one in isolation adds overhead for zero gain.

**Exception**: Context providers must stabilize objects/functions passed as `value` with `useMemo`/`useCallback`.

## Data & Rendering Separation

Static data → `constants.ts`. Components only render. Never inline arrays, config objects, or option lists in components.

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
- Server secrets (`BETTER_AUTH_SECRET`, `DATABASE_URL`, API keys): `process.env.SECRET_NAME` — NEVER use `NEXT_PUBLIC_` prefix
- Client-safe values only in `NEXT_PUBLIC_*` — treat as fully public; NEVER put keys or tokens there
- Generate `BETTER_AUTH_SECRET` with `openssl rand -base64 32` — NEVER hardcode or commit it

### Input Validation
- Validate all request bodies with Zod `safeParse()` — return 400 on failure, NEVER trust raw `request.json()`
- Validate URL/search params before use — user-controlled input
- For complex validation patterns (file uploads, OWASP/CWE): use `shared/validation-patterns/SKILL.md`

### Auth & Route Protection
- These rules apply only after `nextjs-add-auth` has been run (i.e. `src/proxy.ts` and `src/auth.ts` exist).
- `proxy.ts`: NEVER return JSON for unauthorized requests — `new Response(null, { status: 401 })` only
- `proxy.ts` handles auth for pages; API routes independently call `auth()` from `@/auth` and return 401 — defense in depth
- NEVER expose internal IDs or resource identifiers to the client without authorization checks

### Least Privilege
- Return only the fields the client needs — NEVER send full DB records to the browser
- NEVER log tokens, passwords, or PII

