# Skill Prerequisites Design

**Date:** 2026-05-06
**Status:** Approved — pending implementation

---

## Problem

templateCentral's "add-*" and operational shared skills generate files with specific import
paths, folder structures, and config patterns that only make sense inside a
templateCentral-scaffolded project. Currently, any skill can be invoked in any project
with no guard — producing mismatched files, broken imports, and wasted work.

---

## Design Goals

1. **Forced prerequisite** — agents cannot generate files until the project is confirmed
   as a valid templateCentral project.
2. **Self-healing** — when the prerequisite is missing, the agent resolves it automatically
   via `shared-migrate` before continuing.
3. **One human gate** — the only moment a human decides anything is the adopt/migrate
   choice inside `shared-migrate`. Everything before and after is agent-driven.
4. **Centralized migration logic** — all adoption and migration logic lives in
   `shared-migrate`. Skills contain only a compact Step 0 check.
5. **AI-DLC aligned** — mirrors the aidlc-workflows pattern: mandatory prerequisite
   stages, `⛔ GATE` at human decision points, autonomous execution after each gate,
   state tracked by a marker file.
6. **Agent-first** — skills are invoked by agents, not directly by users. Step 0 is
   a safety net against agent context mistakes, not a UX prompt for humans. Path
   discovery (e.g. mono repo layout) is an execution concern handled in Inputs/Steps,
   not a prerequisite gate.

---

## Architecture

### The marker as state

Each scaffold skill writes a marker on line 1 of `AGENTS.md`:

| Stack | Marker |
|---|---|
| Next.js | `<!-- templateCentral: nextjs@1.0.0 -->` |
| Vite + React | `<!-- templateCentral: vite-react@1.0.0 -->` |
| FastAPI | `<!-- templateCentral: fastapi@1.0.0 -->` |
| NestJS | `<!-- templateCentral: nestjs@1.0.0 -->` |

This marker is the single source of truth — equivalent to `aidlc-state.md` in AI-DLC.

### Execution flow

```
Agent invokes any add-* skill
  │
  ▼
Step 0 — check for marker (agent, forced — no exceptions)
  │
  ├─ Found ──────────────────────────────► Step 1 (continue normally)
  │
  └─ Not found ─► auto-invoke shared-migrate
                      │
                      ▼
                  Phase 1: Detect stack (agent, autonomous)
                      │
                      ▼
                  ⛔ GATE — human decision required
                  "Adopt (fast) or Full migrate (thorough) or Stop?"
                      │
                      ├─ A: Adopt ──► agent executes light adoption (autonomous)
                      │               writes marker, notes gaps
                      │               returns to original skill → Step 1
                      │
                      ├─ B: Migrate ► agent executes full migration (autonomous)
                      │               [planned — not in initial release]
                      │               returns to original skill → Step 1
                      │
                      └─ C: Stop ───► exit. No files written.
```

---

## Step 0 Templates

Step 0 is inserted into every applicable skill **after `## Inputs`, before Step 1**.
It is compact and uniform — all resolution logic lives in `shared-migrate`.

### Variant A — Stack-specific (26 skills)

Used by all `nextjs-add-*`, `vite-react-add-*`, `fastapi-add-*`, `nestjs-add-*` skills.
The marker prefix differs per stack.

```markdown
## Prerequisites

Requires a project scaffolded with `templatecentral:<stack>-scaffold`. See Step 0.

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral: <stack>@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.
```

### Variant B — Any-stack (6 skills)

Used by `shared-add-error-handling`, `shared-add-logging`, `shared-add-pagination`,
`shared-validation-patterns`, `shared-remove-example`, and `shared-full-stack-pairing`.

Step 0 checks only the **current working directory** for a marker. Path discovery
(identifying a second project in a mono repo, asking for the backend path, etc.) is
handled in the skill's `## Inputs` section — it is an execution concern, not a
prerequisite gate.

```markdown
## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md` at the current directory.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.
```

**Note for `shared-full-stack-pairing`:** When running from a mono repo root with no
marker at root level, the skill's `## Inputs` section handles discovery — the agent
scans immediate subdirectories for templateCentral markers to identify the frontend
and backend paths before Step 1 begins. Step 0 only validates whether the current
context is resolvable; path discovery is not a prerequisite concern.

---

## Context Prerequisites (soft checks, per-skill)

Some skills produce no useful output if specific code doesn't exist yet. These checks
run **after** the marker check in Step 0. They are hard stops — agents do not proceed
or generate files.

| Skill | Check | Stop message |
|---|---|---|
| `nextjs-add-test` | `src/app/api/` has at least one `.ts` route handler | "No API routes found. Run `nextjs-add-api-route` first." |
| `vite-react-add-test` | `src/features/` or `src/components/` has at least one `.tsx` file | "No components or features found. Add some first." |
| `fastapi-add-test` | `src/routers/` has at least one `.py` file | "No routers found. Run `fastapi-add-endpoint` first." |
| `nestjs-add-test` | `src/modules/` has at least one subdirectory | "No modules found. Run `nestjs-add-module` first." |
| `shared-remove-example` | `src/features/example/` exists | "No example code found — nothing to remove." |
| `shared-add-pagination` | At least one route handler file exists in the project | "No API routes found. Add endpoints first, then add pagination." |

