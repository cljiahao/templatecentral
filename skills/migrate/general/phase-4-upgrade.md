<!-- ref: migrate/general/phase-4-upgrade.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Phase 0 of migrate/general/implementation.md routed here (user chose A); stack known from the AGENTS.md line-1 marker. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate — Phase 4 (harness seed / upgrade)

Loaded from `implementation.md` Phase 0. Phase 5 (health check + safe re-sync) is `phase-5-health-check.md`.

---

## Phase 4 — v4.0–v6.0 Upgrade (agent, autonomous after Phase 0 gate)

Run only when the user chose A in Phase 0. Do not invoke for unmarked projects.

**Step 4a: Read AGENTS.md and detect stack**

Read the full `AGENTS.md`. Extract `<stack>` from the existing marker on line 1.

**Step 4b: Back up and replace AGENTS.md**

Before replacing, save the original:
```bash
cp AGENTS.md AGENTS.md.bak
```

Replace `AGENTS.md` with the compressed template for the detected stack. If the upgrade fails at any point, restore with `cp AGENTS.md.bak AGENTS.md`. For `nextjs`, write exactly:

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

For other stacks (fastapi, nestjs, vite-react): preserve all existing content in `AGENTS.md`, but set line 1 to `<!-- templateCentral: <stack>@6.0.0 -->`. The marker must be final here, for every stack — Step 4f hashes `AGENTS.md` and Step 4f-3 re-baselines it, so a later marker edit leaves a stale `origin_hash` and base snapshot. The `## AI Harness` tail is appended by harness-kit-finalize.md Step G (unconditionally, for every stack) — nothing to hand-append here.

For every stack, ensure the project's rules/conventions section carries the comment doctrine — if absent, add: *"Comments explain why, not what — no commented-out code, no change-narration; own-line over trailing. See `templatecentral:standards (code-standards)`."* Do **not** overwrite an existing lint config; instead recommend the same gate a fresh scaffold ships — in the TS `eslint.config.*`: `no-inline-comments: 'error'` (with an `ignorePattern` for tooling directives), `sonarjs/no-commented-code: 'error'`, `linterOptions.reportUnusedDisableDirectives` + `reportUnusedInlineConfigs` at `'error'`, `@eslint-community/eslint-plugin-eslint-comments` `recommended` + `require-description` (`eslint-enable` exempt) + `disable-enable-pair` (`allowWholeFile`), and `sonarjs/todo-tag`/`fixme-tag` downgraded to `warn`; for FastAPI, Ruff `ERA`, `PGH003`, `PGH004`, `RUF100`, `TD005` (`pyproject.toml`) — so the enforcement matches a freshly scaffolded project. The Enforcement section of `code-standards/comments.md` is the rationale source; copy exact rule config from the stack's scaffold `config-files.md`.

**Step 4c: Create `CLAUDE.md`**

If `CLAUDE.md` does not exist, create it at the project root with exactly one line:

```
@AGENTS.md
```

If it already exists and contains more than `@AGENTS.md`, leave it unchanged.

**Step 4d: Seed the agent harness (shared kit)**

Load the shared harness kit and execute it **in full** — a migrated project must receive the **same** enforcement layer as a scaffolded one:

Load the kit index, the detected stack's variant file, and the two shared part files. `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react and `harness-kit-fastapi.md` for fastapi — load only that one variant file, never both.

These four files (`harness-kit.md`, the variant file, `harness-kit-enforcement.md`, `harness-kit-finalize.md`) are loaded by the phase table in `implementation.md` — if they are not in context, load them from there.

