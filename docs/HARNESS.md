# Harness details

What the guard harness does that an ordinary setup does not. Back to the [README](../README.md).

The value is in the details an ordinary setup gets wrong. Most rows began as a failure found in real use.

| Detail | What templatecentral does | Why it matters |
|:---|:---|:---|
| Branch guard reads the right folder | `block-no-verify.sh` judges a commit by the folder it actually runs in — the hook input's `cwd` plus each literal `cd` in a strict `&&` chain. Anything it cannot resolve also checks the project root. | In a worktree, a naive guard reads the main checkout's branch: it blocks every legitimate commit or misses a commit to `main`. |
| Every bypass spelling is closed | Blocks `--no-verify`, `-n`, `HUSKY=0`, `LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`, force-push or delete of protected branches (incl. `+refspec`, `HEAD:main`), and checkout/restore of guard files. Heredoc commit-message text is ignored. | Blocking only `--no-verify` leaves five other ways around the hooks, and an agent will find one. |
| Secrets blocked, governance asked | `protect-files.sh` hard-blocks `.env*`, `secrets/` and cert files, and asks a human before edits to `AGENTS.md`, the constitution, hooks, settings, CI and the audit allowlist. Paths are canonicalised, so `src/../.github/…` or a symlink cannot disguise the target. | A hard block on CI files also blocks the approved edit; an ask keeps a human in the loop without stopping the work. |
| Tamper detection | `verify-harness.sh` recomputes every enforcement file's hash against `.claude/harness.json` on pre-push and in CI. | If the agent edits a hook to get past it, the next push or PR fails. |
| Upgrades keep local rules | `.claude/.harness-base/` stores the last-seeded bytes, so `migrate` does a three-way re-sync. Project rules in `.claude/hooks/local/` are never touched. | Take upstream security fixes without losing your own guards. |
| Gates fail closed | CI gates fail when a tool is missing, the base branch is missing, output cannot be parsed, or an audit covered nothing. | A gate that passes when it cannot run is no gate. |
| Dependency audit with no bypass | Audits every `pnpm-lock.yaml`, `uv.lock` and `requirements*.txt` for high/critical advisories. Exceptions live only in `.claude/dep-audit-allow.txt` with a reason and an expiry at most 180 days out; package-manager ignore lists are rejected. | Suppressions cannot pile up silently or hide where the gate cannot see them. |
| Authorization denies by default | `add auth` ships role and ownership helpers per stack (`require_roles` / `ensure_owner`, `@Roles` + `RolesGuard` / `assertOwner`, `hasRole` / `isOwner`) with tests. Roles come from the database, never the token; another user's record returns 404. | Revoking a role takes effect on the next request, and record ids cannot be probed. |
| Done means tests pass | The `Stop` hook runs the test suite and `SubagentStop` runs the type check; a failure sends the agent back to fix it. | "Done" is checked, not claimed. |
| Same rules on any host | One `ci-gates.sh` serves GitHub Actions and Azure Pipelines; pipelines that already run a check are reused, not duplicated. | No dead pipeline files, one source of truth for reviewers. |
| Keeps enforcing without the plugin | The guards are files in your repo, not part of the plugin. | Uninstalling the plugin does not switch the rules off. |

## Extra evidence

| Evidence | Result |
|:---|:---|
| Branch-guard rewrite | Checked against the previous hook over 248 command × folder combinations; nothing it blocked became allowed |
| Dependency audit with real tools | pnpm, pip-audit and uv: clean scaffolds pass; a known advisory such as `lodash: GHSA-35jh-r3h4-6jhm (high)` fails and is named |

The full list of results is in the [CHANGELOG](../CHANGELOG.md).
