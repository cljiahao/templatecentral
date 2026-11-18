# Harness reference

Reference detail for the rules in `AGENTS.md` (`## AI Harness`, `## Skills Security`, `## Git Workflow`, `## Skill capture`). `AGENTS.md` keeps the rules an agent obeys on every turn; this file keeps the explanation. Seeded by templateCentral and safe to extend.

## AI Harness

**PreToolUse (Edit/Write/NotebookEdit):** blocks secrets only (exit 2): `.env*` (except `.env.example`), `secrets` folders, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`. It asks for human approval before editing CI/CD definitions (the `.github` and `.azuredevops` folders, the `azure-pipelines` folder, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (AGENTS.md, CLAUDE.md, `.claude/settings.json`, `.claude/hooks/`). Project-specific guards live in a `local` folder under `.claude/hooks`, which re-sync never overwrites. A second Bash guard blocks `--no-verify`, hook-layer bypasses (`LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`), commits to protected branches, and force-pushes to them (including `--force-with-lease`, `HEAD:main`). Skills, specs and all app code are unrestricted.

**SessionStart (startup/resume/clear/compact):** re-injects the CONSTITUTION and the universal invariants so they survive compaction. PostCompact stdout is also injected as context and fires after compaction, but SessionStart additionally covers resume/startup, so it is the seeded mechanism here.

**UserPromptSubmit:** pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.

**PostToolUse:** an incremental type-check (the stack's command is in the `AGENTS.md` bullet) and a comment-hygiene scan (policy: the comments page of `templatecentral:standards`; patterns from `.claude/comment-hygiene-patterns.txt`) after every Edit/Write. Both are feedback-only: findings reach Claude as `additionalContext`, never a block.

**Stop hook:** typechecks, then runs the tests of uncommitted changes. It runs fewer than the full suite only when that is provably sound (TS: `vitest related` for changed code files; pytest: only the changed test files when every changed file is a test file). Any other change (config, setup files, data, fixtures, any file under `docs/` that is not `.md`, `.png`, `.jpg`, `.jpeg`, `.gif` or `.ico`, deletions, renames) or more than 50 changed files runs the full suite; only root `*.md`, `LICENSE*`, `CHANGELOG*` and `.md`, `.png`, `.jpg`, `.jpeg`, `.gif` or `.ico` files under the top-level `docs/` are ignored. The hook sees tracked and untracked files but not gitignored ones, and a directory with no repository at all is not gated. When the project is a subdirectory of a repository, only changes inside it count, with paths relative to it. NestJS `*.e2e-spec.ts` specs sit outside `vitest related` and run in pre-push and CI. Exit 2 feeds failures to Claude via stderr; exit 0 on pass (Claude Code caps consecutive Stop continuations, 8 by default). **Fails closed:** a missing tool (pytest, pyright, pnpm, tsc, vitest) exits 2 with a message naming it. **Time limit:** the hook stops its own run after 270 s (`STOP_GATE_LIMIT`), under the 300 s settings timeout, and exits 2 naming the step that timed out; pre-push and CI stay authoritative. **SubagentStop** type-gates a subagent's uncommitted changes (read-only Explore/Plan agents are skipped).

**Hook wiring:** every `settings.json` hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]`. An array-valued `command` is silently ignored by Claude Code.

**Git hooks (lefthook):** pre-commit runs format/lint/typecheck and a gitleaks secret scan on staged files, a docs check on staged Markdown (`scripts/check-docs.sh`: links and paths in the README, AGENTS.md and `docs/` must exist) and a comment-hygiene warning; commit-msg enforces Conventional Commits; pre-push runs the quality gate and the full docs check. These are hard-local; the coverage, changed-line and comment-hygiene gates run in CI.

**CI** (GitHub Actions `ci.yml` under the `.github` folder, or on Azure DevOps either the project's own pipelines or the `templatecentral-gates.yml` steps template included from the PR pipeline, which a fresh scaffold seeds as `azure-pipelines.yml`). Use the project's own Azure pipelines instead of the seed only when they already run gitleaks, the harness check and a dependency audit. CI runs the harness integrity check, the docs check (`bash scripts/check-docs.sh`, a plain script step with no label bypass) plus the `.claude/ci-gates.sh` gates:
- a gitleaks secret scan (the PR's commits; full history off-PR) via the checksum-verified MIT CLI;
- a changelog-touched check and a comment-hygiene check on added lines. Bypass labels: `skip-changelog`, `skip-comment-check` (on Azure, queue with variable `LABELS`);
- a dependency-audit gate (`deps`): fails on high/critical advisories, no label bypass. The only suppression is the expiring allowlist `dep-audit-allow.txt` in the `.claude` folder.

GitHub also gates changed-line coverage (`diff-cover` ≥80%) and lockfile-in-sync (`--frozen-lockfile`). On Azure the pipeline that includes the template owns those steps (the seeded `azure-pipelines.yml` runs both).

**Files:** project skills in `.claude/skills/`; manifest in `.claude/harness.json`.

**Context load order** (context only, not enforcement; broad to specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → `AGENTS.md` → `.claude/rules/*.md` (lazy per directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security

- Review `SKILL.md` content before installing any third-party skill; treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (for example `Bash(git *)`, not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Git Workflow

**Branch source:** always fork from an up-to-date `main`. Before branching run `git fetch -p`, then update `main` (`git checkout main && git pull --ff-only`). Fork the feature from the freshly pulled `main`.

The seeded hooks separately protect the common branch names `main`/`uat`/`develop` from direct commits and force-push, whichever PR route you use (see "AI Harness" above). That protection is a fixed baseline safety net independent of the route table in `AGENTS.md`; it is not the route this repo follows, only the names the hooks always guard.

The route table for this deployment (for example develop/uat, develop/staging/live, or trunk) belongs in `AGENTS.md` under `## Git Workflow`, below the marker comment. The fetch-first step is universal; the route clause is not.

## Skill capture

- A workflow done twice → author a `.claude/skills/<name>/` project skill and commit it, so the repo (and teammates) carry it, not just session memory. `/skill-audit` surfaces repeats from the skill usage log in the `.claude` folder.
- Do not vendor third-party plugin skills; re-author the workflow as a project skill tuned to this repo.
