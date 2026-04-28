# Shared Skills Bug Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 confirmed bug classes across 7 shared skills — stack detection accuracy, slash-format skill references, file upload security, and missing security audit step.

**Architecture:** Seven targeted SKILL.md edits, no cross-file dependencies. Tasks 1 and 2 are independent. Task 3 and 4 are independent.

**Tech Stack:** Markdown skill files only — no runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-04-28-shared-skills-bugs-design.md`

---

### Task 1: Fix stack detection — add `next.config.mjs` to 4 skills

**Goal:** Update Next.js stack detection in build, test, update, and review agents to recognise `next.config.mjs`.

**Files:**
- Modify: `skills/shared-build-agent/SKILL.md`
- Modify: `skills/shared-test-agent/SKILL.md`
- Modify: `skills/shared-update-agent/SKILL.md`
- Modify: `skills/shared-review-agent/SKILL.md`

**Acceptance Criteria:**
- [ ] `shared-build-agent` table row for Next.js includes `next.config.mjs`
- [ ] `shared-build-agent` error message includes `.mjs`
- [ ] `shared-test-agent` stack detection prose includes `next.config.mjs`
- [ ] `shared-update-agent` stack detection prose includes `next.config.mjs`
- [ ] `shared-review-agent` stack detection prose includes `next.config.mjs`
- [ ] No other lines changed in any of the 4 files

**Verify:** `grep -n "next\.config" skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-review-agent/SKILL.md`
→ Every Next.js detection line mentions `.mjs`

**Steps:**

- [ ] **Step 1: Edit shared-build-agent**

Find (around line 16):
```
| `next.config.ts` or `next.config.js` | Next.js |
```
Replace with:
```
| `next.config.ts`, `next.config.js`, or `next.config.mjs` | Next.js |
```

Find the error message (around line 68):
```
Build agent: could not detect stack. No next.config.ts, vite.config.ts, nest-cli.json, or fastapi in requirements.txt found at project root.
```
Replace with:
```
Build agent: could not detect stack. No next.config.ts/.js/.mjs, vite.config.ts/.js, nest-cli.json, or fastapi in requirements.txt found at project root.
```

- [ ] **Step 2: Edit shared-test-agent**

Find (around line 12):
```
Same as `build-agent`: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.
```
Replace with:
```
Same as `build-agent`: check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

- [ ] **Step 3: Edit shared-update-agent**

