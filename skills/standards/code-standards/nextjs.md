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
| `export function Foo() {}` | Default — most components |
| `export const Foo = React.memo(function Foo() {})` | Components needing memoization |
| `const foo = () => {}` | Hooks, utilities, helpers, internal sub-components |

### Component Best Practices

- Keep components thin — delegate logic to hooks/services.
- Extract when there's a second consumer — don't prematurely extract.

**shadcn/ui primitives** (`src/components/ui/`) — add via CLI, never recreate:
`accordion` · `avatar` · `button` · `card` · `checkbox` · `dialog` · `dropdown-menu` · `form` · `input` · `label` · `select` · `separator` · `skeleton` · `sonner` · `tabs` · `textarea`

To add a shadcn primitive: `npx shadcn@latest add <name>` — NEVER install `@radix-ui/*` manually.

**Widgets** (`src/components/widgets/`) — available patterns, add only when the project uses them:
`brand-logo` · `brand-text` · `custom-card` · `custom-dialog` · `custom-form-field` · `link-list` · `media-card` · `pill` · `theme-toggle-button` · `floating-shape`

A project's widget index exports only what that project contains — NEVER pre-populate with unused widgets.

**Layout** (`src/components/layout/`): `navbar` · `site-footer` · `providers` · `theme-provider`

**Component Placement**

| Scenario | Location |
|----------|----------|
| Used by one feature | `src/features/<name>/components/` |
| Used by 2+ features | `src/components/widgets/` |
| Low-level primitive | `src/components/ui/` |
| App shell | `src/components/layout/` |

### Performance

Do NOT use `React.memo`, `useCallback`, `useMemo` by default — only after profiling. Exception: Context providers must stabilize `value` objects.

### Utility Classes

- `cn()` — `clsx` + `tailwind-merge` in `src/lib/utils/index.ts`
- `flex-center`, `flex-between`, `max-w-site` — custom CSS utilities in `globals.css`

### Barrel Exports

Each feature and shared folder has an `index.ts`. Prefer `import { X } from '@/features/project'` over deep imports.

### Backend Testing (mandatory for API code)

Vitest tests under `test/api/` mirroring `src/app/api/`. Run `pnpm test` and `pnpm build` before handoff.

### Security (Next.js)

**Environment Variables**
- Server secrets: `process.env.SECRET_NAME` — NEVER use `NEXT_PUBLIC_` prefix for secrets
- Client-safe values only in `NEXT_PUBLIC_*`

**Input Validation**
- Validate all request bodies with Zod `safeParse()` — return 400 on failure

**Auth & Route Protection** (after `nextjs-add-auth` is run)
- `proxy.ts`: NEVER return JSON for unauthorized requests — `new Response(null, { status: 401 })` only
- API routes independently call `auth.api.getSession()` — defense in depth

**Least Privilege**
- Return only the fields the client needs — NEVER send full DB records to the browser
- NEVER log tokens, passwords, or PII

**Request APIs (Next.js 16)**
- All Next.js Request APIs (`cookies()`, `headers()`, route `params`, and `searchParams`) return Promises in Next.js 16 — always `await` them. Sync access is a TypeScript error and runtime failure.