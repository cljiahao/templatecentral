# templateCentral Routing & Scaffold Consistency — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four accuracy bugs and make post-scaffold agent dispatch consistent and automatic across all four stacks.

**Architecture:** Targeted edits to existing skill files and AGENTS.md — no new skills, no structural changes. Four independent changes executed in order: requirements.txt path fix → AGENTS.md routing table → nextjs description → post-scaffold agent steps.

**Tech Stack:** Claude Code plugin (Markdown skill files, YAML frontmatter, no build step). Verification is via `grep`.

**Spec:** `docs/superpowers/specs/2026-04-28-templatecentral-routing-scaffold-consistency.md`

---

### Task 1: Fix FastAPI `requirements.txt` path in 5 files

**Goal:** Remove all references to `src/requirements.txt` from skill instructions and the fastapi-scaffold Dockerfile, so agents always write to the correct project-root location.

**Files:**
- Modify: `skills/fastapi-add-auth/SKILL.md:12`
- Modify: `skills/fastapi-add-database/SKILL.md:31,195,276,366,427`
- Modify: `skills/fastapi-add-integration/SKILL.md:28`
- Modify: `skills/shared-add-logging/SKILL.md:300`
- Modify: `skills/fastapi-scaffold/SKILL.md:188,206,285`

**Acceptance Criteria:**
- [ ] `grep -r "src/requirements.txt" skills/` returns zero results
- [ ] `grep "COPY src/requirements" skills/fastapi-scaffold/SKILL.md` returns zero results
- [ ] The Dockerfile verification loop no longer lists `src/requirements.txt`

**Verify:** `grep -r "src/requirements.txt" skills/` → no output

**Steps:**

- [ ] **Step 1: Fix `fastapi-add-auth/SKILL.md`**

Find line 12. Replace:
```
Add to `src/requirements.txt`:
```
With:
```
Add to `requirements.txt`:
```

- [ ] **Step 2: Fix all 5 occurrences in `fastapi-add-database/SKILL.md`**

Replace all occurrences (use replace_all):
- `Add to \`src/requirements.txt\`:` → `Add to \`requirements.txt\`:`
- `add \`email-validator\` to \`src/requirements.txt\`` → `add \`email-validator\` to \`requirements.txt\``

Confirm 5 lines are fixed (lines 31, 195, 276, 366, 427).

- [ ] **Step 3: Fix `fastapi-add-integration/SKILL.md`**

Find line 28. Replace:
```
Add to `src/requirements.txt`:
```
With:
```
Add to `requirements.txt`:
```

- [ ] **Step 4: Fix `shared-add-logging/SKILL.md`**

Find line 300. Replace:
```
- `python-json-logger>=3.3.0` in `src/requirements.txt`
```
With:
```
- `python-json-logger>=3.3.0` in `requirements.txt`
```

- [ ] **Step 5: Fix `fastapi-scaffold/SKILL.md` Dockerfile — remove two stale COPY lines**

In the `deps` stage (around line 188), remove:
```
COPY src/requirements*.txt ./src/
```
(This line appears twice — once in the `deps` stage and once in the `prod-deps` stage around line 206. Remove both occurrences using replace_all.)

- [ ] **Step 6: Fix `fastapi-scaffold/SKILL.md` verification loop (around line 285)**

Find:
```
  for f in requirements.txt src/requirements.txt requirements/*.txt pyproject.toml setup.py setup.cfg; do
```
Replace with:
```
  for f in requirements.txt requirements/*.txt pyproject.toml setup.py setup.cfg; do
```

- [ ] **Step 7: Verify**

Run:
```bash
grep -r "src/requirements.txt" skills/
```
Expected: no output.

