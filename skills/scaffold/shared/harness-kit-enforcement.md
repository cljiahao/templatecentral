<!-- ref: scaffold/shared/harness-kit-enforcement.md
     loaded-by: scaffold/shared/harness-kit.md (index — catted together with it by scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md) → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; harness-kit.md (index + delta table) and the stack's variant file (harness-kit-ts.md or harness-kit-fastapi.md) loaded. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit — enforcement layer (Steps A–B5, every stack)

Stack-agnostic half of Steps A, B, and B2, plus all of B3–B5. Per-stack bodies are in the variant file (`harness-kit-ts.md` / `harness-kit-fastapi.md`); step order and the delta table are in `harness-kit.md`. The scripts and config files named below are real files under the `template*/` directories of `shared/`; `harness-kit.md` Step 0 copies them into the project, so the entries below describe them and add the wiring rules rather than carry their text.

---

## Step A. Create `.claude/settings.json`

Create `.claude/settings.json` at the project root, plus the `.claude/hooks/` scripts it references (Step 0 copies them). If `settings.json` already exists, merge all hook entries (PreToolUse, UserPromptSubmit, PostToolUse, Stop, SubagentStop, SessionStart) and the `permissions.deny` list into the existing object rather than overwriting — preserve any hooks already present, but **replace** any existing entry for one of these `.claude/hooks/` scripts whose `"command"` is a JSON array or whose path lacks `${CLAUDE_PROJECT_DIR}` (those never ran — see the hook-form note below), and drop any leftover `PostToolUseFailure` → `post-tool-failure.sh` entry from older seeds (no longer shipped: Claude already sees tool errors).

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

Hook logic lives in `.claude/hooks/` scripts (copied by Step 0) so complex guards stay readable and testable rather than crammed into inline JSON. All are self-contained — no dependency on the templateCentral plugin, so the harness keeps enforcing even if the plugin is uninstalled.

