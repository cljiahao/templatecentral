<!-- ref: scaffold/shared/harness-kit-enforcement.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table) and the stack's variant file (harness-kit-ts.md or harness-kit-fastapi.md) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — enforcement layer (Steps A–B5, every stack)

Stack-agnostic half of Steps A, B, B2, plus all of B3–B5. Per-stack bodies: the variant file (`harness-kit-ts.md` / `harness-kit-fastapi.md`); step order and delta table: `harness-kit.md`. The files named below are real files under `shared/template*/`, copied by `harness-kit.md` Step 0; entries here describe them and add wiring rules.

---

## Step A. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root plus the `.claude/hooks/` scripts it references (Step 0 copies them). `TC_PART=settings` stops when `.claude/settings.json` exists: report it, do not overwrite. Merging is `migrate`-only: merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, Stop, SubagentStop, SessionStart) and `permissions.deny` into the existing object. Keep hooks already present, but **replace** any entry for these `.claude/hooks/` scripts whose `"command"` is a JSON array or whose path lacks `${CLAUDE_PROJECT_DIR}` (those never ran), and drop any leftover `PostToolUseFailure` → `post-tool-failure.sh` entry (no longer shipped).

**`.claude/settings.json`** — run `tc-copy.sh` with `TC_PART=settings` (it copies the variant's body from `template-settings-ts/.claude/settings.json` or `template-settings-py/.claude/settings.json` under `<skill-dir>/shared/`), then apply the rules below.

**Hook entry form — string `command` + `args`, never an array.** `"command"` is one executable name, `"args"` the argv array. An array-valued `"command"` (e.g. `["bash", "…"]`) is **silently ignored** — the hook never fires. Claude Code substitutes `${CLAUDE_PROJECT_DIR}` (and `${CLAUDE_PLUGIN_ROOT}`) into `command` and each `args` element; anchor every script path on it, because hooks run in Claude's *current* directory, which moves on `cd`. For the same reason every seeded script runs `cd "${CLAUDE_PROJECT_DIR:-.}"` first. `timeout` is seconds; each entry sets its own: 10 s guards/loggers, 30 s comment scan, 60 s typecheck, 120 s `SubagentStop`, 300 s `Stop` test run.

**Secret `Read` denies — explicit variants, not a `.env.*` catch-all.** A `Read(...)` deny also blocks `Edit`/`Write` on that path, so `Read(**/.env.*)` would lock the committed `.env.example`/`.env.default`. The list names the secret-bearing variants (`.env`, `.env.local`, `.env.*.local`, `.env.development`, `.env.production`, `.env.staging`, `.env.test`), key material (`*.pem`, `*.key`) and `secrets/`/`.secrets/`. Other `.env*` names stay **write**-blocked by `protect-files.sh` (exempts only `.env.example`/`.env.default`); a project keeping secrets in another variant (e.g. `.env.qa`) adds a matching `Read(**/.env.qa)` deny. Never add `Edit`/`Write` denies for CI or governance files — `protect-files.sh` asks there, and a deny would block the approved edit. Precedence is deny > ask > allow; `Bash` rules match the command string and are not a security boundary — hooks and the git/CI layers enforce.

**Optional: OS-level sandbox (opt-in, not seeded).** `"sandbox": { "enabled": true }` confines `Bash` only and can break networked installs (`pnpm install`, `pip install`) and Docker until allowed domains/paths are configured — read the Claude Code sandboxing docs first, and add a filesystem deny for `.env*`/`secrets/` there if the schema supports it.

**Build-artefact `Read` denies** ship in the copied `settings.json` (`node_modules`, `.next`, `dist`, `coverage`, `.turbo`, `*.tsbuildinfo` for TS; `.venv`, `__pycache__`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `htmlcov`, `dist` for FastAPI). Generated and dependency dirs burn context; `.gitignore` keeps them out of search, these also block opening them.

Hook logic lives in `.claude/hooks/` scripts (copied by Step 0), self-contained — the harness keeps enforcing if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write|NotebookEdit) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `secrets/` and `.secrets/` directories, and cert/credential files; requires human approval (`permissionDecision: "ask"`) before writing CI/CD pipeline definitions (`.github/workflows/`, `.github/actions/`, `.azuredevops/`, any `azure-pipelines/` folder, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/*`, `.claude/agents/*`, `.mcp.json`, `Dockerfile`, the harness verifier, `ci-gates.sh` and the dependency-audit allowlist `.claude/dep-audit-allow.txt`). Case-insensitive match on a canonicalised project-relative path (leading `./` stripped, symlinked parents resolved). Fails closed (exit 2) if it cannot reach the project root.
- `block-no-verify.sh` (PreToolUse Bash) — splits the command on `&&` `||` `;` `|` and evaluates each git invocation (including `git -C <dir> …`, `/usr/bin/git`, `bash -c "…"`): blocks `--no-verify` on `commit`/`push`/`merge`/`am`/`rebase`/`cherry-pick`, `-n` only as a `git commit` short flag (`git log -n`, `grep -n` pass), the equivalent hook-layer bypasses (`LEFTHOOK=0`/`LEFTHOOK_EXCLUDE`, `git -c core.hooksPath=…`, `git config core.hooksPath …`, `--no-verify` aliases), direct commits to protected branches (`main`/`uat`/`develop`), force-push or delete of a protected branch (`--force`, `--force-with-lease`, `--force-if-includes`, `-f`, `+refspec`, `HEAD:main`), `git checkout`/`restore` that would discard guard-layer files (`.claude/`, `lefthook.yml`, `.github/`, etc.), and `rm -rf` on source dirs. Best-effort tripwire — obfuscation can evade it; lefthook + CI are the backstop.
- `user-prompt-guard` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs with embedded credentials — loopback hosts `localhost`/`127.0.0.1`/`[::1]` exempt as local-dev defaults). FastAPI: `.py` / TS stacks: `.cjs`.
- `post-edit-typecheck.sh` (PostToolUse) — incremental type feedback, filtered to source-file edits in-script. Type errors return as `hookSpecificOutput.additionalContext`. Never blocks; exit 0 always. See delta table for typecheck command.
- `post-edit-comment-check.sh` (PostToolUse) — flags change-narration comments and oversized comment blocks, filtered to source-file edits in-script; patterns come from `.claude/comment-hygiene-patterns.txt`. Feedback via `additionalContext`; exit 0 always.
- `skill-usage-log.sh` (PostToolUse `Skill`) — silently logs each skill invocation (`tool_input.skill`) to `.claude/skill-usage.log` (gitignored). Feeds `/skill-audit`. Exit 0 always.
- `stop-checks.sh` (Stop) — runs the test suite when the working tree has uncommitted changes; exit 2 forces a fix before the turn ends. See delta table for test command. Its `stop_hook_active` guard exits early on a re-run, and Claude Code caps consecutive Stop continuations (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, default 8), so a failing suite cannot loop forever.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted changes so it can't hand back broken code; skips re-runs (`stop_hook_active`) and the read-only `Explore`/`Plan` agents.
- `session-context.sh` (SessionStart: startup/resume/clear/compact) — re-injects the constitution + universal invariants (AGENTS.md comes from the `@AGENTS.md` import). SessionStart also covers resume and startup, so it is the single seeded re-injection path (not PostCompact).
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**Project-local guards — extra hooks, never edits to canonical ones.** A re-sync overwrites seeded hooks, so a project rule (a protected `sit` branch, an extra credential pattern) goes in its own script under `.claude/hooks/local/` with its own `settings.json` entry on the same event and matcher. Any matching hook that blocks (exit 2) or asks wins, so a local hook can only tighten. Re-sync never touches `.claude/hooks/local/` or its entries, `protect-files.sh` asks before edits there, and Step E hashes those scripts — a human blesses each change with `regen-harness.sh`.

---

## Step B. Create hook scripts

Step 0 already copied the 7 per-stack scripts (`protect-files.sh`, `block-no-verify.sh`, `user-prompt-guard.cjs`/`.py`, `post-edit-typecheck.sh`, `post-edit-comment-check.sh`, `stop-checks.sh`, `subagent-stop.sh`) from `template-ts/` or `template-py/`, and the stack-agnostic files below from `template/`.

**Why JSON output, not `echo`:** a `PostToolUse` hook's plain stdout goes to the debug log only. A finding must be emitted as `hookSpecificOutput.additionalContext` to reach the model; both PostToolUse scripts do, truncating below its 10,000-character cap.

**Scope:** narration scanning covers `#`/`//` lines and the opening line of a `"""`/`/** ` doc-comment block, not multi-line docstring bodies.

`.claude/comment-hygiene-patterns.txt` (identical across stacks — the one pattern list the hook, the `comment-hygiene` lefthook command and the CI job read at runtime). Step 0 copies it from `<skill-dir>/shared/template/.claude/comment-hygiene-patterns.txt`.
The first 10 lines are change-narration keyword patterns spelling both cases per letter, so use `grep -Ef`/`grep -qEf`, never `-Eif` (`-i` with the last two patterns matches text like `exit-2`). The last 3 (date, ticket, issue) are lower-precision (`ABC-123` vs. `UTF-8`): the CI hard gate reads only the first 10; the two warn-only surfaces read all 13.

---

`.claude/hooks/session-context.sh` (identical across all stacks — canonical). Step 0 copies it from `<skill-dir>/shared/template/.claude/hooks/session-context.sh`.

`.claude/hooks/skill-usage-log.sh` (identical across all stacks — silent skill-usage logger; parses JSON with `node`, falling back to `python3`). Step 0 copies it from `<skill-dir>/shared/template/.claude/hooks/skill-usage-log.sh`.

The stack `.gitignore` already ignores `.claude/skill-usage.log` (per-developer telemetry).

The hook scripts are already executable: the copy sets each file's mode from `template.manifest`, so no `chmod` is needed.

---

## Step B2. Seed the git-hook layer (lefthook + gitleaks)

The `.claude/hooks/*` above guard the agent. This step seeds **git** hooks that guard *every* committer at commit/push time, via **lefthook** (one Go binary; installs from `pnpm add -D lefthook` or `pip install lefthook`, so it works on FastAPI where Husky cannot). This is the **hard-local** layer (format, lint, typecheck, secret-scan, conventional-commit message); coverage and changed-line gates run in CI.

`lefthook.yml` is the variant copy Step 0 placed in the project (`template-ts/` or `template-py/`); follow the variant file's **Step B2** re-sync note. The stack-agnostic files below came from `template/`.

`.lefthook/commit-msg.sh` (identical across stacks — Conventional Commits gate; lefthook passes the message-file path as `{1}`). Step 0 copies it from `<skill-dir>/shared/template/.lefthook/commit-msg.sh`.

`.gitleaks.toml` (identical across stacks — extends the built-in ruleset; allowlist is for FALSE POSITIVES only, never real secrets). Step 0 copies it from `<skill-dir>/shared/template/.gitleaks.toml`.

**Install wiring:**
- **TS stacks** — verify that `package.json` (copied from the stack's `template/` tree) lists `lefthook` in `devDependencies` and has the `"prepare": "lefthook install || true"` script, and add whichever is missing (`prepare` runs after every `pnpm install`, so hooks self-install on clone; `|| true` keeps Docker builds without `.git` from failing). Freshen the `lefthook` pin with the review utility.
- **FastAPI** — `requirements-dev.txt` (copied from the stack's `template/` tree) already lists `lefthook` (the PyPI package installs the Go binary); run `lefthook install` once after installing it, and document that in the README setup steps.
- **gitleaks** is a system binary, not a package dependency. The pre-commit command (`gitleaks git --pre-commit --staged` — the v8.19+ form; `gitleaks protect`/`detect` are deprecated) skips only when it is absent (CI is the hard gate) and fails the commit on a finding when present; document `brew install gitleaks` / the release binary in the README. A reviewed false positive goes in `.gitleaksignore` (one finding fingerprint per line) or the `[[allowlists]]` table above — never a real secret.

`.lefthook/commit-msg.sh` is already executable from the copy, as are `.claude/verify-harness.sh` and `.claude/regen-harness.sh`.

---

## Step B3. Seed the CI quality gates (GitHub Actions or Azure Pipelines)

CI is the **hard gate** that can't be skipped before merge. Seed the gate script plus one CI file for the host: **changed-line coverage**, **lockfile-in-sync**, **changelog-touched**, **readme-freshness**, and a **dependency-audit** gate. (For GitLab CI, call the same `ci-gates.sh` gates from `.gitlab-ci.yml`.)

**Coverage reporter:** `diff-cover` reads Cobertura XML, which both runners emit.
- **TS stacks** — the Vitest coverage reporters must include `cobertura` (the scaffold's `vitest.config.ts` already does; keep global thresholds lenient or unset, since the diff gate enforces *changed* lines): `coverage: { provider: 'v8', reporter: ['text', 'cobertura'] }` → writes `coverage/cobertura-coverage.xml`.
- **FastAPI** — run pytest with `--cov=src --cov-report=xml` → writes `coverage.xml`.

**Pick the CI host.** A scaffold uses the host settled in `templatecentral:scaffold` Step 1. Otherwise read it from `git remote get-url origin` (and any existing pipeline files): **GitHub** (default) → seed `.github/workflows/ci.yml` (the copy further down in this step). **Azure DevOps** (`dev.azure.com` / `visualstudio.com` remote, or an `azure-pipelines/` folder or `azure-pipelines*.yml` already present) → never `ci.yml` (a GitHub workflow never runs on Azure Repos). First check what the existing pipelines run, including shared templates they `extends:` or `template:`: if they already run a gitleaks scan, the harness check (`verify-harness`) and a dependency audit that fails on high/critical advisories, seed **neither** `azure-pipelines/templatecentral-gates.yml` **nor** `.claude/ci-gates.sh` (Step 0 already copied `.claude/ci-gates.sh`; the `TC_CI=none` run below deletes it) — a file no pipeline runs is dead weight. If they run the first two but no dependency audit, seed `.claude/ci-gates.sh` and add a `bash .claude/ci-gates.sh deps` step to the existing pipeline. Otherwise seed both **and** wire the template into the PR pipeline in the same change (a pipeline edit, so `protect-files.sh` asks the human); never leave it unwired. A fresh scaffold has no pipeline of its own, so the `TC_CI=azure` copy below ships one already wired: `azure-pipelines.yml` at the project root, which includes the template. Both hosts call the same `.claude/ci-gates.sh`, so the gate logic lives once.

Copy the CI file for the picked host with `tc-copy.sh` (`harness-kit.md` Step 0): `TC_STACK=<stack> TC_PART=ci TC_CI=<github|azure> bash "<skill-dir>/shared/tc-copy.sh" "<target>"`, with `STACK` the value used in Step 0. It derives the trees (`github-ts` or `github-py` for GitHub by stack; for Azure, `azure` for every stack plus `azure-ts` or `azure-py` by stack), refuses an unknown value, and refuses unless `lefthook.yml` in the project is the one Step 0 copied for that `STACK`. The `TC_PART=ci` runs of the copy script are scaffold-only: `migrate` copies the CI file by hand (see its Phase 4 Step 4d).

When the paragraph above says to seed neither CI file, run the same script with `TC_PART=ci` and `TC_CI=none` (`TC_STACK=<stack> TC_PART=ci TC_CI=none bash "<skill-dir>/shared/tc-copy.sh" "<target>"`): it copies nothing and deletes `.claude/ci-gates.sh` (placed by Step 0) only when it is byte for byte the template's copy, so the project holds exactly what a seed-neither scaffold always held. It refuses when the file differs or is a symlink.

`.github/workflows/ci.yml` — TS stacks (nestjs / nextjs / vite-react). The copy above places it from `<skill-dir>/shared/template-ci/github-ts/.github/workflows/ci.yml`.

`azure-pipelines/templatecentral-gates.yml` — Azure DevOps (steps template, every stack). The copy above places it from `<skill-dir>/shared/template-ci/azure/azure-pipelines/templatecentral-gates.yml`.

`azure-pipelines.yml` — Azure DevOps starter pipeline (PR and `main` builds), placed by the same copy from `<skill-dir>/shared/template-ci/azure-ts/azure-pipelines.yml` (TS stacks) or `<skill-dir>/shared/template-ci/azure-py/azure-pipelines.yml` (FastAPI). It mirrors the GitHub `quality` job: a full-history checkout, the runtime, the install (`pnpm install --frozen-lockfile`, or pip with `uv` when `uv.lock` exists), then `- template: azure-pipelines/templatecentral-gates.yml` after the install so the `deps` gate finds its tools, then lint, typecheck, tests with coverage, and the `diff-cover` changed-line gate. Like `.github/workflows/ci.yml`, it is part of the enforcement layer: `.claude/harness.json` records its hash, so dropping the `template:` line shows as drift. Grow it (deploy stages, more branches) with human approval and bless the change with `regen-harness.sh`. Create the pipeline in Azure DevOps from this existing YAML file, and add a build-validation branch policy on `main` so PRs run it. The agent pool needs `pipx` on PATH (Microsoft-hosted Ubuntu images have it).

The template needs `refs/remotes/origin/<target>` (Azure PR builds fetch every branch by default; a `fetchFilter` or `fetchTags`-only setup must keep it), and the PR-only gates fail closed without it. It carries only the harness gates: the including pipeline keeps the install / lint / typecheck / test steps. When an existing pipeline includes it instead of the starter, add `pipx run diff-cover <cobertura.xml> --compare-branch="origin/${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}" --fail-under=80` after its test step for the changed-line coverage gate. Wiring the `template:` line into an existing pipeline is a pipeline edit, so `protect-files.sh` asks the human first.

`.claude/ci-gates.sh` (identical across stacks and CI hosts — the PR merge gates both `.github/workflows/ci.yml` and `azure-pipelines/templatecentral-gates.yml` call). Step 0 copies it from `<skill-dir>/shared/template/.claude/ci-gates.sh`.

**The comment gate reads added lines only**, so pre-existing narration in migrated projects does not fail every PR; the warn-only surfaces scan whole files.

**The readme gates skip CI folders (`.github/`, `.azuredevops/`, `azure-pipelines/`), `.claude/`, and secrets dirs:** `documentation-kit.md` never seeds a README there.

**FastAPI:** the GitHub workflow is `template-ci/github-py/` (its Python `quality` job replaces the TS one; the `changelog`, `readme-freshness`, and `comment-hygiene` jobs are identical); `harness-kit-fastapi.md` **Step B3** describes it.

**Notes:**
- **Pin tactics:** caret floors + committed lockfile; `pnpm install --frozen-lockfile` in `ci.yml` is the lockfile-in-sync gate. No caret ban.
- **SHA-pin the actions** (`actions/checkout`, `setup-node`, `setup-python`, `pnpm/action-setup`) to the full commit SHA with the version in a trailing comment; let Dependabot/Renovate (or the review utility) bump them — never hand-type a SHA.
- **pnpm version comes from `packageManager`** — `pnpm/action-setup` gets no `version:` input. pnpm 12 needs `pnpm/action-setup` `>= v6.1.0`; pin that release's SHA, not `@v6`. After bumping `packageManager`, run a plain `pnpm install` and commit `pnpm-lock.yaml`, or the frozen install fails with `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE`. Disable frozen mode with `--no-frozen-lockfile` (pnpm 12 removed `--frozen-lockfile false`).
- **`actions/setup-python` v7** has no `pip-install` input — dependencies install in the explicit `Install deps` step; `cache: pip` keys the cache on `requirements*.txt`.
- **gitleaks runs as the CLI, not `gitleaks/gitleaks-action`** (the action needs a paid `GITLEAKS_LICENSE` on org repos). The version and SHA-256 live once, in `ci-gates.sh` (`secrets` gate) — bump both together from the release's `gitleaks_<version>_checksums.txt`; `sha256sum -c` fails the job on any mismatch. A PR scans only its own commits (`origin/<base>..HEAD` — correct on the synthetic merge checkout GitHub and Azure DevOps PR builds both use; do not add `--first-parent`, which follows the base side of that merge and scans nothing); a push to `main` scans full history. Both need `fetch-depth: 0`. Exit code 1 on any finding fails the job; `--redact` keeps secrets out of the log.
- **Push protection is the third secret layer** (a repo setting, not a seeded file — tell the user to enable it in repo settings): free on public GitHub repos; private repos need GitHub Secret Protection, Azure Repos need GitHub Advanced Security for Azure DevOps.
- **Repository settings to tell the user about** (settings, not seeded files): require peer review before merge, require signed commits, and block direct pushes to the default branch, each where the host supports it.
- **Dependency audit (`deps` gate):** runs on every PR and every push to `main`, takes no base branch and has no label bypass. A `pnpm-lock.yaml` runs `pnpm audit --json --prod` and fails on any `high` or `critical` advisory; every Python source present is audited as well, so one ecosystem never masks another: a `uv.lock` is exported with `uv export --frozen --no-dev --no-emit-project --no-emit-workspace` (the hash-pinned export is then audited by pip-audit with `--no-deps --disable-pip`) and each `requirements*.txt` is audited by pip-audit directly, so an empty lock cannot mask a vulnerable requirements file. pip-audit reports no severity, so every known vulnerability it finds fails the gate. The pip-audit version is pinned once, in `ci-gates.sh` (`PIP_AUDIT_VERSION`). The gate needs the project's package manager (`pnpm` or `uv`) and, for Python, `pipx` on PATH, so on Azure include the template after the pipeline's install steps; the FastAPI `quality` job installs `uv` when `uv.lock` exists. An audit that covered no packages fails ("dependency audit covered no packages"), and so does a pip-audit dependency it skips (not on PyPI, private index, editable install): it was not audited and cannot be allowlisted. The gate fails closed: a missing tool, a network failure or output it cannot parse fails the job instead of passing. Each blocked line reads `<package>: <ids> (<severity>)`, with severity `n/a` for pip-audit. The only suppression is `.claude/dep-audit-allow.txt` (optional, human-approved like the gate script): one `<GHSA|CVE|PYSEC id> <YYYY-MM-DD> <reason>` entry per line, `#` for comments. An advisory matches on any of its ids; pnpm's JSON carries only the GHSA id (no CVE field), so a pnpm advisory is allowlisted by its GHSA id, while a pip-audit advisory matches its PYSEC, GHSA or CVE id. An entry fails the gate on or after its expiry date and is malformed when the expiry is more than 180 days out, so a suppression has to be renewed on purpose. pnpm's own suppression settings (`auditConfig`, `ignoreGhsas`, `ignoreCves`, an `audit.ignore` list in `pnpm-workspace.yaml`, `package.json` or `.npmrc`) bypass that expiry, so the gate rejects them and points at the allowlist. The advisory database is live, so a PR can start failing on its own; upgrade, or allowlist with a short expiry and the reason.
- Every job sets `timeout-minutes`.
- **Optional scanners a project may add to its own CI** (not seeded, not gates; optional for the template, though a project's own security requirements may make them mandatory): a container image scan, a Dockerfile lint, static analysis, and signing of build artefacts.
- CI config (`.github/workflows/`, `azure-pipelines/`) needs human approval before any agent edit (`protect-files.sh` asks).

---

## Step B4. Seed the harness integrity verifier

A SHA-256 **tamper/drift sensor** over the `origin_hash` values in `harness.json` for the **enforcement layer** (hooks, `settings.json`, lefthook, gitleaks, CI). It does **not** verify living docs (`AGENTS.md`, `CLAUDE.md`, the verify skills). To bless an intentional enforcement change, a **human** runs the regen script — never an agent, which would mask the drift this catches.

`.claude/verify-harness.sh` (portable bash — works on every stack via a jq/node/python3 fallback). Step 0 copies it from `<skill-dir>/shared/template/.claude/verify-harness.sh`.

`.claude/regen-harness.sh` (human-run only — re-blesses the baseline). Step 0 copies it from `<skill-dir>/shared/template/.claude/regen-harness.sh`.

**Wiring (already present in the copied files; verify, do not add):**
- **CI** — the `quality` job of `.github/workflows/ci.yml` and the Azure steps template each run `bash .claude/verify-harness.sh` (the hard gate — drift fails the PR).
- **pre-push** — `lefthook.yml` has a `harness-integrity` pre-push command that runs `bash .claude/verify-harness.sh`.
- **protect the manifest** — `protect-files.sh` already asks before an agent edits `.claude/harness.json`, `.claude/verify-harness.sh` or `.claude/regen-harness.sh`, so an agent cannot silently rewrite the baseline or the verifier.

If any of the three is missing from a copy, stop and report it: the template files are the source, so a missing line means the copy or the template is damaged.

---

## Step B5. Seed the `/skill-audit` project skill (skill capture)

The **consumer** of `skill-usage-log.sh` (Step B): an on-demand project skill (never automatic; no nagging) that surfaces repeated workflows not yet committed as a project skill, then helps author one.

`.claude/skills/skill-audit/SKILL.md` (stored as `SKILL.md.tmpl`) is a real file under `<skill-dir>/shared/template-late/`; `tc-copy.sh` copies it with `TC_PART=late` at Step C, together with `FUTURE.md` and `docs/CONSTITUTION.md`.

Track it in `harness.json` (Step E) alongside the other seeded skills.

---
