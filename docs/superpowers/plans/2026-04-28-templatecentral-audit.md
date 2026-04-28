# templateCentral Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix one routing bug in `shared-drift-check` and restore four missing files to the `nextjs-scaffold` directory tree and verbatim blocks.

**Architecture:** Two independent markdown edits — no code compilation, no test suite. Each task edits a single skill file and commits. Verification is manual content inspection.

**Tech Stack:** Markdown skill files only — no runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-04-28-templatecentral-audit-design.md`

---

### Task 1: Fix shared-drift-check routing table

**Goal:** Replace four slash-format skill names with dash-format so agents can correctly load scaffold skills.

**Files:**
- Modify: `skills/shared-drift-check/SKILL.md:30-33`

**Acceptance Criteria:**
- [ ] Line 30 reads `| \`nextjs\` | \`nextjs-scaffold\` |`
- [ ] Line 31 reads `| \`vite-react\` | \`vite-react-scaffold\` |`
- [ ] Line 32 reads `| \`fastapi\` | \`fastapi-scaffold\` |`
- [ ] Line 33 reads `| \`nestjs\` | \`nestjs-scaffold\` |`
- [ ] No other lines in the file changed

**Verify:** `grep "scaffold" skills/shared-drift-check/SKILL.md` → all four rows show dash format, no slashes

**Steps:**

- [ ] **Step 1: Make the edit**

In `skills/shared-drift-check/SKILL.md`, find the table in Step 2 (lines 28-33):

```
| Marker stack | Scaffold skill |
|---|---|
| `nextjs` | `nextjs/scaffold` |
| `vite-react` | `vite-react/scaffold` |
| `fastapi` | `fastapi/scaffold` |
| `nestjs` | `nestjs/scaffold` |
```

Replace with:

```
| Marker stack | Scaffold skill |
|---|---|
| `nextjs` | `nextjs-scaffold` |
| `vite-react` | `vite-react-scaffold` |
| `fastapi` | `fastapi-scaffold` |
| `nestjs` | `nestjs-scaffold` |
```

- [ ] **Step 2: Verify**

```bash
grep "scaffold" skills/shared-drift-check/SKILL.md
```

Expected output — all four rows show dash format:
```
| `nextjs` | `nextjs-scaffold` |
| `vite-react` | `vite-react-scaffold` |
| `fastapi` | `fastapi-scaffold` |
| `nestjs` | `nestjs-scaffold` |
```

No line should contain a slash between stack name and `scaffold`.

- [ ] **Step 3: Commit**

```bash
git add skills/shared-drift-check/SKILL.md
git commit -m "fix(drift-check): correct scaffold skill name format — slash to dash"
```

---

### Task 2: Restore 4 missing files to nextjs-scaffold

**Goal:** Add `src/hooks/index.ts`, `src/lib/constants/index.ts`, `src/integrations/schemas/.gitkeep`, and `src/integrations/factories.ts` to the directory tree (Part A) and add three verbatim blocks to Part C.

**Files:**
- Modify: `skills/nextjs-scaffold/SKILL.md` (directory tree at lines 109-127, Part C after line 1668)

**Acceptance Criteria:**
- [ ] Directory tree shows `src/hooks/index.ts [verbatim — Part C]`
- [ ] Directory tree shows `src/integrations/factories.ts [verbatim — Part C]`
- [ ] Directory tree shows `src/integrations/schemas/.gitkeep [verbatim — empty]`
- [ ] Directory tree shows `src/lib/constants/index.ts [verbatim — Part C]`
- [ ] Part C contains `### \`src/hooks/index.ts\`` block with `export {};`
- [ ] Part C contains `### \`src/lib/constants/index.ts\`` block with two re-exports
- [ ] Part C contains `### \`src/integrations/factories.ts\`` block with comment scaffold
- [ ] No other lines in the file changed

