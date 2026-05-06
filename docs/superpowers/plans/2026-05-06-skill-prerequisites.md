# Skill Prerequisites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add forced prerequisite gates (Step 0) to all 32 applicable templateCentral skills, and create the new `shared-migrate` skill that handles light adoption when no marker is found.

**Architecture:** Every "add-*" and operational shared skill gets a `## Prerequisites` section (declaration) and `### Step 0 — Verify context` (enforcement). Step 0 checks for the templateCentral marker in `AGENTS.md`; if missing, it auto-invokes `shared-migrate` which presents a human gate (adopt / full migrate [future] / stop). All adoption logic lives in `shared-migrate` — skills contain only the compact check.

**Tech Stack:** Markdown file edits only. No code changes. Verification via `grep`.

**Spec:** `docs/specs/2026-05-06-skill-prerequisites-design.md`

---

## Reusable Templates

Define once — referenced by every task below.

### Template: Prerequisites block (Variant A — stack-specific)

Replace `<stack>` with `nextjs`, `vite-react`, `fastapi`, or `nestjs`:

```markdown
## Prerequisites

Requires a project scaffolded with `templatecentral:<stack>-scaffold`. See Step 0.
```

### Template: Prerequisites block (Variant B — any-stack)

```markdown
## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.
```

### Template: Step 0 — Variant A, no context check

Replace `<stack>` with the stack name:

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral: <stack>@` on line 1 of `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.
```

### Template: Step 0 — Variant B, no context check

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to Step 1.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to Step 1.
- Still absent (user chose to stop) → exit. Do not generate any files.
```

---

## Insertion Rules

**`## Prerequisites` block:** Insert immediately before the first `##` section in the
file (before `## Inputs`, `## Steps`, `## Files this skill creates`, etc. — whichever
comes first). Place a blank line before and after.

**`### Step 0`:**
- Skills with `## Steps`: insert as the first `###` subsection, directly after the
  `## Steps` heading line.
- Skills with `## Implementation` (shared-add-* skills): insert as the first `###`
  subsection, directly after the `## Implementation` heading line.
- `shared-remove-example` (no Steps/Implementation): add a new `## Steps` section
  containing Step 0, placed immediately after `## Prerequisites` and before `## Next.js`.

---

## Task 0: Create `shared-migrate` skill

**Goal:** New skill that resolves missing templateCentral markers via a human-gated
adopt/migrate flow, then returns control to the invoking skill.

**Files:**
- Create: `skills/shared-migrate/SKILL.md`

**Acceptance Criteria:**
- [ ] Frontmatter has `name: shared-migrate` and description starting with "Use when"
- [ ] Phase 1 (detect) covers all four stacks with exact file signals
- [ ] Phase 2 gate presents A/B/C choice and does not proceed until user responds
- [ ] Phase 3 light adoption writes `<!-- templateCentral: <stack>@1.0.0 -->` to line 1 of `AGENTS.md`
- [ ] Phase 3 lists structural gaps per stack
- [ ] Phase 3 ends with explicit "Returning to the skill that invoked me" message
- [ ] Full migration (B) responds with not-yet-available message and loops back to Phase 2
- [ ] Stop (C) exits cleanly with "No changes made"

**Verify:** `grep -c "Phase" skills/shared-migrate/SKILL.md` → `3`

**Steps:**

- [ ] **Step 1: Create the skill file**

Create `skills/shared-migrate/SKILL.md` with this exact content:

```markdown
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
A (light adoption) or C (stop)." Return to the top of Phase 2.

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
```

- [ ] **Step 2: Verify**

```bash
grep -c "Phase" skills/shared-migrate/SKILL.md
# Expected: 3

grep "name: shared-migrate" skills/shared-migrate/SKILL.md
# Expected: name: shared-migrate
```

- [ ] **Step 3: Commit**

