<!-- ref: scaffold/nestjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes — config and source files

The config and source files are real files in `<skill-dir>/nestjs/template/` (`AGENTS.md` in `<skill-dir>/nestjs/template-agents/`, the verify skill at `.claude/skills/nest-verify/SKILL.md`, which kit Step E hashes), listed in `<skill-dir>/nestjs/template.manifest`. Steps 1, 4 and 6 copy them (stack, base and agents parts); do not re-type or modify them. Notes:

- `package.json` — Step 1 sets `"name"`. Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/nestjs.md`; `pnpm install` resolves the newest compatible; extra test tooling is omitted (`templatecentral:add (test)` adds it). Freshen pins post-scaffold with the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`). `engines.node` is the Node 26 floor from `versions.txt` (the template's choice; Nest 11 needs less). Nest and Swagger stay on major 11 so `nestjs-zod` runs inside its declared peers and `pnpm install` prints no peer warning (see `.claude/rules/nestjs.md`). The project is CommonJS (no `"type": "module"`), so no `.js` import suffixes are needed.
- `pnpm-workspace.yaml` — If `pnpm install` reports `ERR_PNPM_IGNORED_BUILDS` or rewrites it with unexpected entries, set each listed package under `allowBuilds` to `true` or `false` and re-run `pnpm install`.
- `eslint.config.mjs` — Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin "sonarjs"`). `eslint-plugin-sonarjs` is pinned exact (`4.2.2`, no caret) and identical across the nextjs, nestjs and vite-react scaffolds, because its rule set changes across minor versions. Bump all three together and re-verify. For `linterOptions` and the `eslint-comments` directive hygiene see `templatecentral:standards` code-standards/comments.md.
- `tsconfig.build.json` — `rootDir: "./src"` is build-only so `nest build` emits `dist/main.js` (what `start:prod` and the Dockerfile expect); do not move it into `tsconfig.json`, whose `rootDir: "./"` lets `tsc --noEmit` still typecheck `test/`. `incremental: false` here overrides the base `incremental: true`, which stays for the fast `tsc --noEmit` path: with it on, a second `nest build` with no source change emits an empty `dist/`, despite `deleteOutDir: true`.
- `src/config/env.config.ts` — A `templatecentral:add` capability that needs a new environment variable adds it to `envSchema` and reads it off `env`, not a bare `process.env.X!`, so boot fails loudly.
- `src/config/index.ts` — Files under `config/setups/` import from `'../env.config'`, never from this barrel: that would form an import cycle.

## Scaffold Steps

### 1. Create directory and files

Create the target directory, then load the kit index (its Step 0 names the copy script `<skill-dir>/shared/tc-copy.sh`).

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now as `TC_STACK=nestjs TC_PART=stack bash "<skill-dir>/shared/tc-copy.sh" "<target>"`. It copies `<skill-dir>/nestjs/template/` into the project root per the manifest, and writes nothing, ending with a `STOP:` line, when a path is in the way.

Then:
- Create two empty files: `src/common/types/.gitkeep` and `src/database/.gitkeep`
- Write `README.md` (brief intro and the `package.json` script commands)
- Set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$`; if it does not (a quote, backslash, space or newline would break the JSON), stop, ask the user for a valid name and edit nothing. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with it, then check that nothing is left unsubstituted and the file still parses:

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

Both must print nothing.

### 2. Update Project Settings

In `src/config/env.config.ts`, set the `PROJECT_NAME` default (`'My Project'`) to the project name and update the `PROJECT_DESCRIPTION` default. In `.env.example`, set `PROJECT_NAME=<project-name>`.

### 3. Create Environment File

The user runs this copy themselves (`cp .env.example .env`); the seeded guards block agent access to a real env file, so never read or write one. Continue without it: the quality gates run on the defaults.

### 4. Install Dependencies

Before the first install, run kit Step **0** again as `TC_STACK=nestjs TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `lefthook.yml` and the other harness files, so the `prepare` script wires the git hooks instead of writing a stub config.

```bash
git init
pnpm install
```

### 5. Verification Gate

**Generate AGENTS.md only after `pnpm format` has run and the four checks after it pass** (Prettier drift on newly generated files fails `pnpm check`):

```bash
pnpm format
pnpm build
node scripts/export-openapi.mjs > openapi.json   # the API contract the contract gate compares against (needs dist/)
pnpm check        # format + lint + typecheck
pnpm test
pnpm test:e2e
```

`pnpm test:e2e` is for local use; CI runs the single combined suite (`test:ci`). Fix any failure before proceeding. The gate does not open `/docs`: before handing off, also check that the Swagger docs render.

### 6. Write project AGENTS.md

Run kit Step **0** a third time as `TC_STACK=nestjs TC_PART=agents bash "<skill-dir>/shared/tc-copy.sh" "<target>"`: it copies `AGENTS.md` from `template-agents/` and refuses when one exists. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project title. The title must be one line: if it contains a newline, stop, ask for a one-line title and edit nothing. Then check that no placeholder is left:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

It must print nothing.

### 6b. Seed the agent harness (shared kit)

Load the rest of the shared harness kit using the **nestjs** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`TC_PART=base`) already ran. Execute kit Steps **A through D** now (each `tc-copy.sh` run with `TC_STACK=nestjs`).

### 7. `CLAUDE.md` and task management (optional)

Use the scaffold Step 1 answers. If `CLAUDE.md` is wanted, create `CLAUDE.md` at the project root with exactly one line (kit Step E hashes it into `seeded_files`):

```
@AGENTS.md
```

If task management is wanted, append its section to `AGENTS.md` (the command does not read the file):

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nestjs/template-tail/task-management.md" >> AGENTS.md
```

Then, whatever the answers above, run kit Steps **E through H**: the scaffold is not finished until Step H is done or skipped.

### 8. Remove example code (optional)

Use the scaffold Step 1 answer on removing example code. If yes, once the user confirms the project runs, load the cleanup utility with `cat "<skill-dir>/../cleanup/SKILL.md"`.
