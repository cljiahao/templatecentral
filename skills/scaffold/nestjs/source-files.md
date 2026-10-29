<!-- ref: scaffold/nestjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Part B — Config and Source Files

The config and source files are real files in `<skill-dir>/nestjs/template/` (and `AGENTS.md` in `<skill-dir>/nestjs/template-agents/`), listed in `<skill-dir>/nestjs/template.manifest`. Steps 1 and 6 copy them; do not re-type or modify them. Notes:

- `package.json` — Step 1 sets `"name"`. Versions are caret floors aligned with `.claude/rules/nestjs.md`; the review utility (update mode) freshens them. The project stays CommonJS (no `"type": "module"`) and loads the ESM Nest 12 packages through `require(esm)`. The unmet-peer **warning** for `nestjs-zod` is expected and safe to ignore.
- `pnpm-workspace.yaml` — If `pnpm install` reports `ERR_PNPM_IGNORED_BUILDS` or rewrites `pnpm-workspace.yaml` with unexpected entries, set each listed package under `allowBuilds` to `true` or `false` as appropriate and re-run `pnpm install`.
- `eslint.config.mjs` — Every block touching sonarjs rules reuses the one `sonarjsPlugin` reference (a second `plugins: { sonarjs }` throws `Cannot redefine plugin`). `eslint-plugin-sonarjs` is pinned exact (`4.2.2`) and kept identical across the nextjs, nestjs and vite-react scaffolds, because its enabled-rule set changes across minor versions; bump all three together and re-verify.
- `tsconfig.build.json` — `rootDir: "./src"` is build-only so `nest build` emits `dist/main.js` (what `start:prod` and the Dockerfile expect). `incremental: false` is required: with it on, a second build with no source change emits an empty `dist/`.
- `src/config/env.config.ts` — A `templatecentral:add` capability that needs a new environment variable adds the field to `envSchema` and reads it off `env`, not a bare `process.env.X!`: validation here makes boot fail loudly.
- `src/config/index.ts` — Files under `config/setups/` import from `'../env.config'`, never from this barrel: that would form an import cycle.

## Scaffold Steps

### 1. Create directory and files

Create the target directory, then load the kit index; its Step 0 fence is the copy script.

```bash
cat "<skill-dir>/shared/harness-kit.md"
```

Run kit Step **0** now with `STACK=nestjs` in its fence and `PART=stack` (leave `CI=` empty). It copies `<skill-dir>/nestjs/template/` into the project root per `<skill-dir>/nestjs/template.manifest`, and writes nothing, ending with a `STOP:` line, when a path is in the way.

Then:
- Create two empty files: `src/common/types/.gitkeep` and `src/database/.gitkeep`
- Write `README.md` (a brief intro and the `package.json` script commands)
- Set the project name in `package.json`. The name must match `^[a-z0-9][a-z0-9-]*$`; if it does not (a quote, backslash, space or newline would break the JSON), stop, ask the user for a valid name and edit nothing. Otherwise, with the Edit tool, replace `__TC_PROJECT_NAME__` in `package.json` with it, then check that nothing is left unsubstituted and the file still parses:

```bash
grep -n '__TC_' package.json
node -e 'JSON.parse(require("fs").readFileSync("package.json","utf8"))'
```

Both must print nothing.

### 2. Update Project Settings

In `src/config/env.config.ts`, set the `PROJECT_NAME` default (`'My Project'`) to the project name and update the `PROJECT_DESCRIPTION` default. In `.env.example`, set `PROJECT_NAME=<project-name>`.

### 3. Create Environment File

Run `cp .env.example .env`.

### 4. Install Dependencies

Before the first install, run kit Step **0** again with `STACK=nestjs` in its fence and `PART=base`: it copies the harness files, `lefthook.yml` among them, so the `prepare` script wires the git hooks during the install instead of writing a stub config.

```bash
git init
pnpm install
```

### 5. Verification Gate

**Do NOT generate AGENTS.md until all four pass** (format first: Prettier drift on newly generated files fails `pnpm check`):

```bash
pnpm format
pnpm build
pnpm check        # format + lint + typecheck
pnpm test
pnpm test:e2e
```

If any command fails, fix it before proceeding.

### 6. Write project AGENTS.md

Run kit Step **0** a third time with `STACK=nestjs` in its fence and `PART=agents`: it copies `AGENTS.md` from `<skill-dir>/nestjs/template-agents/` and refuses when the project already holds one. Then, with the Edit tool, replace `__TC_PROJECT_TITLE__` in `AGENTS.md` with the project name. The title must be one line: if it contains a newline, stop, ask for a one-line title and edit nothing. Then check that no placeholder is left in the project:

```bash
grep -rn '__TC_' . --exclude-dir=node_modules --exclude-dir=.git
```

It must print nothing.

### 6b. Seed the agent harness (shared kit)

Load the rest of the shared harness kit (the index was loaded in Step 1) using the **nestjs** row of its delta table:

```bash
cat "<skill-dir>/shared/harness-kit-ts.md"
cat "<skill-dir>/shared/harness-kit-enforcement.md"
cat "<skill-dir>/shared/harness-kit-finalize.md"
```

Kit Step **0** (`PART=base`) already ran. Execute kit Steps **A through D** now (settings.json with `PART=settings`, the hook notes, then FUTURE.md, CONSTITUTION.md and the `/skill-audit` skill with `PART=late`, each run of the Step 0 script with `STACK=nestjs` in its fence). The verify skill (6c) is already in place, as Step E requires.

### 6c. Project skill file (`.claude/skills/`)

`.claude/skills/nest-verify/SKILL.md` was copied in Step 1. A project skill is a **directory** with `SKILL.md` as the entrypoint; flat `.claude/skills/<name>.md` files are silently ignored.

### 6d. Seed additional project skills

Ask whether any repeated workflow (such as `nest-migrate` or `nest-module`) should become a project skill; if so, create it in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

Now execute kit Steps **E through H** using the **nestjs** row: harness.json (E, with the `nest-verify` hash), base snapshot (E2), per-folder docs (E3), `.agents` symlink (F), AGENTS.md tail (G, with the nestjs `PostToolUse` line) and plugins (H).

### 7. Generate `CLAUDE.md` (optional — Claude Code only)

Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

Add a `CLAUDE.md` entry to `seeded_files` in `.claude/harness.json` with its SHA-256 hash (see harness-kit-finalize.md Step E).

### 7b. Optional: Task management

If the user wants structured task management, append the task-management section to `AGENTS.md`:

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nestjs/template-tail/task-management.md" >> AGENTS.md
```

### 8. Remove Example Code (Optional)

Once the user confirms the project runs, use the cleanup utility (`cat "<skill-dir>/../cleanup/SKILL.md"`). NestJS-specific steps: delete `src/modules/example/` and `test/modules/example.controller.spec.ts`, and remove `ExampleModule` from `src/modules/index.ts` and the `imports` array in `src/app.module.ts`.

## Rules

- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- NEVER commit real secrets or paste JWT/DB credentials into `AGENTS.md` / `CLAUDE.md`
- NEVER consider scaffolding complete without a project `AGENTS.md`
- NEVER remove the `base/` module (health check) or the `test/` directory structure