---

## Recommended Prerequisites (advisory, per-skill)

Best-practice sequencing suggestions surfaced to the human by the agent. Not blocking —
teams have valid reasons to sequence differently. The agent must surface these, not
silently skip them:

> "Before proceeding: `shared-add-error-handling` and `shared-add-logging` are not
> yet detected in this project. Adding them first means new features inherit shared
> infrastructure from the start. Run them now, or continue without them?"

Skills that surface this advisory:
- All feature/page/component `add-*` skills → recommend `shared-add-error-handling`,
  `shared-add-logging`
- All integration `add-*` skills → recommend `shared-add-logging`

---

## `shared-migrate` Skill Design

A new skill created as part of this work. Full migrate (option B) is a planned future
capability — not in the initial release.

### Phase 1 — Detect (agent, autonomous)

1. Scan for stack signals in the current directory:
   - `next.config.ts` or `next.config.js` → Next.js
   - `vite.config.ts` with React plugin → Vite + React
   - `pyproject.toml` with FastAPI dependency → FastAPI
   - `nest-cli.json` → NestJS
2. If ambiguous → ask the user which stack applies.
3. Identify the correct scaffold skill and marker for the detected stack.

### Phase 2 — Human decision (⛔ GATE)

Present to the user:

```
⚠️ This project has no templateCentral marker.

Detected stack: <stack>

Choose how to proceed:

A) Light adoption (fast)
   Adds the templateCentral marker to AGENTS.md and lists any structural
   gaps vs templateCentral conventions. Your existing code stays as-is.
   Best if your structure is already close to templateCentral conventions.

B) Full migration (thorough) [planned — not yet available]
   Analyses your project, generates a migration plan, and restructures
   your code to match templateCentral conventions with your approval at
   each step.

C) Stop
   Exit without changes. Run `templatecentral:<stack>-scaffold` to start
   a fresh project instead.

Which would you prefer? (A / B / C)
```

Do not proceed until the user responds.

### Phase 3 — Execute (agent, autonomous after gate)

**If A (Light adoption):**
1. Check if `AGENTS.md` exists.
   - Exists → prepend `<!-- templateCentral: <stack>@1.0.0 -->` as line 1.
   - Does not exist → create it with the marker as line 1.
2. Scan for structural gaps specific to the detected stack (e.g. for Next.js:
   missing `src/app/`, `src/features/`, `tailwind.config.ts`). List each gap.
3. Print adoption summary:
   ```
   ✓ Project adopted as <stack>@1.0.0.

   Structural gaps noted (review generated files carefully):
   - [gap 1]
   - [gap 2]

   Returning to the skill that invoked me — proceeding from Step 1.
   ```
4. Return control to the invoking skill.

**If B (Full migration):** Respond: "Full migration is not yet available. Choose A or C."

**If C (Stop):** Print "No changes made." Return control. The invoking skill exits.

---

## Skill Mapping

### Variant A — Stack-specific (26 skills)

| Stack | Skills |
|---|---|
| `nextjs` | `nextjs-add-api-route`, `nextjs-add-auth`, `nextjs-add-component`, `nextjs-add-database`, `nextjs-add-feature`, `nextjs-add-form`, `nextjs-add-integration`, `nextjs-add-page`, `nextjs-add-test` |
| `vite-react` | `vite-react-add-auth`, `vite-react-add-component`, `vite-react-add-feature`, `vite-react-add-form`, `vite-react-add-integration`, `vite-react-add-page`, `vite-react-add-test` |
| `fastapi` | `fastapi-add-auth`, `fastapi-add-database`, `fastapi-add-endpoint`, `fastapi-add-integration`, `fastapi-add-test` |
| `nestjs` | `nestjs-add-auth`, `nestjs-add-database`, `nestjs-add-integration`, `nestjs-add-module`, `nestjs-add-test` |

### Variant B — Any-stack (6 skills)

`shared-add-error-handling`, `shared-add-logging`, `shared-add-pagination`,
`shared-validation-patterns`, `shared-remove-example`, `shared-full-stack-pairing`

### Not modified (12 skills)

| Skill | Reason |
|---|---|
| All 4 scaffold skills | Source of the marker — no prerequisites |
| All 4 code-standards skills | Reference material only, no code written |
| `shared-build-agent` | Dispatched utility, runs in any project |
| `shared-review-agent` | Dispatched utility, runs in any project |
| `shared-test-agent` | Dispatched utility, runs in any project |
| `shared-update-agent` | Dispatched utility, runs in any project |
| `shared-drift-check` | Already self-detecting via the marker |
| `shared-task-management` | Has its own opt-in detection logic |

---

## What Is Not In Scope

- **Full migration (shared-migrate option B)** — designed and gated, implementation
  deferred to a follow-up.
- **After Writing Code standardisation** — some add-* skills are missing consistent
  dispatch chains. Addressed in a separate pass.
- **Cross-skill hard dependencies** (e.g. nestjs-add-auth requires nestjs-add-module) —
  evidence unclear; deferred until skill behaviour is observed in practice.