**Verify:** `grep -n "hooks/index\|factories\|schemas/.gitkeep\|constants/index" skills/nextjs-scaffold/SKILL.md` → 8 matches (4 tree entries + 3 Part C headings + 1 existing `constants/env.ts` reference doesn't count)

**Steps:**

- [ ] **Step 1: Update the directory tree — `src/hooks/`**

Find this block in the tree (around line 109):

```
    ├── features/
    │   └── example/                   [generate — minimal example with types, service, hook, component]
    ├── integrations/
```

Replace with:

```
    ├── features/
    │   └── example/                   [generate — minimal example with types, service, hook, component]
    ├── hooks/
    │   └── index.ts                    [verbatim — Part C]
    ├── integrations/
```

- [ ] **Step 2: Update the directory tree — `src/integrations/`**

Find this block in the tree (around line 111):

```
    ├── integrations/
    │   ├── error.ts                    [verbatim — Part C]
    │   └── clients/
    │       └── base/
    │           ├── axios-client.ts     [verbatim — Part C]
    │           ├── fetch-client.ts     [verbatim — Part C]
    │           └── https-agent.ts      [verbatim — Part C]
```

Replace with:

```
    ├── integrations/
    │   ├── factories.ts                [verbatim — Part C]
    │   ├── error.ts                    [verbatim — Part C]
    │   ├── schemas/
    │   │   └── .gitkeep                [verbatim — empty]
    │   └── clients/
    │       └── base/
    │           ├── axios-client.ts     [verbatim — Part C]
    │           ├── fetch-client.ts     [verbatim — Part C]
    │           └── https-agent.ts      [verbatim — Part C]
```

- [ ] **Step 3: Update the directory tree — `src/lib/constants/`**

Find this block in the tree (around line 121):

```
        ├── constants/
        │   ├── env.ts                  [verbatim — Part C]
        │   └── routes.ts               [generate — PAGE_ROUTES + API_ROUTES]
```

Replace with:

```
        ├── constants/
        │   ├── index.ts                [verbatim — Part C]
        │   ├── env.ts                  [verbatim — Part C]
        │   └── routes.ts               [generate — PAGE_ROUTES + API_ROUTES]
```

- [ ] **Step 4: Add three verbatim blocks to Part C**

Find this block at the end of Part C (around line 1668):

```ts
export const API_BASE =
  process.env.NEXT_PUBLIC_BASE_URL ?? 'http://localhost:3000';

export const isDev = process.env.NODE_ENV === 'development';
export const isProd = process.env.NODE_ENV === 'production';
```

After the closing ` ``` ` of that block (line 1668), append:

```markdown

### `src/hooks/index.ts`

```ts
export {};
```

### `src/lib/constants/index.ts`

```ts
export * from './env';
export * from './routes';
```

### `src/integrations/factories.ts`

```ts
// Integration factory functions.
// Each factory returns a configured service instance.
// Added by nextjs-add-integration — one export per integration.
```
```

(The `.gitkeep` file needs no verbatim block — the `[verbatim — empty]` annotation in the tree is sufficient.)

- [ ] **Step 5: Verify**

```bash
grep -n "hooks/index\|factories\|schemas/.gitkeep\|constants/index" skills/nextjs-scaffold/SKILL.md
```

Expected — at minimum these lines appear:
```
NNN:    ├── hooks/
NNN:    │   └── index.ts                    [verbatim — Part C]
NNN:    │   ├── factories.ts                [verbatim — Part C]
NNN:    │   ├── schemas/
NNN:    │   │   └── .gitkeep                [verbatim — empty]
NNN:    │   ├── index.ts                [verbatim — Part C]
NNN:### `src/hooks/index.ts`
NNN:### `src/lib/constants/index.ts`
NNN:### `src/integrations/factories.ts`
```

- [ ] **Step 6: Commit**

```bash
git add skills/nextjs-scaffold/SKILL.md
git commit -m "fix(nextjs-scaffold): restore 4 missing files from templates/ baseline

Add src/hooks/index.ts, src/lib/constants/index.ts,
src/integrations/schemas/.gitkeep, and src/integrations/factories.ts
to directory tree and Part C verbatim blocks."
```
