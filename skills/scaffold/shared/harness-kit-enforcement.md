<!-- ref: scaffold/shared/harness-kit-enforcement.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table) and the stack's variant file (harness-kit-ts.md or harness-kit-fastapi.md) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — enforcement layer (Steps A–B5, every stack)

Stack-agnostic half of Steps A, B, B2, plus all of B3–B5. Per-stack bodies: the variant file (`harness-kit-ts.md` / `harness-kit-fastapi.md`); step order and delta table: `harness-kit.md`. The files named below are real files under `shared/template*/`, copied by `harness-kit.md` Step 0; entries here describe them and add wiring rules.

---

## Step A. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root plus the `.claude/hooks/` scripts it references (Step 0 copies them). `TC_PART=settings` stops when `.claude/settings.json` exists: report it, do not overwrite. Merging is `migrate`-only: merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, Stop, SubagentStop, SessionStart) and `permissions.deny` into the existing object. Keep hooks already present, but **replace** any entry for these `.claude/hooks/` scripts whose `"command"` is a JSON array or whose path lacks `${CLAUDE_PROJECT_DIR}` (those never ran), and drop any leftover `PostToolUseFailure` → `post-tool-failure.sh` entry (no longer shipped).

**`.claude/settings.json`** — run `tc-copy.sh` with `TC_PART=settings` (it copies the variant's body from `template-settings-ts/.claude/settings.json` or `template-settings-py/.claude/settings.json` under `<skill-dir>/shared/`), then apply the rules below.

**Hook entry form:** a string `"command"` plus an `"args"` array, with every script path anchored on `${CLAUDE_PROJECT_DIR}`; an array-valued `"command"` is silently ignored, so the hook never fires (lint fails any seeded settings that breaks this).

**Secret `Read` denies name the variants, not a `.env.*` catch-all.** A `Read(...)` deny also blocks `Edit`/`Write` on that path, so `Read(**/.env.*)` would lock the committed `.env.example`/`.env.default`. Other `.env*` names stay **write**-blocked by `protect-files.sh`; a project keeping secrets in another variant (e.g. `.env.qa`) adds a matching `Read(**/.env.qa)` deny. Never add `Edit`/`Write` denies for CI or governance files: `protect-files.sh` asks there, and a deny would block the approved edit. Precedence is deny > ask > allow; `Bash` rules match the command string and are not a security boundary.

**Optional: OS-level sandbox (opt-in, not seeded).** `"sandbox": { "enabled": true }` confines `Bash` only and can break networked installs (`pnpm install`, `pip install`) and Docker until allowed domains/paths are configured — read the Claude Code sandboxing docs first, and add a filesystem deny for `.env*`/`secrets/` there if the schema supports it.

**Build-artefact `Read` denies** ship in the copied `settings.json` (`node_modules`, `.next`, `dist`, `coverage`, `.turbo`, `*.tsbuildinfo` for TS; `.venv`, `__pycache__`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `htmlcov`, `dist` for FastAPI). Generated and dependency dirs burn context; `.gitignore` keeps them out of search, these also block opening them.

Hook logic lives in self-contained `.claude/hooks/` scripts (Step 0 copies them), so the harness keeps enforcing if the plugin is uninstalled; each script's header is its spec.

**Project-local guards — extra hooks, never edits to canonical ones.** A re-sync overwrites seeded hooks, so a project rule (a protected `sit` branch, an extra credential pattern) goes in its own script under `.claude/hooks/local/` with its own `settings.json` entry on the same event and matcher. Any matching hook that blocks (exit 2) or asks wins, so a local hook can only tighten. Re-sync never touches `.claude/hooks/local/` or its entries, `protect-files.sh` asks before edits there, and Step E hashes those scripts — a human blesses each change with `regen-harness.sh`.

---

## Step B. Create hook scripts

Step 0 already copied the 7 per-stack scripts and the stack-agnostic hooks (`session-context.sh`, `skill-usage-log.sh`), `.claude/comment-hygiene-patterns.txt`, `.lefthook/commit-msg.sh` and `.gitleaks.toml`. Nothing is left to create here.

`.claude/comment-hygiene-patterns.txt` is the one pattern list the hook, the `comment-hygiene` lefthook command and the CI job read. Use `grep -Ef`/`grep -qEf` on it, never `-Eif` (`-i` with the last two patterns matches text like `exit-2`). The first 10 lines are the CI hard gate; the last 3 (date, ticket, issue) are lower precision and warn only.

---

## Step B2. Seed the git-hook layer (lefthook + gitleaks)

**Install wiring:**
- **TS stacks** — verify that `package.json` (copied from the stack's `template/` tree) lists `lefthook` in `devDependencies` and has the `"prepare": "lefthook install || true"` script, and add whichever is missing (`prepare` runs after every `pnpm install`, so hooks self-install on clone; `|| true` keeps Docker builds without `.git` from failing). Freshen the `lefthook` pin with the review utility.
- **FastAPI** — `requirements-dev.txt` (copied from the stack's `template/` tree) already lists `lefthook` (the PyPI package installs the Go binary); run `lefthook install` once after installing it, and document that in the README setup steps.
- **gitleaks** is a system binary, not a package dependency. The pre-commit command (`gitleaks git --pre-commit --staged` — the v8.19+ form; `gitleaks protect`/`detect` are deprecated) skips only when it is absent (CI is the hard gate) and fails the commit on a finding when present; document `brew install gitleaks` / the release binary in the README. A reviewed false positive goes in `.gitleaksignore` (one finding fingerprint per line) or the `[[allowlists]]` table above — never a real secret.

---

## Step B3. Seed the CI quality gates (GitHub Actions or Azure Pipelines)

CI is the **hard gate** that can't be skipped before merge. Seed the gate script plus one CI file for the host: **changed-line coverage**, **lockfile-in-sync**, **changelog-touched**, a **docs check** (`scripts/check-docs.sh`, a plain script step) and a **dependency-audit** gate. (For GitLab CI, call the same `ci-gates.sh` gates from `.gitlab-ci.yml`.)

**Coverage reporter:** `diff-cover` reads Cobertura XML, which both runners emit.
- **TS stacks** — the Vitest coverage reporters must include `cobertura` (the scaffold's `vitest.config.ts` already does; the scaffold also sets a global `thresholds: { lines: 80 }` and the ratchet blocks lowering it or widening `exclude`; generated shadcn primitives in `src/components/ui` are the only exclude, because they are not written by hand): `coverage: { provider: 'v8', reporter: ['text', 'cobertura', 'lcov'] }` → writes `coverage/cobertura-coverage.xml`.
- **FastAPI** — run pytest with `--cov=src --cov-report=xml` → writes `coverage.xml`.

**Pick the CI host.** A scaffold uses the host settled in `templatecentral:scaffold` Step 1. Otherwise read it from `git remote get-url origin` and any existing pipeline files. A GitHub workflow never runs on Azure Repos, so Azure never gets `ci.yml`. Check what existing pipelines run, including shared templates they `extends:` or `template:`.

| Host and existing pipelines | Run `TC_PART=ci` with |
|---|---|
| GitHub (default) | `TC_CI=github` (`.github/workflows/ci.yml`) |
| Azure DevOps, pipelines already run gitleaks, `verify-harness` and a dependency audit failing on high/critical | `TC_CI=none` (deletes `.claude/ci-gates.sh`; a file no pipeline runs is dead weight) |
| Azure DevOps, pipelines run the first two but no dependency audit | no `TC_PART=ci` run: keep the `.claude/ci-gates.sh` Step 0 placed and add a `bash .claude/ci-gates.sh deps` step to the pipeline |
| Azure DevOps otherwise (a fresh scaffold lands here) | `TC_CI=azure`: `azure-pipelines/templatecentral-gates.yml` plus a starter `azure-pipelines.yml` that includes it; a template in an existing pipeline must be wired in the same change, never left unwired (a pipeline edit: `protect-files.sh` asks the human) |

`TC_STACK=<stack> TC_PART=ci TC_CI=<github|azure|none> bash "<skill-dir>/shared/tc-copy.sh" "<target>"` (the `harness-kit.md` Step 0 call, with the `TC_STACK` used there). The `TC_PART=ci` runs of the copy script are scaffold-only: `migrate` copies the CI file by hand (its Phase 4 Step 4d).

The Azure starter mirrors the GitHub `quality` job and is part of the enforcement layer: `.claude/harness.json` records its hash, so dropping the `template:` line shows as drift. Grow it with human approval and bless the change with `regen-harness.sh`. Create the pipeline in Azure DevOps from this YAML file and add a build-validation branch policy on `main`. The agent pool needs `pipx` on PATH (Microsoft-hosted Ubuntu images have it).

The template needs `refs/remotes/origin/<target>` (Azure PR builds fetch every branch by default; a `fetchFilter` or `fetchTags`-only setup must keep it), and the PR-only gates fail closed without it. When an existing pipeline includes the template instead of the starter, add `pipx run diff-cover <cobertura.xml> --compare-branch="origin/${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}" --fail-under=80` after its test step for the changed-line coverage gate.

**Notes:**
- `pnpm install --frozen-lockfile` in `ci.yml` is the lockfile-in-sync gate; pnpm 12 removed `--frozen-lockfile false` (use `--no-frozen-lockfile`). After bumping `packageManager`, run a plain `pnpm install` and commit `pnpm-lock.yaml`, or the frozen install fails with `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE`.
- **gitleaks runs as the CLI, not `gitleaks/gitleaks-action`** (the action needs a paid `GITLEAKS_LICENSE` on org repos). Version and SHA-256 live once, in `ci-gates.sh` (`secrets` gate): bump both together from the release's `gitleaks_<version>_checksums.txt`. A PR scans only its own commits (`origin/<base>..HEAD`; do not add `--first-parent`, which scans nothing on the synthetic merge checkout); a push to `main` scans full history. Both need `fetch-depth: 0`.
- **Push protection is the third secret layer** (a repo setting, not a seeded file — tell the user to enable it in repo settings): free on public GitHub repos; private repos need GitHub Secret Protection, Azure Repos need GitHub Advanced Security for Azure DevOps.
- **Repository settings to tell the user about** (settings, not seeded files): require peer review before merge, require signed commits, and block direct pushes to the default branch, each where the host supports it.
- **Dependency audit (`deps` gate):** runs on every PR and push to `main`, with no base branch and no label bypass. It fails closed, and its messages name what failed. The only suppression is `.claude/dep-audit-allow.txt` (optional, human-approved like the gate script): one `<GHSA|CVE|PYSEC id> <YYYY-MM-DD> <reason>` entry per line, `#` for comments; an entry fails on or after its expiry and is malformed past 180 days out. pnpm's own suppression settings are rejected. The advisory database is live, so a PR can start failing on its own: upgrade, or allowlist with a short expiry and the reason. On Azure, include the template after the install steps so the gate finds its tools.
- Every job sets `timeout-minutes`.
- **Optional scanners a project may add to its own CI** (not seeded, not gates; optional for the template, though a project's own security requirements may make them mandatory): a container image scan, a Dockerfile lint, static analysis, and signing of build artefacts.

---

## Step B4. Seed the harness integrity verifier

A SHA-256 **tamper/drift sensor** over the `origin_hash` values in `harness.json` for the **enforcement layer** (hooks, `settings.json`, lefthook, gitleaks, CI). It does **not** verify living docs (`AGENTS.md`, `CLAUDE.md`, the verify skills). To bless an intentional enforcement change, a **human** runs the regen script — never an agent, which would mask the drift this catches.

`.claude/verify-harness.sh` and `.claude/regen-harness.sh` (human-run only; re-blesses the baseline) are copied in Step 0. `gates.txt` lists where CI and `lefthook.yml` must call `verify-harness.sh`, and `protect-files.sh` asks before an agent edits `.claude/harness.json` or either script. If a copy lacks one of these, stop and report it.

---

## Step B5. Seed the `/skill-audit` project skill (skill capture)

The **consumer** of `skill-usage-log.sh` (Step B): an on-demand project skill (never automatic; no nagging) that surfaces repeated workflows not yet committed as a project skill, then helps author one.

`.claude/skills/skill-audit/SKILL.md` (stored as `SKILL.md.tmpl`) is a real file under `<skill-dir>/shared/template-late/`; `tc-copy.sh` copies it with `TC_PART=late` at Step C, together with `FUTURE.md` and `docs/CONSTITUTION.md`.

Track it in `harness.json` (Step E) alongside the other seeded skills.

---
