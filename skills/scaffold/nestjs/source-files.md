<!-- ref: scaffold/nestjs/source-files.md
     loaded-by: scaffold/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->
## Template notes — config and source files

The config and source files are real files in `<skill-dir>/nestjs/template/` (`AGENTS.md` in `<skill-dir>/nestjs/template-agents/`), listed in `<skill-dir>/nestjs/template.manifest`. Steps 1, 4 and 6 copy them (stack, base and agents parts); do not re-type or modify them. Notes:

- `package.json` — Step 1 sets `"name"`. Versions are caret floors aligned with the plugin's `<skill-dir>/../../.claude/rules/nestjs.md`; `pnpm install` resolves the newest compatible; extra test tooling is omitted (`templatecentral:add (test)` adds it). Freshen pins post-scaffold with the review utility (update mode — `cat "<skill-dir>/../review/SKILL.md"`). `engines.node` (`^24.15.0 || >=26.0.0`) is the `@nestjs/schematics` 12 CLI floor for `nest generate`; the app runtime alone needs less (see `.claude/rules/nestjs.md`). The project stays CommonJS (no `"type": "module"`) and loads the ESM Nest 12 packages through `require(esm)`, so no `.js` import suffixes are needed. The unmet-peer **warning** for `nestjs-zod` is expected and safe to ignore.
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

`cp .env.example .env`

If a guard in your session blocks writing the env file, ask the user to run this copy and continue once it exists.

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
pnpm check        # format + lint + typecheck
pnpm test
pnpm test:e2e
```

If any command fails, fix it before proceeding.

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

Kit Step **0** (`TC_PART=base`) already ran. Execute kit Steps **A through D** now (settings.json with `TC_PART=settings`, the hook notes, then FUTURE.md, CONSTITUTION.md and the `/skill-audit` skill with `TC_PART=late`; each run of `tc-copy.sh` names `TC_STACK=nestjs`).

### 6c. Project skill file (`.claude/skills/`)

`.claude/skills/nest-verify/SKILL.md` was copied in Step 1 (Step E requires it). A project skill is a **directory** with `SKILL.md` as the entrypoint; flat `.claude/skills/<name>.md` files are silently ignored.

### 6d. Seed additional project skills

Use the scaffold Step 1 answer on extra project skills; ask the user only if scaffold Step 1 did not settle it. Common candidates: `nest-migrate` (DB migration with a safety gate, if Drizzle/Kysely is wired up) and `nest-module` (a new feature module: controller + service + DTO + test). For each workflow the user named, create a skill in `.claude/skills/` and add a row to the Skills table in `AGENTS.md`.

### 7. Generate `CLAUDE.md` (optional — Claude Code users only)

Use the scaffold Step 1 answer on `CLAUDE.md`; ask only if scaffold Step 1 did not settle it. Skip this step if the user does not use Claude Code — `AGENTS.md` is enough. Create `CLAUDE.md` at the project root with exactly one line:

```
@AGENTS.md
```

Do not duplicate commands or conventions here — everything lives in `AGENTS.md`. Step E hashes it into `seeded_files`.

### 7b. Optional: Task management

Use the scaffold Step 1 answer on task management; ask only if scaffold Step 1 did not settle it. If yes, append the task-management section to `AGENTS.md`:

```bash
printf '\n' >> AGENTS.md
cat "<skill-dir>/nestjs/template-tail/task-management.md" >> AGENTS.md
```

#### Finish the harness (required, whatever the answer above)

Execute kit Steps **E through H** using the **nestjs** row: harness.json (Step E, with the `nest-verify` hash), the base snapshot (E2), per-folder documentation (E3), the `.agents` symlink (F), the AGENTS.md tail and final format pass (G) and plugin install (H). The scaffold is not finished until Step H is done.

### 8. Remove Example Code (Optional)

Use the scaffold Step 1 answer on removing example code; ask only if scaffold Step 1 did not settle it. If yes, once the user confirms the project runs, use the cleanup utility (`cat "<skill-dir>/../cleanup/SKILL.md"`). NestJS-specific steps: delete `src/modules/example/` and `test/modules/example.controller.spec.ts`, and remove `ExampleModule` from `src/modules/index.ts` and the `imports` array in `src/app.module.ts`.

## Rules

- Global pipes and filters go in `app.module.ts`; auth guards at controller/route level (not global, so health checks remain unprotected)
- Verify the API starts and Swagger docs at `/docs` render before handing off to the user
- Do not commit real secrets or put JWT/DB credentials in `AGENTS.md` / `CLAUDE.md`; both are committed and read by every agent
- Leave `node_modules/`, `dist/` and `.env` out of the scaffold; they are installed, built or local
- The scaffold is complete only once the project `AGENTS.md` exists; check for it before handing off
- Keep the `base/` module (health check) and the `test/` directory structure; CI and the e2e tests depend on them
- Install packages with pnpm inside the project, not globally
