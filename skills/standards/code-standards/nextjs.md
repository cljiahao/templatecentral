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

### Backend Testing (API code)

Test behaviour that can regress (`docs/CONSTITUTION.md` §4). Vitest tests under `test/api/` mirroring `src/app/api/`. Run `pnpm test` and `pnpm build` before handoff.

### Comments

- Follow `code-standards/comments.md`.
- JSDoc only on public APIs the signature does not explain: see `comments.md`.
- `eslint.config.mjs` gates comments and directives at `error`; every suppression must be scoped, used, and carry a `-- reason` (rule list: `comments.md` → Enforcement).

### Quality gate (SonarQube default "Sonar way")

Target: Sonar way on new code: 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%; cognitive complexity <= 15 per function. Local and CI mirror it:

- `eslint.config.mjs` runs `sonarjs.configs.recommended` at `error`, with `sonarjs/cognitive-complexity` at 15 and `no-warning-comments` banning `NOSONAR`. Overrides: `src/components/ui/**` (generated shadcn) turns off `prefer-read-only-props`; test files turn off `no-hardcoded-secrets` / `no-clear-text-protocols`. Fix findings; do not add disable comments or raise limits.
- CI runs `jscpd` with the seeded `.jscpd.json` (duplication <= 3% on production source only; Sonar also measures production code, and duplicate tests fall under the test-value rule), Vitest sharded (GitHub `SHARD_COUNT`, Azure `shardCount`; default 2) with coverage merged from shard blob reports, then `diff-cover --fail-under=80` on changed lines.
- There are no coverage exclusions: every changed line under `src` counts toward the 80% diff-coverage gate.

### Sonar way profile notes

Local checks match the default Sonar way profile. If your server flags a rule below, the fix is in the server's quality profile, not the code.

- S1774 bans every ternary and is not in the default profile; remove it on the server. Nested ternaries (S3358) are default and covered locally.
- S6480 (functions or `.bind()` in JSX props) was removed from the default profile.
- S7728 (`for…of` over `.forEach`) is being removed from Sonar way.
- The default profile changes with the server version, and findings from newly added rules are backdated onto existing code.
- Security hotspots need manual review on the server; no local check closes them.
- The server ignores the coverage and duplication conditions until the new code reaches 20 lines; local diff coverage has no such exemption.
- Sonar has two built-in gates; the local checks target plain "Sonar way", not "Sonar way for agentic AI".

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