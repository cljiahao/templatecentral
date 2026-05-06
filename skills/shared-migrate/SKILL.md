---
name: shared-migrate
description: Use when a templateCentral add-* skill cannot proceed because no marker exists in AGENTS.md — detects the project stack, presents adoption or migration options, and executes the chosen path before returning control
---

# Migrate or Adopt Project

Invoked automatically by add-* skills when no templateCentral marker is found in
`AGENTS.md`. Detects the project stack, presents a choice to the user, and executes
autonomously after the decision.

**Do not invoke this skill directly unless directed to by another skill's Step 0.**

---

## Phase 1 — Detect Stack (agent, autonomous)

Scan the current directory for stack signals:

| Signal | Stack |
|---|---|
| `next.config.ts` or `next.config.js` present | Next.js |
| `vite.config.ts` present | Vite + React |
| `pyproject.toml` present (check for FastAPI dependency) | FastAPI |
| `nest-cli.json` present | NestJS |

If multiple signals found (likely a mono repo root) → ask the user: "Which project
should be adopted first — frontend or backend? Please provide the subdirectory path."
Then re-run detection from that subdirectory.

If no signals found → tell the user: "No recognised stack detected in this directory.
Please run this skill from a project directory, not a parent folder." Exit.

If ambiguous (e.g. vite.config.ts without React plugin) → ask the user to confirm
the stack before proceeding.

---

## Phase 2 — Human Decision ⛔ GATE

Do not proceed until the user responds. Present exactly this message (substituting
the detected stack name):

```
⚠️ This project has no templateCentral marker.

Detected stack: <stack>

Choose how to proceed:

A) Light adoption (fast)
   Adds the templateCentral marker to AGENTS.md and notes any structural
   gaps vs templateCentral conventions. Your existing code stays as-is.
   Best if your project structure is already close to templateCentral
   conventions.

B) Full migration (thorough) [not yet available]
   Analyses your project, produces a migration plan, and restructures
   your code to match templateCentral conventions with your approval at
   each step.

C) Stop
   Exit without changes. Run templatecentral:<stack>-scaffold to start
   a fresh project, or proceed manually.

Which would you prefer? (A / B / C)
```

If user answers B → respond: "Full migration is not yet available. Please choose
A (light adoption) or C (stop)." Return to the top of phase 2.

---

## Phase 3 — Execute (agent, autonomous after gate)

### If A — Light adoption

**Step A1: Write the marker**

Check whether `AGENTS.md` exists at the current directory:
- Exists → read its contents, then rewrite it with `<!-- templateCentral: <stack>@1.0.0 -->`
  as the first line, followed by the original content.
- Does not exist → create `AGENTS.md` with `<!-- templateCentral: <stack>@1.0.0 -->`
  as the only line.

**Step A2: Scan for structural gaps**

Check for the following per detected stack. List any that are absent.

**Next.js gaps:**
- `src/app/` directory
- `src/features/` directory
- `src/components/` directory
- `tailwind.config.ts`
- `src/lib/` directory

**Vite + React gaps:**
- `src/features/` directory
- `src/components/` directory
- `vite.config.ts`
- `src/lib/` directory

**FastAPI gaps:**
- `src/routers/` directory
- `src/models/` directory
- `src/config.py` or `src/settings.py`

**NestJS gaps:**
- `src/modules/` directory
- `nest-cli.json`
- `src/main.ts`

**Step A3: Print adoption summary and return**

Print:

```
✓ Project adopted as <stack>@1.0.0.

Structural gaps noted (review generated files carefully where your project
structure differs from templateCentral conventions):
- [list each missing item, or "None — structure matches templateCentral conventions"]

Returning to the skill that invoked me — proceeding from Step 1.
```

Return control to the invoking skill. The invoking skill continues from Step 1.

### If C — Stop

Print: "No changes made."

Return control to the invoking skill. The invoking skill must exit without generating
any files.
