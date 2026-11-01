<!-- ref: scaffold/vite-react/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes — config files

The config files are real files in `<skill-dir>/vite-react/template/`, listed in `<skill-dir>/vite-react/template.manifest`. Step 1 below copies them; do not re-type them. Notes on the ones that need context:

- `package.json` — Step 1 replaces `__TC_PROJECT_NAME__` in `"name"` with the project name (kebab-case) before `pnpm install`. Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/vite-react.md`. shadcn/ui Radix primitives and `@hookform/resolvers` are omitted — `npx shadcn@latest add` (Step 4) and `npx shadcn@latest add form` add them; `templatecentral:add (test)` adds `@testing-library/user-event`. Run the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`) post-scaffold to freshen pins.
  - **ESLint 10** (`eslint ^10.12.0` + `@eslint/js ^10.0.1` — move them together; `@eslint/js` 10 peer-requires `eslint ^10`). ESLint 10's `js.configs.recommended` adds `no-unassigned-vars`, `no-useless-assignment`, and `preserve-caught-error` — rethrowing inside `catch` must pass `{ cause: err }` (`throw new Error('msg', { cause: err })`). Run the review utility (update mode) to move the whole lint toolchain forward as one unit.
- `eslint.config.mjs` — `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret), identical to the nextjs and nestjs scaffolds; its rule set changes across minor versions, so bump all three together and re-verify. Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin "sonarjs"`). Directive hygiene (`linterOptions` + `@eslint-community/eslint-plugin-eslint-comments`) keeps every `eslint-disable` scoped, described, and actually needed — see `templatecentral:standards` code-standards/comments.md.
- `docker/15-frame-protection.envsh` — Sourced by the nginx entrypoint before envsubst renders `nginx.conf.template`. An undefined `${VAR}` stops nginx from starting, so it always exports both variables. Never `exit` from it.
- `src/lib/constants/env.ts` — All env vars use `import.meta.env.VITE_*`; `process.env` does not exist in the browser build.

## Template notes — source files

The source files are real files in `<skill-dir>/vite-react/template/` (and `AGENTS.md` in `<skill-dir>/vite-react/template-agents/`), listed in `<skill-dir>/vite-react/template.manifest`. Steps 1 and 7 below copy them; do not re-type or modify them. Notes on the ones that need context:

- `src/features/example/schemas/index.ts` — Empty placeholder for Zod schemas added by `templatecentral:add` (feature).

---

## Scaffold Steps

### 1. Create directory and copy the files

Create the target directory, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (Step B3 runs it with `TC_PART=ci`).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=vite-react TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/vite-react/template/` into the project root per `<skill-dir>/vite-react/template.manifest`, with the kit's path rules and refusals: it writes nothing and ends with a `STOP:` line when a path is in the way.

Then set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$` (lowercase letters, digits and hyphens, starting with a letter or digit). If it does not (a quote, backslash, space or newline would break the JSON), stop and ask the user for a valid name; do not edit anything. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the name, then check that nothing was left unsubstituted and that the file still parses:

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

Both must print nothing.

### 2. Update project name and branding

- `index.html`: update `<title>` to the project name
- `src/components/layout/navbar.tsx`: replace `templateCentral` with the project name
- `src/components/layout/site-footer.tsx`: replace `'Built with templateCentral'` default with project-appropriate text
- `src/pages/home.tsx`: replace `"Vite + React Template"` heading with the project name

### 3. Copy `.env.example` to `.env`

```bash
cp .env.example .env
```

### 4. Initialize git and install dependencies

