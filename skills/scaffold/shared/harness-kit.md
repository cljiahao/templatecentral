<!-- ref: scaffold/shared/harness-kit.md
     loaded-by: scaffold/<stack>/source-files.md + migrate/general/phase-4-upgrade.md + migrate/general/phase-5-health-check.md → scaffold/SKILL.md | migrate/SKILL.md
     prereq: Stack identified and the target directory created (every templated stack loads this file at its Step 1, before copying its files), or migrate Phase 4/5 in progress. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold and templatecentral:migrate skills. -->

# Shared Harness Kit

Index of the agent harness seeded into every project. Read the **Per-stack delta table** first, then execute every step in the **Step order** below with the current stack's row.

---

## Kit files

The loader cats this index plus exactly three part files — the stack's **one** variant file and both shared files:

| File | Holds | Load for |
|---|---|---|
| `harness-kit-ts.md` | Notes for Steps A, B, B2 (the TS `settings.json` in `template-settings-ts/`, the 7 per-stack hooks incl. `user-prompt-guard.cjs`, and `lefthook.yml`, which live in `template-ts/`) | nestjs · nextjs · vite-react |
| `harness-kit-fastapi.md` | Notes for Steps A, B, B2, B3 (the FastAPI `settings.json` in `template-settings-py/`, the 7 per-stack hooks incl. `user-prompt-guard.py`, `lefthook.yml` and the CI `quality` job, which live in `template-py/` and `template-ci/github-py/`) | fastapi |
| `harness-kit-enforcement.md` | Step A/B/B2 shared rules + notes on the stack-agnostic files (`comment-hygiene-patterns.txt`, `session-context.sh`, `skill-usage-log.sh`, `.lefthook/commit-msg.sh`, `.gitleaks.toml`, held in `template/`); Steps B3 (CI host pick, `ci-gates.sh`, Azure template), B4, B5 | every stack |
| `harness-kit-finalize.md` | Steps C, D, E, E2, E3, F, G, H (the AGENTS.md tail is `template-tail/AGENTS-tail.md`, appended in Step G) | every stack |

## Step order

| Step | Seeds | Where |
|---|---|---|
| 0 | (`tc-copy.sh`) every template file below that is a real file: the 9 `.claude/hooks/` scripts, `.claude/ci-gates.sh`, `.claude/gate-budget.sh`, `.claude/gate-budget.conf`, `.claude/verify-harness.sh`, `.claude/regen-harness.sh`, `.claude/comment-hygiene-patterns.txt`, `lefthook.yml`, `.lefthook/commit-msg.sh`, `.gitleaks.toml` | this file — scaffold only; migrate diffs and merges instead |
| A | `.claude/settings.json` (copied here with `TC_PART=settings`) | enforcement (merge rules, deny lists, hook inventory) + variant notes |
| B | `.claude/hooks/` scripts (copied in Step 0) | notes in the variant (`protect-files`, `block-no-verify`, `user-prompt-guard`, `post-edit-typecheck`, `post-edit-comment-check`, `stop-checks`, `subagent-stop`) + enforcement (`comment-hygiene-patterns.txt`, `session-context`, `skill-usage-log`, `chmod`) |
| B2 | git-hook layer (files copied in Step 0) | notes in the variant (`lefthook.yml`) + enforcement (`.lefthook/commit-msg.sh`, `.gitleaks.toml`, install wiring) |
| B3 | CI quality gates incl. dependency audit (`.claude/ci-gates.sh` from Step 0, plus the CI file copied here: `.github/workflows/ci.yml` on GitHub, or `azure-pipelines/templatecentral-gates.yml` plus the `azure-pipelines.yml` starter that includes it on Azure DevOps) | enforcement (CI host pick and copy; the `deps` dependency-audit gate lives in `ci-gates.sh`) + fastapi variant (notes on the FastAPI `quality` job) |
| B4 | harness integrity verifier (`verify-harness.sh`, `regen-harness.sh`, copied in Step 0) | enforcement |
| B5 | `/skill-audit` project skill | enforcement |
| C, D | `FUTURE.md`, `docs/CONSTITUTION.md`, `docs/harness.md` (copied with `TC_PART=late`, together with the `/skill-audit` skill of Step B5) | finalize |
| E, E2, E3 | `.claude/harness.json`, base snapshot, project docs | finalize |
| F, G, H | `.agents` symlink, post-scaffold workflow, plugins | finalize |

For Step A the enforcement file's section is the step: run `tc-copy.sh` with `TC_PART=settings` as part of it. Steps B and B2 only add rules and notes to the files Step 0 already copied.

---

## Step 0 — copy the template trees

Scaffold only, except `TC_PART=tail`, which `migrate` runs from Step G. `migrate` never runs the other parts: it diffs each file under `<skill-dir>/shared/template/`, `<skill-dir>/shared/template-ts/` and `<skill-dir>/shared/template-py/` against the project and merges (see its Phase 4 and Phase 5).

`<skill-dir>/shared/tc-copy.sh` is the only copy script, and the only thing this step runs; do not read it. Set `TC_STACK=` (`nestjs`, `nextjs`, `vite-react` or `fastapi`), `TC_PART=` and, for `ci` only, `TC_CI=` in the environment, and pass `<target>` as its one argument. `<target>` is the project root (never `/` or your home directory: the script refuses both); the app files may already be there, and only the paths a copy writes must be absent. The script derives its trees and manifest from `TC_STACK` and `TC_PART`, finds them next to itself, and refuses any other value, so a wrong stack cannot copy another stack's files:

```bash
TC_STACK=<stack> TC_PART=base bash "<skill-dir>/shared/tc-copy.sh" "<target>"
```

| `TC_PART` | Run it | Copies |
|---|---|---|
| `base` | here, before Step A and the first `pnpm install` | `template` + `template-ts` (nestjs, nextjs, vite-react) or `template-py` (fastapi), per `<skill-dir>/shared/template.manifest` |
| `settings` | Step A, after the stack's `AGENTS.md` step | `template-settings-ts` or `template-settings-py`: `.claude/settings.json` |
| `ci` | Step B3, with `TC_CI=github` or `TC_CI=azure` | `template-ci/github-ts` or `github-py`, or `azure` plus `azure-ts` or `azure-py`; `TC_CI=none` instead removes the `.claude/ci-gates.sh` that `base` placed, only when it is byte for byte the template's, and refuses otherwise; `.claude/gate-budget.sh` and `.claude/gate-budget.conf` stay, though nothing then records timings |
| `late` | Step C, after the stack's `AGENTS.md` step (which follows its verification gate) | `template-late`: `FUTURE.md`, `docs/CONSTITUTION.md`, `docs/harness.md`, `.claude/skills/skill-audit/SKILL.md` (stored as `SKILL.md.tmpl`; prettier would reformat the first two at an earlier format pass) |
| `stack`, `agents` | the stack's `source-files.md`, when it says | `<skill-dir>/<STACK>/template` and `template-agents`, per `<skill-dir>/<STACK>/template.manifest` |
| `leaf` | an `add` or `migrate` leaf that names its own template tree | `TC_LEAF=<add or migrate>/<leaf stem>` (for example `add/auth/nestjs`) copies every `template*` tree beside that leaf per its `template.manifest`, or only `TC_TREE=<tree>`; `TC_STACK` is not used. Same refusals and `STOP:` line as the other parts |
| `manifest` | Step E, after the verify skills and Steps A–D | writes `.claude/harness.json`: one `seeded_files` entry per seeded file present, `templatecentral_version` from the plugin's `plugin.json`, `adoWiki` from `TC_ADO_WIKI`; refuses when the file exists |
| `finish` | Step G, after `tail` and the TS format pass | refuses while `docs/CONSTITUTION.md`, `FUTURE.md` or `docs/harness.md` holds a placeholder; re-hashes every `harness.json` entry, mirrors each seeded file into `.claude/.harness-base/` (the merge base for migrate Phase 5), and runs `verify-harness.sh` once the project has a commit |
| `tail` | Step G, after the stack's `AGENTS.md` step | appends `template-tail/AGENTS-tail.md` to the project's `AGENTS.md` with the stack's typecheck command filled in; it writes nothing else |

`settings`, `late` and `ci` with `TC_CI=github` or `TC_CI=azure` refuse unless the project's `lefthook.yml` is the one `base` copied for this `TC_STACK`, so run `base` first. `settings`, `late` and `tail` also refuse until `AGENTS.md` exists, which keeps them behind the verification gate and the format pass in every stack.

A template file named `<name>.tmpl` is copied to `<name>` (the manifest lists the `.tmpl` source). Skill files ship that way (`SKILL.md.tmpl`), so no skill loader that scans the plugin registers a template skill.

Substitute `<skill-dir>` and `<target>` as plain text inside the double quotes. A path holding `"`, `$`, a backtick or a backslash needs that character escaped (or single quotes around the whole path); the script never expands a path. Only a newline in a path is refused (`stop`): ask the user for another directory.

The script checks everything before the first write and writes nothing when a check fails. Every refusal and every failed copy ends with a `STOP:` line: do not `rm` or overwrite anything, report it to the user. A `No such file or directory` error for `tc-copy.sh` (a wrong `<skill-dir>`) also means stop: do not look for the script elsewhere.

The CI file is not part of this copy: Step B3 picks the host and copies it. Every later step in this kit that mentions one of these files works on the copy now in `<target>`.

---

## Per-stack delta table

| Stack | JSON-parsing runtime | Typecheck feedback cmd | Stop-checks test cmd | Verify-skill name(s) | Quality-gate line in CONSTITUTION §6 |
|-------|----------------------|------------------------|----------------------|----------------------|---------------------------------------|
| **fastapi** | `python3` | `python -m pyright src/` (errors → `additionalContext`) | only the changed test files when every changed file is a test file, else all of `test/` and `tests/` | `api-verify` | `python -m pyright src/ && ruff check src/ && python -m pytest test/ -q` (the `/api-verify` skill) |
| **nestjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `vitest related --run` for code files (full `pnpm test` for config, setup, data or any non-code change) | `nest-verify` | `pnpm check` |
| **nextjs** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `vitest related --run` for code files (full `pnpm test` for config, setup, data or any non-code change) | `next-verify` + `next-migrate` | `pnpm check` |
| **vite-react** | `node` | `pnpm exec tsc --noEmit --incremental` (errors → `additionalContext`) | `vitest related --run` for code files (full `pnpm test` for config, setup, data or any non-code change) | `vite-verify` | `pnpm check` |