Using the **detected stack's row** in the kit's delta table (TS stacks: `node`; FastAPI: `python3`), execute kit Steps **A through D**:
- **Step A** — `settings.json` (the `permissions.deny` secret-*Read* block, `skillListingBudgetFraction`, and wiring for the 6 hook events templateCentral seeds).
- **Step B** — all **9** `.claude/hooks/` scripts (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`, `session-context`, `skill-usage-log`), `.claude/comment-hygiene-patterns.txt` (the canonical pattern list the new hook, the `comment-hygiene` lefthook command, and the `comment-hygiene` CI job all read at runtime), then `chmod +x .claude/hooks/*.sh`.
- **Step B2** — git-hook layer (`lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`).
- **Step B3** — CI quality gates: `.claude/ci-gates.sh` plus the host's CI file (`.github/workflows/ci.yml` on GitHub, `azure-pipelines/templatecentral-gates.yml` on Azure DevOps — never both).
- **Step B4** — harness integrity verifier (`.claude/verify-harness.sh`, `.claude/regen-harness.sh`) — Phase 5d's re-sync and the pre-push hook both call this, so it MUST be seeded here.
- **Step B5** — the `/skill-audit` project skill (consumes `skill-usage-log.sh`).
- **Steps C, D** — `FUTURE.md`, `docs/CONSTITUTION.md`.

The scripts are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing after adoption even if the plugin is removed.

**Adoption (merge, never clobber):** if the project already runs another git-hook manager, wire the Step B2 commands (secret scan, commit-msg, pre-push verify) into it instead of adding lefthook, and record the choice in AGENTS.md; existing pipelines include the Step B3 gates template rather than gaining a second pipeline. Move any project-specific guard into `.claude/hooks/local/` (kit Step A, "Project-local guards") instead of editing a canonical hook. If `.claude/settings.json`, `lefthook.yml`, `.github/workflows/ci.yml`, or `.gitleaks.toml` already exists, merge the kit's entries into the existing file instead of overwriting; warn on any conflict. In `settings.json`, an existing hook entry that points at a `.claude/hooks/` script with an array-valued `command` (pre-6.0.0 form — Claude Code never ran it) or without the `${CLAUDE_PROJECT_DIR}` prefix is **replaced** by the kit's exec-form entry, not kept alongside it; a leftover `PostToolUseFailure` → `post-tool-failure.sh` entry is removed **and** `.claude/hooks/post-tool-failure.sh` itself is deleted (with its `harness.json` entry, if any) — the script is no longer seeded, and a stale copy would otherwise linger as an un-wired, un-hashed file.

**Step 4d-1: Convert seeded skills to directory form**

For each flat file `.claude/skills/<name>.md` found in the project, convert it to directory form:

```bash
# For each flat .claude/skills/<name>.md:
mkdir -p .claude/skills/<name>
cp .claude/skills/<name>.md .claude/skills/<name>/SKILL.md
rm .claude/skills/<name>.md
```

Run this before Step 4e (so it sees the converted skills) and before Step 4f (so Step E hashes the final paths).

No documentation refresh is needed for this step: the directories it creates live under `.claude/`, which the documentation kit prunes as harness-internal (documentation-kit.md Step 2 — the same prune that keeps the kit from writing into paths `protect-files.sh` blocks).

**Step 4e: Seed project skills**

Create the stack-specific verify skill in `.claude/skills/` only if it does not already exist. Each project skill is a **directory** with `SKILL.md` as the entrypoint — flat `.claude/skills/<name>.md` files are silently ignored by Claude Code (flat files work only under `.claude/commands/`). Run `mkdir -p .claude/skills/<stack>-verify` first, then write the skill file:

| Stack | Skill file | Command |
|-------|-----------|---------|
| nextjs | `.claude/skills/next-verify/SKILL.md` | `pnpm check && pnpm test` |
| nestjs | `.claude/skills/nest-verify/SKILL.md` | `pnpm check && pnpm test` |
| vite-react | `.claude/skills/vite-verify/SKILL.md` | `pnpm check && pnpm test` |
| fastapi | `.claude/skills/api-verify/SKILL.md` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` |

Template for TypeScript stacks (replace `<stack>` and `<command>`):

`<stack>-verify` is **not** a literal substitution of the detected stack id — take the
name from the table above (`next-verify`, `nest-verify`, `vite-verify`, `api-verify`),
not `nextjs-verify`/`fastapi-verify`. The `name:` frontmatter field must match the
directory name exactly.

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

For nextjs only, also create `.claude/skills/next-migrate/SKILL.md` (`mkdir -p .claude/skills/next-migrate` first) if not present:
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

Execute kit **Step E** — it hashes **every** seeded file (all 9 hooks, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`, the host's CI file, `.claude/ci-gates.sh`, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`, any `.claude/hooks/local/*` scripts, the `<stack>-verify` and `skill-audit` skills, plus `next-migrate` for nextjs) and writes the complete manifest. Include only files that were actually created or merged. The kit is the single source for this manifest — do not maintain a separate copy here.

**Step 4f-1b: Seed the base snapshot**

Execute kit **Step E2** — it snapshots every seeded file into `.claude/.harness-base/`, the 3-way-merge base Phase 5d uses to re-sync harness updates without clobbering edits. Commit `.claude/.harness-base/`; `protect-files.sh` guards it.

**Step 4f-1c: Generate per-folder documentation**

Execute kit **Step E3** — it loads `documentation-kit.md`, determines the Azure DevOps Code Wiki and rich-content opt-ins, enumerates every folder in the adopted project, and writes or refreshes each folder's `README.md` (and `.order` files, if opted in):

`documentation-kit.md` is loaded by the phase table in `implementation.md` — if it is not in context, load it from there.

Follow it exactly over the full adopted project tree.

**Step 4f-2: Create `.agents` symlink**

If `.agents` does not already exist, create the cross-vendor symlink:

```bash
ln -s .claude .agents
```

This makes `AGENTS.md`, `settings.json`, `rules/`, `skills/`, and `hooks/` discoverable by any agent framework that resolves from `.agents/` — one source of truth, zero duplication.

**Never commit the symlink** — add `.agents` to the project's `.gitignore` (with a note that it is recreated per machine). A git-tracked symlink breaks Windows CI build agents (e.g. Azure DevOps hosted runners).

**Step 4f-3: Finish the AGENTS.md tail and re-baseline**

Execute kit **Step G** up to (not including) its post-scaffold utilities list: append the shared AGENTS.md tail fragment, then the re-baseline block. For the TS final format pass, run Prettier only on the files this phase wrote (`pnpm exec prettier --write AGENTS.md FUTURE.md docs/CONSTITUTION.md <each README.md written by Step E3>`), never `.` — an adopted codebase is not yours to reformat. Then wire the git hooks per kit Step B2's re-sync note (`pnpm exec lefthook install` / `lefthook install` in the venv). Once `verify-harness.sh` passes, delete `AGENTS.md.bak`.

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
  .claude/ci-gates.sh            — PR merge gates (secrets, changelog, readme, comments)
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