```bash
grep "COPY src/requirements" skills/fastapi-scaffold/SKILL.md
```
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add skills/fastapi-add-auth/SKILL.md skills/fastapi-add-database/SKILL.md skills/fastapi-add-integration/SKILL.md skills/shared-add-logging/SKILL.md skills/fastapi-scaffold/SKILL.md
git commit -m "fix(fastapi): correct requirements.txt path — root not src/"
```

---

### Task 2: Add 5 missing workflow skills to AGENTS.md routing table

**Goal:** Make all 12 shared skills discoverable from AGENTS.md so orchestrators know to invoke `shared-build-agent`, `shared-test-agent`, `shared-review-agent`, `shared-update-agent`, and `shared-drift-check`.

**Files:**
- Modify: `AGENTS.md:89-97` (Shared Skills table)

**Acceptance Criteria:**
- [ ] AGENTS.md Shared Skills table has 12 rows (was 7, now 12)
- [ ] All 5 new rows use exact skill directory names (prefixed `shared-`)
- [ ] Each row has a "when to use" clause an LLM would act on

**Verify:** `grep -c "| \`shared-" AGENTS.md` → `12`

**Steps:**

- [ ] **Step 1: Append 5 rows to the Shared Skills table**

Find the current last row of the table:
```
| `shared-task-management` | Complex multi-step features (3+ files, architectural decisions) — opt-in via project `AGENTS.md` |
```
Replace with:
```
| `shared-task-management` | Complex multi-step features (3+ files, architectural decisions) — opt-in via project `AGENTS.md` |
| `shared-build-agent` | After any code change — confirm the project compiles clean |
| `shared-test-agent` | After any code change — run the full test suite |
| `shared-review-agent` | After non-trivial feature work — review code against templateCentral standards |
| `shared-update-agent` | Periodically or before releases — update deps to latest compatible versions |
| `shared-drift-check` | At session start on an existing project — check convention version and dependency freshness |
```

- [ ] **Step 2: Verify row count**

```bash
grep -c "| \`shared-" AGENTS.md
```
Expected: `12`

- [ ] **Step 3: Verify skill names match directory names**

```bash
grep "| \`shared-" AGENTS.md | grep -o "shared-[a-z-]*"
```
Expected output (order may vary):
```
shared-validation-patterns
shared-add-error-handling
shared-add-logging
shared-full-stack-pairing
shared-add-pagination
shared-remove-example
shared-task-management
shared-build-agent
shared-test-agent
shared-review-agent
shared-update-agent
shared-drift-check
```

Cross-check each name against `find skills/shared-* -maxdepth 0 -type d` — all 12 must match a directory.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "fix(agents): add 5 missing workflow skills to shared skills routing table"
```

---

### Task 3: Fix nextjs-scaffold frontmatter description

**Goal:** Remove "NextAuth" from the skill's description so the Claude Code skill list does not mislead agents into thinking auth is bundled.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md` (frontmatter, line ~3)

**Acceptance Criteria:**
- [ ] `grep "NextAuth" skills/nextjs-scaffold/SKILL.md | head -1` returns no frontmatter result (only content lines if any)
- [ ] Description contains "nextjs-add-auth" as a forward reference

**Verify:** `grep "NextAuth" skills/nextjs-scaffold/SKILL.md` → no match on the `description:` line

**Steps:**

- [ ] **Step 1: Read the first 6 lines to confirm current frontmatter**

The current description line reads approximately:
```
description: Use when scaffolding a new Next.js project following templateCentral conventions with App Router, shadcn/ui, TanStack Query, NextAuth, and Docker support
```

- [ ] **Step 2: Replace the description line**

Find:
```
description: Use when scaffolding a new Next.js project following templateCentral conventions with App Router, shadcn/ui, TanStack Query, NextAuth, and Docker support
```
Replace with:
```
description: Use when scaffolding a new Next.js project following templateCentral conventions with App Router, shadcn/ui, TanStack Query, and Docker support (auth added separately via nextjs-add-auth)
```

- [ ] **Step 3: Verify**

```bash
grep "description:" skills/nextjs-scaffold/SKILL.md | head -1
```
Expected: contains "nextjs-add-auth", does not contain "NextAuth".

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "fix(nextjs-scaffold): remove NextAuth from description — auth is opt-in via nextjs-add-auth"
```

---

### Task 4: Add post-scaffold agent workflow to fastapi-scaffold

**Goal:** After verification gates pass and AGENTS.md is written, fastapi-scaffold dispatches `shared-build-agent`, `shared-test-agent`, and `shared-update-agent` with a bypass-warning mechanism. The generated project AGENTS.md template includes a `shared-drift-check` session-start note.

**Files:**
- Modify: `skills/fastapi-scaffold/SKILL.md` (two locations: AGENTS.md template section, and after Step 6)

**Acceptance Criteria:**
- [ ] `grep "shared-build-agent" skills/fastapi-scaffold/SKILL.md` → at least 1 result
- [ ] `grep "shared-test-agent" skills/fastapi-scaffold/SKILL.md` → at least 1 result
- [ ] `grep "shared-drift-check" skills/fastapi-scaffold/SKILL.md` → at least 1 result
- [ ] The bypass warning text "Skipping post-scaffold validation" is present

**Verify:** `grep -c "shared-build-agent\|shared-test-agent\|shared-update-agent" skills/fastapi-scaffold/SKILL.md` → `3` or more

**Steps:**

- [ ] **Step 1: Add drift-check note to the generated AGENTS.md template**

Find the end of the AGENTS.md template block in Step 6. The template currently ends with:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```