Before the first install, run kit Step **0** again as `TC_STACK=vite-react TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies the harness files, `lefthook.yml` among them, so the `prepare` script wires the git hooks during the install instead of writing a stub config that Step 0 would then refuse to overwrite.

```bash
git init
pnpm install
```

`pnpm install` runs the `prepare` script, installing the lefthook git hooks. Verify installation completed without errors.

### 5. Install shadcn components

```bash
npx shadcn@latest add accordion avatar button button-group card checkbox dialog dropdown-menu field form input input-group label select separator skeleton sonner tabs textarea
```

`button-group`, `field`, and `input-group` are registry components — the CLI owns them, so never hand-write or hand-edit those files. `src/components/widgets/custom-form-field.tsx` imports from `@/components/ui/field`, so the `field` install must succeed before the verification gate.

Current shadcn emits `import { cn } from 'cn'` (its own `cn` package, added to `dependencies`) in generated primitives; project code keeps using `cn` from `@/lib/utils`. Both merge Tailwind classes the same way — do not hand-edit the generated imports.

### 6. Verification gate

Generate `AGENTS.md` only after all of these pass. Prettier drift on newly generated files makes `pnpm check` fail until they are formatted, so run `pnpm format` once first:

```bash
pnpm format
pnpm build        # zero errors
pnpm check        # format + lint + typecheck — zero errors
pnpm test         # all tests pass
```

If any check fails, diagnose and fix before proceeding.

### 7. Write project `AGENTS.md`

Only after the verification gate passes. Run kit Step **0** a third time as `TC_STACK=vite-react TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `AGENTS.md` from `<skill-dir>/vite-react/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title. The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing.

Afterwards, check that no placeholder is left anywhere in the project:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

It must print nothing.

### 7b. Seed the agent harness (shared kit)

Load the rest of the shared harness kit (the index was loaded in Step 1) using the **vite-react** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`TC_PART=base`) already ran before the install. Execute kit Steps **A through D** now (settings.json with `TC_PART=settings`, the hook notes, then FUTURE.md, CONSTITUTION.md and the `/skill-audit` skill with `TC_PART=late`, each a run of `tc-copy.sh` with `TC_STACK=vite-react`). The verify skill (7c) is already in place, which Step E requires.

### 7c. Project skill files (`.claude/skills/`)

`.claude/skills/vite-verify/SKILL.md` was copied in Step 1 with the rest of the template. Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored.

### 7d. Seed additional project skills

Ask: "Do you have any repeated workflows that should be captured as project skills?" Common candidates:
- `vite-feature` — scaffold a new feature module (components + query hook + page)
- `vite-component` — scaffold a reusable widget component with props + story

If yes — create them in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

---

### 8. Generate `CLAUDE.md` (optional — Claude Code users only)

Skip if the user does not use Claude Code.

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

This imports `AGENTS.md` fully into every Claude Code session. Do not duplicate commands or conventions here — everything lives in `AGENTS.md`.

Step E hashes it into `seeded_files` (it runs next).

### 9. Optional: Task management

Ask whether the user wants structured task management for complex features. If yes, append the task-management section to the project's `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/vite-react/template-tail/task-management.md" >> AGENTS.md
```

If no, skip.

Then execute kit Steps **E through H** using the **vite-react** row: harness.json (Step E — includes the `vite-verify` skill hash), the base snapshot (Step E2), per-folder documentation (Step E3), `.agents` symlink (Step F), AGENTS.md tail append (Step G — always appends the shared tail fragment with the vite-react `PostToolUse` line), and plugin install (Step H).

### 10. Optional: Remove example code

Once the project is verified and the user confirms it runs, optionally remove example code:

- Delete `src/features/example/` directory
- Remove the `ExampleList` import and usage from `src/pages/dashboard.tsx`
- Update `src/pages/index.ts` if needed

Or use the cleanup utility — load it with: `cat "<skill-dir>/../cleanup/SKILL.md"`.

---

## Rules

- Always update `package.json` name before installing dependencies
- Copy `.env.example` to `.env` before the first run; do not commit `.env` or put secrets in `AGENTS.md` / `CLAUDE.md`
- Update the `index.html` title; it is the browser tab name
- Routes are defined in `src/router.tsx`, not by filesystem convention
- Read env only through `import.meta.env.VITE_*` in `src/lib/constants/env.ts`; `process.env` is undefined in the browser
- Verify `pnpm build`, `pnpm typecheck`, and `pnpm test` all pass before generating `AGENTS.md`
- Remove example code only after the user confirms the project runs
- Leave `node_modules/` and `dist/` out of the scaffold; they are installed or built
- The scaffold is complete only once the project `AGENTS.md` exists; check for it before handing off