```bash
git add skills/shared-migrate/SKILL.md
git commit -m "feat(skills): add shared-migrate skill for project adoption"
```

---

## Task 1: Add Step 0 to Next.js skills (Variant A, 9 skills)

**Goal:** Add `## Prerequisites` + `### Step 0` to all nine `nextjs-add-*` skills.
Eight skills use the standard Variant A Step 0; `nextjs-add-test` adds a context check.

**Files:**
- Modify: `skills/nextjs-add-api-route/SKILL.md`
- Modify: `skills/nextjs-add-auth/SKILL.md`
- Modify: `skills/nextjs-add-component/SKILL.md`
- Modify: `skills/nextjs-add-database/SKILL.md`
- Modify: `skills/nextjs-add-feature/SKILL.md`
- Modify: `skills/nextjs-add-form/SKILL.md`
- Modify: `skills/nextjs-add-integration/SKILL.md`
- Modify: `skills/nextjs-add-page/SKILL.md`
- Modify: `skills/nextjs-add-test/SKILL.md`

**Acceptance Criteria:**
- [ ] All 9 files contain `## Prerequisites`
- [ ] All 9 files contain `### Step 0 — Verify context`
- [ ] All 9 files check for `<!-- templateCentral: nextjs@`
- [ ] All 9 files reference `templatecentral:shared-migrate` on not-found
- [ ] `nextjs-add-test` additionally checks `src/app/api/` for `.ts` route handlers

**Verify:**
```bash
grep -l "Step 0" skills/nextjs-add-*/SKILL.md | wc -l   # Expected: 9
grep -l "shared-migrate" skills/nextjs-add-*/SKILL.md | wc -l   # Expected: 9
```

**Steps:**

- [ ] **Step 1: Edit the eight standard Next.js skills**

For each of these eight files, find the first line starting with `## ` and insert
the Prerequisites block immediately before it (see Templates above, `<stack>` = `nextjs`):

```
skills/nextjs-add-api-route/SKILL.md  — first ## is: ## Inputs
skills/nextjs-add-auth/SKILL.md       — first ## is: ## Files this skill creates
skills/nextjs-add-component/SKILL.md  — first ## is: ## Inputs
skills/nextjs-add-database/SKILL.md   — first ## is: ## Choose Your Database
skills/nextjs-add-feature/SKILL.md    — first ## is: ## Inputs
skills/nextjs-add-form/SKILL.md       — first ## is: ## What the Template Already Provides
skills/nextjs-add-integration/SKILL.md — first ## is: ## Inputs
skills/nextjs-add-page/SKILL.md       — first ## is: ## Inputs
```

Then find `## Steps` in each file and insert the standard Variant A Step 0 (no context
check, `<stack>` = `nextjs`) as the first `###` subsection immediately after `## Steps`.

- [ ] **Step 2: Edit `nextjs-add-test` with context check**

In `skills/nextjs-add-test/SKILL.md`:

1. Find the first `## ` line (`## Test Structure`) and insert before it:

```markdown
## Prerequisites

Requires a project scaffolded with `templatecentral:nextjs-scaffold`. See Step 0.
```

2. Find `## Steps` (or the first numbered section if none) and insert this Step 0
immediately after — note it differs from the standard template by adding a context check:

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral: nextjs@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/app/api/` contains at least one `.ts` route handler file.

If not found → ⛔ STOP. Tell the user: "No API routes found. Run
`templatecentral:nextjs-add-api-route` first, then return here."

If found → proceed to Step 1.
```

- [ ] **Step 3: Verify**

```bash
grep -l "Step 0" skills/nextjs-add-*/SKILL.md | wc -l
# Expected: 9

grep "src/app/api" skills/nextjs-add-test/SKILL.md
# Expected: one line containing the context check path
```

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-add-*/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to nextjs-add-* skills"
```

---

## Task 2: Add Step 0 to Vite+React skills (Variant A, 7 skills)

**Goal:** Add `## Prerequisites` + `### Step 0` to all seven `vite-react-add-*` skills.
Six skills use standard Variant A Step 0; `vite-react-add-test` adds a context check.