Replace that closing section with:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

- [ ] **Step 2: Insert the post-scaffold agent step after Step 6**

Find the heading for Step 7 (CLAUDE.md):
```
### Step 7 — Generate CLAUDE.md (optional — Claude Code users only)
```
Replace with:
```
### Step 6b — Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean and the API starts
2. `shared-test-agent` — verify all scaffold tests pass (`pytest test/ -v`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

---

### Step 7 — Generate CLAUDE.md (optional — Claude Code users only)
```

- [ ] **Step 3: Verify**

```bash
grep -n "shared-build-agent\|shared-test-agent\|shared-update-agent\|shared-drift-check" skills/fastapi-scaffold/SKILL.md
```
Expected: at least 4 results (one per skill).

```bash
grep "Skipping post-scaffold" skills/fastapi-scaffold/SKILL.md
```
Expected: 1 result.

- [ ] **Step 4: Commit**

```bash
git add skills/fastapi-scaffold/SKILL.md
git commit -m "feat(fastapi-scaffold): add post-scaffold agent workflow with bypass warning"
```

---

### Task 5: Add post-scaffold agent workflow to nestjs-scaffold

**Goal:** After verification gates pass and AGENTS.md is written, nestjs-scaffold dispatches the three agent skills with bypass warning. Generated project AGENTS.md includes the drift-check note.

**Files:**
- Modify: `skills/nestjs-scaffold/SKILL.md` (two locations: AGENTS.md template, after Step 6)

**Acceptance Criteria:**
- [ ] `grep "shared-build-agent" skills/nestjs-scaffold/SKILL.md` → at least 1 result
- [ ] `grep "shared-drift-check" skills/nestjs-scaffold/SKILL.md` → at least 1 result
- [ ] Bypass warning text present

**Verify:** `grep -c "shared-build-agent\|shared-test-agent\|shared-update-agent" skills/nestjs-scaffold/SKILL.md` → `3` or more

**Steps:**

- [ ] **Step 1: Add drift-check note to the generated AGENTS.md template**

