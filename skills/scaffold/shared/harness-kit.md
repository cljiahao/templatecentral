<!-- ref: scaffold/shared/harness-kit.md
     loaded-by: scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified and the target directory created (every templated stack loads this file at its Step 1, before copying its files), or migrate Phase 4/5 in progress. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit

This file is the index of the single source of truth for the Claude Code agent harness seeded into every scaffolded project. Read the **Per-stack delta table** first, then execute ALL steps in the **Step order** below using the row matching the current stack.

---

## Kit files

The kit is split by stack so a run never loads the other stack's script bodies. The loader (a scaffold stack file or a migrate phase file) cats this index plus exactly three part files — the stack's **one** variant file and both shared files:

| File | Holds | Load for |
|---|---|---|
| `harness-kit-ts.md` | Notes for Steps A, B, B2 (the TS `settings.json` in `template-settings-ts/`, the 7 per-stack hooks incl. `user-prompt-guard.cjs`, and `lefthook.yml`, which live in `template-ts/`) | nestjs · nextjs · vite-react |
| `harness-kit-fastapi.md` | Notes for Steps A, B, B2, B3 (the FastAPI `settings.json` in `template-settings-py/`, the 7 per-stack hooks incl. `user-prompt-guard.py`, `lefthook.yml` and the CI `quality` job, which live in `template-py/` and `template-ci/github-py/`) | fastapi |
| `harness-kit-enforcement.md` | Step A/B/B2 shared rules + notes on the stack-agnostic files (`comment-hygiene-patterns.txt`, `session-context.sh`, `skill-usage-log.sh`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`, held in `template/`); Steps B3 (CI host pick, `ci-gates.sh`, Azure template), B4, B5 | every stack |
| `harness-kit-finalize.md` | Steps C, D, E, E2, E3, F, G, H (the AGENTS.md tail is `template-tail/AGENTS-tail.md`, appended in Step G) | every stack |

## Step order

| Step | Seeds | Where |
|---|---|---|
| 0 | (`tc-copy.sh`) every template file below that is a real file: the 9 `.claude/hooks/` scripts, `.claude/ci-gates.sh`, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml` | this file — scaffold only; migrate diffs and merges instead |
| A | `.claude/settings.json` (copied here with `PART=settings`) | enforcement (merge rules, deny lists, hook inventory) + variant notes |
| B | `.claude/hooks/` scripts (copied in Step 0) | notes in the variant (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`) + enforcement (`comment-hygiene-patterns.txt`, `session-context`, `skill-usage-log`, `chmod`) |
| B2 | git-hook layer (files copied in Step 0) | notes in the variant (`lefthook.yml`) + enforcement (`.lefthook/commit-msg.sh`, `.gitleaks.toml`, install wiring) |
| B3 | CI quality gates incl. dependency audit (`.claude/ci-gates.sh` from Step 0, plus the CI file copied here: `.github/workflows/ci.yml` on GitHub, or `azure-pipelines/templatecentral-gates.yml` on Azure DevOps) | enforcement (CI host pick and copy; the `deps` dependency-audit gate lives in `ci-gates.sh`) + fastapi variant (notes on the FastAPI `quality` job) |
| B4 | harness integrity verifier (`verify-harness.sh`, `regen-harness.sh`, copied in Step 0) | enforcement |
| B5 | `/skill-audit` project skill | enforcement |
| C, D | `FUTURE.md`, `docs/CONSTITUTION.md` (copied with `PART=late`, together with the `/skill-audit` skill of Step B5) | finalize |
| E, E2, E3 | `.claude/harness.json`, base snapshot, per-folder docs | finalize |
| F, G, H | `.agents` symlink, post-scaffold workflow, plugins | finalize |

For Step A the enforcement file's section is the step: run `tc-copy.sh` with `PART=settings` as part of it. Steps B and B2 only add rules and notes to the files Step 0 already copied.

---

## Step 0 — copy the template trees

Scaffold only, except `PART=tail`, which `migrate` runs from Step G. `migrate` never runs the other parts: it diffs each file under `<skill-dir>/shared/template/`, `<skill-dir>/shared/template-ts/` and `<skill-dir>/shared/template-py/` against the project and merges (see its Phase 4 and Phase 5).

`<skill-dir>/shared/tc-copy.sh` is the only copy script, and the only thing this step runs; do not read it. Set `STACK=` (`nestjs`, `nextjs`, `vite-react` or `fastapi`), `PART=` and, for `ci` only, `CI=` in the environment, and pass `<target>` as its one argument. `<target>` is the project root; the app files may already be there, and only the paths a copy writes must be absent. The script derives its trees and manifest from `STACK` and `PART`, finds them next to itself, and refuses any other value, so a wrong stack cannot copy another stack's files:

```bash
STACK=<stack> PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

| `PART` | Run it | Copies |
|---|---|---|
| `base` | here, before Step A and the first `pnpm install` | `template` + `template-ts` (nestjs, nextjs, vite-react) or `template-py` (fastapi), per `<skill-dir>/shared/template.manifest` |
| `settings` | Step A, after the stack's `AGENTS.md` step | `template-settings-ts` or `template-settings-py`: `.claude/settings.json` |
| `ci` | Step B3, with `CI=github` or `CI=azure` | `template-ci/github-ts`, `github-py` or `azure`; `CI=none` instead removes the `.claude/ci-gates.sh` that `base` placed, only when it is byte for byte the template's, and refuses otherwise |
| `late` | Step C, after the stack's `AGENTS.md` step (which follows its verification gate) | `template-late`: `FUTURE.md`, `docs/CONSTITUTION.md`, `.claude/skills/skill-audit/SKILL.md` (stored as `SKILL.md.tmpl`; prettier would reformat the first two at an earlier format pass) |
| `stack`, `agents` | the stack's `source-files.md`, when it says | `<skill-dir>/<STACK>/template` and `template-agents`, per `<skill-dir>/<STACK>/template.manifest` |
| `tail` | Step G, after the stack's `AGENTS.md` step | appends `template-tail/AGENTS-tail.md` to the project's `AGENTS.md` with the stack's typecheck command filled in; it writes nothing else |

`settings`, `late` and `ci` with `CI=github` or `CI=azure` refuse unless the project's `lefthook.yml` is the one `base` copied for this `STACK`, so run `base` first (`CI=none` returns before that check: it only removes a file, and compares it with the template's). `settings`, `late` and `tail` also refuse until `AGENTS.md` exists, which keeps them behind the verification gate and the format pass in every stack.

A template file named `<name>.tmpl` is copied to `<name>` (the manifest lists the `.tmpl` source). Skill files ship that way (`SKILL.md.tmpl`), so no skill loader that scans the plugin registers a template skill.

Substitute `<skill-dir>` and `<target>` as plain text inside the double quotes. A path that holds `"`, `$`, a backtick or a backslash needs that character escaped (or single quotes around the whole path); the script itself never expands a path. A path must not contain a newline: if one does, stop and ask the user for another directory before substituting.

The script writes nothing when a check fails: an empty or unsubstituted target; a target that is not an existing directory; a tree holding a symlink or an empty directory; a manifest that is missing, empty or disagrees with the trees (it names the differing files, such as a stray `.DS_Store`); a file it would write that already exists; a symlink or non-directory where it needs a directory; an existing directory that is not writable, or a source file that is not readable (all checked before the first write). It then creates only the missing parent directories and copies each listed file with `cp`, setting the manifest mode; it never copies attributes onto the project root or an existing directory and never changes a mode it did not create. Every refusal and every failed copy ends with a `STOP:` line: do not `rm` or overwrite anything, and report it to the user (a failed copy also lists the files already written). The script runs in its own `bash`, so it behaves the same from bash or zsh and a refusal ends only that process, never the caller's shell.

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