Find (around line 12):
```
Same as `build-agent`: check for `next.config.ts`, `vite.config.ts`, `nest-cli.json`, `requirements.txt` containing `fastapi`.
```
Replace with:
```
Same as `build-agent`: check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

- [ ] **Step 4: Edit shared-review-agent**

Find (around line 12):
```
Check for `next.config.ts` → Next.js, `vite.config.ts` → Vite-React, `nest-cli.json` → NestJS, `requirements.txt` containing `fastapi` → FastAPI.
```
Replace with:
```
Check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI.
```

- [ ] **Step 5: Verify**

```bash
grep -n "next\.config" skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-review-agent/SKILL.md
```

Every line mentioning `next.config` must include `.mjs`.

- [ ] **Step 6: Commit**

```bash
git add skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-review-agent/SKILL.md
git commit -m "fix(shared-agents): add next.config.mjs to stack detection in 4 skills"
```

---

### Task 2: Fix slash-format skill name references in 7 skills

**Goal:** Replace all `stack/skill-name` slash-format cross-skill references with correct `stack-skill-name` dash format.

**Files:**
- Modify: `skills/shared-build-agent/SKILL.md`
- Modify: `skills/shared-test-agent/SKILL.md`
- Modify: `skills/shared-update-agent/SKILL.md`
- Modify: `skills/shared-add-error-handling/SKILL.md`
- Modify: `skills/shared-add-logging/SKILL.md`
- Modify: `skills/shared-add-pagination/SKILL.md`
- Modify: `skills/shared-validation-patterns/SKILL.md`

**Acceptance Criteria:**
- [ ] `grep -r "nextjs/\|vite-react/\|fastapi/\|nestjs/\|shared/" skills/shared-*/SKILL.md` returns only `@nestjs/` npm package imports, no skill name references
- [ ] All callers/related-skills sections use dash-format names
- [ ] No other lines changed

**Verify:**
```bash
grep -rn "nextjs/\|vite-react/\|fastapi/\|nestjs/\|shared/" skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-add-error-handling/SKILL.md skills/shared-add-logging/SKILL.md skills/shared-add-pagination/SKILL.md skills/shared-validation-patterns/SKILL.md | grep -v "@nestjs/"
```
→ No output.

**Steps:**

- [ ] **Step 1: Fix shared-build-agent Callers section**

Find the Callers line (around line 75):
```
This skill is dispatched by: `nextjs/scaffold`, `vite-react/scaffold`, `fastapi/scaffold`, `nestjs/scaffold`, `shared/update-agent`, `nextjs/add-feature`, `nextjs/add-component`, `nextjs/add-api-route`, `vite-react/add-feature`, `vite-react/add-component`, `fastapi/add-endpoint`, `nestjs/add-module`.
```
Replace with:
```
This skill is dispatched by: `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-update-agent`, `nextjs-add-feature`, `nextjs-add-component`, `nextjs-add-api-route`, `vite-react-add-feature`, `vite-react-add-component`, `fastapi-add-endpoint`, `nestjs-add-module`.
```

- [ ] **Step 2: Fix shared-test-agent — dispatch list and Callers**

Find the dispatch list (around lines 18–21). It contains lines like:
```
   - Next.js → `nextjs/add-test`
   - Vite-React → `vite-react/add-test`
   - FastAPI → `fastapi/add-test`
   - NestJS → `nestjs/add-test`
```
Replace each with dash format:
```
   - Next.js → `nextjs-add-test`
   - Vite-React → `vite-react-add-test`
   - FastAPI → `fastapi-add-test`
   - NestJS → `nestjs-add-test`
```

Find the Callers line (around line 64):
```
Dispatched by: `nextjs/add-feature`, `nextjs/add-api-route`, `vite-react/add-feature`, `fastapi/add-endpoint`, `nestjs/add-module`.
```
Replace with:
```
Dispatched by: `nextjs-add-feature`, `nextjs-add-api-route`, `vite-react-add-feature`, `fastapi-add-endpoint`, `nestjs-add-module`.
```

- [ ] **Step 3: Fix shared-update-agent Callers section**

Find (around line 80):
```
Dispatched by: `nextjs/scaffold`, `vite-react/scaffold`, `fastapi/scaffold`, `nestjs/scaffold`, `shared/drift-check` (when drift detected and user accepts update).
```
Replace with:
```
Dispatched by: `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`, `shared-drift-check` (when drift detected and user accepts update).
```

- [ ] **Step 4: Fix shared-add-error-handling Related Skills**

Find (near end of file):
```
- `shared/add-logging` — Integrate structured logging with error handlers
- `shared/validation-patterns` — Zod/Pydantic schemas for validation errors
```
Replace with:
```
- `shared-add-logging` — Integrate structured logging with error handlers
- `shared-validation-patterns` — Zod/Pydantic schemas for validation errors
```

- [ ] **Step 5: Fix shared-add-logging Related Skills**

Find (near end of file):
```
- `shared/add-error-handling` — Unified error response schema; `logError` integration
- `shared/validation-patterns` — Zod/Pydantic validation before any log call
```
Replace with:
```
- `shared-add-error-handling` — Unified error response schema; `logError` integration
- `shared-validation-patterns` — Zod/Pydantic validation before any log call
```

- [ ] **Step 6: Fix shared-add-pagination — body references and Related Skills**

Find all occurrences of `shared/add-error-handling` and `shared/validation-patterns` in the file (there are ~5 total) and replace each with `shared-add-error-handling` and `shared-validation-patterns` respectively.

Key locations:
- Around line 29: `shared/add-error-handling` in prose
- Around line 58: `shared/add-error-handling` in error response note
- Around line 73: `shared/validation-patterns` in validation note
- Near end: Related Skills section with both references

- [ ] **Step 7: Fix shared-validation-patterns Related Skills**

Find (near end of file):
```
- `shared/add-error-handling` — Transform validation errors to consistent response format
- `shared/add-logging` — Log validation failures with context
```
Replace with:
```
- `shared-add-error-handling` — Transform validation errors to consistent response format
- `shared-add-logging` — Log validation failures with context
```

- [ ] **Step 8: Verify**

```bash
grep -rn "nextjs/\|vite-react/\|fastapi/\|nestjs/\|shared/" skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-add-error-handling/SKILL.md skills/shared-add-logging/SKILL.md skills/shared-add-pagination/SKILL.md skills/shared-validation-patterns/SKILL.md | grep -v "@nestjs/"
```
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add skills/shared-build-agent/SKILL.md skills/shared-test-agent/SKILL.md skills/shared-update-agent/SKILL.md skills/shared-add-error-handling/SKILL.md skills/shared-add-logging/SKILL.md skills/shared-add-pagination/SKILL.md skills/shared-validation-patterns/SKILL.md
git commit -m "fix(shared-skills): correct slash-format skill references to dash format across 7 skills"
```