Find the closing section of the AGENTS.md template in Step 6:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```
Replace with:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

- [ ] **Step 2: Insert the post-scaffold agent step after Step 6**

Find the heading for Step 7 (CLAUDE.md):
```
### 7. Generate CLAUDE.md (Optional — Claude Code users only)
```
Replace with:
```
### 6b. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean (`pnpm build`)
2. `shared-test-agent` — verify all scaffold tests pass (`pnpm test && pnpm test:e2e`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

---

### 7. Generate CLAUDE.md (Optional — Claude Code users only)
```

- [ ] **Step 3: Verify**

```bash
grep -n "shared-build-agent\|shared-test-agent\|shared-update-agent\|shared-drift-check" skills/nestjs-scaffold/SKILL.md
```
Expected: at least 4 results.

- [ ] **Step 4: Commit**

```bash
git add skills/nestjs-scaffold/SKILL.md
git commit -m "feat(nestjs-scaffold): add post-scaffold agent workflow with bypass warning"
```

---

### Task 6: Add post-scaffold agent workflow to vite-react-scaffold

**Goal:** After verification gates pass and AGENTS.md is written, vite-react-scaffold dispatches the three agent skills with bypass warning. Generated project AGENTS.md includes the drift-check note.

**Files:**
- Modify: `skills/vite-react-scaffold/SKILL.md` (two locations: AGENTS.md template in Step 7, new step after Step 7)

**Acceptance Criteria:**
- [ ] `grep "shared-build-agent" skills/vite-react-scaffold/SKILL.md` → at least 1 result
- [ ] `grep "shared-drift-check" skills/vite-react-scaffold/SKILL.md` → at least 1 result
- [ ] Bypass warning text present

**Verify:** `grep -c "shared-build-agent\|shared-test-agent\|shared-update-agent" skills/vite-react-scaffold/SKILL.md` → `3` or more

**Steps:**

- [ ] **Step 1: Add drift-check note to the generated AGENTS.md template**

Find the closing section of the AGENTS.md template in Step 7:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->
```
Replace with:
```
## Project-Specific Notes
<!-- Add decisions, custom patterns, and context as the project evolves -->

## Session Start
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

- [ ] **Step 2: Insert the post-scaffold agent step after Step 7**

Find the heading for Step 8 (CLAUDE.md):
```
### 8. Generate `CLAUDE.md` (optional — Claude Code users only)
```
Replace with:
```
### 7b. Post-scaffold agent workflow

After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean (`pnpm build && pnpm typecheck`)
2. `shared-test-agent` — verify all scaffold tests pass (`pnpm test`)
3. `shared-update-agent` — freshen any deps that have newer compatible versions

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.

---

### 8. Generate `CLAUDE.md` (optional — Claude Code users only)
```

- [ ] **Step 3: Verify**

```bash
grep -n "shared-build-agent\|shared-test-agent\|shared-update-agent\|shared-drift-check" skills/vite-react-scaffold/SKILL.md
```
Expected: at least 4 results.

- [ ] **Step 4: Commit**

```bash
git add skills/vite-react-scaffold/SKILL.md
git commit -m "feat(vite-react-scaffold): add post-scaffold agent workflow with bypass warning"
```

---

### Task 7: Standardise nextjs-scaffold Step 7 agent dispatch

**Goal:** Update the existing nextjs-scaffold agent dispatch step to use the `shared-` prefixed skill names, add the missing `shared-test-agent`, replace the redundant second `build-agent` call, and add a bypass warning. Also standardise the drift-check reference to `shared-drift-check`.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md` (two locations: AGENTS.md template drift-check note at ~line 1706, Step 7 at lines 1742-1750)

**Acceptance Criteria:**
- [ ] `grep "shared-test-agent" skills/nextjs-scaffold/SKILL.md` → at least 1 result
- [ ] `grep "\bbuild-agent\b" skills/nextjs-scaffold/SKILL.md` returns only `shared-build-agent` (no bare `build-agent`)
- [ ] `grep "shared-drift-check" skills/nextjs-scaffold/SKILL.md` → at least 1 result
- [ ] Bypass warning text present

**Verify:** `grep "build-agent\|update-agent\|test-agent" skills/nextjs-scaffold/SKILL.md | grep -v "shared-"` → no output (all agent refs are prefixed)

**Steps:**

- [ ] **Step 1: Update drift-check note in generated AGENTS.md template**

Find (around line 1706):
```
> **Session start:** Invoke the `drift-check` skill to check for templateCentral convention and dependency updates before starting work.
```
Replace with:
```
> **Session start:** Run `shared-drift-check` to check for templateCentral convention and dependency updates before starting work.
```

- [ ] **Step 2: Rewrite Step 7 dispatch block**

Find the current Step 7 body (lines 1744-1748):
```
After AGENTS.md is written, dispatch in order:

1. **build-agent** — run `pnpm build && pnpm check`, verify no errors
2. **update-agent** — freshen all dependencies to latest patch/minor versions
3. **build-agent** — verify build still passes after dep updates
```
Replace with:
```
After AGENTS.md is written, run the following agent skills in order. These are **on by default** — skipping requires explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean (`pnpm build && pnpm check`)
2. `shared-test-agent` — verify all scaffold tests pass (`pnpm test`)
3. `shared-update-agent` — freshen all dependencies to latest compatible versions

**If the user asks to skip:** Warn: "Skipping post-scaffold validation means undetected issues may exist in the project. This is not recommended." Ask for explicit confirmation before proceeding. Only skip all three if the user confirms.
```

- [ ] **Step 3: Fix the Rules section trailing reference**

Find (in the Rules/Changelog section near the end):
```
- update-agent replaces lockfile for dependency freshness
```
Replace with:
```
- shared-update-agent replaces lockfile for dependency freshness
```

- [ ] **Step 4: Verify no bare agent references remain**

```bash
grep "build-agent\|update-agent\|test-agent\|drift-check" skills/nextjs-scaffold/SKILL.md | grep -v "shared-"
```
Expected: no output.

```bash
grep -c "shared-build-agent\|shared-test-agent\|shared-update-agent" skills/nextjs-scaffold/SKILL.md
```
Expected: `3` or more.

- [ ] **Step 5: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "fix(nextjs-scaffold): standardise agent dispatch — shared- prefix, add test-agent, bypass warning"
```
