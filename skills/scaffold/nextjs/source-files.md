<!-- ref: scaffold/nextjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
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

Create the target directory, then load the kit index: its Step 0 fence is the copy script, and it is the only copy of it.

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now with `STACK=nextjs` in its fence and `PART=stack` (leave `CI=` empty). It copies `<skill-dir>/nextjs/template/` into the project root per `<skill-dir>/nextjs/template.manifest`, with the kit's path rules and refusals: it writes nothing and ends with a `STOP:` line when a path is in the way. Then, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the project name (kebab-case), and check that nothing else was left unsubstituted:

```bash
grep -n '__TC_' package.json
```

It must print nothing.

### 2. Update project name and branding

- In `package.json`: set `"name"` to kebab-case project name
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

Run kit Step **0** a third time with `STACK=nextjs` in its fence and `PART=agents`: it copies `AGENTS.md` from `<skill-dir>/nextjs/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project name, and check that no placeholder is left anywhere in the project:

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

Kit Step **0** (`PART=base`) already ran before the install. Execute kit Steps **A through D** now (settings.json, hook scripts, FUTURE.md, CONSTITUTION.md). Then continue with step 6c below to create the verify skills. After step 6c, execute kit Steps **E through H** (harness.json requires the verify skills to exist first — Step E's prerequisites note explains this).



### 6c. Create project skill files (`.claude/skills/`)

Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`).

Run `mkdir -p .claude/skills/next-migrate .claude/skills/next-verify`, then create `.claude/skills/next-migrate/SKILL.md`:

```markdown
---
name: next-migrate
description: Run Drizzle push/migrate for this project with a safety gate.
allowed-tools: Bash(pnpm *)
---

Check that `src/integrations/database/` exists before running — database must be wired up first (`templatecentral:add (database)`).

- `pnpm db:push` — dev only, no migration files generated (schema overwrite)
- `pnpm db:migrate` — production-safe, generates migration files

Before running against production: verify `DATABASE_URL` in `.env.local` points to the correct instance.
```

Create `.claude/skills/next-verify/SKILL.md`:

```markdown
---
name: next-verify
description: Run typecheck + lint + test suite for this project in one pass.
allowed-tools: Bash(pnpm *)
---

Run `pnpm check && pnpm test` and report any failures.

- If `pnpm check` fails: fix TypeScript or lint errors before marking work done.
- If `pnpm test` fails: investigate root cause — do not skip or disable tests.
```

Now execute kit Steps **E through H** using the **nextjs** row: harness.json (Steps E — both `next-verify` and `next-migrate` skill hashes are included for nextjs), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail append (Step G — always appends the shared tail fragment with the nextjs `PostToolUse` line), and plugin install (Step H).

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

Ask whether the user wants structured task management for complex features. If yes, append this to the project's `AGENTS.md`:

```markdown
## Task Management

For complex tasks (3+ files, architectural decisions): `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan`. Skip for single-file edits or quick fixes.
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