---

### Task 3: Fix file upload security in `shared-validation-patterns`

**Goal:** Expand the extension blocklist and add URL-decode protection to the path traversal check.

**Files:**
- Modify: `skills/shared-validation-patterns/SKILL.md`

**Acceptance Criteria:**
- [ ] Extension blocklist includes Windows executables, scripts, Unix shells, PHP variants, Java types, and libraries
- [ ] Path traversal refinement calls `decodeURIComponent` wrapped in try/catch
- [ ] Path traversal check also rejects `./` relative paths
- [ ] No other lines in the file changed

**Verify:**
```bash
grep -A 20 "File validation" skills/shared-validation-patterns/SKILL.md | head -30
```
→ Shows expanded blocklist and `decodeURIComponent` in the traversal check.

**Steps:**

- [ ] **Step 1: Replace the fileUploadSchema filename refinements**

Find this exact block (around lines 64–79):
```ts
export const fileUploadSchema = z.object({
  name: z
    .string()
    .refine(
      (name) => !name.includes('..') && !name.startsWith('/'),
      'Invalid filename'
    )
    .refine(
      (name) => {
        const ext = name.split('.').pop()?.toLowerCase();
        const blocked = ['exe', 'sh', 'bat', 'cmd', 'dll'];
        return !blocked.includes(ext || '');
      },
      'File type not allowed'
    ),
```

Replace with:
```ts
export const fileUploadSchema = z.object({
  name: z
    .string()
    .refine(
      (name) => {
        try {
          const decoded = decodeURIComponent(name);
          return !decoded.includes('..') && !decoded.startsWith('/') && !decoded.startsWith('./');
        } catch {
          return false;
        }
      },
      'Invalid filename'
    )
    .refine(
      (name) => {
        const ext = name.split('.').pop()?.toLowerCase();
        const blocked = [
          'exe', 'com', 'scr', 'pif', 'msi', 'msp',  // Windows executables
          'bat', 'cmd', 'vbs', 'ps1', 'hta',           // Windows scripts
          'sh', 'bash', 'zsh', 'csh',                  // Unix shells
          'php', 'php3', 'php4', 'php5', 'phtml',      // PHP variants
          'jsp', 'jspx', 'jnlp', 'jar',                // Java
          'dll', 'so', 'dylib',                         // Libraries
        ];
        return !blocked.includes(ext || '');
      },
      'File type not allowed'
    ),
```

- [ ] **Step 2: Verify**

