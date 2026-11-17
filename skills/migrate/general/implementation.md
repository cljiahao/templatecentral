<!-- ref: migrate/general/implementation.md
     loaded-by: migrate/SKILL.md
     prereq: Migration workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate or Adopt Project

Goal: bring an existing project up to the templateCentral standard — harness seeded, code measured, findings fixed, result proven. Detect the stack, ask the user once, then run autonomously.

**Marker.** Line 1 of `AGENTS.md` is `<!-- templateCentral: <stack>@6.0.0 -->`. `@6.0.0` is the harness schema version, not the plugin version; it moves only on a schema change. The installed plugin version is `templatecentral_version` in `.claude/harness.json`.

**Loading.** The shared kits load here, so every chain stays within two `cat` hops (CONVENTIONS §2). `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react and `harness-kit-fastapi.md` for fastapi — load only that one.

**Baseline** (every route except a clean Phase 5, before any write):
```bash
cat "<skill-dir>/general/quality-baseline.md"
```
It tells you to run `<skill-dir>/general/quality-baseline.sh`.

**Quality pass** (only after the separate consent in Phase 3; the test and comment rules load with it, so the chain stays at two hops):
```bash
cat "<skill-dir>/general/quality-pass.md"
cat "<skill-dir>/../test/SKILL.md"
cat "<skill-dir>/../standards/code-standards/comments.md"
```

**Phase 4** — full harness seed / v4–v6 upgrade:
```bash
cat "<skill-dir>/general/phase-4-upgrade.md"
cat "<skill-dir>/../scaffold/shared/harness-kit.md"
cat "<skill-dir>/../scaffold/shared/<variant-file>"
cat "<skill-dir>/../scaffold/shared/harness-kit-enforcement.md"
cat "<skill-dir>/../scaffold/shared/harness-kit-finalize.md"
cat "<skill-dir>/../scaffold/shared/documentation-kit.md"
```

**Phase 5** — harness health check (5a–5c), then the safe re-sync (5d) only if the user approves it:
```bash
cat "<skill-dir>/general/phase-5-health-check.md"
```
On an approved 5d re-sync, load the five kit files that Phase 4 loads after `phase-4-upgrade.md` (the four harness-kit files and `documentation-kit.md`).

---

## Phase 0 — Route by marker (agent, autonomous)

Read `AGENTS.md` line 1.

| Marker | Route |
|---|---|
| none | Phase 1, baseline, gate |
| `@6.0.0` or later, `.claude/harness.json` present | Phase 5 (5a–5c); a *clean* Phase 5 (every file `UNCHANGED`, plugin version equals `templatecentral_version`, `@AGENTS.md` import present) ends there; otherwise baseline, gate with 5d as the A step |
| `@6.0.0` or later, no `.claude/harness.json` | adopted, never seeded: baseline, gate with the seed as the A step |
| `@5.x` | hooks are inert (array-valued `command`, which Claude Code skips). With `.claude/harness.json`: baseline, gate with Phase 5 5d as the A step; 5d sets the marker first, before anything hashes `AGENTS.md`. Without it: baseline, gate with a re-seed in exec form (`"command"` + `"args"`, `${CLAUDE_PROJECT_DIR}` paths) as the A step, marker first |
| `@4.x` or earlier | baseline, gate with the upgrade (v4 adds the harness layer, v5 converts skills to directory form and fixes hooks) as the A step |

Take the stack from the marker or Phase 1.

## Phase 1 — Detect stack (agent, autonomous)

| Signal | Stack |
|---|---|
| `next.config.ts` or `next.config.js` or `next.config.mjs` present | Next.js |
| `vite.config.ts` or `vite.config.js` present AND no `next.config.*` | Vite + React |
| `requirements.txt` contains `fastapi` | FastAPI |
| `nest-cli.json` present, or `@nestjs/core` in `package.json` | NestJS |

Several signals (likely a monorepo root) → ask which subdirectory to adopt first and work there. No signal → say so and exit. Ambiguous (for example `vite.config.ts` without the React plugin) → ask.

## Phase 2 — Human Decision ⛔ GATE

Run the baseline (`quality-baseline.sh` reads the project and writes nothing) and print its table. Do not proceed until the user responds. Present exactly this message, substituting the detected stack, the marker status line (`This project has no templateCentral marker.`, or its current marker and what it means) and the route's A line from the table below it:

```
⚠️ <marker status>

Detected stack: <stack>

Baseline: <the metric table above>

Choose how to proceed:

A) Adopt
   <A line for this route>
   The harness step shows its own plan first and needs its own yes.

B) Light
   Adds the marker and docs/quality-baseline.md. Your code and config
   stay as they are.

C) Stop
   Exit without changes. Run `templatecentral:scaffold` to start a fresh
   project, or proceed manually.

Which would you prefer? (A / B / C)
```

| Route | A line |
|---|---|
| none, or `@6.0.0` or later without `.claude/harness.json` | Seeds the full harness (hooks, skills, CI gates, docs). |
| `@5.x` without `harness.json`, or `@4.x` and earlier | Upgrades the harness to the current schema (v4 adds the harness layer, v5 converts skills to directory form and fixes hooks). |
| `@5.x` or `@6.0.0` or later with `harness.json` | Re-syncs the seeded files with a 3-way merge (Phase 5, Step 5d). |

Choosing A selects the route only. The harness step then presents its dry-run plan (per file: action and diff preview) and writes nothing until the user says yes to that plan. Afterwards a separate question covers the quality pass (Phase 3).

## Phase 3 — Execute (agent, autonomous after the gate)

**A** — Run the route's harness step, adapting to the CI, sharding and coverage thresholds the baseline found (never duplicating a pipeline, never lowering a threshold). Write the baseline to `docs/quality-baseline.md`. Then ask separately whether to run the quality pass, which changes code and tests and needs a clean tree: commit the migration changes only on the user's explicit instruction. On yes, load and follow `quality-pass.md` (this is its only trigger), then run `quality-baseline.sh <project-dir> --label after`, add its column as `after` in `docs/quality-baseline.md` and print the before/after table.

**B** — Set line 1 of `AGENTS.md` to the marker (create the file if absent) and write `docs/quality-baseline.md`. Add a short list of structural differences between the project and the Architecture section of `<skill-dir>/../../.claude/rules/<stack>.md`. Return control to the invoking skill, which continues from Step 1 and reviews generated files where the layout differs.

**C** — Change nothing and tell the invoking skill to exit without generating files.
