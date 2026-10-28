<!-- ref: scaffold/nextjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Config Files

The config files are real files in `<skill-dir>/nextjs/template/`, listed in `<skill-dir>/nextjs/template.manifest`. Step 1 below copies them; do not re-type them. Notes on the ones that need context:

- `package.json` — Step 1 replaces `__TC_PROJECT_NAME__` in `"name"` with the project name (kebab-case) before `pnpm install`. Dependency versions use caret floors aligned with `.claude/rules/nextjs.md` and the current stable; `pnpm install` resolves the newest compatible. shadcn/ui Radix primitives and `@testing-library/*` are intentionally omitted — they are added by `npx shadcn@latest add` (Step 4) and `templatecentral:add (test)` respectively. Run the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`) post-scaffold to freshen pins.
  - **ESLint 10** (`^10.12.0`; engines `^20.19 || ^22.13 || >=24`, so Node ≥24 is fine). Direct plugins all peer-support `^10` (`eslint-config-next` `>=9`, `eslint-plugin-react-hooks` 7.1.1, `eslint-plugin-sonarjs`, `@eslint-community/eslint-plugin-eslint-comments`, `typescript-eslint` 8.x). `eslint-config-next` 16.4's transitive `eslint-plugin-react` 7.37 / `eslint-plugin-import` 2.32 / `eslint-plugin-jsx-a11y` 6.10 still declare peers only up to `^9`, so `pnpm install` prints an "unmet peer eslint" warning — non-fatal (pnpm does not enforce strict peers by default), and their rules (`react/jsx-key`, `jsx-a11y/alt-text`, `import/no-anonymous-default-export`, `@next/next/no-img-element`) were verified to fire normally under ESLint 10. Do not add `--legacy-peer-deps`/peer overrides to silence it; the warning clears once those plugins ship `^10` peers.
- `scripts/check-route-logging.mjs` — Next.js App Router has no global request-logging layer, so coverage can't be automatic like NestJS (pino-http) or FastAPI (ASGI middleware). This dependency-free check fails the build if any API handler ships unwrapped — wired into `pnpm check`, so it runs locally, in lefthook, and in CI. See `add/logging/nextjs.md`.
- `eslint.config.mjs` — Next.js 16 ships `eslint-config-next` as native flat configs — `FlatCompat` causes circular JSON crashes. Import the flat config objects directly and spread them. `pnpm check` runs `eslint .`, so this file must exist.
  - `sonarjs.configs.recommended` enables ~230 of the plugin's 295 rules at `error` (bugs, security, code smell, tests, React/JSX) — see `templatecentral:standards` code-standards notes for the two scoping overrides in the file. Mixing `sonarjs.configs.recommended` with a separate `plugins: { sonarjs }` block throws `Cannot redefine plugin "sonarjs"`; every block touching sonarjs rules must reuse the same `sonarjsPlugin` reference. `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret; peer `eslint ^8 || ^9 || ^10`) and kept identical across the nextjs, nestjs, and vite-react scaffolds — `configs.recommended`'s enabled-rule set and rule heuristics change across minor versions (4.1.0 enabled ~206 of 268; 4.2.x also skips low-entropy literals in `no-hardcoded-passwords`, which can turn an existing `eslint-disable` for it into an unused-directive error); bump all three together, deliberately, and re-verify — don't let `pnpm install` silently resolve a newer minor. Directive hygiene (`linterOptions` + `@eslint-community/eslint-plugin-eslint-comments`) keeps every `eslint-disable` scoped, described, and actually needed — see `templatecentral:standards` code-standards/comments.md.

## Part C — Source Files

The source files are real files in `<skill-dir>/nextjs/template/` (and `AGENTS.md` in `<skill-dir>/nextjs/template-agents/`), listed in `<skill-dir>/nextjs/template.manifest`. Steps 1 and 6 below copy them; do not re-type or modify them. Notes on the ones that need context:

- `public/image_assets/logo.svg` — **Required.** `BrandLogo` resolves this path at build time, and the Dockerfile copies `public/` into the runner stage — the build fails outright if `public/` does not exist. This is a placeholder; the user replaces it with their own logo.
- `public/image_assets/default-square.svg` — **Required.** Default `src` for `FloatingShape` — see the note above on why `public/` must exist.
- `src/components/widgets/brand-text.tsx` — After the copy, update the text content to match the actual project name. Replace `template` and `Central` with the project's brand name split appropriately, or simplify to a single `<span>` if no gradient split is needed.
- `src/app/error.tsx` — Root-level error boundary — catches any render-phase error not caught by a more specific route-segment `error.tsx` (see `templatecentral:add (page)` Step 4 for adding one scoped to a specific route).
- `src/app/api/health/route.ts` — The single health endpoint. `/api/health` is the path the Dockerfile `HEALTHCHECK` probes and the only one `templatecentral:add (auth)` puts in `PUBLIC_API_PREFIXES` — do not add a sibling handler at `/api`, which would start returning 401 the moment auth lands.
- `src/lib/security/frame-protection.ts` — The app's Content-Security-Policy and anti-clickjacking headers, applied at runtime by `src/proxy.ts`. When the platform injects `APPCENTRAL_PORTAL_ORIGIN` (e.g. `https://appcentral-uat.cpfnet.gov.sg`) and it passes the origin check, only that portal may frame the app. Otherwise framing is denied outright. This is the only place the CSP is set — `next.config.ts` `headers()` does not send one.
- `src/proxy.ts` — Sets the CSP and anti-clickjacking headers on every page and route response. `templatecentral:add (auth)` replaces this file with its route-protection proxy, which keeps the same `applyFrameProtection` call on every response it returns.
- `src/app/(public)/page.tsx` — Replace the `templateCentral` heading with the project name in Step 2.
- `src/components/layout/navbar.tsx` — The brand wordmark comes from `BrandText` — update that widget in Step 2, not this file.
- `src/components/layout/site-footer.tsx` — Update `creditText` default in Step 2. Pass `links` once the project has real footer pages.

---

## Scaffold Steps

### 1. Create directory and files

Create the target directory, then load the kit index: its Step 0 fence is the copy script (Step B3 runs it with `PART=ci`).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now with `STACK=nextjs` in its fence and `PART=stack` (leave `CI=` empty). It copies `<skill-dir>/nextjs/template/` into the project root per `<skill-dir>/nextjs/template.manifest`, with the kit's path rules and refusals: it writes nothing and ends with a `STOP:` line when a path is in the way.

Then set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$` (lowercase letters, digits and hyphens, starting with a letter or digit). If it does not (a quote, backslash, space or newline would break the JSON), stop and ask the user for a valid name; do not edit anything. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the name, then check that nothing was left unsubstituted and that the file still parses:

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

Both must print nothing.

### 2. Update project name and branding

- In `src/app/layout.tsx`: update `metadata.title` and `metadata.description`
- In `src/app/(public)/page.tsx`: replace the `templateCentral` heading with the project name
- In `src/components/layout/site-footer.tsx`: update credit text
- In `src/components/widgets/brand-text.tsx`: update the text spans to reflect the project name (the navbar renders this widget)
- In `src/components/widgets/brand-logo.tsx`: logo path stays as `/image_assets/logo.svg` — user replaces the SVG file with their own logo

### 3. Initialise git and install dependencies

Before the first install, run kit Step **0** again with `STACK=nextjs` in its fence and `PART=base`: it copies the harness files, `lefthook.yml` among them, so the `prepare` script wires the git hooks during the install instead of writing a stub config that Step 0 would then refuse to overwrite.

```bash
git init
pnpm install
```

`pnpm install` runs the `prepare` script, installing the lefthook git hooks.

### 4. Install shadcn components

`components.json` was written in Step 1 — no interactive init needed. Add primitives directly:

```bash
npx shadcn@latest add button card dialog field form input label select separator sonner tabs textarea
```

`field` is a registry component — the CLI owns it, never hand-write or hand-edit that file. `src/components/widgets/custom-form-field.tsx` imports from `@/components/ui/field`, so the `field` install must succeed before the verification gate.

shadcn ≥4.21 emits `import { cn } from 'cn'` (its own `cn` package, added to `dependencies`) in generated primitives; project code keeps using `cn` from `@/lib/utils`. Both merge Tailwind classes the same way — do not hand-edit the generated imports.

### 5. Copy `.env.example` to `.env.local`

```bash
cp .env.example .env.local
```

Never commit `.env.local`.

### 5b. Run verification gate before copying AGENTS.md

Do not copy AGENTS.md (Step 6) until this passes: prettier would reformat it.

```bash
pnpm format      # Run this once before pnpm check — normalizes any formatting drift from file creation
pnpm build       # production build — zero errors
pnpm check       # format + lint + typecheck — zero errors
pnpm test        # all tests pass
```

If build fails with module-not-found errors, a `pnpm add` is missing.
If check fails, a generated file violates the eslint or prettier config.

### 6. Write project AGENTS.md

Run kit Step **0** a third time with `STACK=nextjs` in its fence and `PART=agents`: it copies `AGENTS.md` from `<skill-dir>/nextjs/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project name. The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing.

