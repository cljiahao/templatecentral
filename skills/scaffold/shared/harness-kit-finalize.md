<!-- ref: scaffold/shared/harness-kit-finalize.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table), the stack's variant file, and harness-kit-enforcement.md loaded; Steps A–B5 done. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — governance, manifest, and post-scaffold (Steps C–H)

Every stack. Step order and the delta table are in `harness-kit.md`.

---

## Step C. Seed `FUTURE.md`, `docs/CONSTITUTION.md`, `docs/harness.md` and the `/skill-audit` skill

Run `tc-copy.sh` of `harness-kit.md` Step 0 as `TC_STACK=<stack> TC_PART=late bash "<skill-dir>/shared/tc-copy.sh" "<target>"` with the `STACK` of Step 0, after the stack's verification gate and its format pass. It copies four files from `<skill-dir>/shared/template-late/` and refuses when any already exists:

- `FUTURE.md` — design seams for AI collaboration patterns not yet activated.
- `docs/CONSTITUTION.md` — binding invariants; wins over `AGENTS.md` and all skill guidance.
- `docs/harness.md` — the reference detail behind the short `## AI Harness` / `## Git Workflow` tail of Step G, which points to it.
- `.claude/skills/skill-audit/SKILL.md` — the Step B5 skill.

---

## Step D. Fill in `docs/CONSTITUTION.md`

With the Edit tool, replace `__TC_PROJECT_TITLE__` in `docs/CONSTITUTION.md` with the project title. The title must be a single line: if it holds a newline, stop and ask the user for a one-line title and edit nothing. Replace each `[Fill in: …]` line with the project's real value, or delete it where it says so. The §6 quality gate is the **quality-gate line** from the per-stack delta table. `TC_PART=finish` in Step G refuses while a placeholder is left in this file, `FUTURE.md` or `docs/harness.md`.

---

## Step E. Create `.claude/harness.json`

**Prerequisites:** run only after the stack's verify skills exist (and `next-migrate` for nextjs); the script refuses when one is missing.

