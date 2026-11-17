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

**Quality pass** (only after the separate consent in Phase 3):
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
| none | Phase 1, baseline, gate |
| `@6.0.0` or later, `.claude/harness.json` present | Phase 5 (5a–5c); a *clean* Phase 5 (every file `UNCHANGED`, plugin version equals `templatecentral_version`, `@AGENTS.md` import present) ends there; otherwise baseline, gate with 5d as the A step |
| `@6.0.0` or later, no `.claude/harness.json` | adopted, never seeded: baseline, gate with the seed as the A step |
| `@5.x` | hooks are inert (array-valued `command`, which Claude Code skips); baseline, gate with a re-seed in exec form (`"command"` + `"args"`, `${CLAUDE_PROJECT_DIR}` paths) as the A step |
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

## Phase 2 — Baseline, then gate ⛔

Run the baseline and print its report; nothing is written yet. Running the project's own lint, typecheck and tests is read-only measurement; when a command is missing, record `n/a` and do not invent one. Then ask one question, do not proceed before the answer, and use the same three choices on every route:

- **A. Adopt** — the harness step for this route (Phase 4 seed or upgrade, or 5d). Then a separate question about the quality pass (Phase 3).
- **B. Light** — marker plus the baseline report only; nothing else changes.
- **C. Stop** — write nothing.

## Phase 3 — Execute (agent, autonomous after the gate)

**A** — Run the route's harness step, adapting to the CI, sharding and coverage thresholds the baseline found (never duplicating a pipeline, never lowering a threshold). Write `docs/quality-baseline.md`. Then ask separately whether to run the quality pass, which changes code and tests. On yes, load and follow `quality-pass.md` (this is its only trigger), then print the before/after table.

**B** — Set line 1 of `AGENTS.md` to the marker (create the file if absent) and write `docs/quality-baseline.md`. Add a short list of structural differences between the project and the Architecture section of `<skill-dir>/../../.claude/rules/<stack>.md`. Return control to the invoking skill, which continues from Step 1 and reviews generated files where the layout differs.

**C** — Change nothing and tell the invoking skill to exit without generating files.
