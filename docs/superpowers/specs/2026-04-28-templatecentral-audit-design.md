# templateCentral Audit — Design Spec

**Date:** 2026-04-28
**Scope:** Option B — fix confirmed routing bug + restore 4 missing Next.js scaffold files from deleted `templates/` baseline

---

## Background

Full audit of all 46 skills, root `AGENTS.md`, plugin manifests, and git history against the deleted `templates/` directory (removed in commit `591ce19` during plugin-first migration). Goal: highest priority on accuracy and security; token reduction secondary; leave minor issues that do not affect either.

---

## Findings

### What is clean (no changes needed)

- No literal TODO stubs anywhere in any skill
- No stale `next-auth` or `templates/` references in skills (cleaned in prior commits)
- Version markers (`<!-- templateCentral: nextjs@1.0.0 -->`) correctly match each scaffold skill's `version: "1.0.0"` frontmatter field
- Auth stubs in `fastapi-add-auth` and `nestjs-add-auth` are intentional, clearly documented — leave as-is
- Code quality section duplication across skills and `AGENTS.md` is intentional for agent access — leave as-is
- **FastAPI:** All test subdirectories (`test_logic/`, `test_models/`, `test_utils/`, `test_api/test_health.py`) present in scaffold ✓
- **NestJS:** Full template structure represented; integrations correctly use `src/modules/<name>-integration/` (NestJS module convention, not a separate integrations dir) ✓
- **Vite-React:** `src/hooks/index.ts`, `src/lib/constants/index.ts`, `src/lib/errors/index.ts` all present; `src/integrations/` correctly absent at scaffold time (documented as created on first `add-integration` use) ✓

### Confirmed bug (affects accuracy — must fix)

**`shared-drift-check` Step 2 — wrong skill name format**

The routing table maps stack markers to scaffold skill names using slash format:

```
| nextjs     | nextjs/scaffold     |
| vite-react | vite-react/scaffold |
| fastapi    | fastapi/scaffold    |
| nestjs     | nestjs/scaffold     |
```

Actual plugin skill names use dash format: `nextjs-scaffold`, `vite-react-scaffold`, `fastapi-scaffold`, `nestjs-scaffold`. An agent following this table would fail to load the correct skill.

**Fix:** Replace all four slash-format entries with dash-format.

### Structural gaps — Next.js scaffold only

Comparing `templates/nextjs/` (deleted) against the current `nextjs-scaffold` skill's directory tree, four files present in the template are missing from the scaffold:

| File | Template had it | Current scaffold | Impact |
|---|---|---|---|
| `src/hooks/index.ts` | ✓ | Missing | add-* skills that append shared hooks have no barrel to append to |
| `src/lib/constants/index.ts` | ✓ | Missing | `@/lib/constants` import path resolves nothing; add-* skills expect a barrel |
| `src/integrations/schemas/.gitkeep` | ✓ | Missing | `add-integration` creates this dir on first use, but no placeholder means the directory architecture is not visible at scaffold time |
| `src/integrations/factories.ts` | ✓ | Missing | `nextjs-add-integration` Step 4 appends to this file; without a scaffold baseline the agent must create it from scratch with no structural reference |

Vite-React, NestJS, and FastAPI have **no equivalent gaps**.

---

## Changes

### Change 1 — `skills/shared-drift-check/SKILL.md`

In Step 2, replace the scaffold skill routing table:

**Before:**
```
| nextjs     | nextjs/scaffold     |
| vite-react | vite-react/scaffold |
| fastapi    | fastapi/scaffold    |
| nestjs     | nestjs/scaffold     |
```

**After:**
```
| nextjs     | nextjs-scaffold     |
| vite-react | vite-react-scaffold |
| fastapi    | fastapi-scaffold    |
| nestjs     | nestjs-scaffold     |
```

---

### Change 2 — `skills/nextjs-scaffold/SKILL.md` — directory tree

Add 4 entries to the directory tree (Part A):

```
├── src/
│   ├── hooks/
│   │   └── index.ts                [verbatim — Part C]   ← ADD
│   ├── lib/
│   │   ├── constants/
│   │   │   ├── index.ts            [verbatim — Part C]   ← ADD
│   │   │   ├── env.ts
│   │   │   └── routes.ts
│   ├── integrations/
│   │   ├── factories.ts            [verbatim — Part C]   ← ADD
│   │   ├── error.ts
│   │   ├── schemas/
│   │   │   └── .gitkeep            [verbatim — empty]    ← ADD
│   │   └── clients/
│   │       └── base/
```

---

### Change 3 — `skills/nextjs-scaffold/SKILL.md` — Part C verbatim blocks

Add three verbatim blocks to Part C. The `.gitkeep` needs no block (tree entry marked `[verbatim — empty]` is sufficient).

**`src/hooks/index.ts`**
```ts
export {};
```
Empty barrel — add-* skills append named hook exports here as the project grows.

**`src/lib/constants/index.ts`**
```ts
export * from './env';
export * from './routes';
```
Re-exports both constants modules so `@/lib/constants` resolves cleanly.

**`src/integrations/factories.ts`**
```ts
// Integration factory functions.
// Each factory returns a configured service instance.
// Added by nextjs-add-integration — one export per integration.
```
Establishes the file and documents the pattern before `add-integration` appends to it.

---

## Non-goals

- No changes to FastAPI, NestJS, or Vite-React scaffolds
- No refactoring of code quality sections (intentional duplication)
- No changes to auth stubs (intentional behavior)
- No changes to plugin version numbers
- No README updates beyond what the implementation requires

---

## Acceptance criteria

- [ ] `shared-drift-check`: all 4 skill name entries use dash format (`nextjs-scaffold` etc.)
- [ ] `nextjs-scaffold` directory tree includes `src/hooks/index.ts`, `src/lib/constants/index.ts`, `src/integrations/factories.ts`, `src/integrations/schemas/.gitkeep`
- [ ] Part C of `nextjs-scaffold` includes verbatim blocks for the 3 new files
- [ ] `export {}` in `hooks/index.ts` — not empty (empty TS files can cause linter warnings)
- [ ] `integrations/factories.ts` comment block explains the pattern for `add-integration` to follow
- [ ] No other skills modified
