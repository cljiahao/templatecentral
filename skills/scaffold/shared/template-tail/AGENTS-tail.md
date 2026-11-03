## AI Harness
Enforced by hooks in `.claude/settings.json`. Detail, bypass labels and CI gates: `docs/harness.md#ai-harness`.
- PreToolUse blocks secret files (exit 2): `.env*` (not `.env.example`), `secrets/`, `.pem`/`.key`/`.secret`, `credentials.json`, `.netrc`. It asks a human before edits to CI/CD definitions and governance files (AGENTS.md, CLAUDE.md, `.claude/settings.json`, `.claude/hooks/`).
- The Bash guard blocks `--no-verify`, hook bypasses (`LEFTHOOK=0`, `core.hooksPath`), commits to protected branches and force-pushes to them.
- PostToolUse runs an incremental type-check (see delta table for stack command) and a comment-hygiene scan after each edit. Feedback only: fix what they report.
- The Stop hook runs the full test suite when changes are uncommitted; exit 2 means fix the failures.
- Project-specific guards go in `.claude/hooks/local/` (re-sync never overwrites it). Project skills: `.claude/skills/`. Manifest: `.claude/harness.json`.

## Skills Security
- Review `SKILL.md` before installing a third-party skill; treat skills like packages.
- Scope `allowed-tools:` to the minimum (`Bash(git *)`, not `Bash`).
- Never install skills that hardcode secrets or make outbound calls without an explicit allow-list.

## Git Workflow
- Fork every branch from a fresh `main`: `git fetch -p`, then `git checkout main && git pull --ff-only`.
- Hooks always guard `main`/`uat`/`develop` from direct commits and force-push; this is a fixed baseline, not this repo's route (`docs/harness.md#git-workflow`).
<!-- Per-repo: below this line, document the protected-branch route table for THIS deployment. -->

## Skill capture
- A workflow done twice becomes a committed `.claude/skills/<name>/` project skill; `/skill-audit` surfaces repeats.
- Don't vendor third-party plugin skills; re-author them for this repo.