- `protect-files.sh` (PreToolUse Edit|Write|NotebookEdit) — hard-blocks writes to `.env*` (except `.env.example`/`.env.default`), `secrets/` and `.secrets/` directories, and cert/credential files; requires human approval (`permissionDecision: "ask"`) before writing CI/CD pipeline definitions (`.github/workflows/`, `.github/actions/`, `.azuredevops/`, any `azure-pipelines/` folder, `azure-pipelines*.y[a]ml`, `.gitlab-ci.yml`, `Jenkinsfile`) and governance files (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/hooks/*`, `.claude/agents/*`, `.mcp.json`, `Dockerfile`, the harness verifier, `ci-gates.sh` and the dependency-audit allowlist `.claude/dep-audit-allow.txt`). Matching is case-insensitive (`.ENV`, `dockerfile`) and runs on a canonicalised project-relative path (leading `./` stripped, symlinked parents such as macOS `/tmp` → `/private/tmp` resolved). Fails closed (exit 2) if it cannot reach the project root. Paired with `permissions.deny` above, which blocks *reading* secrets.
- `block-no-verify.sh` (PreToolUse Bash) — splits the command on `&&` `||` `;` `|` and evaluates each git invocation (including `git -C <dir> …`, `/usr/bin/git`, `bash -c "…"`): blocks `--no-verify` on `commit`/`push`/`merge`/`am`/`rebase`/`cherry-pick`, `-n` only as a `git commit` short flag (`git log -n`, `grep -n` pass), the equivalent hook-layer bypasses (`LEFTHOOK=0`/`LEFTHOOK_EXCLUDE`, `git -c core.hooksPath=…`, `git config core.hooksPath …`, `--no-verify` aliases), direct commits to protected branches (`main`/`uat`/`develop`), force-push or delete of a protected branch (`--force`, `--force-with-lease`, `--force-if-includes`, `-f`, `+refspec`, `HEAD:main`), `git checkout`/`restore` that would discard guard-layer files (`.claude/`, `lefthook.yml`, `.github/`, etc.), and `rm -rf` on source dirs. A best-effort tripwire — shell obfuscation can evade any pattern guard; lefthook + CI are the backstop.
- `user-prompt-guard` (UserPromptSubmit) — blocks prompt-injection phrases (OWASP LLM01) and inline credentials (LLM02: AWS/GitHub/Anthropic keys, PEM blocks, DB URLs with embedded credentials — loopback hosts `localhost`/`127.0.0.1`/`[::1]` exempt as local-dev defaults). FastAPI: `.py` / TS stacks: `.cjs`.
- `post-edit-typecheck.sh` (PostToolUse) — incremental type feedback, filtered to source-file edits in-script. Type errors are returned as `hookSpecificOutput.additionalContext` JSON (plain stdout on a PostToolUse hook only reaches the debug log). Never blocks; exit 0 always. See delta table for typecheck command.
- `post-edit-comment-check.sh` (PostToolUse) — flags change-narration comments and oversized comment blocks, filtered to source-file edits in-script; patterns come from `.claude/comment-hygiene-patterns.txt`. Feedback via `additionalContext`; exit 0 always.
- `skill-usage-log.sh` (PostToolUse `Skill`) — silently logs each skill invocation (`tool_input.skill`) to `.claude/skill-usage.log` (gitignored, per-developer). Feeds `/skill-audit`, which surfaces repeated workflows worth capturing as a committed project skill. Never blocks (exit 0 always).
- `stop-checks.sh` (Stop) — runs the test suite when the working tree has uncommitted changes; exit 2 forces a fix before the turn ends. See delta table for test command. Claude Code caps consecutive Stop-hook continuations (8 by default, configurable via the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` env var), and the script's `stop_hook_active` guard exits early on a re-run, so a persistently failing suite cannot loop forever.
- `subagent-stop.sh` (SubagentStop) — type-gates a subagent's uncommitted changes so it can't hand back broken code; skips re-runs (`stop_hook_active`) and the read-only `Explore`/`Plan` agents.
- `session-context.sh` (SessionStart: startup/resume/clear/compact) — re-injects the constitution + universal invariants (AGENTS.md comes from the `@AGENTS.md` import). PostCompact fires after compaction and its stdout is injected as context too — both PostCompact and SessionStart(source: compact) are valid re-injection mechanisms, but SessionStart also covers session resume and startup, so it stays the single seeded path here.
- `skillListingBudgetFraction` — caps skill-listing context overhead at 2 % of the budget.

**Project-local guards — extra hooks, never edits to canonical ones.** A re-sync overwrites the seeded hook scripts, so a project rule (a protected `sit` branch, an extra credential pattern, an approval prompt for `src/auth.ts`) goes in its own script under `.claude/hooks/local/` with its own `settings.json` entry on the same event and matcher. Claude Code runs every matching hook, and any one blocking (exit 2) or asking wins, so a local hook can only tighten the canonical guards. Re-sync never touches `.claude/hooks/local/` or the `settings.json` entries pointing at it, `protect-files.sh` still asks before edits there, and Step E hashes those scripts like any other hook — so a human blesses each local-guard change with `regen-harness.sh`, exactly as for canonical hooks.

---

## Step B. Create hook scripts

Step 0 already copied the 7 per-stack scripts (`protect-files.sh`, `block-no-verify.sh`, `user-prompt-guard.cjs`/`.py`, `post-edit-typecheck.sh`, `post-edit-comment-check.sh`, `stop-checks.sh`, `subagent-stop.sh`) from `template-ts/` or `template-py/`, and the stack-agnostic files below from `template/`. This step adds the rules around them.

**Why JSON output, not a plain `echo`:** a `PostToolUse` hook's plain stdout on exit 0 is written to the debug log only — it is never shown to Claude or the user (the exceptions are `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, and `PostModelSwitch`). To actually surface a finding, the hook must emit `hookSpecificOutput.additionalContext`, which Claude Code inserts into the model's context at the point the hook fired — the same mechanism this repo's own `skills/add/redaction` hook already uses. A bare `echo` here would make this entire tier silently inert. `post-edit-typecheck.sh` uses the same mechanism for its type errors. (`additionalContext` is capped at 10,000 characters, so both scripts truncate their findings well below that.)

**Scoping note:** narration scanning covers plain `#`/`//` lines and the opening line of a `"""`/`/** ` doc-comment block (the common single-line case, e.g. `"""Refactored to support X."""`). Deep multi-line docstring *body* scanning (continuation lines with no per-line marker) is out of scope for this pass.

`.claude/comment-hygiene-patterns.txt` (identical across stacks — the canonical pattern list every comment-hygiene surface above, and the `comment-hygiene` lefthook command and CI job seeded later in this kit, read at runtime instead of hardcoding their own copy). Step 0 copies it from `<skill-dir>/shared/template/.claude/comment-hygiene-patterns.txt`.
The first 10 lines are the anchored change-narration keyword patterns (each spells out both cases per letter via bracket expressions — `grep -Ef`/`grep -qEf` is correct everywhere; never `-Eif`, since `-i` combined with the last two patterns would match ordinary lowercase text like `exit-2`). The last 3 lines (date, ticket-reference, issue-reference) are lower-precision — real tickets and legitimate technical terms (`ABC-123` vs. `UTF-8`) can be structurally identical, so the CI hard gate later in this kit reads only the first 10 lines; the two warn-only surfaces read all 13.

---

`.claude/hooks/session-context.sh` (identical across all stacks — canonical). Step 0 copies it from `<skill-dir>/shared/template/.claude/hooks/session-context.sh`.

`.claude/hooks/skill-usage-log.sh` (identical across all stacks — silent skill-usage logger; parses JSON with `node`, falling back to `python3`). Step 0 copies it from `<skill-dir>/shared/template/.claude/hooks/skill-usage-log.sh`.

Add `.claude/skill-usage.log` to the project `.gitignore` — it is per-developer telemetry, not shared state.

The hook scripts are already executable: the copy sets each file's mode from `template.manifest`, so no `chmod` is needed.

---

## Step B2. Seed the git-hook layer (lefthook + gitleaks)

The `.claude/hooks/*` above are **Claude-Code** hooks (they guard the agent). This step seeds **git** hooks that guard *every* committer — agent or human — at commit/push time. Uses **lefthook** (a single Go binary, no Node/Python runtime lock-in) so the same hook model works on the TS stacks **and** FastAPI. This is the **hard-local** layer (format, lint, typecheck, secret-scan, conventional-commit message); coverage and changed-line gates run in CI (warn-local, hard-CI — see the seeded CI workflow).

> **Why lefthook, not Husky:** Husky needs a Node runtime, so it cannot run in a Python-only FastAPI scaffold. lefthook installs from either ecosystem (`pnpm add -D lefthook` or `pip install lefthook`) and runs hook commands in parallel.

`lefthook.yml` is the variant copy Step 0 placed in the project (`template-ts/` or `template-py/`); follow the variant file's **Step B2** re-sync note. The stack-agnostic files below came from `template/`.

`.lefthook/commit-msg.sh` (identical across stacks — Conventional Commits gate; lefthook passes the message-file path as `{1}`). Step 0 copies it from `<skill-dir>/shared/template/.lefthook/commit-msg.sh`.

`.gitleaks.toml` (identical across stacks — extends the built-in ruleset; allowlist is for FALSE POSITIVES only, never real secrets). Step 0 copies it from `<skill-dir>/shared/template/.gitleaks.toml`.

**Install wiring:**
- **TS stacks** — verify that `package.json` (written by the stack's config-files step) lists `lefthook` in `devDependencies` and has the `"prepare": "lefthook install || true"` script, and add whichever is missing (the `prepare` script runs after every `pnpm install`, so hooks self-install on clone; the `|| true` keeps Docker builds — which exclude `.git` via `.dockerignore` — from failing, since `lefthook install` hard-errors when no `.git` is present and has no built-in graceful skip). Freshen the `lefthook` pin with the review utility.
- **FastAPI** — add `lefthook` to `requirements-dev.txt` (it is an official PyPI package — `pip install lefthook` installs the Go binary, no Node needed) and run `lefthook install` once after install; document it in the README setup steps. *(Verified: `pip install lefthook` → 2.x, `lefthook validate` passes, hooks fire.)*
- **gitleaks** is a system binary, not a package dependency. The pre-commit command (`gitleaks git --pre-commit --staged` — the v8.19+ form; `gitleaks protect`/`detect` are deprecated) skips only when it is absent (CI is the hard gate) and fails the commit on a finding when present; document `brew install gitleaks` / the release binary in the README. A reviewed false positive goes in `.gitleaksignore` (one finding fingerprint per line) or the `[[allowlists]]` table above — never a real secret.

`.lefthook/commit-msg.sh` is already executable from the copy, as are `.claude/verify-harness.sh` and `.claude/regen-harness.sh`.

---

## Step B3. Seed the CI quality gates (GitHub Actions or Azure Pipelines)

The git hooks above are the **warn-local** layer; CI is the **hard gate** that can't be skipped before merge. Seed the gate script plus one CI file for the host, enforcing what the hooks only warn about: **changed-line coverage**, **lockfile-in-sync**, a **changelog-touched** gate, and a **readme-freshness** gate, plus a **dependency-audit** gate that no hook covers. (GitHub Actions and Azure Pipelines are seeded; for GitLab CI, call the same `ci-gates.sh` gates from `.gitlab-ci.yml`.)

**Coverage reporter (so `diff-cover` has input):** `diff-cover` reads a Cobertura XML, which both runners emit — one gate works for every stack.
- **TS stacks** — add `cobertura` to the Vitest coverage reporters (keep global thresholds lenient or unset; the diff gate enforces *changed* lines): `coverage: { provider: 'v8', reporter: ['text', 'cobertura'] }` → writes `coverage/cobertura-coverage.xml`.
- **FastAPI** — run pytest with `--cov=src --cov-report=xml` → writes `coverage.xml`.

**Pick the CI host** from `git remote get-url origin` (and any existing pipeline files): **GitHub** (default) → seed `.github/workflows/ci.yml` (the copy further down in this step). **Azure DevOps** (`dev.azure.com` / `visualstudio.com` remote, or an `azure-pipelines/` folder or `azure-pipelines*.yml` already present) → never `ci.yml` (a GitHub workflow never runs on Azure Repos). First check what the existing pipelines run, including shared templates they `extends:` or `template:`: if they already run a gitleaks scan, the harness check (`verify-harness`) and a dependency audit that fails on high/critical advisories, seed **neither** `azure-pipelines/templatecentral-gates.yml` **nor** `.claude/ci-gates.sh` (Step 0 already copied `.claude/ci-gates.sh`; the fence below deletes it) — those gates are covered, and a file no pipeline runs is dead weight that reviewers rightly flag. If they run the first two but no dependency audit, seed `.claude/ci-gates.sh` and add a `bash .claude/ci-gates.sh deps` step to the existing pipeline. Otherwise seed both **and** wire the template into the PR pipeline in the same change (a pipeline edit, so `protect-files.sh` asks the human); never leave it unwired. Both hosts call the same `.claude/ci-gates.sh`, so the gate logic lives once.

Copy the CI file for the picked host. Edit only the `STACK=` line (it ships empty; use the same value as in Step 0, and the script refuses when `lefthook.yml` in the project is not the one that value's Step 0 copied) and the `CI=` line (`github` or `azure`); `PART=ci` stays; the script derives the tree (`github-ts` or `github-py` for GitHub by stack, `azure` for every stack) and refuses an unknown value. The guard, the path rules and the refusals are the ones in `harness-kit.md` Step 0. This fence and the seed-neither fence below are scaffold-only: the first refuses unless `lefthook.yml` is the copy Step 0 made, and the second assumes Step 0 placed `.claude/ci-gates.sh`. `migrate` copies the CI file by hand (see its Phase 4 Step 4d).

```bash
bash <<'TC_GUARD'
STACK=
CI=github
PART=ci
WHAT="seed CI"
NL='
'
IFS= read -r -d '' SK <<'TC_PATH'
<skill-dir>/shared
TC_PATH
SK=${SK%"$NL"}
IFS= read -r -d '' TGT <<'TC_PATH'
<target>
TC_PATH
TGT=${TGT%"$NL"}
TAB=$(printf '\t')
stop() { printf 'Refusing to %s: %s\nSTOP: do not rm or overwrite anything; report this to the user.\n' "$WHAT" "$1"; exit 1; }
case "$SK" in ''|*'<skill'"-dir>"*) stop "the skill directory path is empty or was not substituted" ;; esac
case "$TGT" in ''|*'<tar'"get>"*) stop "the target path is empty or was not substituted" ;; esac
case "$SK$TGT" in *"$NL"*) stop "a path ends in or contains a newline" ;; esac
case "$SK" in /*) ;; *) SK=./$SK ;; esac
case "$TGT" in /*) ;; *) TGT=./$TGT ;; esac
[ -d "$SK" ] || stop "$SK is not a directory"
[ -d "$TGT" ] || stop "$TGT is not an existing directory"
case "$STACK" in
  nestjs|nextjs|vite-react) V=ts ;;
  fastapi) V=py ;;
  *) stop "unknown STACK '$STACK' (want nestjs, nextjs, vite-react or fastapi)" ;;
esac
case "$PART" in
  base)
    [ -z "$CI" ] || stop "CI must stay empty in Step 0"
    SEL="template template-$V" ;;
  ci)
    case "$CI" in
      github) SEL="template-ci/github-$V" ;;
      azure) SEL="template-ci/azure" ;;
      *) stop "unknown CI '$CI' (want github or azure)" ;;
    esac ;;
  *) stop "unknown PART '$PART'" ;;
esac
for t in $SEL; do
  [ -n "$(find "$SK/$t" -type f 2>/dev/null | head -n 1)" ] || stop "no files under $SK/$t"
  [ -z "$(find "$SK/$t" \( -type l -o -type d -empty \) 2>/dev/null | head -n 1)" ] || stop "$SK/$t holds a symlink or an empty directory"
done
[ -s "$SK/template.manifest" ] || stop "$SK/template.manifest is missing or empty"
plan=$(awk -v sel="$SEL" '
  BEGIN { n = split(sel, s, " ") }
  /^#/ || NF == 0 { next }
  { for (i = 1; i <= n; i++) if (index($1, s[i] "/") == 1) { print $2 "\t" s[i] "\t" substr($1, length(s[i]) + 2); next } }
' "$SK/template.manifest")
listed=$(printf '%s\n' "$plan" | cut -f3 | LC_ALL=C sort)
found=$(for t in $SEL; do (cd "$SK/$t" && find . -type f | sed 's|^\./||'); done | LC_ALL=C sort)
if [ -z "$listed" ] || [ "$listed" != "$found" ]; then
  stop "template.manifest and the template trees ($SEL) disagree.${NL}Only in the manifest:${NL}$(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$found"))${NL}Only in the trees:${NL}$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$found"))"
fi
clash=$(printf '%s\n' "$found" | while IFS= read -r p; do
  if [ -e "$TGT/$p" ] || [ -L "$TGT/$p" ]; then echo "$p (exists)"; fi
  d=$p
  while [ "${d%/*}" != "$d" ]; do
    d=${d%/*}
    if [ -L "$TGT/$d" ]; then echo "$d (symlink)"; elif [ -e "$TGT/$d" ] && [ ! -d "$TGT/$d" ]; then echo "$d (not a directory)"; fi
  done
done | LC_ALL=C sort -u)
[ -z "$clash" ] || stop "these paths already exist, are symlinks or are not directories in $TGT:$NL$clash"
if [ "$PART" = ci ]; then
  cmp -s -- "$TGT/lefthook.yml" "$SK/template-$V/lefthook.yml" || stop "$TGT/lefthook.yml is not the one Step 0 copied for STACK=$STACK, so this STACK does not match Step 0 (or Step 0 has not run)"
fi
bad=$(printf '%s\n' "$plan" | while IFS="$TAB" read -r mode t p; do
  [ -r "$SK/$t/$p" ] || echo "$SK/$t/$p (unreadable)"
  d=$p
  if [ "${d%/*}" != "$d" ]; then d=${d%/*}; else d=; fi
  while [ -n "$d" ] && [ ! -d "$TGT/$d" ]; do
    if [ "${d%/*}" != "$d" ]; then d=${d%/*}; else d=; fi
  done
  if [ -n "$d" ]; then base="$TGT/$d"; else base="$TGT"; fi
  if [ ! -w "$base" ] || [ ! -x "$base" ]; then echo "$base (not writable or not searchable)"; fi
done | LC_ALL=C sort -u)
[ -z "$bad" ] || stop "nothing was written, because the copy would fail part way:$NL$bad"
copied=""
while IFS="$TAB" read -r mode t p; do
  d=${p%/*}
  if [ "$d" != "$p" ]; then
    mkdir -p -- "$TGT/$d" || stop "mkdir failed for $d; the copy may have created parent directories and files may be partly written in $TGT.${NL}Files already written:$copied"
  fi
  cp -- "$SK/$t/$p" "$TGT/$p" || stop "copy failed for $p; the copy may also have written a partial $p or created parent directories, so files may be partly written in $TGT.${NL}Files already written:$copied"
  copied="$copied$NL$p"
  chmod -- "$mode" "$TGT/$p" || stop "chmod failed for $p; files may be partly written in $TGT.${NL}Files already written:$copied"
done <<TC_PLAN
$plan
TC_PLAN
TC_GUARD
```

When the paragraph above says to seed neither CI file, copy nothing and delete the one file Step 0 already placed for this decision, so the project holds exactly what a seed-neither scaffold always held. The script deletes `.claude/ci-gates.sh` only when it is byte for byte the template's copy, and refuses otherwise:

```bash
bash <<'TC_RM'
WHAT="seed CI"
NL='
'
IFS= read -r -d '' SK <<'TC_PATH'
<skill-dir>/shared
TC_PATH
SK=${SK%"$NL"}
IFS= read -r -d '' TGT <<'TC_PATH'
<target>
TC_PATH
TGT=${TGT%"$NL"}
TAB=$(printf '\t')
stop() { printf 'Refusing to %s: %s\nSTOP: do not rm or overwrite anything; report this to the user.\n' "$WHAT" "$1"; exit 1; }
case "$SK" in ''|*'<skill'"-dir>"*) stop "the skill directory path is empty or was not substituted" ;; esac
case "$TGT" in ''|*'<tar'"get>"*) stop "the target path is empty or was not substituted" ;; esac
case "$SK$TGT" in *"$NL"*) stop "a path ends in or contains a newline" ;; esac
case "$SK" in /*) ;; *) SK=./$SK ;; esac
case "$TGT" in /*) ;; *) TGT=./$TGT ;; esac
[ -d "$SK" ] || stop "$SK is not a directory"
[ -d "$TGT" ] || stop "$TGT is not an existing directory"
gate=.claude/ci-gates.sh
if [ -L "$TGT/.claude" ] || [ -L "$TGT/$gate" ]; then stop "$TGT/.claude or $TGT/$gate is a symlink, so removing the file could delete something outside the project"; fi
[ -e "$TGT/$gate" ] || { echo "Nothing to remove: $TGT/$gate does not exist."; exit 0; }
[ -f "$TGT/$gate" ] || stop "$TGT/$gate is not a regular file"
cmp -s -- "$SK/template/$gate" "$TGT/$gate" || stop "$TGT/$gate differs from the template, so it is not the file Step 0 placed"
rm -f -- "$TGT/$gate" || stop "rm failed for $TGT/$gate"
TC_RM
```

`.github/workflows/ci.yml` — TS stacks (nestjs / nextjs / vite-react). The copy above places it from `<skill-dir>/shared/template-ci/github-ts/.github/workflows/ci.yml`.

`azure-pipelines/templatecentral-gates.yml` — Azure DevOps (steps template, every stack). The copy above places it from `<skill-dir>/shared/template-ci/azure/azure-pipelines/templatecentral-gates.yml`.

The template needs `refs/remotes/origin/<target>` (Azure PR builds fetch every branch by default; a `fetchFilter` or `fetchTags`-only setup must keep it), and the PR-only gates fail closed without it. It carries only the harness gates: the project's own pipeline keeps its install / lint / typecheck / test steps. Add `pipx run diff-cover <cobertura.xml> --compare-branch="origin/${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}" --fail-under=80` after its test step for the changed-line coverage gate. Wiring the `template:` line into the PR pipeline is a pipeline edit, so `protect-files.sh` asks the human first.

`.claude/ci-gates.sh` (identical across stacks and CI hosts — the PR merge gates both `.github/workflows/ci.yml` and `azure-pipelines/templatecentral-gates.yml` call). Step 0 copies it from `<skill-dir>/shared/template/.claude/ci-gates.sh`.

**Why only the first 10 pattern lines gate CI:** the date / ticket / issue patterns also match legitimate comment openers (`UTF-8`, `SHA-256`, `RFC-7231`), a false-positive rate a blocking gate cannot carry; the warn-only hook and lefthook command still read all 13.

**Why only added lines:** a PR touching a file with pre-existing narration (common in `templatecentral:migrate`-adopted projects) would otherwise fail forever and train everyone to apply the bypass label. The warn-only surfaces scan whole files — a nudge about old comments is harmless there.

**Why the readme gates skip CI folders (`.github/`, `.azuredevops/`, `azure-pipelines/`), `.claude/`, and secrets dirs:** `documentation-kit.md` never seeds a README there (`protect-files.sh` blocks or gates those writes), so demanding one would fail every harness or CI change.

**FastAPI:** the GitHub workflow is `template-ci/github-py/` (its Python `quality` job replaces the TS one; the `changelog`, `readme-freshness`, and `comment-hygiene` jobs are identical); `harness-kit-fastapi.md` **Step B3** describes it.

**Notes:**
- **Pin tactics:** the pinning model stays caret-floors + committed lockfile; `pnpm install --frozen-lockfile` in the copied `ci.yml` is the lockfile-in-sync gate (fails CI if the lockfile is stale). No caret ban.
- **SHA-pin the actions** (`actions/checkout`, `setup-node`, `setup-python`, `pnpm/action-setup`) to the full commit SHA of the current major for supply-chain hygiene, with the version in a trailing comment; let Dependabot/Renovate (or the review utility) bump them — never hand-type a SHA.
- **pnpm version comes from `packageManager`** in `package.json` — `pnpm/action-setup` is given no `version:` input so CI can never drift from the pinned pnpm. pnpm 12 needs `pnpm/action-setup` ≥ v6.1.0 (the floating `v6` tag lagged behind v6.1.0, so pin the v6.1.0+ SHA rather than `@v6`). The lockfile records the package manager too: after bumping `packageManager`, run a plain `pnpm install` and commit `pnpm-lock.yaml`, or the frozen install fails with `ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE`. To disable frozen mode use `--no-frozen-lockfile` (pnpm 12 removed `--frozen-lockfile false`).
- **`actions/setup-python` v7** has no `pip-install` input — dependencies install in the explicit `Install deps` step; `cache: pip` keys the cache on `requirements*.txt`.
- **gitleaks runs as the CLI, not `gitleaks/gitleaks-action`:** the action needs a paid `GITLEAKS_LICENSE` secret on organization-owned repos; the CLI is MIT, needs no key or token, and is the same current scanner (upstream calls gitleaks feature-complete; its maintainer's successor is Betterleaks — note only). The version and SHA-256 live once, in `ci-gates.sh` (`secrets` gate) — bump both together from the release's `gitleaks_<version>_checksums.txt`; `sha256sum -c` fails the job on any mismatch. A PR scans only its own commits (`origin/<base>..HEAD` — correct on the synthetic merge checkout GitHub and Azure DevOps PR builds both use; do NOT add `--first-parent`, which follows the base side of that merge and scans nothing); a push to `main` scans full history. Both need `fetch-depth: 0`. Exit code 1 on any finding fails the job; `--redact` keeps secrets out of the log.
- **Push protection is the third secret layer** (after the pre-commit hook and this CI scan): the host rejects a push containing a recognised secret before it lands. Enable it in repo settings — free on public GitHub repos; private repos need GitHub Secret Protection, and Azure Repos need GitHub Advanced Security for Azure DevOps. It is a setting, not a seeded file.
- **Dependency audit (`deps` gate):** runs on every PR and every push to `main`, takes no base branch and has no label bypass. A `pnpm-lock.yaml` runs `pnpm audit --json --prod` and fails on any `high` or `critical` advisory; every Python source present is audited as well, so one ecosystem never masks another: a `uv.lock` is exported with `uv export --frozen --no-dev --no-emit-project --no-emit-workspace` (the hash-pinned export is then audited by pip-audit with `--no-deps --disable-pip`) and each `requirements*.txt` is audited by pip-audit directly, so an empty lock cannot mask a vulnerable requirements file. pip-audit reports no severity, so every known vulnerability it finds fails the gate. The pip-audit version is pinned once, in `ci-gates.sh` (`PIP_AUDIT_VERSION`). The gate needs the project's package manager (`pnpm` or `uv`) and, for Python, `pipx` on PATH, so on Azure include the template after the pipeline's install steps; the FastAPI `quality` job installs `uv` when `uv.lock` exists. An audit that covered no packages fails ("dependency audit covered no packages"), and so does a pip-audit dependency it skips (not on PyPI, private index, editable install): it was not audited and cannot be allowlisted. The gate fails closed: a missing tool, a network failure or output it cannot parse fails the job instead of passing. Each blocked line reads `<package>: <ids> (<severity>)`, with severity `n/a` for pip-audit. The only suppression is `.claude/dep-audit-allow.txt` (optional, human-approved like the gate script): one `<GHSA|CVE|PYSEC id> <YYYY-MM-DD> <reason>` entry per line, `#` for comments. An advisory matches on any of its ids; pnpm's JSON carries only the GHSA id (no CVE field), so a pnpm advisory is allowlisted by its GHSA id, while a pip-audit advisory matches its PYSEC, GHSA or CVE id. An entry fails the gate on or after its expiry date and is malformed when the expiry is more than 180 days out, so a suppression has to be renewed on purpose. pnpm's own suppression settings (`auditConfig`, `ignoreGhsas`, `ignoreCves`, an `audit.ignore` list in `pnpm-workspace.yaml`, `package.json` or `.npmrc`) bypass that expiry, so the gate rejects them and points at the allowlist. The audit queries a live advisory database, so a PR can start failing without any change of its own; fix it by upgrading, or allowlist the advisory with a short expiry and the reason.
- Every job sets `timeout-minutes` so a hung step can't hold a runner for the 6-hour default.
- CI config (`.github/workflows/`, `azure-pipelines/`) needs human approval before any agent edit (`protect-files.sh` asks) — CI is human-reviewed by design.

---

## Step B4. Seed the harness integrity verifier

`harness.json` records an `origin_hash` for every seeded file but nothing *checks* it. This step closes that loop with a **tamper/drift sensor** over the **enforcement layer** (hooks, `settings.json`, lefthook, gitleaks, CI) — the files that should never change except by deliberate human action. It deliberately does **not** verify living docs (`AGENTS.md`, `CLAUDE.md`, the verify skills) — those legitimately evolve. SHA-256, read-only, deterministic (the agent never self-certifies). To bless an intentional enforcement change, a **human** runs the regen script — never an agent, which would mask the very drift this catches.

`.claude/verify-harness.sh` (portable bash — works on every stack via a jq/node/python3 fallback). Step 0 copies it from `<skill-dir>/shared/template/.claude/verify-harness.sh`.

`.claude/regen-harness.sh` (HUMAN-RUN ONLY — re-blesses the baseline). Step 0 copies it from `<skill-dir>/shared/template/.claude/regen-harness.sh`.


**Wiring (already present in the copied files; verify, do not add):**
- **CI** — the `quality` job of `.github/workflows/ci.yml` and the Azure steps template each run `bash .claude/verify-harness.sh` (the hard gate — drift fails the PR).
- **pre-push** — `lefthook.yml` has a `harness-integrity` pre-push command that runs `bash .claude/verify-harness.sh`.
- **protect the manifest** — `protect-files.sh` already asks before an agent edits `.claude/harness.json`, `.claude/verify-harness.sh` or `.claude/regen-harness.sh`, so an agent cannot silently rewrite the baseline or the verifier.

If any of the three is missing from a copy, stop and report it: the template files are the source, so a missing line means the copy or the template is damaged.

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