**Files:**
- Modify: `skills/vite-react-add-auth/SKILL.md`
- Modify: `skills/vite-react-add-component/SKILL.md`
- Modify: `skills/vite-react-add-feature/SKILL.md`
- Modify: `skills/vite-react-add-form/SKILL.md`
- Modify: `skills/vite-react-add-integration/SKILL.md`
- Modify: `skills/vite-react-add-page/SKILL.md`
- Modify: `skills/vite-react-add-test/SKILL.md`

**Acceptance Criteria:**
- [ ] All 7 files contain `## Prerequisites` and `### Step 0 — Verify context`
- [ ] All 7 files check for `<!-- templateCentral: vite-react@`
- [ ] `vite-react-add-test` additionally checks `src/features/` or `src/components/` for `.tsx` files

**Verify:**
```bash
grep -l "Step 0" skills/vite-react-add-*/SKILL.md | wc -l   # Expected: 7
grep "vite-react@" skills/vite-react-add-*/SKILL.md | wc -l  # Expected: 7
```

**Steps:**

- [ ] **Step 1: Edit the six standard Vite+React skills**

First `##` sections for reference:
```
skills/vite-react-add-auth/SKILL.md        — first ## is: ## What the Template Already Provides
skills/vite-react-add-component/SKILL.md   — first ## is: ## Inputs
skills/vite-react-add-feature/SKILL.md     — first ## is: ## Inputs
skills/vite-react-add-form/SKILL.md        — first ## is: ## What the Template Provides
skills/vite-react-add-integration/SKILL.md — first ## is: ## Inputs
skills/vite-react-add-page/SKILL.md        — first ## is: ## Inputs
```

For each: insert Variant A Prerequisites block before the first `## ` line (`<stack>` = `vite-react`).
Then insert standard Variant A Step 0 as first subsection of `## Steps`.

- [ ] **Step 2: Edit `vite-react-add-test` with context check**

In `skills/vite-react-add-test/SKILL.md` (first `##` is `## Test Structure`):

1. Insert Variant A Prerequisites block before `## Test Structure`.
2. Add Step 0 with context check (no `## Steps` heading exists — add one immediately after `## Prerequisites`):

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral: vite-react@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/features/` or `src/components/` contains at least
one `.tsx` file.

If not found → ⛔ STOP. Tell the user: "No components or features found. Add some
using `templatecentral:vite-react-add-feature` or `templatecentral:vite-react-add-component`
first, then return here."

If found → proceed to Step 1.
```

- [ ] **Step 3: Verify and commit**

```bash
grep -l "Step 0" skills/vite-react-add-*/SKILL.md | wc -l   # Expected: 7
git add skills/vite-react-add-*/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to vite-react-add-* skills"
```

---

## Task 3: Add Step 0 to FastAPI skills (Variant A, 5 skills)

**Goal:** Add `## Prerequisites` + `### Step 0` to all five `fastapi-add-*` skills.
Four use standard Variant A; `fastapi-add-test` adds a context check.

**Files:**
- Modify: `skills/fastapi-add-auth/SKILL.md`
- Modify: `skills/fastapi-add-database/SKILL.md`
- Modify: `skills/fastapi-add-endpoint/SKILL.md`
- Modify: `skills/fastapi-add-integration/SKILL.md`
- Modify: `skills/fastapi-add-test/SKILL.md`

**Acceptance Criteria:**
- [ ] All 5 files contain `## Prerequisites` and `### Step 0 — Verify context`
- [ ] All 5 check for `<!-- templateCentral: fastapi@`
- [ ] `fastapi-add-test` additionally checks `src/routers/` for `.py` files

