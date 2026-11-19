# Harness reference

Reference detail for the rules in `AGENTS.md` (`## AI Harness`, `## Skills Security`, `## Git Workflow`). `AGENTS.md` keeps the rules an agent obeys on every turn; this file keeps the explanation. Seeded by templateCentral and safe to extend.

## AI Harness

**PreToolUse (Edit/Write/NotebookEdit):** blocks secrets only (exit 2): `.env*` (except `.env.example`), `secrets` folders, cert files (`.pem`/`.key`/`.secret`), `credentials.json`/`.netrc`. It asks for human approval before editing CI/CD definitions (the `.github` and `.azuredevops` folders, the `azure-pipelines` folder, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (AGENTS.md, CLAUDE.md, `.claude/settings.json`, `.claude/hooks/`). Project-specific guards live in a `local` folder under `.claude/hooks`, which re-sync never overwrites. A second Bash guard blocks `--no-verify`, hook-layer bypasses (`LEFTHOOK=0`, `git -c core.hooksPath=…`, `git config core.hooksPath`), commits to protected branches, and force-pushes to them (including `--force-with-lease`, `HEAD:main`). Skills, specs and all app code are unrestricted.

**SessionStart (startup/resume/clear/compact):** `AGENTS.md` is already loaded, so the hook prints only what it cannot say: a line when the checkout is on `main`/`uat`/`develop`, and on compact three invariant lines that point at `docs/CONSTITUTION.md`. The CONSTITUTION itself is read on demand, not injected.

**UserPromptSubmit:** pattern-checks incoming prompts for injection phrases; exit 2 blocks the prompt.

**PostToolUse:** an incremental type-check (the stack's command is in the `AGENTS.md` bullet) and a comment-hygiene scan (policy: the comments page of `templatecentral:standards`; patterns from `.claude/comment-hygiene-patterns.txt`) after every Edit/Write. Both are feedback-only: findings reach Claude as `additionalContext`, never a block.

**Stop hook:** typechecks, then runs the tests of uncommitted changes. It runs fewer than the full suite only when that is provably sound (TS: `vitest related` for changed code files; pytest: only the changed test files when every changed file is a test file). Any other change (config, setup files, data, fixtures, any file under `docs/` that is not `.md`, `.png`, `.jpg`, `.jpeg`, `.gif` or `.ico`, deletions, renames) or more than 50 changed files runs the full suite; only root `*.md`, `LICENSE*`, `CHANGELOG*` and `.md`, `.png`, `.jpg`, `.jpeg`, `.gif` or `.ico` files under the top-level `docs/` are ignored. The hook sees tracked and untracked files but not gitignored ones, and a directory with no repository at all is not gated. When the project is a subdirectory of a repository, only changes inside it count, with paths relative to it. NestJS `*.e2e-spec.ts` specs sit outside `vitest related` and run in pre-push and CI. Exit 2 feeds failures to Claude via stderr; exit 0 on pass (Claude Code caps consecutive Stop continuations, 8 by default). **Fails closed:** a missing tool (pytest, pyright, pnpm, tsc, vitest) exits 2 with a message naming it. **Time limit:** the hook stops its own run after 270 s (`STOP_GATE_LIMIT`), under the 300 s settings timeout, and exits 2 naming the step that timed out; pre-push and CI stay authoritative. **SubagentStop** type-gates a subagent's uncommitted changes (read-only Explore/Plan agents are skipped).

**Hook wiring:** every `settings.json` hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]`. An array-valued `command` is silently ignored by Claude Code.

**Git hooks (lefthook):** pre-commit runs format/lint/typecheck and a gitleaks secret scan on staged files, a docs check on staged Markdown (`scripts/check-docs.sh`: links and paths in the README, AGENTS.md and `docs/` must exist) and a comment-hygiene warning; commit-msg enforces Conventional Commits; pre-push runs the quality gate and the full docs check. These are hard-local; the coverage, changed-line and comment-hygiene gates run in CI.

**Test budget:** `bash scripts/test-budget.sh` (ADR-0001, `docs/adr/0001-test-each-behaviour-once.md`) is offline and read-only. It prints one line per run: source and test lines, the ratio, test-file count and likely duplicate tests. It fails only when test lines per 100 source lines exceed `TEST_BUDGET_MAX_RATIO` (default 35); `-v` lists likely duplicates, which never fail. The `test-consolidate` project skill is the fix path.

**CI** (GitHub Actions `ci.yml` under the `.github` folder, or on Azure DevOps either the project's own pipelines or the `templatecentral-gates.yml` steps template included from the PR pipeline, which a fresh scaffold seeds as `azure-pipelines.yml`). Use the project's own Azure pipelines instead of the seed only when they already run gitleaks, the harness check and a dependency audit. CI runs the harness integrity check, the docs check (`bash scripts/check-docs.sh`, a plain script step with no label bypass) plus the `.claude/ci-gates.sh` gates:
- a gitleaks secret scan (the PR's commits; full history off-PR) via the checksum-verified MIT CLI;
- a changelog-touched check and a comment-hygiene check on added lines. Bypass labels: `skip-changelog`, `skip-comment-check` (on Azure, queue with variable `LABELS`);
- a dependency-audit gate (`deps`): fails on high/critical advisories, no label bypass. The only suppression is the expiring allowlist `dep-audit-allow.txt` in the `.claude` folder.

GitHub also gates changed-line coverage (`diff-cover` ≥80%) and lockfile-in-sync (`--frozen-lockfile`). On Azure the pipeline that includes the template owns those steps (the seeded `azure-pipelines.yml` runs both).

**Supply-chain and container gates** (all offline and keyless; CI runs each through `.claude/ci-gates.sh`, and the fast ones also run in lefthook):
- `supplychain` (`scripts/check-supply-chain.sh`): pnpm install scripts stay off unless `allowBuilds` lists the package, `minimumReleaseAge` waits at least a day (seeded 7 days, never add `minimumReleaseAgeExclude`), CI installs are frozen (`pnpm --frozen-lockfile`, `pip --require-hashes`), `requirements.txt` carries `--hash` values, every lockfile host is the public registry or listed in `.claude/registry-hosts.txt`, and every Dependabot entry has a `cooldown` of at least 7 days (`default-days`). pip has no release-age setting, so Python relies on the Dependabot cooldown alone; `requirements-dev.txt` stays unhashed. Python direct dependencies live in `requirements.in`: edit it, then run `uv pip compile requirements.in --generate-hashes -o requirements.txt` (`pip install uv` in the venv provides uv) and `pip install --require-hashes -r requirements.txt`. The install check judges each `pnpm install` and `pip install -r` command on its own; `npm ci`, `yarn install` and `npm install` are not checked because the seeded stacks use pnpm only. When `package.json` sits only in a subdirectory the check prints a NOTE and does not look inside it, so run it from that project's root.
- `workflows` (`scripts/check-workflows.sh`): actions pinned to a 40-character SHA, a top-level read-only `permissions:` block, no `pull_request_target`, no `github.event` data inside `run:` (pass it through `env:`), and `persist-credentials: false` on checkout unless the job pushes. Azure pipelines get the `persistCredentials` and branch-name injection checks.
- `envexample` (`scripts/check-env-example.sh`): the variables the code reads and the keys of `.env.example` must match. It never reads a real `.env`, prints the directories it scanned (`src`, `app`, `lib`, `next.config.*`, `vite.config.*`) and warns when source exists in another top-level directory. It sees `process.env.X`, `process.env?.X`, `process.env['X']`, `const { A, B } = process.env`, `import.meta.env.X`, `os.environ.get("X")`, `os.getenv` and `os.environ["X"]`, and accepts `export NAME=` and `NAME = value` lines.
- `dockerfile` (`scripts/check-dockerfile.sh`): base images pinned by digest and never `:latest`, a non-root final `USER`, no `ADD` from a URL; hadolint runs too, with its own empty config, no `HADOLINT_*` variables and inline ignore pragmas off, so `.hadolint.yaml`, an environment variable or a `# hadolint ignore` comment cannot loosen it; a missing hadolint warns locally but fails in CI. `CI=false` counts as a local run. The CI step downloads a pinned hadolint for Linux x86_64 and needs `sha256sum`; on any other OS or architecture it fails with a message, so install hadolint on that runner first. To bump an image, run `docker buildx imagetools inspect <image>:<tag>` and paste the new digest (Dependabot does not read the `FROM` ARG).
- A missing gitleaks warns with the install command on every commit (`scripts/check-secret-scanner.sh`) and fails in CI. `.claude/settings.json` denies reading `.env*`, `*.pem`, `*.key` and `secrets` folders, denies `eval`, bare `sh`/`bash` and `sh -s`/`bash -s`, and asks before `curl` and `wget` so the agent can still smoke-test its own app on localhost; the rules match the command as typed, so a wrapper script or an absolute path is not covered. `verify-harness.sh` fails when one is removed.
- The gate ratchet fails a PR that lowers `minimumReleaseAge`, adds an `allowBuilds` entry or a `registry-hosts.txt` line, and treats the new scripts as gate scripts.

**Files:** project skills in `.claude/skills/`; manifest in `.claude/harness.json`.

**Context load order** (context only, not enforcement; broad to specific): managed policy → `~/.claude/CLAUDE.md` → `CLAUDE.md` `@AGENTS.md` (optional, Claude Code) → `AGENTS.md` → `.claude/rules/**/*.md` without `paths:` (loaded at launch) → rules with `paths:` (loaded when a matching file is read or edited). `docs/CONSTITUTION.md` is read on demand and is not injected at session start; its security invariants that no hook or CI check enforces are restated in `AGENTS.md` (`## Security`, `## Skills Security`). Hard enforcement: PreToolUse hooks in `settings.json` only.

## Skills Security

- Review `SKILL.md` content before installing any third-party skill; treat skills like packages.
- Scope `allowed-tools:` in skill frontmatter to the minimum needed (for example `Bash(git *)`, not `Bash`).
- Never install skills that hardcode secrets or make outbound network calls without an explicit allow-list.

## Git Workflow

**Branch source:** always fork from an up-to-date `main`. Before branching run `git fetch -p`, then update `main` (`git checkout main && git pull --ff-only`). Fork the feature from the freshly pulled `main`.

The seeded hooks separately protect the common branch names `main`/`uat`/`develop` from direct commits and force-push, whichever PR route you use (see "AI Harness" above). That protection is a fixed baseline safety net independent of the route table in `AGENTS.md`; it is not the route this repo follows, only the names the hooks always guard.

The route table for this deployment (for example develop/uat, develop/staging/live, or trunk) belongs in `AGENTS.md` under `## Git Workflow`, below the marker comment. The fetch-first step is universal; the route clause is not.

**Gate ratchet:** CI runs the merge-base copy of `.claude/ci-gates.sh` and `scripts/gate-ratchet.sh` and fails a PR that weakens a gate or changes a gate script, runner or manifest. A maintainer can apply the `allow-gate-change` label after review: the log then prints every finding plus a line saying the label waived them. The label cannot waive a change to the files that enforce the gates (the CI files, `lefthook.yml`, `.claude/ci-gates.sh`, `.claude/gates.txt`, `.claude/verify-harness.sh`, `scripts/gate-ratchet.sh`, `scripts/test-budget.sh`, the protect-files hooks); that needs owner review. The label waives only a weakened setting on other files, never an unreadable config or a checker failure. A nested `pyproject.toml` or `eslint.config.*` in a sub-package is not read and needs the label.

The ratchet is the second line of defence; the first is the agent file-protection hooks. To make it binding, mark the CI check as required and require owner review for the CI pipeline files, `.claude/` and `scripts/` in the host's branch protection. No CODEOWNERS file is seeded, because it needs an account name.

## Sonar way profile notes

Local checks match the default Sonar way profile. If your server flags a rule below, the fix is in the server's quality profile, not the code.

- S1774 bans every ternary and is not in the default profile; remove it on the server. Nested ternaries (S3358) are default and covered locally.
- S6480 (functions or `.bind()` in JSX props) was removed from the default profile.
- S7728 (`for…of` over `.forEach`) is being removed from Sonar way.
- The default profile changes with the server version, and findings from newly added rules are backdated onto existing code.
- Security hotspots need manual review on the server; no local check closes them.
- The server ignores the coverage and duplication conditions until the new code reaches 20 lines; local diff coverage has no such exemption.
- Sonar has two built-in gates; the local checks target plain "Sonar way", not "Sonar way for agentic AI".

## Skill capture

- A workflow done twice → author a `.claude/skills/<name>/` project skill and commit it, so the repo (and teammates) carry it, not just session memory. `/skill-audit` surfaces repeats from the skill usage log in the `.claude` folder.
- Do not vendor third-party plugin skills; re-author the workflow as a project skill tuned to this repo.

## Test speed

Speed changes keep the same tests, the same coverage and the same gates. The levers that are on:

- **Vitest runs on `pool: 'threads'`.** Threads start faster than forks and keep test IDs, coverage and per-file isolation.
- **Caches are used only where a stale result cannot hide a finding.** `pnpm typecheck` and the lefthook typecheck step run `tsc --noEmit --incremental` on every TS stack; `pnpm check` runs plain `tsc --noEmit`, which reads and writes `*.tsbuildinfo` only where the tsconfig sets `incremental` (NestJS and Next.js). `pnpm lint` runs `eslint --cache` on Next.js and Vite + React, whose rules read one file at a time. NestJS lint, `pnpm check` and the lefthook eslint step run uncached: NestJS uses type-aware rules, and an edit in one file can change a finding in a file you did not touch. `*.tsbuildinfo` and `.eslintcache` are gitignored. CI is uncached because a fresh checkout has no cache file.
- **CI shards the vitest suite up to 4 ways** (`SHARD_MAX` on GitHub, `shardMax` on Azure). A plan job counts the test files vitest resolves (`vitest list --filesOnly`) and uses `min(4, files)` shards, because vitest refuses `--shard=i/N` when N is above the file count; no test files fails the plan. A merge step fails unless the merged test count equals a collection-only count of the unsharded suite and no test failed, then the existing changed-line coverage bar (80%) applies to the merged report.
- **FastAPI tests run serially.** `python -m pytest -n auto` was removed because xdist measured slower at this suite size. Add it back only after measuring a longer suite.

Acceptance rule for any further speed change. All of these hold before it merges:

1. The test IDs are the same before and after (list and diff them).
2. Coverage is equal and at least 80%.
3. The mutation score is not lower.
4. Ten random-order runs (`--sequence.shuffle` for vitest) show no flake.
5. No gate is skipped, loosened or made optional.
6. The full suite runs before merge to `main`. A sample or an affected-only run is never the final gate.

Rejected levers, with the reason:

- `pool: 'vmThreads'`: a shared VM context leaks module and global state between tests and raises memory use.
- `--no-isolate` / `isolate: false`: tests share module state, so order starts to matter.
- `--bail`: stops at the first failure and hides the rest of the run, so the test IDs differ.
- A lower `maxWorkers` than the seeded `'50%'` in CI (`process.env.CI ? '50%' : undefined` in the vitest config): the runners are small, so half the cores per process keeps memory flat, and the shards supply the parallelism. Tighter caps only slow a shard.
- xdist or shards for Python: slower than serial at this suite size.
- Affected-only test selection: a sample, not the full suite, so it cannot be the final gate.
