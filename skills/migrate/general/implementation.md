<!-- ref: migrate/general/implementation.md
     loaded-by: migrate/SKILL.md
     prereq: Migration workflow. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Migrate or Adopt Project

Detects the stack, asks the user once, then runs autonomously.

**Phase files.** Phases 0–3 are below. Load Phase 4 or 5 only when Phase 0 routes to it. The shared kits load **here**, so every chain stays within two `cat` hops (CONVENTIONS §2). `<variant-file>` is `harness-kit-ts.md` for nestjs / nextjs / vite-react and `harness-kit-fastapi.md` for fastapi — load only that one.

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

"The Step 4b marker update" means: set line 1 of `AGENTS.md` to `<!-- templateCentral: <stack>@6.0.0 -->`.

---

## Phase 0 — Check for Version Upgrade (agent, autonomous)

Check `AGENTS.md` line 1 for a templateCentral version marker:

```
<!-- templateCentral: <stack>@<version> -->
```

**If no marker** → skip to Phase 1 (stack detection).

**If marker present, version `@6.0.0` or later** → check whether `.claude/harness.json` exists:

- **`.claude/harness.json` exists** → print:
  ```
  ✓ This project is at templateCentral v6.0.0 or later. No migration needed.
  ```
  Then load and run **Phase 5** (5a–5c; offer 5d) — see the phase table above.

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

**If marker present, version `@5.0.0` through `@5.x`** → the hooks are inert: pre-6.0.0 schemas wrote
each `settings.json` hook with an array-valued `command`, which Claude Code silently skips. Re-seed
them in exec form (`"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>"]`)
from the harness kit. Skip Phases 1–3 and present:
```
⚠ This project was scaffolded with templateCentral <version>.

Its .claude/settings.json hooks use an array-form "command", which Claude Code
silently ignores — the harness guards have never actually run.

v6.0 re-seeds the enforcement layer from the harness kit:
- settings.json hooks rewritten to exec form ("command" + "args", ${CLAUDE_PROJECT_DIR} paths)
- .claude/hooks/* reset to canonical (post-tool-failure.sh removed — Claude already sees tool errors)

Re-sync? (A) Yes  (B) Skip
```
User A → first do the Step 4b marker update, before anything hashes `AGENTS.md` (or its
`origin_hash` goes stale). Then, if `.claude/harness.json` exists, run Phase 5 (5a–5c) and the
Step 5d re-sync, which replaces the array-form entries; otherwise proceed to Phase 4.
User B → print "No changes made — hooks remain inert until re-synced." Exit.

**If marker present, version `@4.0.0` through `@4.x`** → skip Phases 1–3. Present:
```
ℹ️ This project was scaffolded with templateCentral <version>.

v5.0 converts seeded project skills to directory form:
- .claude/skills/<name>/SKILL.md  — flat <name>.md files are silently ignored by Claude Code
v6.0 re-seeds settings.json hooks in exec form — earlier array-form hooks never ran

Upgrade? (A) Yes  (B) Skip
```
User A → proceed to Phase 4.
User B → print "No changes made." Exit.

**If marker present, version earlier than `@4.0.0`** → skip Phases 1–3. Present:
```
ℹ️ This project was scaffolded with templateCentral <version>.

v4.0 adds an AI harness layer to all scaffolds:
- .claude/settings.json  — PreToolUse (.env guard), PostToolUse (type-check), Stop (test suite), SessionStart (re-injects AGENTS.md after compaction)
- AGENTS.md              — ## AI Harness section with post-harness seams

Upgrade? (A) Yes  (B) Skip
```
User A → proceed to Phase 4.
User B → print "No changes made." Exit.

---

## Phase 1 — Detect Stack (agent, autonomous)

Scan the current directory for stack signals:

| Signal | Stack |
|---|---|
| `next.config.ts` or `next.config.js` or `next.config.mjs` present | Next.js |
| `vite.config.ts` or `vite.config.js` present AND no `next.config.*` | Vite + React |
| `requirements.txt` contains `fastapi` | FastAPI |
| `nest-cli.json` present, or `@nestjs/core` in `package.json` | NestJS |

If multiple signals found (likely a monorepo root) → ask the user: "Which project
should be adopted first — frontend or backend? Please provide the subdirectory path."
Re-run detection there; Phases 2 and 3 then work in that subdirectory, not the original working directory.

If no signals found → tell the user: "No recognised stack detected in this directory.
Please run this skill from a project directory, not a parent folder." Exit.

If ambiguous (e.g. vite.config.ts without the React plugin) → ask the user to confirm the stack.

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

B) Stop
   Exit without changes. Run `templatecentral:scaffold` to start
   a fresh project, or proceed manually.

Which would you prefer? (A / B)
```

---

## Phase 3 — Execute (agent, autonomous after gate)

### If A — Light adoption

**Step A1: Write the marker**

Make `<!-- templateCentral: <stack>@6.0.0 -->` the first line of `AGENTS.md`, above the original
content; if the file does not exist, create it with that line only.

**Step A2: Scan for structural gaps**

List any that are absent for the detected stack.

**Next.js gaps:**
- `src/app/` directory
- `src/features/` directory
- `src/components/` directory
- `src/lib/` directory

**Vite + React gaps:**
- `src/features/` directory
- `src/components/` directory
- `src/lib/` directory

**FastAPI gaps:**
- `src/api/routers/` directory
- `src/models/` directory
- `src/core/config.py`

**NestJS gaps:**
- `src/modules/` directory
- `src/common/` directory
- `src/config/` directory

**Step A3: Print adoption summary and return**

Print:

```
✓ Project adopted as <stack>@6.0.0.

Structural gaps noted (review files generated by the invoking skill carefully
where your project structure differs from templateCentral conventions):
- [list each missing item, or "None — structure matches templateCentral conventions"]

Returning to the skill that invoked me — proceeding from Step 1.
```

Return control; the invoking skill continues from Step 1.

### If B — Stop

Print: "No changes made."

Return control; the invoking skill must exit without generating any files.

---