**Verify:**
```bash
grep -l "Step 0" skills/fastapi-add-*/SKILL.md | wc -l   # Expected: 5
grep "fastapi@" skills/fastapi-add-*/SKILL.md | wc -l     # Expected: 5
```

**Steps:**

- [ ] **Step 1: Edit the four standard FastAPI skills**

First `##` sections for reference:
```
skills/fastapi-add-auth/SKILL.md        — first ## is: ## Dependencies
skills/fastapi-add-database/SKILL.md    — first ## is: ## Choose Your Database
skills/fastapi-add-endpoint/SKILL.md    — first ## is: ## Steps
skills/fastapi-add-integration/SKILL.md — first ## is: ## Inputs
```

For each: insert Variant A Prerequisites block (`<stack>` = `fastapi`) before the first
`## ` line. Then insert standard Variant A Step 0 as the first `###` inside `## Steps`.

- [ ] **Step 2: Edit `fastapi-add-test` with context check**

In `skills/fastapi-add-test/SKILL.md` (first `##` is `## Test Structure`):

1. Insert Variant A Prerequisites block before `## Test Structure`.
2. Add a `## Steps` section immediately after `## Prerequisites`, containing:

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral: fastapi@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/routers/` contains at least one `.py` file.

If not found → ⛔ STOP. Tell the user: "No routers found. Run
`templatecentral:fastapi-add-endpoint` first, then return here."

If found → proceed to Step 1.
```

- [ ] **Step 3: Verify and commit**

```bash
grep -l "Step 0" skills/fastapi-add-*/SKILL.md | wc -l   # Expected: 5
git add skills/fastapi-add-*/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to fastapi-add-* skills"
```

---

## Task 4: Add Step 0 to NestJS skills (Variant A, 5 skills)

**Goal:** Add `## Prerequisites` + `### Step 0` to all five `nestjs-add-*` skills.
Four use standard Variant A; `nestjs-add-test` adds a context check.

**Files:**
- Modify: `skills/nestjs-add-auth/SKILL.md`
- Modify: `skills/nestjs-add-database/SKILL.md`
- Modify: `skills/nestjs-add-integration/SKILL.md`
- Modify: `skills/nestjs-add-module/SKILL.md`
- Modify: `skills/nestjs-add-test/SKILL.md`

**Acceptance Criteria:**
- [ ] All 5 files contain `## Prerequisites` and `### Step 0 — Verify context`
- [ ] All 5 check for `<!-- templateCentral: nestjs@`
- [ ] `nestjs-add-test` additionally checks `src/modules/` for at least one subdirectory

**Verify:**
```bash
grep -l "Step 0" skills/nestjs-add-*/SKILL.md | wc -l   # Expected: 5
grep "nestjs@" skills/nestjs-add-*/SKILL.md | wc -l       # Expected: 5
```

**Steps:**

- [ ] **Step 1: Edit the four standard NestJS skills**

First `##` sections for reference:
```
skills/nestjs-add-auth/SKILL.md        — first ## is: ## Dependencies
skills/nestjs-add-database/SKILL.md    — first ## is: ## Choose Your Database
skills/nestjs-add-integration/SKILL.md — first ## is: ## Inputs
skills/nestjs-add-module/SKILL.md      — first ## is: ## Naming Convention
```

For each: insert Variant A Prerequisites block (`<stack>` = `nestjs`) before the first
`## ` line. Then insert standard Variant A Step 0 as first `###` inside `## Steps`.

- [ ] **Step 2: Edit `nestjs-add-test` with context check**

In `skills/nestjs-add-test/SKILL.md` (first `##` is `## Unit Tests`):

1. Insert Variant A Prerequisites block before `## Unit Tests`.
2. Add a `## Steps` section immediately after `## Prerequisites`, containing:

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral: nestjs@` on line 1 of `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm `src/modules/` exists and contains at least one subdirectory.

If not found → ⛔ STOP. Tell the user: "No modules found. Run
`templatecentral:nestjs-add-module` first, then return here."

