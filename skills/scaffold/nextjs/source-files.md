<!-- ref: scaffold/nextjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nextjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes

The files are real files in `<skill-dir>/nextjs/template/` (`AGENTS.md` in `<skill-dir>/nextjs/template-agents/`, the verify skills at `.claude/skills/next-verify/SKILL.md` and `next-migrate/SKILL.md`, which kit Step E hashes), listed in `<skill-dir>/nextjs/template.manifest`; `tc-copy.sh` copies them, so do not re-type or modify them. Notes:

- `package.json` — Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/nextjs.md`. shadcn/ui Radix primitives and `@testing-library/*` are omitted; `npx shadcn@latest add` (Step 4) and `templatecentral:add (test)` add them. Freshen pins post-scaffold with the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`).
  - **ESLint 10**: `eslint-config-next`'s transitive `eslint-plugin-react` / `-import` / `-jsx-a11y` may still declare peers up to `^9`, so `pnpm install` can print an "unmet peer eslint" warning. It is non-fatal and their rules fire under ESLint 10. Do not add `--legacy-peer-deps` or peer overrides to silence it.
- `eslint.config.mjs` — `eslint-config-next` ships native flat configs; `FlatCompat` crashes with circular JSON, so import and spread the flat config objects. Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin "sonarjs"`). `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret), identical across the nextjs, nestjs and vite-react scaffolds, because its rule set changes across minor versions; bump all three together and re-verify. Scoping overrides and directive hygiene: `templatecentral:standards` code-standards notes and code-standards/comments.md.
- `scripts/check-route-logging.mjs` — App Router has no global request-logging layer, so this check fails `pnpm check` (local, lefthook, CI) if any API handler ships unwrapped. See `add/logging/nextjs.md`.
- `public/image_assets/logo.svg`, `default-square.svg` — **Required** placeholders: `BrandLogo` resolves the logo at build time and the Dockerfile copies `public/`, so the build fails without them. The user replaces them.
- `src/components/widgets/brand-text.tsx` — Replace `template` and `Central` with the project's brand name, split as fits, or one `<span>` if no gradient split is needed. The navbar renders this widget; update it, not the navbar.
- `src/app/api/health/route.ts` — The single health endpoint: the Dockerfile `HEALTHCHECK` probes `/api/health`, and it is the only path `templatecentral:add (auth)` puts in `PUBLIC_API_PREFIXES`. Do not add a sibling handler at `/api`, which would start returning 401 once auth lands.
- `src/lib/security/frame-protection.ts`, `src/proxy.ts` — The only place the CSP and anti-clickjacking headers are set; the proxy applies them to every response. With a valid `EMBED_PARENT_ORIGIN` only that portal may frame the app, otherwise framing is denied. `templatecentral:add (auth)` replaces the proxy with a route-protection one that keeps the `applyFrameProtection` call.

## Scaffold Steps

### 1. Create directory and files

Create the target directory, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (later steps run it with other `PART` values).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=nextjs TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`.

Then set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$`; if it does not, stop and ask the user for a valid name; do not edit anything. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the name, then check that nothing was left unsubstituted and that the file still parses (both commands must print nothing):

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

### 2. Update project name and branding

- In `src/app/layout.tsx`: update `metadata.title` and `metadata.description`
- In `src/app/(public)/page.tsx`: replace the `templateCentral` heading with the project name
- In `src/components/layout/site-footer.tsx`: update credit text
- In `src/components/widgets/brand-text.tsx`: update the text spans to the project name
- In `src/components/widgets/brand-logo.tsx`: the logo path stays `/image_assets/logo.svg`; the user replaces the SVG

### 3. Initialise git and install dependencies

Run kit Step **0** again as `TC_STACK=nextjs TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"` before the first install, so the `prepare` script wires the git hooks.

```bash
git init
pnpm install
```

### 4. Install shadcn components

`components.json` came with the template, so no interactive init is needed:

```bash
npx shadcn@latest add button card dialog field form input label select separator sonner tabs textarea
```

`field` is a registry component: the CLI owns it, never hand-write or hand-edit that file. `src/components/widgets/custom-form-field.tsx` imports from `@/components/ui/field`, so the `field` install must succeed before the verification gate. Current shadcn emits `import { cn } from 'cn'` in generated primitives; project code keeps `cn` from `@/lib/utils`. Do not hand-edit the generated imports.

### 5. Environment file

The user runs `cp .env.example .env.local` themselves; the seeded guards block agent access to a real env file, so never read or write one. Continue without it: the quality gates run on the defaults.

### 5b. Run verification gate before copying AGENTS.md

Do not copy AGENTS.md (Step 6) until this passes: prettier would reformat it.
```bash
pnpm format      # once before pnpm check: normalizes formatting drift from file creation
pnpm build       # production build — zero errors
pnpm check       # format + lint + typecheck — zero errors
pnpm test        # all tests pass
```

A module-not-found build error means a `pnpm add` is missing; a check failure means a generated file violates the eslint or prettier config.

### 6. Write project AGENTS.md

Run kit Step **0** again as `TC_STACK=nextjs TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`, then replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title (the Edit tool). The title must be one line: if it contains a newline, stop, ask for a one-line title and edit nothing. Check that no placeholder is left anywhere in the project; the command must print nothing:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

### 6b. Seed the agent harness (shared kit)

Load the rest of the kit, using the **nextjs** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`TC_PART=base`) already ran. Execute kit Steps **A through D** now (each `tc-copy.sh` run with `TC_STACK=nextjs`).

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Use the scaffold Step 1 answer on `CLAUDE.md`. If yes, create `CLAUDE.md` at the project root with exactly one line (kit Step E hashes it into `seeded_files`):

```
@AGENTS.md
```

### 7b. Optional: Task management

Use the scaffold Step 1 answer on task management. If yes, append the section to `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nextjs/template-tail/task-management.md" >> AGENTS.md
```

Then, whatever the answers above, run kit Steps **E through H**: the scaffold is not finished until Step H is done or skipped.

### 8. Remove example code (optional)

Use the scaffold Step 1 answer on removing example code. If yes, once the user confirms the project runs, load the cleanup utility with `cat "<skill-dir>/../cleanup/SKILL.md"`.
