## AI Harness
Hooks in `.claude/settings.json` block secret files, `--no-verify`, hook bypasses, and commits or force-pushes to main/uat/develop; they ask a human before edits to CI, AGENTS.md, CLAUDE.md and `.claude/{settings.json,hooks/}`. After each edit an incremental type-check (`see delta table for stack command`) and a comment scan report findings; Stop-gate exit 2 means fix the failures. Hook wiring and own guards: `docs/harness.md`.

## Skills Security
Vet a third-party `SKILL.md` like a package: never install one that hardcodes secrets or makes outbound calls; scope `allowed-tools:` minimally; never vendor. A workflow done twice becomes a committed project skill.

## Security
No hook enforces these. Authenticate every route that reads or changes user data before its logic, and keep one unauthenticated-rejected test for it. Keep secrets out of code, logs and build output. Binding invariants live in `docs/CONSTITUTION.md`, read on demand, not injected at session start.

## Gate Time
`.claude/ci-gates.sh` times every gate; a "gate-time: over budget" note at session start or in the CI log means the gates run too long.
Revise the project to make them faster: dependency and build cache, independent gates in parallel, only affected tests locally while CI runs all, a smaller Docker build context with better layer order, faster test setup.
Never remove, skip or weaken a check to save time.
Budgets are in `.claude/gate-budget.conf`; only a human raises one.

## Git Workflow
Branch from a fresh `main` (`git fetch -p`, `git pull --ff-only`).
Fix a stale README or doc in the same change; `scripts/check-docs.sh` checks them.