If found → proceed to Step 1.
```

- [ ] **Step 3: Verify and commit**

```bash
grep -l "Step 0" skills/nestjs-add-*/SKILL.md | wc -l   # Expected: 5
git add skills/nestjs-add-*/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to nestjs-add-* skills"
```

---

## Task 5: Add Step 0 to shared Implementation skills (Variant B, 4 skills)

**Goal:** Add `## Prerequisites` + `### Step 0` to the four shared skills that use
`## Implementation` as their action section. `shared-add-pagination` gets an
additional context check.

**Files:**
- Modify: `skills/shared-add-error-handling/SKILL.md`
- Modify: `skills/shared-add-logging/SKILL.md`
- Modify: `skills/shared-add-pagination/SKILL.md`
- Modify: `skills/shared-validation-patterns/SKILL.md`

**Acceptance Criteria:**
- [ ] All 4 files contain `## Prerequisites` (Variant B wording) and `### Step 0`
- [ ] All 4 check for `<!-- templateCentral:` (any stack)
- [ ] `shared-add-pagination` additionally checks that at least one route handler file exists

**Verify:**
```bash
grep -l "Step 0" skills/shared-add-error-handling/SKILL.md \
  skills/shared-add-logging/SKILL.md \
  skills/shared-add-pagination/SKILL.md \
  skills/shared-validation-patterns/SKILL.md | wc -l   # Expected: 4
```

**Steps:**

- [ ] **Step 1: Edit the three standard shared Implementation skills**

For `shared-add-error-handling`, `shared-add-logging`, and `shared-validation-patterns`:

1. Find first `## ` line (all three start with `## When to Use`). Insert Variant B
   Prerequisites block immediately before it.

2. Find `## Implementation` in each file. Insert standard Variant B Step 0 as the
   first `###` subsection immediately after `## Implementation`.

- [ ] **Step 2: Edit `shared-add-pagination` with context check**

In `skills/shared-add-pagination/SKILL.md` (first `##` is `## When to Use`):

1. Insert Variant B Prerequisites block before `## When to Use`.
2. Find `## Implementation` and insert this Step 0 (with context check) as first `###`:

```markdown
### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Confirm the project contains at least one route handler file
(e.g. any `.ts` file under `src/app/api/` for Next.js, any `.py` file under
`src/routers/` for FastAPI, any controller file under `src/modules/` for NestJS,
or any `.ts` file under `src/features/*/api/` for Vite + React).

If none found → ⛔ STOP. Tell the user: "No API routes or endpoints found. Add some
first, then return here to add pagination."

If found → proceed to Step 1.
```

- [ ] **Step 3: Verify and commit**

```bash
grep -l "Step 0" \
  skills/shared-add-error-handling/SKILL.md \
  skills/shared-add-logging/SKILL.md \
  skills/shared-add-pagination/SKILL.md \
  skills/shared-validation-patterns/SKILL.md | wc -l   # Expected: 4

git add skills/shared-add-error-handling/SKILL.md \
        skills/shared-add-logging/SKILL.md \
        skills/shared-add-pagination/SKILL.md \
        skills/shared-validation-patterns/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to shared-add-* implementation skills"
```

---

## Task 6: Update special shared skills (Variant B, 2 skills)

**Goal:** Add Step 0 to `shared-full-stack-pairing` (has `## Steps`, needs Inputs
section updated for mono repo discovery) and `shared-remove-example` (unique
per-stack structure, requires a new `## Steps` section and a context check).

**Files:**
- Modify: `skills/shared-full-stack-pairing/SKILL.md`
- Modify: `skills/shared-remove-example/SKILL.md`

**Acceptance Criteria:**
- [ ] `shared-full-stack-pairing` has Variant B Prerequisites + Step 0 inside `## Steps`
- [ ] `shared-full-stack-pairing` has an `## Inputs` section noting mono repo path discovery
- [ ] `shared-remove-example` has Variant B Prerequisites + a new `## Steps` section with Step 0
- [ ] `shared-remove-example` Step 0 detects which stack is in use from the marker and checks for stack-specific example directory

**Verify:**
```bash
grep "Step 0" skills/shared-full-stack-pairing/SKILL.md   # Expected: one match
grep "Step 0" skills/shared-remove-example/SKILL.md        # Expected: one match
grep "mono repo" skills/shared-full-stack-pairing/SKILL.md # Expected: one match
```

**Steps:**

- [ ] **Step 1: Update `shared-full-stack-pairing`**

In `skills/shared-full-stack-pairing/SKILL.md` (first `##` is `## Supported Pairings`):

1. Insert Variant B Prerequisites block before `## Supported Pairings`.

2. Insert a new `## Inputs` section immediately after `## Prerequisites`:

```markdown
## Inputs

- **Frontend project path** — current directory if running from inside the frontend
  project, or ask if running from a mono repo root. The agent should scan immediate
  subdirectories for a `<!-- templateCentral:` marker to identify the frontend path
  automatically before asking.
- **Backend project path** — ask the user. The agent should scan immediate
  subdirectories for a second `<!-- templateCentral:` marker to suggest the backend
  path.
```

3. Find `## Steps` and insert standard Variant B Step 0 as the first `###` subsection.

- [ ] **Step 2: Update `shared-remove-example`**

In `skills/shared-remove-example/SKILL.md` (first `##` is `## Next.js`):

1. Insert Variant B Prerequisites block before `## Next.js`.

2. Insert a new `## Steps` section immediately after `## Prerequisites`, containing
   this context-aware Step 0:

```markdown
## Steps

### Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → note the detected stack from the marker (nextjs / vite-react / fastapi /
nestjs) and proceed to context check below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed to context check below.
- Still absent (user chose to stop) → exit. Do not generate any files.

**Context check:** Verify the example directory exists for the detected stack:

| Stack | Example directory to check |
|---|---|
| `nextjs` | `src/features/example/` |
| `vite-react` | `src/features/example/` |
| `fastapi` | `src/example/` |
| `nestjs` | `src/modules/example/` |

If the directory does not exist → ⛔ STOP. Tell the user: "No example code found —
nothing to remove. The example may have already been removed."

If found → proceed to the section for your detected stack below.
```

- [ ] **Step 3: Verify and commit**

```bash
grep "Step 0" skills/shared-full-stack-pairing/SKILL.md   # Expected: one match
grep "Step 0" skills/shared-remove-example/SKILL.md        # Expected: one match
grep "Inputs" skills/shared-full-stack-pairing/SKILL.md    # Expected: at least one match

git add skills/shared-full-stack-pairing/SKILL.md skills/shared-remove-example/SKILL.md
git commit -m "feat(skills): add prerequisite Step 0 to shared-full-stack-pairing and shared-remove-example"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Forced prerequisite gate on all 32 applicable skills | Tasks 1–6 |
| Stack-specific marker check (Variant A, 26 skills) | Tasks 1–4 |
| Any-stack marker check (Variant B, 6 skills) | Tasks 5–6 |
| shared-migrate created with Phase 1/2/3 | Task 0 |
| Human ⛔ GATE in shared-migrate | Task 0 (Phase 2) |
| Light adoption writes marker, notes gaps | Task 0 (Phase 3-A) |
| Full migration gated as not-yet-available | Task 0 (Phase 3-B) |
| Context checks for 6 skills | Tasks 1–6 (test skills + pagination + remove-example) |
| Mono repo path discovery in Inputs (not Step 0) | Task 6 |
| shared-full-stack-pairing Inputs section | Task 6 |
| 12 skills not modified | Confirmed — not in any task |

**Gap check:** None identified. All 32 skills covered across Tasks 1–6.
