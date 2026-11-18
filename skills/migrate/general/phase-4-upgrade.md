<!-- ref: migrate/general/phase-4-upgrade.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Phase 0 of migrate/general/implementation.md routed here (user chose A); stack known from the AGENTS.md line-1 marker. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate — Phase 4 (harness seed / upgrade)

Phase 5 (health check + safe re-sync) is `phase-5-health-check.md`.

---

## Phase 4 — Upgrade to the current harness (agent, autonomous after Phase 0 gate)

Run when the user chose A in Phase 0, or full adoption in the Phase 2 gate (the marker is already written).

**Step 4a: Read AGENTS.md and detect stack**

Read `AGENTS.md`; take `<stack>` from the line-1 marker.

**Step 4b: Back up and replace AGENTS.md**

Save the original first:
```bash
cp AGENTS.md AGENTS.md.bak
```

If the upgrade fails at any point, restore with `cp AGENTS.md.bak AGENTS.md`. For `nextjs`, replace `AGENTS.md` with the scaffold's template, then set the title:

```bash
cp "<skill-dir>/../scaffold/nextjs/template-agents/AGENTS.md" AGENTS.md
```

With the Edit tool, replace `__TC_PROJECT_TITLE__` with the project title (one line). Then move any project-specific notes from `AGENTS.md.bak` under `## Project-Specific Notes`.

For fastapi, nestjs and vite-react: keep the existing content and set line 1 to `<!-- templateCentral: <stack>@6.0.0 -->`. The marker must be final here: Step 4f hashes `AGENTS.md`, so a later edit leaves a stale `origin_hash`. Step G writes the `## AI Harness` tail between its `templatecentral-tail` markers; write nothing of it by hand.

Every stack's rules section carries this one line; add it if absent and restate no policy: *"Comments: see `templatecentral:standards (code-standards)`, file `comments.md`."* Do **not** overwrite an existing lint config; recommend the scaffold's comment rules from `<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs` or `<skill-dir>/../scaffold/fastapi/template/pyproject.toml` (TS: `no-inline-comments: 'error'`, `sonarjs/no-commented-code: 'error'`, `linterOptions.reportUnusedDisableDirectives` and `reportUnusedInlineConfigs` at `'error'`, `sonarjs/todo-tag`/`fixme-tag` as `warn`; FastAPI: Ruff `ERA`, `PGH003`, `PGH004`, `RUF100`, `TD005`).

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
- **Step B3** — CI quality gates (by hand, per the scaffold-only note above): `.claude/ci-gates.sh` plus the host's CI file (`.github/workflows/ci.yml` on GitHub, `azure-pipelines/templatecentral-gates.yml` on Azure DevOps — never both). The kit's Step B3 rules for existing Azure pipelines apply (skip, or add only the `deps` step).
- **Step B4** — harness integrity verifier (`.claude/verify-harness.sh`, `.claude/regen-harness.sh`); seed it, because Phase 5d and pre-push call it.
- **Step B5** — the `/skill-audit` project skill, from `template-late/`.
- **Steps C, D** — `FUTURE.md`, `docs/CONSTITUTION.md`, `docs/harness.md` from `template-late/` (set `__TC_PROJECT_TITLE__` to the project name and fill or delete each `[Fill in: …]` line per kit Step D).

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

Execute kit **Step E** with the copy script at `<skill-dir>/../scaffold/shared/tc-copy.sh`: it hashes every seeded file present and writes the manifest, with `templatecentral_version` from the plugin's `plugin.json`. If the project already has a `.claude/harness.json`, the script refuses; move the old file to `.claude/harness.json.bak`, run it, then delete the backup once `verify-harness.sh` passes.

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

Execute kit **Step G** up to its post-scaffold utilities list: write the AGENTS.md tail between its markers (an existing generic tail with no markers must be wrapped in them by hand first; the script refuses otherwise; here the script is `<skill-dir>/../scaffold/shared/tc-copy.sh`; use that path in the kit's `TC_PART=tail` call), then the re-baseline block. Run Prettier (TS) only on files this phase wrote (`pnpm exec prettier --write AGENTS.md FUTURE.md docs/CONSTITUTION.md docs/harness.md <each README.md written by Step E3>`), never `.`. Then wire the git hooks per kit Step B2's re-sync note (`pnpm exec lefthook install` / `lefthook install` in the venv). Once `verify-harness.sh` passes, delete `AGENTS.md.bak`.

**Step 4f-4: Prove the harness is live**

Run `bash "<skill-dir>/general/harness-live.sh" <project-dir>`. It reports PASS or FAIL per item (lefthook installed and the git hooks wired, gitleaks resolvable, each hook executable and registered, CI running the gates) and exits non-zero on any FAIL. Fix each FAIL at its cause, for example install the missing tool or rerun lefthook install, and rerun until it exits 0; a hash match alone proves nothing. A tool the user must install (gitleaks, lefthook) is named in the summary, not skipped.

**Step 4g: Print summary**

`<version>` is the plugin release, read from `.claude-plugin/plugin.json` (`version`) in the plugin directory. Print `✓ Upgraded to templateCentral <version>.`, then one line per file or tree written, grouped as: `AGENTS.md` (marker `@6.0.0` plus shared tail; nextjs: compressed template), `CLAUDE.md` (`@AGENTS.md` import), `.claude/settings.json` (merged: secret-read deny block, `skillListingBudgetFraction`, 6 hook events in exec form), the 9 `.claude/hooks/*.sh` scripts, `.claude/comment-hygiene-patterns.txt`, the git-hook layer (`lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`), the CI gates (`.claude/ci-gates.sh` plus the host's CI file), `.claude/verify-harness.sh` and `regen-harness.sh`, the `skill-audit` and `<stack>-verify` skills (nextjs also `next-migrate`), `.claude/harness.json` and `.claude/.harness-base/`, `FUTURE.md`, `docs/CONSTITUTION.md`, per-folder `README.md`, and any deletion (`post-tool-failure.sh`). End with the live check's last line and: "Commit these files together — the harness only enforces as a complete set."
