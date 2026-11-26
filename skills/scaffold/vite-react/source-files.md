<!-- ref: scaffold/vite-react/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = vite-react. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes

The files are real files in `<skill-dir>/vite-react/template/` (`AGENTS.md` in `<skill-dir>/vite-react/template-agents/`, the verify skill at `.claude/skills/vite-verify/SKILL.md`, which kit Step E hashes), listed in `<skill-dir>/vite-react/template.manifest`; `tc-copy.sh` copies them, so do not re-type or modify them. Notes:

- `package.json` — Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/vite-react.md`. shadcn/ui Radix primitives and `@hookform/resolvers` are omitted; `npx shadcn@latest add` (Step 4) adds them, and `templatecentral:add (test)` adds `@testing-library/user-event`. Freshen pins post-scaffold with the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`).
  - **ESLint 10** (`eslint` + `@eslint/js` — move them together; `@eslint/js` peer-requires the matching `eslint` major). Its `js.configs.recommended` adds `no-unassigned-vars`, `no-useless-assignment` and `preserve-caught-error`: rethrowing inside `catch` must pass `{ cause: err }` (`throw new Error('msg', { cause: err })`).
- `eslint.config.mjs` — `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret), identical to the nextjs and nestjs scaffolds; its rule set changes across minor versions, so bump all three together and re-verify. Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin "sonarjs"`). Directive hygiene: `templatecentral:standards` code-standards/comments.md.
- `docker/15-frame-protection.envsh` — Sourced by the nginx entrypoint before envsubst renders `nginx.conf.template`. An undefined `${VAR}` stops nginx from starting, so it always exports both variables. Never `exit` from it.
- `src/lib/constants/env.ts` — All env vars use `import.meta.env.VITE_*`; `process.env` does not exist in the browser build.

---

## Scaffold Steps

### 1. Create directory and copy the files

Create the target directory, then load the kit index: its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh` (later steps run it with other `PART` values).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=vite-react TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`.

Then set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$`; if it does not, stop and ask the user for a valid name; do not edit anything. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with the name, then check that nothing was left unsubstituted and that the file still parses (both commands must print nothing):

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

### 2. Update project name and branding

- `index.html`: update `<title>` to the project title (the browser tab name)
- `src/components/layout/navbar.tsx`: replace `templateCentral` with the project title
- `src/components/layout/site-footer.tsx`: replace the `'Built with templateCentral'` default with the project description
- `src/pages/home.tsx`: replace the `"Vite + React Template"` heading with the project title

### 3. Initialize git and install dependencies

Run kit Step **0** again as `TC_STACK=vite-react TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"` before the first install, so the `prepare` script wires the git hooks.

```bash
git init
pnpm install
```

### 4. Install shadcn components

```bash
npx shadcn@latest add accordion avatar button button-group card checkbox dialog dropdown-menu field form input input-group label select separator skeleton sonner tabs textarea
```

`button-group`, `field` and `input-group` are registry components: the CLI owns them, so never hand-write or hand-edit those files. `src/components/widgets/custom-form-field.tsx` imports from `@/components/ui/field`, so the `field` install must succeed before the verification gate.

Current shadcn emits `import { cn } from 'cn'` (its own `cn` package, added to `dependencies`) in generated primitives; project code keeps using `cn` from `@/lib/utils`. Both merge Tailwind classes the same way: do not hand-edit the generated imports.

### 5. Environment file

The user runs `cp .env.example .env` themselves; the seeded guards block agent access to a real env file, so never read or write one. Continue without it: the quality gates run on the defaults.

### 5b. Verification gate

Generate `AGENTS.md` only after all of these pass. Prettier drift on newly generated files makes `pnpm check` fail, so run `pnpm format` once first:

```bash
pnpm format
pnpm build        # zero errors
pnpm check        # format + lint + typecheck — zero errors
pnpm test         # all tests pass
```

If any check fails, diagnose and fix before proceeding.

### 6. Write project `AGENTS.md`

Run kit Step **0** again as `TC_STACK=vite-react TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`, then replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title (the Edit tool). The title must be a single line: if it contains a newline, stop and ask the user for a one-line title, and edit nothing. Check that no placeholder is left anywhere in the project; the command must print nothing:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

### 6b. Seed the agent harness (shared kit)

Load the rest of the kit, using the **vite-react** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`TC_PART=base`) already ran. Execute kit Steps **A through D** now (each `tc-copy.sh` run with `TC_STACK=vite-react`).

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Use the scaffold Step 1 answer on `CLAUDE.md`. If yes, create `CLAUDE.md` at the project root with exactly one line (kit Step E hashes it into `seeded_files`):

```
@AGENTS.md
```

### 7b. Optional: Task management

Use the scaffold Step 1 answer on task management. If yes, append the section to `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/vite-react/template-tail/task-management.md" >> AGENTS.md
```

Then, whatever the answers above, run kit Steps **E through H**: the scaffold is not finished until Step H is done or skipped.

### 8. Optional: Remove example code

Use the scaffold Step 1 answer on removing example code. If yes, once the user confirms the project runs, load the cleanup utility with `cat "<skill-dir>/../cleanup/SKILL.md"`.
