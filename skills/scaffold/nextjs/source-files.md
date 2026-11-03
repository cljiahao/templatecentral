<!-- ref: scaffold/nextjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes — config files

The config files are real files in `<skill-dir>/nextjs/template/`, listed in `<skill-dir>/nextjs/template.manifest`. Step 1 below copies them; do not re-type them. Notes on the ones that need context:

- `package.json` — Step 1 replaces `__TC_PROJECT_NAME__` in `"name"` with the project name (kebab-case) before `pnpm install`. Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/nextjs.md`. shadcn/ui Radix primitives and `@testing-library/*` are omitted — `npx shadcn@latest add` (Step 4) and `templatecentral:add (test)` add them. Run the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`) post-scaffold to freshen pins.
  - **ESLint 10**: `eslint-config-next`'s transitive `eslint-plugin-react` / `eslint-plugin-import` / `eslint-plugin-jsx-a11y` may still declare peers up to `^9`, in which case `pnpm install` prints an "unmet peer eslint" warning. It is non-fatal and their rules fire under ESLint 10. Do not add `--legacy-peer-deps`/peer overrides to silence it.
- `scripts/check-route-logging.mjs` — App Router has no global request-logging layer, so this check fails `pnpm check` (local, lefthook, CI) if any API handler ships unwrapped. See `add/logging/nextjs.md`.
- `eslint.config.mjs` — `eslint-config-next` ships native flat configs; `FlatCompat` crashes with circular JSON. Import and spread the flat config objects. `pnpm check` runs `eslint .`, so this file must exist.
  - `sonarjs.configs.recommended` enables most of the plugin's rules at `error` — see `templatecentral:standards` code-standards notes for the two scoping overrides. Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin "sonarjs"`). `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret) and identical across the nextjs, nestjs and vite-react scaffolds, because its rule set changes across minor versions; bump all three together and re-verify. Directive hygiene (`linterOptions` + `@eslint-community/eslint-plugin-eslint-comments`) keeps every `eslint-disable` scoped, described, and actually needed — see `templatecentral:standards` code-standards/comments.md.

## Template notes — source files

The source files are real files in `<skill-dir>/nextjs/template/` (and `AGENTS.md` in `<skill-dir>/nextjs/template-agents/`), listed in `<skill-dir>/nextjs/template.manifest`. Steps 1 and 6 below copy them; do not re-type or modify them. Notes on the ones that need context:

- `public/image_assets/logo.svg` — **Required** placeholder logo: `BrandLogo` resolves it at build time and the Dockerfile copies `public/`, so the build fails without it. The user replaces it.
- `public/image_assets/default-square.svg` — **Required.** Default `src` for `FloatingShape`.
- `src/components/widgets/brand-text.tsx` — Replace `template` and `Central` with the project's brand name, split as fits, or one `<span>` if no gradient split is needed.
- `src/app/error.tsx` — Root error boundary for render errors no route-segment `error.tsx` catches.
- `src/app/api/health/route.ts` — The single health endpoint. `/api/health` is the path the Dockerfile `HEALTHCHECK` probes and the only one `templatecentral:add (auth)` puts in `PUBLIC_API_PREFIXES` — do not add a sibling handler at `/api`, which would start returning 401 the moment auth lands.
- `src/lib/security/frame-protection.ts` — The app's CSP and anti-clickjacking headers, applied by `src/proxy.ts`. When the platform injects `APPCENTRAL_PORTAL_ORIGIN` and it passes the origin check, only that portal may frame the app; otherwise framing is denied. The only place the CSP is set.
- `src/proxy.ts` — Applies those headers to every response. `templatecentral:add (auth)` replaces it with a route-protection proxy that keeps the `applyFrameProtection` call.
- `src/components/layout/navbar.tsx` — The wordmark comes from `BrandText`; update that widget, not this file.
- `src/components/layout/site-footer.tsx` — Pass `links` once the project has real footer pages.

---

## Scaffold Steps

### 1. Create directory and files

Create the target directory, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (Step B3 runs it with `TC_PART=ci`).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=nextjs TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/nextjs/template/` into the project root per `<skill-dir>/nextjs/template.manifest`: it writes nothing and ends with a `STOP:` line when a path is in the way.

Then set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$`; if it does not, stop and ask the user for a valid name; do not edit anything. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the name, then check that nothing was left unsubstituted and that the file still parses:

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

Before the first install, run kit Step **0** again as `TC_STACK=nextjs TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies the harness files, `lefthook.yml` among them, so the `prepare` script wires the git hooks.

```bash
git init
pnpm install
```

### 4. Install shadcn components

`components.json` was written in Step 1 — no interactive init needed. Add primitives directly:

```bash
npx shadcn@latest add button card dialog field form input label select separator sonner tabs textarea
```

`field` is a registry component — the CLI owns it, never hand-write or hand-edit that file. `src/components/widgets/custom-form-field.tsx` imports from `@/components/ui/field`, so the `field` install must succeed before the verification gate.

Current shadcn emits `import { cn } from 'cn'` in generated primitives; project code keeps `cn` from `@/lib/utils`. Do not hand-edit the generated imports.

### 5. Copy `.env.example` to `.env.local`

```bash
cp .env.example .env.local
```

If a guard in your session blocks writing the env file, ask the user to run this copy and continue once it exists.

**No interactive user** (headless run): skip the copy, continue, and note in your final report that the env file was not created. The quality gates run on the defaults.

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

Run kit Step **0** a third time as `TC_STACK=nextjs TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `AGENTS.md` from `<skill-dir>/nextjs/template-agents/` and refuses when one exists. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title. The title must be one line: if it contains a newline, stop, ask for a one-line title and edit nothing.

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

Kit Step **0** (`TC_PART=base`) already ran before the install. Execute kit Steps **A through D** now (`TC_PART=settings`, the hook notes, then `TC_PART=late`; each run uses `TC_STACK=nextjs`). The verify skills (6c) are already in place, which Step E requires.

### 6c. Project skill files (`.claude/skills/`)

`.claude/skills/next-migrate/SKILL.md` and `.claude/skills/next-verify/SKILL.md` were copied in Step 1 with the rest of the template. Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored.

### 6d. Seed additional project skills

Use the scaffold Step 1 answer on extra project skills; ask the user only if scaffold Step 1 did not settle it.

If they named workflows — or if the user ran any workflow more than once during the scaffold process — create skills in `.claude/skills/`. Common candidates for new projects:

| Workflow | Suggested skill name | Body |
|----------|---------------------|------|
| Start dev + open browser | `dev-start` | `pnpm dev` + describe URL |
| Reset DB to clean state | `db-reset` | `pnpm db:push --force-reset` (dev only) |
| Generate a new shadcn component | `add-component` | `pnpm dlx shadcn@latest add <name>` |

Each skill gets a SKILL.md with `name:` and `description:` frontmatter and a short body, capturing this-project specifics only.

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Use the scaffold Step 1 answer on `CLAUDE.md`; ask only if scaffold Step 1 did not settle it. Skip this step if the user does not use Claude Code — `AGENTS.md` is enough.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

Step E, in the finish step below, hashes it into `seeded_files`.

### 7b. Optional: Task management

Use the scaffold Step 1 answer on task management; ask only if scaffold Step 1 did not settle it. If yes, append the task-management section to the project's `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nextjs/template-tail/task-management.md" >> AGENTS.md
```

#### Finish the harness (required, whatever the answer above)

Execute kit Steps **E through H** using the **nextjs** row: harness.json (Step E, with the `next-verify` and `next-migrate` hash), the base snapshot (E2), per-folder documentation (E3), the `.agents` symlink (F), the AGENTS.md tail and final format pass (G) and plugin install (H). The scaffold is not finished until Step H is done or skipped.

### 8. Remove example code (optional)

Use the scaffold Step 1 answer on removing example code; ask only if scaffold Step 1 did not settle it. If yes, once the project is verified and the user confirms it runs, use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

It deletes `src/features/example/` and the `ExampleList` import in `src/app/dashboard/(overview)/page.tsx`.

---

## Rules

- Always update `package.json` name before `pnpm install` — affects Docker image names and lockfiles
- Always copy `.env.example` to `.env.local` before first run — never commit `.env.local`
- Never put secrets in `NEXT_PUBLIC_*` — exposed to every browser
- Never skip AGENTS.md — scaffolding is not complete without it
- Never copy `node_modules/` or `.next/` — generated at install/build time
- Remove example code after the user confirms the project runs — cleanup utility (`cat "<skill-dir>/../cleanup/SKILL.md"`)

---