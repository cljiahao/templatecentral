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

Run it once, before Step A, with `<target>` the (empty) project root. The file list is `<skill-dir>/shared/template.manifest`. Set `SEL` to `template template-ts` for nestjs, nextjs and vite-react, or `template template-py` for fastapi, and keep exactly one of the last two `cp` lines. The guard runs first and stops without writing anything when the manifest is missing, empty or disagrees with the files in the selected trees, when any file the copy writes already exists in `<target>`, or when any directory the copy writes into (`.claude`, `.claude/hooks`, `.lefthook`, ...) is a symlink there. Every `cp` stops the step if it fails. The fence hands its script to `bash` through a quoted heredoc, so it behaves the same from bash or zsh (zsh does not split `$SEL`) and a refusal ends only that child process, never the caller's shell. `cp -Rp` with the trailing `/.` keeps dotfiles and the exec bit.

```bash
bash <<'TC_GUARD'
SEL="template template-ts"
SK="<skill-dir>/shared"
TGT="<target>"
for t in $SEL; do
  [ -n "$(find "$SK/$t" -type f 2>/dev/null | head -n 1)" ] || { echo "Refusing to scaffold: no files under $SK/$t"; exit 1; }
done
[ -s "$SK/template.manifest" ] || { echo "Refusing to scaffold: $SK/template.manifest is missing or empty"; exit 1; }
listed=$(awk -v sel="$SEL" '
  BEGIN { n = split(sel, s, " ") }
  /^#/ || NF == 0 { next }
  { for (i = 1; i <= n; i++) if (index($1, s[i] "/") == 1) { print substr($1, length(s[i]) + 2); next } }
' "$SK/template.manifest" | LC_ALL=C sort)
found=$(for t in $SEL; do (cd "$SK/$t" && find . -type f | sed 's|^\./||'); done | LC_ALL=C sort)
if [ -z "$listed" ] || [ "$listed" != "$found" ]; then echo "Refusing to scaffold: template.manifest and the template trees ($SEL) do not list the same files"; exit 1; fi
clash=$(printf '%s\n' "$found" | while IFS= read -r p; do
  if [ -e "$TGT/$p" ] || [ -L "$TGT/$p" ]; then echo "$p"; fi
done)
links=$(printf '%s\n' "$found" | while IFS= read -r p; do
  d=$p
  while [ "${d%/*}" != "$d" ]; do
    d=${d%/*}
    if [ -L "$TGT/$d" ]; then echo "$d"; fi
  done
done | LC_ALL=C sort -u)
if [ -n "$clash$links" ]; then printf 'Refusing to scaffold: these paths already exist or are symlinks in %s:\n%s\n%s\n' "$TGT" "$clash" "$links"; exit 1; fi
cp -Rp "<skill-dir>/shared/template/." "<target>/" || exit 1
cp -Rp "<skill-dir>/shared/template-ts/." "<target>/" || exit 1
cp -Rp "<skill-dir>/shared/template-py/." "<target>/" || exit 1
TC_GUARD
```

Lines one and two are for nestjs, nextjs and vite-react; lines one and three are for fastapi. The CI file is not part of this copy: Step B3 picks the host and copies it. Every later step in this kit that mentions one of these files works on the copy now in `<target>`.

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
