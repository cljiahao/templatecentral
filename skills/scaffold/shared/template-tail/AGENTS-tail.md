## AI Harness
PreToolUse (Edit/Write/NotebookEdit): blocks secrets only (exit 2): `.env*` (except `.env.example`), `secrets/`, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`; asks for human approval before editing CI/CD definitions (`.github/workflows/`, `.github/actions/`, `.azuredevops/`, `azure-pipelines/`, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (AGENTS.md, CLAUDE.md, `.claude/settings.json`, `.claude/hooks/`); project-specific guards live in `.claude/hooks/local/`, which re-sync never overwrites; a second Bash guard blocks `--no-verify`, hook-layer bypasses (`LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`), commits to protected branches, and force-pushes to them (incl. `--force-with-lease`, `HEAD:main`). Skills, specs, and all app code are unrestricted. SessionStart (startup/resume/clear/compact): re-injects the CONSTITUTION + universal invariants so they survive compaction (PostCompact stdout is also injected as context and fires after compaction, but SessionStart additionally covers resume/startup, so it's the seeded mechanism here).
UserPromptSubmit: pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.
PostToolUse: incremental type-check (see delta table for stack command) and a comment-hygiene scan (change-narration comments, oversized comment blocks — patterns from `.claude/comment-hygiene-patterns.txt`) after every Edit/Write. Both feedback-only — findings reach Claude as `additionalContext`, never a block.
Stop hook: runs the full test suite when there are uncommitted changes; exit 2 feeds failures to Claude via stderr; exit 0 on pass (Claude Code caps consecutive Stop continuations — 8 by default). SubagentStop: type-gates a subagent's uncommitted changes (read-only Explore/Plan agents skipped).
Hook wiring: every `settings.json` hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]` — an array-valued `command` is silently ignored by Claude Code.
Git hooks (lefthook): pre-commit runs format/lint/typecheck + gitleaks secret-scan on staged files, plus a readme-coupling staleness warning and a comment-hygiene warning; commit-msg enforces Conventional Commits; pre-push runs the quality gate. Hard-local; coverage/changed-line/comment-hygiene gates run in CI.
CI (GitHub Actions `.github/workflows/ci.yml`, or on Azure DevOps either the project's own pipelines — skipping the seed only when they already run gitleaks, the harness check and a dependency audit — or the `azure-pipelines/templatecentral-gates.yml` steps template included from the PR pipeline): the harness integrity check plus `.claude/ci-gates.sh` gates — a gitleaks secret scan (the PR's commits; full history off-PR) via the checksum-verified MIT CLI, a changelog-touched check, a readme-freshness check, and a comment-hygiene check on added lines (bypass labels `skip-changelog` / `skip-readme-check` / `skip-comment-check`; on Azure, queue with variable `LABELS`), and a dependency-audit gate (`deps`: fails on high/critical advisories, no label bypass; the only suppression is the expiring allowlist `.claude/dep-audit-allow.txt`). GitHub also gates changed-line coverage (`diff-cover` ≥80%) and lockfile-in-sync (`--frozen-lockfile`); on Azure the project pipeline owns those steps.
Project skills: `.claude/skills/` | Manifest: `.claude/harness.json`
Context load order (context only — not enforcement, broad → specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → this file → `.claude/rules/*.md` (lazy per-directory). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security
- Review `SKILL.md` content before installing any third-party skill — treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (e.g. `Bash(git *)` not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Git Workflow

**Branch source:** Always fork from an up-to-date `main`.
Before branching: `git fetch -p` then update `main` (`git checkout main && git pull --ff-only`). Fork the feature FROM the freshly-pulled `main`.

(The seeded hooks separately protect the common branch names `main`/`uat`/`develop` from direct commits and force-push regardless of which PR route you use — see "AI Harness" above. That protection is a fixed baseline safety net independent of the route table below; it is not "the route" this repo follows, just names the hooks always guard.)

<!-- Per-repo: below this line, document the protected-branch route table for THIS deployment (e.g. develop/uat, develop/staging/live, or trunk). The fetch-first step above is universal; the route clause is not. -->

## Skill capture
- A workflow done twice → author a `.claude/skills/<name>/` project skill and commit it, so the repo (and teammates) carry it, not just session memory. `/skill-audit` surfaces repeats from `.claude/skill-usage.log`.
- Don't vendor third-party plugin skills — re-author the workflow as a project skill tuned to this repo.
