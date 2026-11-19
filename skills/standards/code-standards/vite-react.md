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