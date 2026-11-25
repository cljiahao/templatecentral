<!-- ref: migrate/general/implementation.md
     loaded-by: migrate/SKILL.md
     prereq: Migration workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate or Adopt Project

Goal: bring an existing project up to the templateCentral standard in one run: measure a baseline, seed the whole harness, prove it is live, and end with a comparison against the baseline. Detects the stack, asks the user once, then runs autonomously.

**Phase files** (paths under `<skill-dir>/`; the kits load here so every chain stays within two `cat` hops, CONVENTIONS §2). `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react, `harness-kit-fastapi.md` for fastapi.

| Load | When | Files |
|---|---|---|
| Baseline | no-marker path, after Phase 1 | `general/quality-baseline.md` |
| Quality pass | only on a yes to its question | `general/quality-baseline.md`, `general/quality-pass.md`, `../test/implementation.md`, `../standards/code-standards/comments.md` |
| Phase 4 | full seed (Phase 2 choice A, or Phase 0 seed) | `general/phase-4-upgrade.md`, then `../scaffold/shared/harness-kit.md`, `shared/<variant-file>` (`harness-kit-ts.md` for nestjs, nextjs, vite-react; `harness-kit-fastapi.md` for fastapi; load only that one), `shared/harness-kit-enforcement.md`, `shared/harness-kit-finalize.md`, `shared/documentation-kit.md` |
| Phase 5 | health check 5a–5c; 5d re-sync only if approved | `general/phase-5-health-check.md`; for 5d also the five kit files Phase 4 loads |
| Defect notes | after the defect report | `general/UPGRADE-NOTES.md` |

---

## Phase 0 — Check for Version Upgrade (agent, autonomous)

Check `AGENTS.md` line 1 for a templateCentral version marker:

```
<!-- templateCentral: <stack>@<version> -->
```

**If no marker** → skip to Phase 1 (stack detection).

**Baseline on every route that changes project files** (no marker, the seed or re-sync of a light adoption): after the user's yes and before the first write, run the Phase 3 A step 1 `--full` before-run; after the last write, run the Phase 3 A step 5 `--compare`. Phases 1–3 may be skipped, this step may not. The Phase 3 A step 1 before-run is this same run: take it once. A route that changes nothing takes none.

**If a marker is present** → check whether `.claude/harness.json` exists:

- **`.claude/harness.json` exists** → run the harness refresh first: load `general/harness-refresh.md` and follow it (dry run, confirm, apply, merge the `.templatecentral-new` files). When it is done, load and run **Phase 5** (5a–5c; offer 5d) for the source-level checks and the optional extras the refresh does not touch. A project that has `.claude/harness.json` never takes the Phase 1–4 path.

- **`.claude/harness.json` does not exist** → a light adoption wrote the marker but never seeded
  the harness. Do **not** exit. Skip Phases 1–3 and present:
  ```
  ℹ️ This project carries a templateCentral <version> marker but has no harness
     (.claude/harness.json is absent — it was adopted, not fully seeded).

  Seed the full harness now? It adds:
  - .claude/settings.json + .claude/hooks/  — the enforcement layer
  - lefthook.yml, .gitleaks.toml, CI quality gates
  - .claude/harness.json                    — the integrity manifest

  Seed it? (A) Yes  (B) Skip
  ```
  User A → proceed to Phase 4.
  User B → print "No changes made." Exit.

**If the marker names a version before `@6.0.0`** → the file-existence rules above and below decide the route, not the version. Run `harness-refresh` when `.claude/harness.json` exists, else the seed offer above, then `defect-report.sh` (see "Known-defect report"). A project from `@5.x` or earlier can carry hooks whose `command` in `.claude/settings.json` is an array: Claude Code skips them, so they never ran. `harness-refresh.sh` does not rewrite a `settings.json` it cannot match to a shipped hash; it writes `.claude/settings.json.templatecentral-new`, so replace every array-form hook with the exec form from that file when you merge it.

---

## Phase 1 — Detect Stack (agent, autonomous)

Detect the stack as `detect_stack` in `<skill-dir>/general/harness-refresh.sh` does; it is the one source and refuses when several stacks match.

If multiple signals found (likely a monorepo root) → ask the user: "Which project
should be adopted first — frontend or backend? Please provide the subdirectory path."
Re-run detection there; Phases 2 and 3 then work in that subdirectory, not the original working directory.

If no signals found → tell the user: "No recognised stack detected in this directory.
Please run this skill from a project directory, not a parent folder." Exit.

If ambiguous (e.g. vite.config.ts without the React plugin) → ask the user to confirm the stack.

**Static baseline.** Once the stack and project directory are resolved, run `bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --static` and print its table as information. It runs no project code and asks nothing.

---

## Phase 2 — Human Decision ⛔ GATE

Do not proceed until the user responds. Write nothing into the project before the answer. Present exactly this message (substituting the detected stack name):

```
⚠️ This project has no templateCentral marker.

