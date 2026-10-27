<!-- ref: scaffold/shared/harness-kit.md
     loaded-by: scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified; scaffold app+config files already written (or migrate Phase 4/5 in progress). Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit

This file is the index of the single source of truth for the Claude Code agent harness seeded into every scaffolded project. Read the **Per-stack delta table** first, then execute ALL steps in the **Step order** below using the row matching the current stack.

---

## Kit files

The kit is split by stack so a run never loads the other stack's script bodies. The loader (a scaffold stack file or a migrate phase file) cats this index plus exactly three part files — the stack's **one** variant file and both shared files:

| File | Holds | Load for |
|---|---|---|
| `harness-kit-ts.md` | TS body for Step A (`settings.json`) and the notes for Steps B, B2 (the 7 per-stack hooks incl. `user-prompt-guard.cjs`, and `lefthook.yml`, which live in `template-ts/`) | nestjs · nextjs · vite-react |
| `harness-kit-fastapi.md` | FastAPI body for Step A (`settings.json`) and the notes for Steps B, B2, B3 (the 7 per-stack hooks incl. `user-prompt-guard.py`, `lefthook.yml` and the CI `quality` job, which live in `template-py/` and `template-ci/github-py/`) | fastapi |
| `harness-kit-enforcement.md` | Step A/B/B2 shared rules + notes on the stack-agnostic files (`comment-hygiene-patterns.txt`, `session-context.sh`, `skill-usage-log.sh`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`, held in `template/`); Steps B3 (CI host pick, `ci-gates.sh`, Azure template), B4, B5 | every stack |
| `harness-kit-finalize.md` | Steps C, D, E, E2, E3, F, G, H + the shared AGENTS.md tail fragment | every stack |

## Step order

| Step | Seeds | Where |
|---|---|---|
| 0 | every template file below that is a real file: the 9 `.claude/hooks/` scripts, `.claude/ci-gates.sh`, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml` | this file — scaffold only; migrate diffs and merges instead |
| A | `.claude/settings.json` | variant (JSON body) + enforcement (merge rules, deny lists, hook inventory) |
| B | `.claude/hooks/` scripts (copied in Step 0) | notes in the variant (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`) + enforcement (`comment-hygiene-patterns.txt`, `session-context`, `skill-usage-log`, `chmod`) |
| B2 | git-hook layer (files copied in Step 0) | notes in the variant (`lefthook.yml`) + enforcement (`.lefthook/commit-msg.sh`, `.gitleaks.toml`, install wiring) |
| B3 | CI quality gates incl. dependency audit (`.claude/ci-gates.sh` from Step 0, plus the CI file copied here: `.github/workflows/ci.yml` on GitHub, or `azure-pipelines/templatecentral-gates.yml` on Azure DevOps) | enforcement (CI host pick and copy; the `deps` dependency-audit gate lives in `ci-gates.sh`) + fastapi variant (notes on the FastAPI `quality` job) |
| B4 | harness integrity verifier (`verify-harness.sh`, `regen-harness.sh`, copied in Step 0) | enforcement |
| B5 | `/skill-audit` project skill | enforcement |
| C, D | `FUTURE.md`, `docs/CONSTITUTION.md` | finalize |
| E, E2, E3 | `.claude/harness.json`, base snapshot, per-folder docs | finalize |
| F, G, H | `.agents` symlink, post-scaffold workflow, plugins | finalize |

For Step A the enforcement file's section is the step: write the variant file's `settings.json` body as part of it. Steps B and B2 only add rules and notes to the files Step 0 already copied.

---

## Step 0 — copy the template trees

Scaffold only. `migrate` never runs this step: it diffs each file under `<skill-dir>/shared/template/`, `<skill-dir>/shared/template-ts/` and `<skill-dir>/shared/template-py/` against the project and merges (see its Phase 4 and Phase 5).

Run it once, before Step A and before the first `pnpm install`, with `<target>` the project root. The app files may already be there; only the paths the copy writes must be absent. The file list is `<skill-dir>/shared/template.manifest`. Edit only the `STACK=` line, the first of the script: `nestjs`, `nextjs`, `vite-react` or `fastapi`. The script derives the template trees from it (`template` plus `template-ts` for the three TS stacks, `template-py` for fastapi) and refuses any other value, so a wrong stack cannot copy the other stack's hooks. Leave `CI=` empty and `PART=base` here; Step B3 sets them.

Substitute `<skill-dir>` and `<target>` as plain text, with no quoting or escaping: the script reads each path from a quoted heredoc, so no character in a path is expanded or run. A path must not contain a newline, and the fence cannot reliably catch one that does (a line equal to `TC_PATH` ends the heredoc early and the lines after it run). If a path contains a newline, stop and ask the user for another directory before substituting.

The script writes nothing when any check fails: the skill or target path is empty or not substituted, the target is not an existing directory, a template tree holds a symlink or an empty directory, the manifest is missing, empty or disagrees with the files in the trees (it names the files that differ, such as a stray `.DS_Store`), a file it would write already exists, or a directory it would write into is a symlink or not a directory. It then creates only the missing parent directories and copies each listed file with `cp`, giving the file the mode in the manifest. It never copies attributes onto the project root or an existing directory and never changes a mode it did not create. Every refusal and every failed copy ends with a `STOP:` line: do not `rm` or overwrite anything, and report it to the user. After a failed copy the message lists the files already written. The script runs in `bash` through a quoted heredoc, so it behaves the same from bash or zsh and a refusal ends only that child process, never the caller's shell.

```bash
bash <<'TC_GUARD'
STACK=nextjs
CI=
PART=base
WHAT="scaffold"
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
stop() { printf 'Refusing to %s: %s\nSTOP: do not rm or overwrite anything; report this to the user.\n' "$WHAT" "$1"; exit 1; }
case "$SK" in ''|*'<skill'"-dir>"*) stop "the skill directory path is empty or was not substituted" ;; esac
case "$TGT" in ''|*'<tar'"get>"*) stop "the target path is empty or was not substituted" ;; esac
case "$SK$TGT" in *"$NL"*) stop "a path ends in or contains a newline" ;; esac
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
TAB=$(printf '\t')
copied=""
while IFS="$TAB" read -r mode t p; do
  d=${p%/*}
  if [ "$d" != "$p" ]; then
    mkdir -p -- "$TGT/$d" || stop "mkdir failed for $d; files may be partly written in $TGT.${NL}Files already written:$copied"
  fi
  cp -- "$SK/$t/$p" "$TGT/$p" && chmod -- "$mode" "$TGT/$p" || stop "copy failed for $p; files may be partly written in $TGT.${NL}Files already written:$copied"
  copied="$copied$NL$p"
done <<TC_PLAN
$plan
TC_PLAN
TC_GUARD
```

The CI file is not part of this copy: Step B3 picks the host and copies it. Every later step in this kit that mentions one of these files works on the copy now in `<target>`.

---

## Per-stack delta table

| Stack | JSON-parsing runtime | Typecheck feedback cmd | Stop-checks test cmd | Verify-skill name(s) | Quality-gate line in CONSTITUTION §6 |
|-------|----------------------|------------------------|----------------------|----------------------|---------------------------------------|
| **fastapi** | `python3` | `python -m pyright src/` (errors → `additionalContext`) | `python -m pytest test/ -q` | `api-verify` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` (the `/api-verify` skill) |
| **nestjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `nest-verify` | `pnpm check` |
| **nextjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `next-verify` + `next-migrate` | `pnpm check` |
| **vite-react** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `pnpm test` | `vite-verify` | `pnpm check` |

**Additional per-stack notes:**
- `user-prompt-guard` filename: `user-prompt-guard.py` for **fastapi**; `user-prompt-guard.cjs` for all TS stacks (`.cjs`, not `.js` — the scaffold's `package.json` sets `"type": "module"` for Next.js/Vite+React, which makes plain `.js` load as ESM and `require()` throw; `.cjs` forces CommonJS regardless of that field).
- `user-prompt-guard` settings.json invocation: `"command": "python3", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/user-prompt-guard.py"]` (fastapi) vs `"command": "node", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/user-prompt-guard.cjs"]` (TS stacks).
- `harness.json` `"stack"` value: use the lowercase stack name (`fastapi` / `nestjs` / `nextjs` / `vite-react`).
- `harness.json` verify-skill path: use the stack's verify-skill name(s) from the table above (next.js has two skills).
- CLAUDE.md hash in `harness.json`: all stacks use the conditional form `[ -f CLAUDE.md ] && sha256_claude=$(...)` — CLAUDE.md is created in a later optional step.
