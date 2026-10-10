<!-- ref: scaffold/shared/harness-kit-enforcement.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table) and the stack's variant file (harness-kit-ts.md or harness-kit-fastapi.md) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — enforcement layer (Steps A–B5, every stack)

Stack-agnostic half of Steps A, B, and B2, plus all of B3–B5. Per-stack bodies are in the variant file (`harness-kit-ts.md` / `harness-kit-fastapi.md`); step order and the delta table are in `harness-kit.md`.

---

## Step A. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (below). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present, but **replace** any existing entry for one of these `.claude/hooks/` scripts whose `"command"` is a JSON array or whose path lacks `${CLAUDE_PROJECT_DIR}` (those never ran — see the hook-form note below), and drop any leftover `PostToolUseFailure` → `post-tool-failure.sh` entry from older seeds (no longer shipped: Claude already sees tool errors).

**`.claude/settings.json`** — write the variant file's **Step A** body, then apply the rules below.

**Hook entry form — string `command` + `args`, never an array.** Every hook above uses Claude Code's exec form: `"command"` is a single executable name and `"args"` is the argv array. An array-valued `"command"` (a JSON list such as `["bash", "…"]` in place of the string) is **silently ignored** by Claude Code — the hook never fires and nothing reports it — so always write string `command` + `args`. Claude Code substitutes `${CLAUDE_PROJECT_DIR}` (and `${CLAUDE_PLUGIN_ROOT}`) into `command` and each `args` element; anchor every script path on it, because hooks execute in Claude's *current* directory, which moves whenever Claude `cd`s into a subdirectory. The same reason makes every seeded script `cd "${CLAUDE_PROJECT_DIR:-.}"` first, so relative paths (`AGENTS.md`, `.claude/comment-hygiene-patterns.txt`, `.venv`) resolve. `timeout` is in seconds; the defaults (600 s for command hooks, 30 s for `UserPromptSubmit`) are far longer than these guards need, so each entry sets its own: 10 s for the guards/loggers, 30 s for the comment scan, 60 s for the typecheck, 120 s for `SubagentStop`, 300 s for the `Stop` test run.

**Secret `Read` denies — explicit variants, not a `.env.*` catch-all.** A `Read(...)` deny also blocks `Edit`/`Write` on the same path in current Claude Code, so a catch-all `Read(**/.env.*)` would make the committed `.env.example`/`.env.default` templates uneditable. The deny list therefore names the conventional secret-bearing variants (`.env`, `.env.local`, `.env.*.local`, `.env.development`, `.env.production`, `.env.staging`, `.env.test`) plus key material (`*.pem`, `*.key`) and the `secrets/`/`.secrets/` directories. Every other `.env*` name stays **write**-blocked by `protect-files.sh` (which exempts only `.env.example`/`.env.default`); if the project keeps secrets in another variant (e.g. `.env.qa`), add a matching `Read(**/.env.qa)` deny. Never add `Edit`/`Write` denies for CI or governance files — `protect-files.sh` asks there, and a deny would block the approved edit too. Permission precedence is deny > ask > allow, and `Bash` permission rules are pattern matches on the command string, not a security boundary — the hooks and the git/CI layers are the enforcement.

**Optional: OS-level sandbox (opt-in, not seeded).** For defence in depth, a project can add `"sandbox": { "enabled": true }` to `settings.json`. It confines `Bash` commands only (not `Read`/`Edit`/`Write`, which the deny list and `protect-files.sh` cover) and can break networked installs (`pnpm install`, `pip install`) and Docker until the allowed domains/paths are configured — consult the Claude Code sandboxing docs for the filesystem/network keys before enabling it, and add a filesystem deny for `.env*`/`secrets/` there if the schema supports it.

**Build-artefact `Read` denies** — also add these to `permissions.deny`, per stack. Generated/dependency dirs burn Claude's context if it greps or opens them; committing the denies gives every developer the same noise reduction (Anthropic, *How Claude Code Works in Large Codebases*). `.gitignore` already keeps gitignored paths out of *search* — these also block *opening* them and cover any checked-in artefacts.

| Stack | Add to `permissions.deny` |
|---|---|
| Next.js | `Read(./**/node_modules/**)`, `Read(./**/.next/**)`, `Read(./**/dist/**)`, `Read(./**/coverage/**)`, `Read(./**/.turbo/**)`, `Read(./**/*.tsbuildinfo)` |
| NestJS · Vite + React | `Read(./**/node_modules/**)`, `Read(./**/dist/**)`, `Read(./**/coverage/**)`, `Read(./**/.turbo/**)`, `Read(./**/*.tsbuildinfo)` |
| FastAPI | `Read(./**/.venv/**)`, `Read(./**/__pycache__/**)`, `Read(./**/.pytest_cache/**)`, `Read(./**/.ruff_cache/**)`, `Read(./**/.mypy_cache/**)`, `Read(./**/htmlcov/**)`, `Read(./**/dist/**)` |

