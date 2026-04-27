# templateCentral Routing & Scaffold Consistency

**Goal:** Fix four accuracy bugs, close an agent-routing gap, and make post-scaffold agent dispatch consistent and automatic across all four stacks.

**Architecture:** All changes are targeted edits to existing skill files and AGENTS.md — no new skills, no structural changes. Each fix is independent.

**Tech stack:** Claude Code plugin (Markdown skill files, YAML frontmatter, no build step).

---

## Change 1 — FastAPI `requirements.txt` path bug

**Problem:** Four skills tell agents to add packages to `src/requirements.txt`. The fastapi-scaffold places `requirements.txt` at the **project root**, not in `src/`. An agent following these instructions will either create a stray `src/requirements.txt` or fail to find the file.

The fastapi-scaffold Dockerfile also has two defensive `COPY src/requirements*.txt ./src/` lines (lines 188 and 206) that silently no-op but reinforce the wrong mental model. A verification loop at line 285 also checks for `src/requirements.txt`.

**Fix:** In all four files, replace every instance of the path `src/requirements.txt` (as an instruction target for adding packages) with `requirements.txt`. In `fastapi-scaffold/SKILL.md`, remove the two `COPY src/requirements*.txt ./src/` lines from both Dockerfile stages and remove `src/requirements.txt` from the verification loop.

**Files:**
- `skills/fastapi-add-auth/SKILL.md`
- `skills/fastapi-add-database/SKILL.md`
- `skills/fastapi-add-integration/SKILL.md`
- `skills/shared-add-logging/SKILL.md` (FastAPI section only)
- `skills/fastapi-scaffold/SKILL.md` (Dockerfile lines 188, 206, 285)

**Acceptance criteria:**
- `grep -r "src/requirements.txt" skills/` → zero results
- Dockerfile in fastapi-scaffold has no `COPY src/requirements*.txt` line
- The verification loop in fastapi-scaffold checks only `requirements.txt` (not `src/requirements.txt`)

---

## Change 2 — AGENTS.md: add 5 missing workflow skills

**Problem:** Five shared skills are registered in `plugin.json`, have SKILL.md files, and are usable — but are absent from AGENTS.md's Shared Skills routing table. An orchestrator agent reading AGENTS.md would never know they exist and would never invoke them.

Missing skills: `shared-build-agent`, `shared-drift-check`, `shared-review-agent`, `shared-test-agent`, `shared-update-agent`.

**Fix:** Add five rows to the Shared Skills table in AGENTS.md, after the existing seven, with clear "when to use" descriptions that tell an agent exactly when to invoke each one.

```markdown
| `shared-build-agent`  | After any code change — confirm the project compiles clean |
| `shared-test-agent`   | After any code change — run the full test suite |
| `shared-review-agent` | After non-trivial feature work — review code against templateCentral standards |
| `shared-update-agent` | Periodically or before releases — update deps to latest compatible versions |
| `shared-drift-check`  | At session start on an existing project — check convention version and dependency freshness |
```

**Files:**
- `AGENTS.md`

**Acceptance criteria:**
- AGENTS.md Shared Skills table has 12 rows (7 existing + 5 new)
- Each new row has a "when to use" clause specific enough that an LLM would invoke it in the right context
- All 5 added skill names exactly match their directory names in `skills/`

---

## Change 3 — Consistent post-scaffold agent dispatch (all 4 stacks)

**Problem:** `nextjs-scaffold` already dispatches `shared-build-agent` and `shared-update-agent` as a final step after verification gates pass, and includes a `drift-check` note in the generated project AGENTS.md. The other three scaffolds (`fastapi-scaffold`, `nestjs-scaffold`, `vite-react-scaffold`) do neither. Only Next.js projects get automatic post-scaffold validation.

**Fix:** Add an identical final step to all three missing scaffolds. Update the generated project AGENTS.md template inside all three scaffolds to include the `drift-check` note. Also verify the existing nextjs-scaffold step matches the new standard and update if needed (e.g. adding `shared-test-agent` if missing).

**The standard post-scaffold agent step (to be consistent across all 4 scaffolds):**

```markdown
### Step N — Post-scaffold agent workflow

Run the following agent skills in order. These are **on by default** — skipping requires
explicit user confirmation and is not recommended.

1. `shared-build-agent` — verify the scaffold compiles clean
2. `shared-test-agent` — verify all scaffold tests pass
3. `shared-update-agent` — freshen any deps that have newer compatible versions

**If the user asks to skip:**
Warn: "Skipping post-scaffold validation means undetected issues may exist in the project.
This is not recommended." Ask for explicit confirmation before proceeding.
```

**The standard drift-check note for generated project AGENTS.md (all 4 stacks):**

```markdown
Run `shared-drift-check` at the start of each session to check for convention or dependency drift.
```

**Files:**
- `skills/fastapi-scaffold/SKILL.md` — add Step N, add drift-check to generated AGENTS.md template
- `skills/nestjs-scaffold/SKILL.md` — add Step N, add drift-check to generated AGENTS.md template
- `skills/vite-react-scaffold/SKILL.md` — add Step N, add drift-check to generated AGENTS.md template
- `skills/nextjs-scaffold/SKILL.md` — verify existing step matches standard; add `shared-test-agent` if absent; confirm drift-check note is in generated AGENTS.md template

**Acceptance criteria:**
- All 4 scaffold skills have a final step dispatching `shared-build-agent`, `shared-test-agent`, and `shared-update-agent` (in that order)
- All 4 steps include the bypass warning and confirmation requirement
- All 4 scaffold-generated project AGENTS.md templates include the `shared-drift-check` note
- `grep -n "shared-build-agent" skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md` → at least one result per file

---

## Change 4 — Fix `nextjs-scaffold` frontmatter description

**Problem:** The `description:` field in `nextjs-scaffold/SKILL.md` frontmatter reads `"...with App Router, shadcn/ui, TanStack Query, NextAuth, and Docker support"`. Auth is **not** included in the scaffold — it is added separately via `nextjs-add-auth`. This description surfaces in Claude Code's skill list and could cause an agent or user to assume auth is pre-wired.

**Fix:** Remove "NextAuth" from the description. Add a parenthetical to avoid confusion.

```yaml
description: >
  Use when scaffolding a new Next.js project following templateCentral conventions
  with App Router, shadcn/ui, TanStack Query, and Docker support
  (auth added separately via nextjs-add-auth)
```

**Files:**
- `skills/nextjs-scaffold/SKILL.md` (frontmatter only, first 5 lines)

**Acceptance criteria:**
- Frontmatter description contains no "NextAuth" substring
- Description contains "nextjs-add-auth" as a hint for where to find auth

---

## Out of scope

- Normalising `name:` frontmatter fields across skills (cosmetic; no functional impact since routing is by directory name)
- Archiving `docs/superpowers/plans/` (historical; no correctness impact)
- Removing `.pnpm-store/` from disk (not tracked by git; local cleanup only)
- Removing `.DS_Store` (already in `.gitignore`; remove separately)

---

## Execution order

Changes 1, 2, and 4 are independent and can be executed in any order. Change 3 depends on Change 2 being complete (so the added skill names in AGENTS.md match before scaffold steps reference them). Suggested order: 1 → 2 → 4 → 3.