Detected stack: <stack>

Choose how to proceed:

A) Full adoption (recommended)
   Measures a baseline first, then seeds the whole harness (agent hooks,
   lefthook, gitleaks, CI quality gates, AGENTS.md tail), proves it is live,
   and ends with a comparison against the baseline. Your code stays as-is.
   The baseline runs the project's lint, typecheck and tests (project code
   executes) and installs pinned scratch tools (network).
   Also run the quality pass afterwards? It then changes code, tests and
   config, each batch confirmed first. Answer: A+pass or A.

B) Light adoption (fast)
   Adds the marker to AGENTS.md and notes structural gaps. Runs and seeds
   nothing else.

C) Stop
   Exit without changes. Run `templatecentral:scaffold` to start
   a fresh project, or proceed manually.

Which would you prefer? (A+pass / A / B / C)
```

---

## Phase 3 — Execute (agent, autonomous after gate)

### If A — Full adoption

1. **Baseline, before any change.** Create a scratch directory outside the project, then run `bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --full --label before --keep-coverage <scratch>/cov-before > <scratch>/before.md` and print the table. On `CHANGED` in its last row, stop and show the files it names.
2. **Marker.** Make `<!-- templateCentral: <stack>@6.0.0 -->` the first line of `AGENTS.md`, above the original content; create the file with that line only if it does not exist.
3. **Seed.** Load and run Phase 4 (phase table above). Rerunning the whole flow on an adopted project is safe: files that match the canonical copy are left alone, and differing ones follow Phase 4's diff-and-ask rules.
4. **Quality pass**, only on `A+pass`: follow `quality-pass.md` (loaded with the files listed under "Quality pass"). It starts from `<scratch>/before.md`.
5. **Close the loop.** Run `quality-baseline.sh <project-dir> --full --label after > <scratch>/after.md`, then `quality-baseline.sh --compare <scratch>/before.md <scratch>/after.md`. Print the table and save it as `docs/quality-baseline.md` (under 60 lines). Exit 3 means no number got worse but a gate configuration file changed: show the list, state for each changed file what changed and why, and never describe a threshold, scope or rule change as neutral. Exit 1 means a number got worse: show the rows, fix the cause or report it; never accept it by editing a threshold, a suppression or an exclusion. The one suppression `comments.md` allows is the user's decision: once they approve it, retake `before` after that single change with the reason recorded and compare against the new table; the agent never retakes a baseline to make compare pass. Phase 5a–5c (the live check) must also pass.

### If B — Light adoption

**Step B1: Write the marker.** As step 2 above.

**Step B2: Scan for structural gaps.** List each of these that is absent.

- Next.js: `src/app/`, `src/features/`, `src/components/`, `src/lib/`
- Vite + React: `src/features/`, `src/components/`, `src/lib/`
- FastAPI: `src/api/routers/`, `src/models/`, `src/core/config.py`
- NestJS: `src/modules/`, `src/common/`, `src/config/`

**Step B3: Print the summary and return.**

```
✓ Project adopted as <stack>@6.0.0.

Structural gaps noted (review files generated by the invoking skill carefully
where your project structure differs from templateCentral conventions):
- [list each missing item, or "None — structure matches templateCentral conventions"]

Returning to the skill that invoked me — proceeding from Step 1.
```

Return control; the invoking skill continues from Step 1.

### If C — Stop

Print: "No changes made."

Return control; the invoking skill must exit without generating any files.

---

## Known-defect report (read-only)

After a seed, re-sync or harness refresh, and whenever the user asks which older template code a project still carries, run `bash "<skill-dir>/general/defect-report.sh" <project-dir>` and show its output as printed. It writes nothing and needs no login, key or network. It does not filter by version, because a refresh rewrites the recorded one. Exit 1 means a `high` line, exit 2 means it could not run. Load the defect notes (table above) for the fix details and the two review-by-hand items.
Change project source only after the user confirms each fix, one at a time. A line means a known older pattern, not a verdict: `check` lines need a look first.

## Quality pass (opt-in)

For an unmarked project the question is in the Phase 2 gate. For a marked project (Phase 0 routes into Phase 4 or an approved Phase 5 re-sync), when migrate was invoked directly and the tree is clean after adoption, ask once, separately from every approval above: "Run the quality pass? It runs the project's lint, typecheck and tests, then changes code, tests and config, and needs a clean tree." Never ask after light adoption, Stop or Skip. On yes, load the files listed under "Quality pass" above and follow `quality-pass.md`. On no, print "Quality pass skipped." and finish.