Afterwards, check that no placeholder is left anywhere in the project:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

It must print nothing.

### 6b. Seed the agent harness (shared kit)

Load the rest of the shared harness kit (the index was loaded in Step 1) using the **nextjs** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`PART=base`) already ran before the install. Execute kit Steps **A through D** now (settings.json with `PART=settings`, the hook notes, then FUTURE.md, CONSTITUTION.md and the `/skill-audit` skill with `PART=late`, each run of the Step 0 script with `STACK=nextjs` in its fence). The verify skills (6c) are already in place, which Step E requires.

### 6c. Project skill files (`.claude/skills/`)

`.claude/skills/next-migrate/SKILL.md` and `.claude/skills/next-verify/SKILL.md` were copied in Step 1 with the rest of the template. Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Execute kit Steps **E through H** using the **nextjs** row: harness.json (Steps E — both `next-verify` and `next-migrate` skill hashes are included for nextjs), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail append (Step G — always appends the shared tail fragment with the nextjs `PostToolUse` line), and plugin install (Step H).

### 6d. Seed additional project skills

After all dispatch agents complete, ask the user: "Do you want to create project-scoped skills for any workflows you'll run regularly in this project?"

If yes — or if the user ran any workflow more than once during the scaffold process — create skills in `.claude/skills/`. Common candidates for new projects:

| Workflow | Suggested skill name | Body |
|----------|---------------------|------|
| Start dev + open browser | `dev-start` | `pnpm dev` + describe URL |
| Reset DB to clean state | `db-reset` | `pnpm db:push --force-reset` (dev only) |
| Generate a new shadcn component | `add-component` | `pnpm dlx shadcn@latest add <name>` |

Each skill gets a SKILL.md with `name:` and `description:` frontmatter and a short body. Skills capture this-project specifics — not generic advice that templateCentral already provides.

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This makes Claude Code automatically load `AGENTS.md` on every session without duplicating its content.

After creating it, add a `CLAUDE.md` entry to `seeded_files` in `.claude/harness.json` with its SHA-256 hash (see harness-kit-finalize.md Step E).

### 7b. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append the task-management section to the project's `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nextjs/template-tail/task-management.md" >> AGENTS.md
```

### 8. Remove example code (optional)

Once the project is verified and the user confirms it runs, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

Next.js-specific steps (the utility covers these):
- Delete `src/features/example/` directory
- Remove `ExampleList` import from `src/app/dashboard/(overview)/page.tsx`

The cleanup utility handles both steps automatically.

---

## Rules

- Always update `package.json` name before `pnpm install` — affects Docker image names and lockfiles
- Always copy `.env.example` to `.env.local` before first run — never commit `.env.local`
- Never put secrets in `NEXT_PUBLIC_*` — exposed to every browser
- Never skip AGENTS.md — scaffolding is not complete without it
- Never copy `node_modules/` or `.next/` — generated at install/build time
- Remove example code after user confirms the project runs — use the cleanup utility (`cat "<skill-dir>/../cleanup/SKILL.md"`) — handles both `src/features/example/` deletion and the `ExampleList` import in `src/app/dashboard/(overview)/page.tsx`

---