# templateCentral Round 7 Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close five accuracy and security gaps identified in the Round 7 audit across templateCentral's skills.

**Architecture:** Targeted text edits to SKILL.md files only — no new files, no structural changes. Each task is self-contained and grep-verified.

**Tech Stack:** templateCentral plugin (SKILL.md markdown files), plugin.json, CHANGELOG.md

---

## File Map

| File | Task | Change |
|------|------|--------|
| `skills/nextjs-add-database/SKILL.md` | 1 | Retire Drizzle RC warning → stable note |
| `skills/nestjs-add-database/SKILL.md` | 1 | Same |
| `skills/nestjs-add-auth/SKILL.md` | 2 | Add argon2id guidance note to Rules |
| `skills/fastapi-add-auth/SKILL.md` | 2 | Same |
| `skills/shared-add-ai-security/SKILL.md` | 3 | Replace NRIC + Singapore phone with generic patterns |
| `skills/nextjs-add-auth/SKILL.md` | 4 | Drop "v1.5" version pin from Drizzle adapter note |
| `.claude-plugin/plugin.json` | 5 | `2.6.0` → `2.7.0` |
| `CHANGELOG.md` | 5 | New `[2.7.0]` entry |

---

### Task 1: Drizzle v1.0 Stable Promotion

**Goal:** Replace the "release candidate" warning in both database skills with a stable-release note that retains the casing API guidance.

**Files:**
- Modify: `skills/nextjs-add-database/SKILL.md:49`
- Modify: `skills/nestjs-add-database/SKILL.md:49`

**Acceptance Criteria:**
- [ ] Neither database skill contains "release candidate" or "verify stable release"
- [ ] Both files retain the casing API guidance and migration guide link

**Verify:** `grep "release candidate" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Update nextjs-add-database Drizzle callout**

In `skills/nextjs-add-database/SKILL.md`, find line 49:

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use. In rc.1, the `casing` option was removed from the `drizzle()` instance; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

Replace with:

```
> **Drizzle ORM v1**: The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 2: Update nestjs-add-database Drizzle callout**

In `skills/nestjs-add-database/SKILL.md`, find line 49 (identical text):

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use. In rc.1, the `casing` option was removed from the `drizzle()` instance; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

Replace with:

```
> **Drizzle ORM v1**: The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 3: Verify**

Run: `grep "release candidate" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md`

Expected: no output

Run: `grep "casing" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md`

Expected: one match per file (casing guidance retained)

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
git commit -m "fix(audit): promote Drizzle ORM v1 to stable — retire RC warning"
```

---

### Task 2: argon2id Guidance Note

**Goal:** Add a guidance note to the Rules section of both auth skills noting that argon2id is the current industry recommendation for new projects, without mandating a rewrite of the existing bcrypt implementation.

**Files:**
- Modify: `skills/nestjs-add-auth/SKILL.md` — Rules section (line 336)
- Modify: `skills/fastapi-add-auth/SKILL.md` — Rules section (line 300)

**Acceptance Criteria:**
- [ ] `nestjs-add-auth/SKILL.md` Rules section mentions argon2id as the recommended choice for new projects
- [ ] `fastapi-add-auth/SKILL.md` Rules section mentions argon2id as the recommended choice for new projects
- [ ] Neither file removes or contradicts the existing bcrypt guidance

**Verify:** `grep "argon2id" skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md` → one match per file

**Steps:**

- [ ] **Step 1: Add argon2id note to nestjs-add-auth Rules**

In `skills/nestjs-add-auth/SKILL.md`, find the Rules section line:

```
- Always hash passwords with `bcrypt` — never store plaintext.
```

Replace with:

```
- Always hash passwords with `bcrypt` — never store plaintext. For new projects, prefer `argon2id` (OWASP and NIST SP 800-63B recommendation) — it is memory-hard and more resistant to GPU-based attacks than bcrypt. Use the `argon2` npm package; bcrypt remains acceptable if already in use.
```

- [ ] **Step 2: Verify nestjs-add-auth change**

Run: `grep "argon2id" skills/nestjs-add-auth/SKILL.md`

Expected: one match in the Rules section

- [ ] **Step 3: Add argon2id note to fastapi-add-auth Rules**

In `skills/fastapi-add-auth/SKILL.md`, find the Rules section line:

```
- Always hash passwords with `bcrypt` — never store plaintext.
```

Replace with:

```
- Always hash passwords with `bcrypt` — never store plaintext. For new projects, prefer `argon2id` (OWASP and NIST SP 800-63B recommendation) — it is memory-hard and more resistant to GPU-based attacks than bcrypt. Use the `argon2-cffi` package for Python; bcrypt remains acceptable if already in use.
```

- [ ] **Step 4: Verify fastapi-add-auth change**

Run: `grep "argon2id" skills/fastapi-add-auth/SKILL.md`

Expected: one match in the Rules section

- [ ] **Step 5: Commit**

```bash
git add skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md
git commit -m "fix(audit): add argon2id guidance note to auth skill Rules sections"
```

---

### Task 3: Generalize Region-Specific PII Patterns

**Goal:** Replace the Singapore NRIC regex and Singapore phone country code in `shared-add-ai-security` with jurisdiction-neutral patterns that work globally.

