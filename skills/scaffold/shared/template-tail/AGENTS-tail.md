## AI Harness
Hooks in `.claude/settings.json` block secret files, `--no-verify`, hook bypasses, and commits or force-pushes to main/uat/develop; they ask a human before edits to CI, AGENTS.md, CLAUDE.md and `.claude/{settings.json,hooks/}`. After each edit an incremental type-check (`see delta table for stack command`) and a comment scan report findings; Stop-gate exit 2 means fix the failures. Hook wiring and own guards: `docs/harness.md`.

## Skills Security
Vet a third-party `SKILL.md` like a package; scope `allowed-tools:` minimally; never vendor. A workflow done twice becomes a committed project skill.

## Git Workflow
Branch from a fresh `main` (`git fetch -p`, `git pull --ff-only`).
Fix a stale README or doc in the same change; `scripts/check-docs.sh` checks them.
