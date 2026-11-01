<!-- ref: migrate/general/phase-4-upgrade.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Phase 0 of migrate/general/implementation.md routed here (user chose A); stack known from the AGENTS.md line-1 marker. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate — Phase 4 (harness seed / upgrade)

Phase 5 (health check + safe re-sync) is `phase-5-health-check.md`.

---

## Phase 4 — v4.0–v6.0 Upgrade (agent, autonomous after Phase 0 gate)

Run only when the user chose A in Phase 0. Never for unmarked projects.

**Step 4a: Read AGENTS.md and detect stack**

Read `AGENTS.md`; take `<stack>` from the line-1 marker.

**Step 4b: Back up and replace AGENTS.md**

Save the original first:
```bash
cp AGENTS.md AGENTS.md.bak
```

If the upgrade fails at any point, restore with `cp AGENTS.md.bak AGENTS.md`. For `nextjs`, replace `AGENTS.md` with exactly:

~~~markdown
<!-- templateCentral: nextjs@6.0.0 -->
# AGENTS.md — [Project Name]

> STOP — Next.js breaking changes: `cookies()`, `headers()`, `params`, `searchParams` are
> ALL async. `middleware.ts` is replaced by `proxy.ts`. Verify before writing route handlers.

## Stack
Next.js · App Router · TypeScript strict · shadcn/ui · TanStack Query
React Hook Form · Zod · Vitest · pnpm · Node
Stack versions: tracked in the templateCentral plugin's `.claude/rules/nextjs.md`

## Commands
```bash
pnpm dev          # dev server — http://localhost:3000
pnpm build        # production build
pnpm test         # run test suite
pnpm check        # format + lint + typecheck
```

## File Layout
src/app/                — app router (pages, layouts, route handlers)
src/app/api/            — API route handlers
src/features/<name>/    — feature modules: api/, components/, hooks/, types.ts
src/components/ui/      — shadcn primitives (CLI-managed, do not edit directly)
src/components/widgets/ — reusable composed components (project-owned)
proxy.ts + src/lib/auth.ts — auth layer
src/integrations/database/ — database layer (after `templatecentral:add (database)`)
src/lib/constants/env.ts — environment constants

## Skills

### Project skills — check here first
Skills in `.claude/skills/` are scoped to this project. Invoke with `/skill-name`.

| Skill | What it does |
|-------|-------------|
| `/next-verify` | typecheck + lint + test in one pass |
| `/next-migrate` | Drizzle push/migrate with safety gate |

### templateCentral plugin skills — framework-level operations
| Skill | When to use |
|-------|-------------|
| `templatecentral:add (auth)` | JWT/OAuth/session auth |
| `templatecentral:add (database)` | connect Drizzle/Kysely/Mongoose |
| `templatecentral:add (feature)` | full feature: page + API route + hooks; also the route for a reusable UI component |
| `templatecentral:add (endpoint)` | API route with auth guard |
| `templatecentral:migrate` | DB migrations or framework upgrades |
| `templatecentral:standards` | drift check, validation patterns |

## Rules (always)
- TypeScript strict — no `any`, no `@ts-ignore`
- All user input validated with Zod at every boundary
- DB writes via repository layer only
- `z.input<typeof Schema>` for form types; `z.infer` for post-parse output
- No secrets in `NEXT_PUBLIC_*` variables
- Comments explain *why*, not *what* — no commented-out code, no change-narration (`// was X, now Y`); own-line over trailing. See `templatecentral:standards (code-standards)`

(AGENTS.md tail — AI Harness / Skills Security / Git Workflow / Skill capture — is appended by harness-kit-finalize.md Step G; not embedded here to avoid duplication.)

## Project-Specific Notes
<!-- [[post-harness]] — reserved for trace capture and meta-harness integration (v5.0+) -->
~~~

For fastapi, nestjs and vite-react: keep the existing content and set line 1 to `<!-- templateCentral: <stack>@6.0.0 -->`. The marker must be final here: Step 4f hashes `AGENTS.md`, so a later edit leaves a stale `origin_hash`. Step G appends the `## AI Harness` tail; append nothing by hand.

Every stack's rules section must carry the comment doctrine; if absent, add: *"Comments explain why, not what — no commented-out code, no change-narration; own-line over trailing. See `templatecentral:standards (code-standards)`."* Do **not** overwrite an existing lint config; recommend the scaffold's comment rules from `<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs` or `<skill-dir>/../scaffold/fastapi/template/pyproject.toml` (TS: `no-inline-comments: 'error'`, `sonarjs/no-commented-code: 'error'`, `linterOptions.reportUnusedDisableDirectives` and `reportUnusedInlineConfigs` at `'error'`, `sonarjs/todo-tag`/`fixme-tag` as `warn`; FastAPI: Ruff `ERA`, `PGH003`, `PGH004`, `RUF100`, `TD005`).

**Step 4c: Create `CLAUDE.md`**

If `CLAUDE.md` does not exist, create it at the project root with exactly one line:

```
@AGENTS.md
```