```bash
grep -A 30 "File validation" skills/shared-validation-patterns/SKILL.md | head -35
```
Expected: shows `decodeURIComponent`, `startsWith('./')`, and the expanded blocklist with comments.

- [ ] **Step 3: Commit**

```bash
git add skills/shared-validation-patterns/SKILL.md
git commit -m "fix(validation-patterns): expand file upload blocklist and add URL-decode to path traversal check"
```

---

### Task 4: Add security audit step to `shared-update-agent`

**Goal:** Add `pnpm audit --audit-level=high` (Node) and `pip-audit` (FastAPI) steps after a successful build, with report-only behavior and graceful skip for missing tools.

**Files:**
- Modify: `skills/shared-update-agent/SKILL.md`

**Acceptance Criteria:**
- [ ] Node steps list includes audit step after build-agent dispatch
- [ ] FastAPI steps list includes audit step after build-agent dispatch
- [ ] Audit step is report-only (no auto-rollback on CVE findings)
- [ ] FastAPI audit gracefully skips if `pip-audit` is not installed
- [ ] Reporting section includes "Security advisories" block description
- [ ] No other lines changed

**Verify:**
```bash
grep -n "audit" skills/shared-update-agent/SKILL.md
```
→ Shows audit commands in both Node and FastAPI sections plus reporting description.

**Steps:**

- [ ] **Step 1: Add audit step to Node Stacks section**

Find (around lines 29–32):
```
4. Rewrite `package.json` with bumped versions (keep `^` prefix for all updated deps)
5. Run `pnpm install`
6. Dispatch `build-agent`
7. If build fails → rollback (see Rollback below)
8. Report results (see Reporting below)
```
Replace with:
```
4. Rewrite `package.json` with bumped versions (keep `^` prefix for all updated deps)
5. Run `pnpm install`
6. Dispatch `build-agent`
7. If build fails → rollback (see Rollback below)
8. Run `pnpm audit --audit-level=high`
   - Report any high/critical CVEs under "Security advisories" in the results summary
   - Do NOT auto-rollback — advisories are report-only; the user decides next steps
9. Report results (see Reporting below)
```

- [ ] **Step 2: Add audit step to FastAPI section**

Find (around lines 43–46):
```
4. Rewrite `requirements.txt` with exact pinned versions (`package==new_version`)
5. Run `pip install -r requirements.txt`
6. Dispatch `build-agent`
7. If build fails → rollback
8. Report results
```
Replace with:
```
4. Rewrite `requirements.txt` with exact pinned versions (`package==new_version`)
5. Run `pip install -r requirements.txt`
6. Dispatch `build-agent`
7. If build fails → rollback
8. Run `pip-audit` if available (`pip-audit --requirement requirements.txt`)
   - If `pip-audit` is not installed: add note "pip-audit not installed — CVE check skipped" to report
   - If run: report any vulnerabilities under "Security advisories" in the results summary
   - Do NOT auto-rollback — advisories are report-only; the user decides next steps
9. Report results
```

- [ ] **Step 3: Update Reporting section**

Find the Reporting block (around lines 59–76) and add the Security advisories block after the "Could not update" block:

```
Security advisories (pnpm audit / pip-audit):
- some-package 2.3.0: GHSA-xxxx-xxxx-xxxx (high) — upgrade to 2.3.1 or higher
```

Add the following note after the `Build: passed` line in the example:
```
Security advisories:
- (none) or list of CVEs found
```

And add to the prose before the example block:
```
If security advisories are found, list them under "Security advisories". If none are found, omit the block.
```

- [ ] **Step 4: Verify**

```bash
grep -n "audit" skills/shared-update-agent/SKILL.md
```
Expected: lines referencing `pnpm audit`, `pip-audit`, "Security advisories" in both sections and reporting.

- [ ] **Step 5: Commit**

```bash
git add skills/shared-update-agent/SKILL.md
git commit -m "fix(update-agent): add security audit step after dependency updates"
```
