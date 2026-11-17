<!-- ref: migrate/general/implementation.md
     loaded-by: migrate/SKILL.md
     prereq: Migration workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate or Adopt Project

Goal: bring an existing project up to the templateCentral standard — harness seeded, code measured, findings fixed, result proven. Detect the stack, ask the user once, then run autonomously.

**Marker.** Line 1 of `AGENTS.md` is `<!-- templateCentral: <stack>@6.0.0 -->`. The `@6.0.0` is the harness schema floor, not the plugin version, so it does not go stale when the plugin updates. The installed plugin version lives in `.claude/harness.json` (`templatecentral_version`). Only a schema change moves the marker; "the Step 4b marker update" sets it to `@6.0.0`.

**Loading.** The shared kits load here, so every chain stays within two `cat` hops (CONVENTIONS §2). `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react and `harness-kit-fastapi.md` for fastapi — load only that one.

**Baseline** (every route, before any write):
```bash
cat "<skill-dir>/general/quality-baseline.md"
```

**Quality pass** (full adoption only, after the seed):
```bash
cat "<skill-dir>/general/quality-pass.md"
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
| none | Phase 1 → Phase 2 gate |
| `@6.0.0` or later, `.claude/harness.json` present | already on the current schema: Phase 5 (5a–5c, offer 5d), then offer the quality pass |
| `@6.0.0` or later, no `.claude/harness.json` | adopted but never seeded: Phase 1, baseline, offer the full seed |
| `@5.x` | hooks are inert (array-valued `command`, which Claude Code skips); offer a re-seed in exec form (`"command"` + `"args"`, `${CLAUDE_PROJECT_DIR}` paths) |
| earlier than `@4.0.0`, or `@4.x` | offer the upgrade: v4 adds the harness layer, v5 converts skills to directory form and fixes hooks |

For every route except a clean Phase 5, take the stack from the marker (or Phase 1), run the **baseline**, print the report, then ask once: proceed (A) or skip (B). On B write nothing but the baseline report and exit. On A: `@5.x` with a harness runs Step 4b's marker update first (before anything hashes `AGENTS.md`), then Phase 5 and 5d; every other route runs Phase 4, then the **quality pass**, then the before/after table.

## Phase 1 — Detect stack (agent, autonomous)

| Signal | Stack |
|---|---|
| `next.config.ts` or `next.config.js` or `next.config.mjs` present | Next.js |
| `vite.config.ts` or `vite.config.js` present AND no `next.config.*` | Vite + React |
| `requirements.txt` contains `fastapi` | FastAPI |
| `nest-cli.json` present, or `@nestjs/core` in `package.json` | NestJS |

Several signals (likely a monorepo root) → ask which subdirectory to adopt first and work there. No signal → say so and exit. Ambiguous (for example `vite.config.ts` without the React plugin) → ask.

## Phase 2 — Gate ⛔

Show the baseline report, then ask which to run; do not proceed until the user answers.

- **A. Full adoption** — Phase 4 (harness seed), lint alignment and the quality pass, then re-measure. Done only when lint, typecheck and tests pass and no number regressed.
- **B. Light adoption** — marker plus the baseline report only. Code and config stay as they are; the report shows the gap.
- **C. Stop** — write nothing.

## Phase 3 — Execute (agent, autonomous after the gate)

**A** — Phase 4 with the stack from Phase 1, then the quality pass, then the before/after table. Existing CI, sharding and stricter coverage thresholds found by the baseline are adapted to, not duplicated or lowered.

**B** — Make `<!-- templateCentral: <stack>@6.0.0 -->` the first line of `AGENTS.md` (create the file with that line if absent), write the baseline report, and return control to the invoking skill: it continues from Step 1, treating structural differences from templateCentral conventions as review points.

**C** — Make no change, and tell the invoking skill to exit without generating files.