Write `.claude/harness.json` with the copy script. It hashes every seeded file present (`AGENTS.md`, `CLAUDE.md` if the stack's CLAUDE.md step created it, `settings.json`, the verify skills of the delta table, `/skill-audit`, every file under `.claude/hooks/` including `local/`, the git-hook layer, the CI files Step B3 seeded and the harness scripts), takes `templatecentral_version` from the plugin's `.claude-plugin/plugin.json`, and refuses when the file already exists or a verify skill is missing:

```bash
TC_STACK=<stack> TC_PART=manifest TC_ADO_WIKI=<true|false> bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

`TC_ADO_WIKI` is the Step E3 documentation choice (default `false`). In a scaffold, set it from the scaffold Step 1 answer on the wiki (`adoWiki`), so Step E3 reads it and asks nothing. A migration has no scaffold Step 1: reuse the `adoWiki` value of the project's previous manifest when it has one, and otherwise ask the user, worded as in `documentation-kit.md` Step 1, before running the script. It becomes the top-level `adoWiki` field that `documentation-kit.md` reads. The hashes are provisional: `TC_PART=finish` in Step G re-hashes every entry once the files are final. A file seeded later (a hook added to `.claude/hooks/local/`) gets its own `seeded_files` entry in the same `{ "origin_hash": …, "path": … }` shape.

---

## Step E2. Base snapshot

`TC_PART=finish` (Step G) mirrors every seeded file into `.claude/.harness-base/`, the as-seeded merge base `templatecentral:migrate` Phase 5 uses to 3-way-merge harness updates. Keep it tracked: it goes in with the first commit. A migration that needs the snapshot before Step G runs the same command.

---

## Step E3. Seed the project docs

Seed the root README, the architecture codemap, boundary READMEs and the opt-in wiki ordering file now that every file exists, then run the docs check:

```bash
cat "<skill-dir>/shared/documentation-kit.md"   # migrate: <skill-dir>/../scaffold/shared/documentation-kit.md
```

Follow it exactly.

---

## Step F. Create `.agents` symlink

Create the cross-vendor symlink for tools that resolve from `.agents/`:

```bash
ln -s .claude .agents
```

**Never commit the symlink** — verify `.gitignore` lists `.agents` (add it when migrating). A tracked symlink breaks Windows CI agents ("Unable to load symbolic/hard linked file" on Azure DevOps hosted runners).

---

## Step G. Post-scaffold agent workflow

**AGENTS.md tail — managed block, single source:** the `## AI Harness` / `## Skills Security` / `## Git Workflow` tail comes only from this step. After the stack-specific AGENTS.md is written, `TC_PART=tail` writes `<skill-dir>/shared/template-tail/AGENTS-tail.md` between the `<!-- BEGIN:templatecentral-tail … -->` and `<!-- END:templatecentral-tail -->` lines (a migration runs `<skill-dir>/../scaffold/shared/tc-copy.sh`: change only that path). A re-run replaces the block and adds no second copy; repo rules go outside the markers. On malformed markers, or an `## AI Harness` heading with no markers, it stops and writes nothing: wrap the existing generic tail in the two marker lines by hand, then re-run.

```bash
TC_STACK=<stack> TC_PART=tail bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

**Final format pass (TS stacks only):** Steps C/D, E3 and the tail wrote files after the first format pass, so run `pnpm format` once now, or `pnpm run check` and CI's `quality` job fail on files nobody edited. FastAPI needs none.

**Finish the seeding (all stacks, once, before the first commit):** the tail and the format pass changed seeded files, so re-hash every `origin_hash`, refresh `.claude/.harness-base/` and run `verify-harness.sh`. It refuses while a placeholder is left. A `CLAUDE.md` created in this step needs its `seeded_files` entry before this runs.

```bash
TC_STACK=<stack> TC_PART=finish bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

Then run these agent skills in order. They are **on by default** — skipping requires explicit user confirmation.

1. the stack's check command (`pnpm build && pnpm check`; fastapi `ruff check src/ && python -m pyright src/`) — verify the scaffold compiles clean; on failure, fix what this change broke and report anything else as `file:line — message`
2. the test utility — load it with: `cat "<skill-dir>/../test/SKILL.md"` — run the existing suite and confirm it passes. At scaffold time it writes no new tests and does not load `templatecentral:add (test)`: the template's tests already cover the copied code.
3. the review utility (update operation) — load it with: `cat "<skill-dir>/../review/SKILL.md"` — freshen any deps that have newer compatible versions
4. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — review only the files the agent edited by hand during the scaffold: the stack guide's Step 1 and Step 2 edits (project name, branding, settings), the filled-in `docs/CONSTITUTION.md` and the project docs (README, `docs/architecture.md`, boundary READMEs). The copied templates are not in scope; they are reviewed when the plugin is released. The project has no commit yet, so this review writes no `.claude/review-baseline.md`; the first review after the project's first commit writes it.

**Skipping these steps:** use the scaffold Step 1 answer on post-scaffold checks. If the user asks to skip and has not already confirmed it, warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip these steps if the user confirms.

**If any agent reports failures:** Stop there and do not run the next agent. Report the specific errors to the user and wait for them to be resolved before re-running that agent.

---

## Step H. Install Claude Code plugins

**Claude Code users only.** `marketplace add` only registers a source; then install. **Off by default** — install only when the scaffold Step 1 answer on Claude Code plugins is yes, or the user asks now. Installs are user-scoped.

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman
claude plugin marketplace add obra/superpowers
claude plugin install superpowers
```

- **caveman** — compresses Claude output prose, reducing token cost in development sessions. Disable with `/caveman off` when writing committed files (`AGENTS.md`, `CLAUDE.md`, docs).
- **superpowers** — brainstorm → plan → implement for features touching 3+ files. Skip for one-liners.

**No interactive user** (headless run): skip this step unless the run's instructions say to install the plugins, and note the skip in your final report. An unattended run does not change user-scoped Claude Code configuration on its own.