If it exists, change nothing except: when the import is missing, append `@AGENTS.md` at the end (after a newline if the file lacks a final one) and tell the user. Claude Code reads `AGENTS.md` only through this import. Never rewrite any other line.

**Import-present rule (Phase 5 uses it too):** some line outside a code fence, trimmed of `\r` and spaces, equals `@AGENTS.md` or `@./AGENTS.md`.

This append runs before Step 4f hashes and Step 4f-1b snapshots `CLAUDE.md`, so both include the line.

**Step 4d: Seed the agent harness (shared kit)**

Execute the shared harness kit (loaded by the phase table in `implementation.md`) **in full**: a migrated project gets the **same** enforcement layer as a scaffolded one.

**Template files.** Every seeded harness file is a real file under `<skill-dir>/../scaffold/shared/`: `template/` (every stack), `template-ts/` (nestjs / nextjs / vite-react) or `template-py/` (fastapi), and `template-ci/github-ts/`, `template-ci/github-py/` or `template-ci/azure/` for the CI file. So are `settings.json` (`<skill-dir>/../scaffold/shared/template-settings-ts/` or `template-settings-py/`), `FUTURE.md`, `docs/CONSTITUTION.md`, `/skill-audit` (`<skill-dir>/../scaffold/shared/template-late/`) and the AGENTS.md tail (`template-tail/`); `<skill-dir>/../scaffold/shared/template.manifest` lists them all. Kit Step 0 (the scaffold's copy guard) does **not** run in a migration: for each file, absent from the project → copy that one file with `cp -p` so the exec bit survives (a source named `<name>.tmpl` is copied to `<name>`, so `SKILL.md.tmpl` becomes `SKILL.md`); present → diff and merge per the adoption rules below. A customized enforcement file (hook, gate script, verifier, pattern list) is never overwritten silently: show the diff, ask, overwrite only on approval, and move any project-specific rule to `.claude/hooks/local/` (kit Step A, "Project-local guards"). Never copy a whole tree over an existing project. The `TC_PART=ci` runs of the copy script are scaffold-only: they assume `TC_PART=base` made `lefthook.yml` and `.claude/ci-gates.sh`. In a migration, copy the host's CI file by hand from `template-ci/` under the same diff, ask and overwrite-on-approval rules.

Using the **detected stack's row** in the kit's delta table (TS stacks: `node`; FastAPI: `python3`), execute kit Steps **A through D**:
- **Step A** — `settings.json` from the template-settings tree (`permissions.deny` secret-*Read* block, `skillListingBudgetFraction`, 6 hook events).
- **Step B** — all **9** `.claude/hooks/` scripts (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`, `session-context`, `skill-usage-log`) and `.claude/comment-hygiene-patterns.txt` (read by the hook, lefthook and CI), then `chmod +x .claude/hooks/*.sh`.
- **Step B2** — git-hook layer (`lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`).
- **Step B3** — CI quality gates, by hand: `.claude/ci-gates.sh` plus the host's CI file (`.github/workflows/ci.yml` on GitHub, `azure-pipelines/templatecentral-gates.yml` on Azure DevOps — never both). The kit's Step B3 rules for existing Azure pipelines apply (skip, or add only the `deps` step).
- **Step B4** — harness integrity verifier (`.claude/verify-harness.sh`, `.claude/regen-harness.sh`); it MUST be seeded (Phase 5d and pre-push call it).
- **Step B5** — the `/skill-audit` project skill, from `template-late/`.
- **Steps C, D** — `FUTURE.md`, `docs/CONSTITUTION.md` from `template-late/` (set `__TC_PROJECT_TITLE__` to the project name).

The scripts do not depend on the plugin, so the harness keeps enforcing if the plugin is removed.

**Adoption (merge, never clobber):** if the project runs another git-hook manager, wire the Step B2 commands (secret scan, commit-msg, pre-push verify) into it instead of adding lefthook, and record the choice in AGENTS.md. Existing pipelines include the Step B3 gates template rather than gaining a second pipeline. Merge the kit's entries into any existing `.claude/settings.json`, `lefthook.yml`, `.github/workflows/ci.yml` or `.gitleaks.toml`; warn on conflicts. In `settings.json`, a hook entry for a `.claude/hooks/` script with an array-valued `command` (pre-6.0.0, never ran) or no `${CLAUDE_PROJECT_DIR}` prefix is **replaced** by the kit's exec-form entry, not kept alongside it; a leftover `PostToolUseFailure` → `post-tool-failure.sh` entry is removed **and** `.claude/hooks/post-tool-failure.sh` is deleted (with any `harness.json` entry): it is no longer seeded.

**Step 4d-1: Convert seeded skills to directory form**

For each flat file `.claude/skills/<name>.md` found in the project, convert it to directory form:

```bash
# For each flat .claude/skills/<name>.md:
mkdir -p .claude/skills/<name>
cp .claude/skills/<name>.md .claude/skills/<name>/SKILL.md
rm .claude/skills/<name>.md
```

Run this before Steps 4e and 4f. No documentation refresh is needed (the kit skips `.claude/`).

**Step 4e: Seed project skills**

Create the stack's verify skill if absent. A project skill is a **directory** with `SKILL.md`; a flat `.claude/skills/<name>.md` is silently ignored. Run `mkdir -p .claude/skills/<stack>-verify` first, then write the skill file:

| Stack | Skill file | Command |
|-------|-----------|---------|
| nextjs | `.claude/skills/next-verify/SKILL.md` | `pnpm check && pnpm test` |
| nestjs | `.claude/skills/nest-verify/SKILL.md` | `pnpm check && pnpm test` |
| vite-react | `.claude/skills/vite-verify/SKILL.md` | `pnpm check && pnpm test` |
| fastapi | `.claude/skills/api-verify/SKILL.md` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` |

Template for TypeScript stacks (replace `<stack>` and `<command>`):

Take `<stack>-verify` from the table (`next-verify`, `nest-verify`, `vite-verify`, `api-verify`), not from the stack id. The `name:` frontmatter must match the directory name exactly.

~~~markdown
---
name: <stack>-verify
description: Run typecheck, lint, and tests for this project in one pass
allowed-tools: Bash(pnpm *)
---

Run all quality checks in sequence:

```bash
<command>
```

Report failures with the exact error output. Fix before proceeding.
~~~

For nextjs only, also create `.claude/skills/next-migrate/SKILL.md` (`mkdir -p` first) if absent:
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

**Step 4f: Create `.claude/harness.json`**

Execute kit **Step E**: it hashes every seeded file and writes the manifest. Include only files actually created or merged.

**Step 4f-1b: Seed the base snapshot**

Execute kit **Step E2**: it snapshots every seeded file into `.claude/.harness-base/`, the 3-way-merge base for Phase 5d. Commit it; `protect-files.sh` guards it.

**Step 4f-1c: Generate per-folder documentation**

Execute kit **Step E3** over the full adopted project tree: it follows `documentation-kit.md` (loaded by the phase table in `implementation.md`) and writes or refreshes each folder's `README.md`.

**Step 4f-2: Create `.agents` symlink**

If `.agents` does not exist, create the cross-vendor symlink:

```bash
ln -s .claude .agents
```

**Never commit the symlink**: add `.agents` to `.gitignore` (it is recreated per machine). A tracked symlink breaks Windows CI agents.

**Step 4f-3: Finish the AGENTS.md tail and re-baseline**

Execute kit **Step G** up to its post-scaffold utilities list: append the AGENTS.md tail (here the script is `<skill-dir>/../scaffold/shared/tc-copy.sh`; use that path in the kit's `TC_PART=tail` call), then the re-baseline block. Run Prettier (TS) only on files this phase wrote (`pnpm exec prettier --write AGENTS.md FUTURE.md docs/CONSTITUTION.md <each README.md written by Step E3>`), never `.`. Then wire the git hooks per kit Step B2's re-sync note (`pnpm exec lefthook install` / `lefthook install` in the venv). Once `verify-harness.sh` passes, delete `AGENTS.md.bak`.

**Step 4h: Print summary**

```
✓ Upgraded to templateCentral v6.0.

Changes made:
  AGENTS.md                      — Marker @6.0.0 + shared tail (nextjs: compressed template)
  CLAUDE.md                      — Created (@AGENTS.md one-liner)
  .claude/settings.json          — Created/merged: permissions.deny secret-read block,
                                   skillListingBudgetFraction, 6 hook events
                                   (exec form: "command" + "args")
  .claude/hooks/*.sh             — 9 scripts: protect-files, block-no-verify,
                                   user-prompt-guard, post-edit-typecheck,
                                   post-edit-comment-check, stop-checks,
                                   subagent-stop, session-context, skill-usage-log
  .claude/hooks/post-tool-failure.sh — Deleted if present (no longer seeded; its
                                   PostToolUseFailure settings entry removed)
  .claude/comment-hygiene-patterns.txt — canonical pattern list (hook + lefthook + CI)
  lefthook.yml                   — git-hook layer
  .lefthook/commit-msg.sh        — Conventional Commits gate
  .gitleaks.toml                 — secret-scan config
  .claude/ci-gates.sh            — PR merge gates (secrets, changelog, readme, comments, deps)
  .github/workflows/ci.yml       — CI quality gates (GitHub) — or
  azure-pipelines/templatecentral-gates.yml — steps template (Azure DevOps)
  .claude/verify-harness.sh      — harness integrity verifier
  .claude/regen-harness.sh       — human-run baseline re-bless (never agent-run)
  .claude/skills/skill-audit/    — repeat-workflow surfacing skill
  .claude/skills/<stack>-verify/SKILL.md   (converted to directory form if previously flat)
  (nextjs only) .claude/skills/next-migrate/SKILL.md   (converted to directory form if previously flat)
  .claude/harness.json           — Created with origin hashes for every file above
  .claude/.harness-base/         — as-seeded snapshot (3-way-merge base for Phase 5d)
  FUTURE.md                      — deferred-work log
  docs/CONSTITUTION.md           — project invariants
  README.md (per folder)         — created/refreshed via documentation-kit.md

Commit these files together — the harness only enforces as a complete set.
```