Hook logic lives in `.claude/hooks/` scripts (seeded below) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write|NotebookEdit) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `secrets/` and `.secrets/` directories, and cert/credential files; requires human approval (`permissionDecision: "ask"`) before writing CI/CD pipeline definitions (`.github/workflows/`, `.github/actions/`, `.azuredevops/`, any `azure-pipelines/` folder, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/*`, `.claude/agents/*`, `.mcp.json`, `Dockerfile`, the harness verifier and `ci-gates.sh`). Matching is case-insensitive (`.ENV`, `dockerfile`) and runs on a canonicalised project-relative path (leading `./` stripped, symlinked parents such as macOS `/tmp` → `/private/tmp` resolved). Fails closed (exit 2) if it cannot reach the project root. Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — splits the command on `&&` `||` `;` `|` and evaluates each git invocation (including `git -C <dir> …`, `/usr/bin/git`, `bash -c "…"`): blocks `--no-verify` on `commit`/`push`/`merge`/`am`/`rebase`/`cherry-pick`, `-n` only as a `git commit` short flag (`git log -n`, `grep -n` pass), the equivalent hook-layer bypasses (`LEFTHOOK=0`/`LEFTHOOK_EXCLUDE`, `git -c core.hooksPath=…`, `git config core.hooksPath …`, `--no-verify` aliases), direct commits to protected branches (`main`/`uat`/`develop`), force-push or delete of a protected branch (`--force`, `--force-with-lease`, `--force-if-includes`, `-f`, `+refspec`, `HEAD:main`), `git checkout`/`restore` that would discard guard-layer files (`.claude/`, `lefthook.yml`, `.github/`, etc.), and `rm -rf` on source dirs. A best-effort tripwire — shell obfuscation can evade any pattern guard; lefthook + CI are the backstop.
- `user-prompt-guard` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs with embedded credentials — loopback hosts `localhost`/`127.0.0.1`/`[::1]` exempt as local-dev defaults). FastAPI: `.py` / TS stacks: `.cjs`.
- `post-edit-typecheck.sh` (PostToolUse) — incremental type feedback, filtered to source-file edits in-script. Type errors are returned as `hookSpecificOutput.additionalContext` JSON (plain stdout on a PostToolUse hook only reaches the debug log). Never blocks; exit 0 always. See delta table for typecheck command.
- `post-edit-comment-check.sh` (PostToolUse) — flags change-narration comments and oversized comment blocks, filtered to source-file edits in-script; patterns come from `.claude/comment-hygiene-patterns.txt`. Feedback via `additionalContext`; exit 0 always.
- `skill-usage-log.sh` (PostToolUse `Skill`) — silently logs each skill invocation (`tool_input.skill`) to `.claude/skill-usage.log` (gitignored, per-developer). Feeds `/skill-audit`, which surfaces repeated workflows worth capturing as a committed project skill. Never blocks (exit 0 always).
- `stop-checks.sh` (Stop) — runs the test suite when the working tree has uncommitted changes; exit 2 forces a fix before the turn ends. See delta table for test command. Claude Code caps consecutive Stop-hook continuations (8 by default, configurable via the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var), and the script's `stop_hook_active` guard exits early on a re-run, so a persistently failing suite cannot loop forever.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted changes so it can't hand back broken code; skips re-runs (`stop_hook_active`) and the read-only `Explore`/`Plan` agents.
- `session-context.sh` (SessionStart: startup/resume/clear/compact) — re-injects AGENTS.md routing context + universal invariants. PostCompact fires after compaction and its stdout is injected as context too — both PostCompact and SessionStart(source: compact) are valid re-injection mechanisms, but SessionStart also covers session resume and startup, so it stays the single seeded path here.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**Project-local guards — extra hooks, never edits to canonical ones.** A re-sync overwrites the seeded hook scripts, so a project rule (a protected `sit` branch, an extra credential pattern, an approval prompt for `src/auth.ts`) goes in its own script under `.claude/hooks/local/` with its own `settings.json` entry on the same event and matcher. Claude Code runs every matching hook, and any one blocking (exit 2) or asking wins, so a local hook can only tighten the canonical guards. Re-sync never touches `.claude/hooks/local/` or the `settings.json` entries pointing at it, `protect-files.sh` still asks before edits there, and Step E hashes those scripts like any other hook — so a human blesses each local-guard change with `regen-harness.sh`, exactly as for canonical hooks.

---

## Step B. Create hook scripts

Write the 7 per-stack scripts from the variant file's **Step B** (`protect-files.sh`, `block-no-verify.sh`, `user-prompt-guard.cjs`/`.py`, `post-edit-typecheck.sh`, `post-edit-comment-check.sh`, `stop-checks.sh`, `subagent-stop.sh`), then the stack-agnostic files below.

**Why JSON output, not a plain `echo`:** a `PostToolUse` hook's plain stdout on exit 0 is written to the debug log only — it is never shown to Claude or the user (the exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`). To actually surface a finding, the hook must emit `hookSpecificOutput.additionalContext`, which Claude Code inserts into the model's context at the point the hook fired — the same mechanism this repo's own `skills/add/redaction` hook already uses. A bare `echo` here would make this entire tier silently inert. `post-edit-typecheck.sh` uses the same mechanism for its type errors. (`additionalContext` is capped at 10,000 characters, so both scripts truncate their findings well below that.)

**Scoping note:** narration scanning covers plain `#`/`//` lines and the opening line of a `"""`/`/** ` doc-comment block (the common single-line case, e.g. `"""Refactored to support X."""`). Deep multi-line docstring *body* scanning (continuation lines with no per-line marker) is out of scope for this pass.

**`.claude/comment-hygiene-patterns.txt`** (identical across stacks — the canonical pattern list every comment-hygiene surface above, and the `comment-hygiene` lefthook command and CI job seeded later in this kit, read at runtime instead of hardcoding their own copy):
```
^[Ww][Aa][Ss][[:space:]]
^[Aa][Dd][Dd][Ee][Dd][[:space:]]
^[Rr][Ee][Mm][Oo][Vv][Ee][Dd][[:space:]]
^[Cc][Hh][Aa][Nn][Gg][Ee][Dd][[:space:]]
^[Uu][Pp][Dd][Aa][Tt][Ee][Dd][[:space:]]
^[Rr][Ee][Nn][Aa][Mm][Ee][Dd][[:space:]]
^[Mm][Oo][Vv][Ee][Dd][[:space:]]
^[Rr][Ee][Ff][Aa][Cc][Tt][Oo][Rr][Ee][Dd][[:space:]]
^[Pp][Ee][Rr] [Rr][Ee][Vv][Ii][Ee][Ww]
^[Aa][Ss] [Rr][Ee][Qq][Uu][Ee][Ss][Tt][Ee][Dd]
[0-9]{4}-[0-9]{2}-[0-9]{2}
^[A-Z]{2,}-[0-9]+
^#[0-9]+
```
The first 10 lines are the anchored change-narration keyword patterns (each spells out both cases per letter via bracket expressions — `grep -Ef`/`grep -qEf` is correct everywhere; never `-Eif`, since `-i` combined with the last two patterns would match ordinary lowercase text like `exit-2`). The last 3 lines (date, ticket-reference, issue-reference) are lower-precision — real tickets and legitimate technical terms (`ABC-123` vs. `UTF-8`) can be structurally identical, so the CI hard gate later in this kit reads only the first 10 lines; the two warn-only surfaces read all 13.

---

**`.claude/hooks/session-context.sh`** (identical across all stacks — canonical):
```bash
#!/usr/bin/env bash
# SessionStart(startup|resume|clear|compact) — re-inject routing context + universal invariants.
# Plain stdout is added to Claude's context (per Claude Code hooks docs); this is what survives compaction.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
echo "=== templateCentral routing context ==="
head -30 AGENTS.md 2>/dev/null

# If a CONSTITUTION.md exists, re-inject it (project binding invariants survive compaction)
if [ -f docs/CONSTITUTION.md ]; then
  echo ""
  echo "=== Project invariants (docs/CONSTITUTION.md) ==="
  cat docs/CONSTITUTION.md
fi

cat <<'EOF'

## Always-on invariants (survive compaction)
1. Secrets are never read or written by the agent — .env*, secrets/** and .secrets/** are guarded.
2. Run the quality gate (typecheck + tests) before declaring any task done.
3. Work on a feature branch — never commit directly to main/uat/develop.
4. Protected files — AGENTS.md, CLAUDE.md, Dockerfile, .claude/settings.json, .claude/hooks/*, docs/CONSTITUTION.md — require human approval.
5. Respect the architecture/dependency boundaries documented in AGENTS.md and docs/CONSTITUTION.md.
EOF
```

**`.claude/hooks/skill-usage-log.sh`** (identical across all stacks — silent skill-usage logger; parses JSON with `node`, falling back to `python3`):
```bash
#!/usr/bin/env bash
# PostToolUse(Skill) — silent skill-usage logger. Records which skills are invoked so the
# /skill-audit skill can later surface workflows worth capturing as a committed project skill.
# Silent + non-blocking: always exits 0, never interrupts. Log is per-developer (gitignored).
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
# Real JSON parse (a regex misreads values containing `}`): node on TS stacks, python3 on FastAPI.
if command -v node >/dev/null 2>&1; then
  name=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const s=((JSON.parse(b||'{}')||{}).tool_input||{}).skill;if(typeof s==='string')process.stdout.write(s)}catch(e){}})" 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  name=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    s=(json.load(sys.stdin).get('tool_input') or {}).get('skill')
except Exception:
    s=None
sys.stdout.write(s if isinstance(s, str) else '')" 2>/dev/null)
else
  exit 0
fi
name=$(printf '%s' "$name" | head -1 | tr -d '\t\r')
[ -z "$name" ] && exit 0
[ -d .claude ] || exit 0
printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" >> .claude/skill-usage.log 2>/dev/null
exit 0
```

Add `.claude/skill-usage.log` to the project `.gitignore` — it is per-developer telemetry, not shared state.

Make all hook scripts executable:
```bash
chmod +x .claude/hooks/*.sh
```

---

## Step B2. Seed the git-hook layer (lefthook + gitleaks)

The `.claude/hooks/*` above are **Claude-Code** hooks (they guard the agent). This step seeds **git** hooks that guard *every* committer — agent or human — at commit/push time. Uses **lefthook** (a single Go binary, no Node/Python runtime lock-in) so the same hook model works on the TS stacks **and** FastAPI. This is the **hard-local** layer (format, lint, typecheck, secret-scan, conventional-commit message); coverage and changed-line gates run in CI (warn-local, hard-CI — see the seeded CI workflow).

> **Why lefthook, not Husky:** Husky needs a Node runtime, so it cannot run in a Python-only FastAPI scaffold. lefthook installs from either ecosystem (`pnpm add -D lefthook` or `pip install lefthook`) and runs hook commands in parallel.

**`lefthook.yml`** — write the variant file's **Step B2** body (and follow its re-sync note), then the stack-agnostic files below.

**`.lefthook/commit-msg.sh`** (identical across stacks — Conventional Commits gate; lefthook passes the message-file path as `{1}`):
```bash
#!/usr/bin/env bash
# Conventional Commits gate. Invoked by lefthook commit-msg with the message file as $1.
set -euo pipefail
msg=$(head -1 "$1")

# Allow git-generated subjects (merge, revert, autosquash) and release commits.
if printf '%s' "$msg" | grep -qE '^(Merge |Revert |fixup! |squash! |amend! )' || [[ "$msg" == "chore(release):"* ]]; then
  exit 0
fi

pattern='^(feat|fix|chore|docs|style|refactor|test|ci|perf|build|revert)(\([a-z0-9/._-]+\))?!?: .{1,100}$'
if ! printf '%s' "$msg" | grep -qE "$pattern"; then
  {
    echo "❌ Commit message must follow Conventional Commits:"
    echo "   <type>(<scope>)!: <description>   e.g.  feat(auth): add OAuth2 sign-in   (! marks a breaking change)"
    echo "   types: feat fix chore docs style refactor test ci perf build revert"
    echo "   your message: $msg"
  } >&2
  exit 1
fi
```

**`.gitleaks.toml`** (identical across stacks — extends the built-in ruleset; allowlist is for FALSE POSITIVES only, never real secrets):
```toml
[extend]
useDefault = true

[[allowlists]]
description = "Known non-secrets"
paths = [
  '''\.env\.example$''',
  '''\.env\.default$''',
  '''(^|/)(pnpm-lock\.yaml|package-lock\.json|poetry\.lock|uv\.lock)$''',
]
```

**Install wiring:**
- **TS stacks** — add `lefthook` to `devDependencies` and a `"prepare": "lefthook install || true"` script to `package.json` (the `prepare` script runs after every `pnpm install`, so hooks self-install on clone; the `|| true` keeps Docker builds — which exclude `.git` via `.dockerignore` — from failing, since `lefthook install` hard-errors when no `.git` is present and has no built-in graceful skip). Freshen the `lefthook` pin with the review utility.
- **FastAPI** — add `lefthook` to `requirements-dev.txt` (it is an official PyPI package — `pip install lefthook` installs the Go binary, no Node needed) and run `lefthook install` once after install; document it in the README setup steps. *(Verified: `pip install lefthook` → 2.x, `lefthook validate` passes, hooks fire.)*
- **gitleaks** is a system binary, not a package dependency. The pre-commit command (`gitleaks git --pre-commit --staged` — the v8.19+ form; `gitleaks protect`/`detect` are deprecated) skips only when it is absent (CI is the hard gate) and fails the commit on a finding when present; document `brew install gitleaks` / the release binary in the README. A reviewed false positive goes in `.gitleaksignore` (one finding fingerprint per line) or the `[[allowlists]]` table above — never a real secret.

Then create the lefthook commit-msg script executable:
```bash
chmod +x .lefthook/commit-msg.sh
```

---

## Step B3. Seed the CI quality gates (GitHub Actions or Azure Pipelines)

The git hooks above are the **warn-local** layer; CI is the **hard gate** that can't be skipped before merge. Seed the gate script plus one CI file for the host, enforcing what the hooks only warn about: **changed-line coverage**, **lockfile-in-sync**, a **changelog-touched** gate, and a **readme-freshness** gate. (GitHub Actions and Azure Pipelines are seeded; for GitLab CI, call the same `ci-gates.sh` gates from `.gitlab-ci.yml`.)

**Coverage reporter (so `diff-cover` has input):** `diff-cover` reads a Cobertura XML, which both runners emit — one gate works for every stack.
- **TS stacks** — add `cobertura` to the Vitest coverage reporters (keep global thresholds lenient or unset; the diff gate enforces *changed* lines): `coverage: { provider: 'v8', reporter: ['text', 'cobertura'] }` → writes `coverage/cobertura-coverage.xml`.
- **FastAPI** — run pytest with `--cov=src --cov-report=xml` → writes `coverage.xml`.

**Pick the CI host** from `git remote get-url origin` (and any existing pipeline files): **GitHub** (default) → seed `.github/workflows/ci.yml` below. **Azure DevOps** (`dev.azure.com` / `visualstudio.com` remote, or an `azure-pipelines/` folder or `azure-pipelines*.yml` already present) → seed `azure-pipelines/templatecentral-gates.yml` instead and never `ci.yml` (a GitHub workflow never runs on Azure Repos). Both call the same `.claude/ci-gates.sh`, so the gate logic lives once.

**`.github/workflows/ci.yml`** — TS stacks (nestjs / nextjs / vite-react):
```yaml
name: CI
on:
  pull_request: { branches: [main, uat, develop] }
  push: { branches: [main] }
permissions: { contents: read }
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  quality:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1 — SHA-pinned per Skills Security; re-verify/bump via the review utility, don't hand-edit
        with: { fetch-depth: 0 }    # diff-cover needs full history
      - uses: pnpm/action-setup@ea17c68df8912ef543352723c149a84f56e3d413 # v6.1.0 — no `version:`; reads packageManager from package.json
      - uses: actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0
        with: { node-version: "24", cache: pnpm }
      - run: pnpm install --frozen-lockfile     # lockfile-in-sync gate
      - name: Harness integrity
        run: bash .claude/verify-harness.sh
      - run: pnpm run check                      # format:check + lint + typecheck
      - run: pnpm exec vitest --run --coverage    # writes coverage/cobertura-coverage.xml
      - name: Changed-line coverage (>= 80%)
        env:
          BASE_REF: ${{ github.base_ref }}
        run: pipx run diff-cover coverage/cobertura-coverage.xml --compare-branch="origin/${BASE_REF:-main}" --fail-under=80
      - name: Secret scan (gitleaks CLI, checksum-verified)   # PR: the PR's commits; push: full history
        env:
          BASE_REF: ${{ github.base_ref }}
        run: bash .claude/ci-gates.sh secrets "$BASE_REF"
  changelog:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0 }
      - name: Require CHANGELOG for src changes (apply 'skip-changelog' label to bypass)
        env:
          BASE_REF: ${{ github.base_ref }}
          LABELS: "${{ join(github.event.pull_request.labels.*.name, ' ') }}"
        run: bash .claude/ci-gates.sh changelog "$BASE_REF"
  readme-freshness:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0 }
      - name: Require README.md update for changed folders (apply 'skip-readme-check' label to bypass)
        env:
          BASE_REF: ${{ github.base_ref }}
          LABELS: "${{ join(github.event.pull_request.labels.*.name, ' ') }}"
        run: bash .claude/ci-gates.sh readme "$BASE_REF"
  comment-hygiene:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with: { fetch-depth: 0 }
      - name: Require no change-narration comments (apply 'skip-comment-check' label to bypass)
        env:
          BASE_REF: ${{ github.base_ref }}
          LABELS: "${{ join(github.event.pull_request.labels.*.name, ' ') }}"
        run: bash .claude/ci-gates.sh comments "$BASE_REF"
```

**`azure-pipelines/templatecentral-gates.yml`** — Azure DevOps (steps template, every stack):
```yaml
# templateCentral merge gates. Include from the PR pipeline after a full-history checkout:
#   - checkout: self
#     fetchDepth: 0
#   - template: templatecentral-gates.yml   # path is relative to the including file
# Bypass a PR-only gate by queueing the run with variable LABELS=skip-changelog (or skip-readme-check / skip-comment-check).
steps:
  - bash: bash .claude/verify-harness.sh
    displayName: Harness integrity
  - bash: bash .claude/ci-gates.sh secrets "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"
    displayName: Secret scan (gitleaks CLI, checksum-verified)
  - bash: bash .claude/ci-gates.sh changelog "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"
    displayName: Changelog gate
    env: { LABELS: $(LABELS) }
  - bash: bash .claude/ci-gates.sh readme "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"
    displayName: README freshness gate
    env: { LABELS: $(LABELS) }
  - bash: bash .claude/ci-gates.sh comments "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}"
    displayName: Comment hygiene gate
    env: { LABELS: $(LABELS) }
```

The template needs `refs/remotes/origin/<target>` (Azure PR builds fetch every branch by default; a `fetchFilter` or `fetchTags`-only setup must keep it), and the PR-only gates fail closed without it. It carries only the harness gates: the project's own pipeline keeps its install / lint / typecheck / test steps. Add `pipx run diff-cover <cobertura.xml> --compare-branch="origin/${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}" --fail-under=80` after its test step for the changed-line coverage gate. Wiring the `template:` line into the PR pipeline is a pipeline edit, so `protect-files.sh` asks the human first.

**`.claude/ci-gates.sh`** (identical across stacks and CI hosts — the PR merge gates both `.github/workflows/ci.yml` and `azure-pipelines/templatecentral-gates.yml` call):
```bash
#!/usr/bin/env bash
# CI merge gates shared by GitHub Actions and Azure Pipelines.
# Usage: ci-gates.sh <secrets|changelog|readme|comments> [base-branch]
# An empty base-branch scans full history (secrets) or skips the PR-only gates.
# LABELS: space-separated PR labels; skip-changelog / skip-readme-check / skip-comment-check bypass a gate.
set -uo pipefail
gate=${1:-}
branch=${2:-}
branch=${branch#refs/heads/}
base="origin/$branch"

fail() {
  if [ -n "${TF_BUILD:-}" ]; then echo "##vso[task.logissue type=error]$1"; else echo "::error::$1"; fi
  exit 1
}
bypassed() {
  case " ${LABELS:-} " in *" $1 "*) echo "$1 label present — OK"; return 0 ;; esac
  return 1
}
pr_only() {
  [ -n "$branch" ] || { echo "$gate: not a pull request — skipped"; exit 0; }
  git rev-parse --verify -q "$base^{commit}" >/dev/null || fail "$base not found — check out with full history (fetch-depth 0)"
}

case "$gate" in
  secrets)
    GITLEAKS_VERSION="8.30.1"   # bump VERSION and SHA256 together, from the release's gitleaks_<version>_checksums.txt
    GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"   # gitleaks_<version>_linux_x64.tar.gz
    if ! command -v gitleaks >/dev/null 2>&1; then
      tmp=$(mktemp -d "${RUNNER_TEMP:-${AGENT_TEMPDIRECTORY:-${TMPDIR:-/tmp}}}/gitleaks.XXXXXX")
      curl -fsSL -o "$tmp/gitleaks.tar.gz" "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" || fail "gitleaks download failed"
      echo "${GITLEAKS_SHA256}  $tmp/gitleaks.tar.gz" | sha256sum -c - || fail "gitleaks checksum mismatch"
      tar -xzf "$tmp/gitleaks.tar.gz" -C "$tmp" gitleaks || fail "gitleaks install failed"
      PATH="$tmp:$PATH"   # no sudo: works on hosted and self-hosted Linux x64 agents
    fi
    if [ -n "$branch" ]; then
      gitleaks git --redact --no-banner --log-opts="$base..HEAD" || fail "gitleaks found secrets in this PR's commits"
    else
      gitleaks git --redact --no-banner || fail "gitleaks found secrets in history"
    fi
    ;;
  changelog)
    pr_only
    changed=$(git diff --name-only "$base"...HEAD) || fail "cannot diff against $base"
    # Here-strings, not pipes: under pipefail, grep -q exiting early would SIGPIPE printf and flip the result.
    if grep -qE '^src/' <<< "$changed" && ! grep -qx 'CHANGELOG.md' <<< "$changed"; then
      bypassed skip-changelog && exit 0
      fail "src/ changed but CHANGELOG.md was not updated. Add an entry or apply the 'skip-changelog' label."
    fi
    ;;
  readme)
    pr_only
    tmp=$(mktemp)
    git diff --name-only "$base"...HEAD > "$tmp" || fail "cannot diff against $base"
    missing=""
    while IFS= read -r f; do
      case "$f" in */README.md|README.md) continue ;; esac
      # documentation-kit.md never writes a README into these folders, so never demand one
      case "$f" in .github/*|.azuredevops/*|azure-pipelines/*|*/azure-pipelines/*|.claude/*|*/.claude/*|secrets/*|*/secrets/*|.secrets/*|*/.secrets/*) continue ;; esac
      d=$(dirname "$f")
      rm_path="README.md"
      [ "$d" != "." ] && rm_path="$d/README.md"
      grep -qxF "$rm_path" "$tmp" || missing="$missing\n  - $d/"
    done < "$tmp"
    rm -f "$tmp"
    missing=$(printf '%b' "$missing" | sort -u)
    if [ -n "$missing" ]; then
      bypassed skip-readme-check && exit 0
      printf '%s\n' "$missing"
      fail "Folders changed without updating their README.md (listed above). Update them or apply the 'skip-readme-check' label."
    fi
    ;;
  comments)
    pr_only
    patterns=".claude/comment-hygiene-patterns.txt"
    [ -f "$patterns" ] || fail "comment-hygiene pattern list missing ($patterns)"
    strict_patterns=$(mktemp)
    head -n 10 "$patterns" > "$strict_patterns"
    nl=$(printf '\nx'); nl=${nl%x}
    flagged=""
    while IFS= read -r -d '' f; do
      case "$f" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py) ;; *) continue ;; esac
      [ -f "$f" ] || continue
      while IFS= read -r content; do
        stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|//|\*|"""|/\*\*?)[[:space:]]?@@')
        if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$strict_patterns"; then
          flagged="$flagged$nl  - $f: $stripped"
        fi
      done < <(git diff -U0 "$base"...HEAD -- "$f" | grep '^+' | grep -vE '^\+\+\+' | sed 's/^+//' | grep -E '^[[:space:]]*(#|//|\*|"""|/\*\*?)')
    done < <(git diff -z --name-only "$base"...HEAD)
    rm -f "$strict_patterns"
    if [ -n "$flagged" ]; then
      bypassed skip-comment-check && exit 0
      printf '%s\n' "$flagged"
      fail "Change-narration comments found (listed above). State WHAT the code does now, or apply the 'skip-comment-check' label."
    fi
    ;;
  *)
    echo "usage: ci-gates.sh <secrets|changelog|readme|comments> [base-branch]" >&2
    exit 2
    ;;
esac
exit 0
```

**Why only the first 10 pattern lines gate CI:** the date / ticket / issue patterns also match legitimate comment openers (`UTF-8`, `SHA-256`, `RFC-7231`), a false-positive rate a blocking gate cannot carry; the warn-only hook and lefthook command still read all 13.

**Why only added lines:** a PR touching a file with pre-existing narration (common in `templatecentral:migrate`-adopted projects) would otherwise fail forever and train everyone to apply the bypass label. The warn-only surfaces scan whole files — a nudge about old comments is harmless there.

**Why the readme gates skip CI folders (`.github/`, `.azuredevops/`, `azure-pipelines/`), `.claude/`, and secrets dirs:** `documentation-kit.md` never seeds a README there (`protect-files.sh` blocks or gates those writes), so demanding one would fail every harness or CI change.

**FastAPI:** replace the `quality` job above with the variant file's **Step B3** block (`harness-kit-fastapi.md`); the `changelog`, `readme-freshness`, and `comment-hygiene` jobs are identical.

**Notes:**
- **Pin tactics:** the pinning model stays caret-floors + committed lockfile; `pnpm install --frozen-lockfile` above is the lockfile-in-sync gate (fails CI if the lockfile is stale). No caret ban.
- **SHA-pin the actions** (`actions/checkout`, `setup-node`, `setup-python`, `pnpm/action-setup`) to the full commit SHA of the current major for supply-chain hygiene, with the version in a trailing comment; let Dependabot/Renovate (or the review utility) bump them — never hand-type a SHA.
- **pnpm version comes from `packageManager`** in `package.json` — `pnpm/action-setup` is given no `version:` input so CI can never drift from the pinned pnpm. pnpm 12 needs `pnpm/action-setup` ≥ v6.1.0 (the floating `v6` tag lagged behind v6.1.0, so pin the v6.1.0+ SHA rather than `@v6`). The lockfile records the package manager too: after bumping `packageManager`, run a plain `pnpm install` and commit `pnpm-lock.yaml`, or the frozen install fails with `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE`. To disable frozen mode use `--no-frozen-lockfile` (pnpm 12 removed `--frozen-lockfile false`).
- **`actions/setup-python` v7** has no `pip-install` input — dependencies install in the explicit `Install deps` step; `cache: pip` keys the cache on `requirements*.txt`.
- **gitleaks runs as the CLI, not `gitleaks/gitleaks-action`:** the action needs a paid `GITLEAKS_LICENSE` secret on organization-owned repos; the CLI is MIT, needs no key or token, and is the same current scanner (upstream calls gitleaks feature-complete; its maintainer's successor is Betterleaks — note only). The version and SHA-256 live once, in `ci-gates.sh` (`secrets` gate) — bump both together from the release's `gitleaks_<version>_checksums.txt`; `sha256sum -c` fails the job on any mismatch. A PR scans only its own commits (`origin/<base>..HEAD` — correct on the synthetic merge checkout GitHub and Azure DevOps PR builds both use; do NOT add `--first-parent`, which follows the base side of that merge and scans nothing); a push to `main` scans full history. Both need `fetch-depth: 0`. Exit code 1 on any finding fails the job; `--redact` keeps secrets out of the log.
- **Push protection is the third secret layer** (after the pre-commit hook and this CI scan): the host rejects a push containing a recognised secret before it lands. Enable it in repo settings — free on public GitHub repos; private repos need GitHub Secret Protection, and Azure Repos need GitHub Advanced Security for Azure DevOps. It is a setting, not a seeded file.
- Every job sets `timeout-minutes` so a hung step can't hold a runner for the 6-hour default.
- CI config (`.github/workflows/`, `azure-pipelines/`) needs human approval before any agent edit (`protect-files.sh` asks) — CI is human-reviewed by design.

---

## Step B4. Seed the harness integrity verifier

`harness.json` records an `origin_hash` for every seeded file but nothing *checks* it. This step closes that loop with a **tamper/drift sensor** over the **enforcement layer** (hooks, `settings.json`, lefthook, gitleaks, CI) — the files that should never change except by deliberate human action. It deliberately does **not** verify living docs (`AGENTS.md`, `CLAUDE.md`, the verify skills) — those legitimately evolve. SHA-256, read-only, deterministic (the agent never self-certifies). To bless an intentional enforcement change, a **human** runs the regen script — never an agent, which would mask the very drift this catches.

**`.claude/verify-harness.sh`** (portable bash — works on every stack via a jq/node/python3 fallback):
```bash
#!/usr/bin/env bash
# Harness integrity sensor. Recomputes sha256 of the enforcement-layer seeded files and
# compares to the origin_hash baseline in .claude/harness.json. Read-only; exits non-zero
# on drift (1) or on an unreadable/unfilled manifest (2). Wired into CI and lefthook pre-push.
# Bless intentional changes with regen-harness.sh.
set -euo pipefail
manifest=".claude/harness.json"
[ -f "$manifest" ] || { echo "verify-harness: $manifest missing" >&2; exit 2; }

# Enforcement layer only — AGENTS.md / CLAUDE.md / *-verify skills legitimately evolve.
guard='^(\.claude/hooks/|\.claude/settings\.json$|\.claude/(verify|regen)-harness\.sh$|\.claude/comment-hygiene-patterns\.txt$|lefthook\.yml$|\.lefthook/|\.gitleaks\.toml$|\.github/workflows/|\.claude/ci-gates\.sh$|azure-pipelines/templatecentral-gates\.yml$)'

sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
read_manifest() {
  if command -v jq >/dev/null 2>&1; then
    jq -er '.seeded_files | to_entries[] | "\(.value.path)\t\(.value.origin_hash)"' "$manifest"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const m=JSON.parse(require("fs").readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(m.seeded_files))console.log(v.path+"\t"+v.origin_hash)'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json;m=json.load(open(".claude/harness.json"));[print(str(v["path"])+"\t"+str(v["origin_hash"])) for v in m["seeded_files"].values()]'
  else echo "verify-harness: need jq, node, or python3" >&2; return 3; fi
}

# Capture first: a parse failure must fail the run, not silently yield zero entries.
entries=$(read_manifest) || { echo "verify-harness: cannot parse $manifest" >&2; exit 2; }

drift=0; checked=0; unfilled=0
while IFS=$'\t' read -r path origin; do
  [ -n "$path" ] || continue
  case "$origin" in ""|null|undefined|None|"<"*) echo "UNFILLED: $path (origin_hash is a placeholder)" >&2; unfilled=1; continue ;; esac
  printf '%s' "$path" | grep -qE "$guard" || continue   # enforcement layer only
  checked=$((checked + 1))
  if [ ! -f "$path" ]; then echo "MISSING:  $path" >&2; drift=1; continue; fi
  [ "$(sha "$path")" = "$origin" ] || { echo "MODIFIED: $path" >&2; drift=1; }
done <<< "$entries"

[ "$unfilled" -eq 0 ] || { echo "❌ $manifest still has unfilled origin_hash placeholders — finish Step E" >&2; exit 2; }
[ "$checked" -gt 0 ] || { echo "❌ verify-harness checked zero enforcement-layer entries — manifest empty or malformed" >&2; exit 2; }
if [ "$drift" -ne 0 ]; then
  echo "❌ harness integrity drift. If intentional, a human runs: bash .claude/regen-harness.sh" >&2
  exit 1
fi
echo "✓ harness integrity OK ($checked enforcement files)"
```

**`.claude/regen-harness.sh`** (HUMAN-RUN ONLY — re-blesses the baseline):
```bash
#!/usr/bin/env bash
# HUMAN-RUN ONLY. Rewrites origin_hash in .claude/harness.json to the current files.
# NEVER let an agent run this — regenerating the baseline masks the drift the verifier
# exists to catch. protect-files.sh requires human approval to edit harness.json itself.
set -euo pipefail
if command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),cr=require("crypto"),j=JSON.parse(fs.readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(j.seeded_files)){if(fs.existsSync(v.path))v.origin_hash=cr.createHash("sha256").update(fs.readFileSync(v.path)).digest("hex");}fs.writeFileSync(".claude/harness.json",JSON.stringify(j,null,2)+"\n");console.log("harness baseline regenerated");'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,hashlib,os;j=json.load(open(".claude/harness.json"));[v.__setitem__("origin_hash",hashlib.sha256(open(v["path"],"rb").read()).hexdigest()) for v in j["seeded_files"].values() if os.path.isfile(v["path"])];open(".claude/harness.json","w").write(json.dumps(j,indent=2)+"\n");print("harness baseline regenerated")'
else
  echo "regen-harness: need node or python3" >&2; exit 3
fi
```

```bash
chmod +x .claude/verify-harness.sh .claude/regen-harness.sh
```

**Wiring:**
- **CI** — add a step to the `quality` job in `.github/workflows/ci.yml`: `- name: Harness integrity` / `run: bash .claude/verify-harness.sh` (this is the hard gate — drift fails the PR).
- **pre-push** — add a `harness-integrity` command to `lefthook.yml` pre-push: `run: bash .claude/verify-harness.sh`.
- **protect the manifest** — add `.claude/harness.json`, `.claude/verify-harness.sh`, and `.claude/regen-harness.sh` to the `protect-files.sh` approval list (Step B) so an agent can't silently rewrite the baseline or the verifier. This is the "protect the manifest itself" safeguard — without it, drift detection is defeatable.

---

## Step B5. Seed the `/skill-audit` project skill (skill capture)

The `skill-usage-log.sh` hook (Step B) silently records which skills get used; this is its **consumer**. Seed a stack-agnostic project skill that turns the log into action — surface workflows the developer repeats but hasn't committed as a project skill, then help author one. Run **on demand** (never automatic; no nagging).

```bash
mkdir -p .claude/skills/skill-audit
```

**`.claude/skills/skill-audit/SKILL.md`**:
~~~markdown
---
name: skill-audit
description: Surface repeated workflows worth capturing as committed project skills, from the skill-usage log.
disable-model-invocation: true
allowed-tools: "Bash(awk *), Bash(sort *), Bash(cat .claude/skill-usage.log), Bash(ls .claude/skills/*)"
---

# Skill Audit

Find workflows you repeat often that aren't yet committed project skills — so the repo (and teammates) carry them, not just your session memory.

## 1. Aggregate usage
```bash
[ -f .claude/skill-usage.log ] || { echo "No skill usage logged yet."; exit 0; }
awk -F'\t' '{c[$2]++} END{for (k in c) printf "%4d  %s\n", c[k], k}' .claude/skill-usage.log | sort -rn
```

## 2. Filter to capture candidates
A skill is a **capture candidate** when it is used **≥ 2 times** AND:
- it is NOT a Claude Code built-in (`code-review`, `verify`, `run`, `init`, `review`, `security-review`, `simplify`) — those ship with the CLI, nothing to capture;
- it is NOT already a project skill — `.claude/skills/<name>/SKILL.md` does not exist (`ls .claude/skills/`).

## 3. Capture (with the user, per candidate)
- **Author a project skill** (recommended) — create `.claude/skills/<name>/SKILL.md` encoding the workflow, tuned to this project, and commit it. Do NOT vendor a third-party skill's files — write a project skill that captures the same intent (a plugin skill used often is a *signal* to author your own).
- **Skip** — note it's intentionally not captured.

Keep each new SKILL.md to one workflow, with a clear trigger description and tightly-scoped `allowed-tools`. See the `## Skill capture` norm in AGENTS.md.
~~~

Track it in `harness.json` (Step E) alongside the other seeded skills.

---
