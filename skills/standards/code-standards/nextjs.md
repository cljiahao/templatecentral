<!-- ref: standards/code-standards/nextjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Next.js

### File Naming

All files use **kebab-case**. Exceptions: Next.js special files (`layout.tsx`, `page.tsx`, `route.ts`, `not-found.tsx`, `loading.tsx`, `error.tsx`) and dynamic segments (`[id]`, `[...slug]`).

### Exports & Variable Naming

| Type | Convention | Example |
|------|-----------|---------|
| Components, classes | PascalCase | `UploadService`, `DashboardHeader` |
| Functions, hooks, variables | camelCase | `useUploadForm`, `projectFormSchema` |
| Constants | UPPER_SNAKE_CASE | `FRAMEWORK_OPTIONS` |
| Types/interfaces | PascalCase | `ProjectFormSchema`, `UploadMode` |

**Always use named exports.** Never `export default` except where required by Next.js.

### Function vs Const

| Pattern | When to use |
|---------|-------------|
| `export function Foo() {}` | Default |
| `export const Foo = React.memo(function Foo() {})` | Components needing memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

- Keep components thin — delegate logic to hooks/services. Extract on the second consumer.

**shadcn/ui primitives** (`src/components/ui/`) — add via CLI, never recreate:
`accordion` · `avatar` · `button` · `card` · `checkbox` · `dialog` · `dropdown-menu` · `form` · `input` · `label` · `select` · `separator` · `skeleton` · `sonner` · `tabs` · `textarea`

To add a shadcn primitive: `npx shadcn@latest add <name>` ; do not install `@radix-ui/*` by hand.

**Widgets** (`src/components/widgets/`) — available patterns, add only when the project uses them:
`brand-logo` · `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill` · `theme-toggle-button` · `floating-shape`

A project's widget index exports only what that project contains ; do not pre-populate it with unused widgets.

**Layout** (`src/components/layout/`): `navbar` · `site-footer` · `providers` · `theme-provider`

**Component Placement**

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` |
| App shell | `src/components/layout/` |

### Performance

Reach for `React.memo`, `useCallback` and `useMemo` only after profiling shows a need. Exception: Context providers must stabilize `value` objects.

### Utility Classes

- `cn()` — `clsx` + `tailwind-merge` in `src/lib/utils/index.ts`
- `flex-center`, `flex-between`, `max-w-site` — custom CSS utilities in `globals.css`

### Barrel Exports

Each feature and shared folder has an `index.ts`. Prefer `import { X } from '@/features/project'` over deep imports.

### Backend Testing (mandatory for API code)

Vitest tests under `test/api/` mirroring `src/app/api/`. Run `pnpm test` and `pnpm build` before handoff.

### Comments

- Follow `code-standards/comments.md`.
- JSDoc on exported functions/components describes the contract (props, return, behavior) — not the implementation.
- `eslint.config.mjs` gates comments and directives at `error`; every suppression must be scoped, used, and carry a `-- reason` (rule list: `comments.md` → Enforcement).

### Static Analysis (`eslint-plugin-sonarjs`)

`eslint.config.mjs` extends `sonarjs.configs.recommended` at `error` (bugs, security, code smells, tests, React/JSX). Two overrides: `src/components/ui/**` (generated shadcn) turns off `prefer-read-only-props`; test files (`test/**`, `**/*.test.{ts,tsx}`) turn off `no-hardcoded-secrets` / `no-clear-text-protocols`.

### Security (Next.js)

**Environment Variables**
- Server secrets: `process.env.SECRET_NAME`; a `NEXT_PUBLIC_` prefix ships the value to every browser, so never use it for secrets
- Client-safe values only in `NEXT_PUBLIC_*`

**Input Validation**
- Validate all request bodies with Zod `safeParse()` — return 400 on failure

**Auth & Route Protection** (after `templatecentral:add` (auth) is run)
- `proxy.ts` answers unauthorized requests with `new Response(null, { status: 401 })`, not JSON (a JSON body discloses information)
- API routes independently call `auth.api.getSession()` — defense in depth

**Least Privilege**
- Return only the fields the client needs, not full DB records
- Do not log tokens, passwords or PII

**Request APIs (Next.js 16)**
- `cookies()`, `headers()`, route `params` and `searchParams` return Promises — always `await` them.