**Files:**
- Modify: `skills/shared-add-ai-security/SKILL.md` — LLM02 PII patterns block (lines 110–115)

**Acceptance Criteria:**
- [ ] No `NRIC` label or Singapore NRIC regex remains
- [ ] No `\+?65` Singapore country code in the phone pattern
- [ ] Both replacements have comments instructing developers to adapt to their jurisdiction

**Verify:** `grep "NRIC\|\\\\+?65" skills/shared-add-ai-security/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Replace NRIC and Singapore phone patterns**

In `skills/shared-add-ai-security/SKILL.md`, find the PII_PATTERNS block:

```ts
const PII_PATTERNS: Array<[RegExp, string]> = [
  [/\b[A-Z]\d{7}[A-Z]\b/g, '[NRIC]'],                           // Singapore NRIC
  [/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, '[CARD]'],   // Credit card
  [/\b[\w.+-]+@[\w-]+\.\w{2,}\b/g, '[EMAIL]'],
  [/\b\+?65[\s-]?\d{4}[\s-]?\d{4}\b/g, '[PHONE]'],
];
```

Replace with:

```ts
const PII_PATTERNS: Array<[RegExp, string]> = [
  [/\b\d{6,12}\b/g, '[NATIONAL-ID]'],                            // National ID — adapt regex to your jurisdiction's format
  [/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, '[CARD]'],   // Credit card
  [/\b[\w.+-]+@[\w-]+\.\w{2,}\b/g, '[EMAIL]'],
  [/\b\+?\d{1,3}[\s-]?\d{3,5}[\s-]?\d{4,8}\b/g, '[PHONE]'],    // International phone — adapt to expected formats
];
```

- [ ] **Step 2: Verify no Singapore-specific patterns remain**

Run: `grep "NRIC" skills/shared-add-ai-security/SKILL.md`

Expected: no output

Run: `grep "NATIONAL-ID" skills/shared-add-ai-security/SKILL.md`

Expected: one match

- [ ] **Step 3: Commit**

```bash
git add skills/shared-add-ai-security/SKILL.md
git commit -m "fix(audit): replace Singapore-specific NRIC and phone patterns with generic jurisdiction-neutral PII patterns"
```

---

### Task 4: Remove better-auth Version Pin

**Goal:** Drop the hardcoded "v1.5" version reference from the Drizzle adapter note in `nextjs-add-auth`, replacing it with a version-neutral statement.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md:140`

**Acceptance Criteria:**
- [ ] Line 140 no longer contains "v1.5"
- [ ] The `@better-auth/drizzle` package name and install instruction are retained

**Verify:** `grep "v1\.5" skills/nextjs-add-auth/SKILL.md` → no output (and no other v1.5 references remain)

**Steps:**

- [ ] **Step 1: Remove version pin**

In `skills/nextjs-add-auth/SKILL.md`, find line 140:

```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Since better-auth v1.5, the Drizzle adapter ships as a separate package (`@better-auth/drizzle` — install alongside `drizzle-orm`). See [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

Replace with:

```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. The Drizzle adapter is a separate package (`@better-auth/drizzle` — install alongside `drizzle-orm`). See [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

- [ ] **Step 2: Verify**

Run: `grep "v1\.5" skills/nextjs-add-auth/SKILL.md`

Expected: no output

Run: `grep "@better-auth/drizzle" skills/nextjs-add-auth/SKILL.md`

Expected: one match (package reference retained)

- [ ] **Step 3: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md
git commit -m "fix(audit): remove better-auth v1.5 version pin from Drizzle adapter note"
```

---

### Task 5: Version Bump and CHANGELOG

**Goal:** Bump plugin version from `2.6.0` to `2.7.0` and record all Round 7 changes in `CHANGELOG.md`.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.7.0"`
- [ ] `CHANGELOG.md` has `[2.7.0]` entry dated 2026-05-07

**Verify:** `grep '"version"' .claude-plugin/plugin.json && grep '\[2.7.0\]' CHANGELOG.md` → both match

**Steps:**

- [ ] **Step 1: Bump plugin version**

In `.claude-plugin/plugin.json`, find:

```json
  "version": "2.6.0",
```

Replace with:

```json
  "version": "2.7.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

In `CHANGELOG.md`, insert above the existing `## [2.6.0]` entry:

```markdown
## [2.7.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: retired Drizzle ORM v1 RC warning — v1.0 is now stable; retained casing API guidance and migration guide link
- `nestjs-add-auth`, `fastapi-add-auth`: added argon2id guidance note to Rules — argon2id is the current OWASP/NIST recommendation for new projects; bcrypt remains acceptable
- `shared-add-ai-security`: replaced Singapore-specific NRIC regex and phone country code with generic jurisdiction-neutral PII patterns
- `nextjs-add-auth`: removed hardcoded `v1.5` version pin from better-auth Drizzle adapter note

```

- [ ] **Step 3: Verify**

Run: `grep '"version"' .claude-plugin/plugin.json && grep '\[2.7.0\]' CHANGELOG.md`

Expected: `"version": "2.7.0"` and `## [2.7.0] — 2026-05-07`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump version to 2.7.0"
```
