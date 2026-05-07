# templateCentral Round 6 Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close five accuracy and security gaps identified in the Round 6 audit across templateCentral's 48 skills.

**Architecture:** Targeted text edits to SKILL.md files only — no new files, no structural changes. Each task is a self-contained change to one or two files with grep-verified acceptance criteria.

**Tech Stack:** templateCentral plugin (SKILL.md markdown files), plugin.json, CHANGELOG.md

---

## File Map

| File | Task | Change |
|------|------|--------|
| `skills/shared-validation-patterns/SKILL.md` | 1 | `min_length=8` → `min_length=12` |
| `skills/fastapi-add-auth/SKILL.md` | 1 | Add algorithm whitelisting comment |
| `skills/nextjs-add-auth/SKILL.md` | 2 | Note `@better-auth/drizzle` separate package |
| `skills/nextjs-add-database/SKILL.md` | 2 | Extend Drizzle RC callout with rc.1 casing note |
| `skills/nestjs-add-database/SKILL.md` | 2 | Same as above |
| `skills/nestjs-add-auth/SKILL.md` | 3 | Add `pnpm.onlyBuiltDependencies` for bcrypt |
| `skills/vite-react-scaffold/SKILL.md` | 4 | Add explicit `"types": []` to tsconfig |
| `.claude-plugin/plugin.json` | 5 | `2.5.0` → `2.6.0` |
| `CHANGELOG.md` | 5 | New `[2.6.0]` entry |

---

### Task 1: Security Accuracy

**Goal:** Fix the password `min_length` mismatch in shared-validation-patterns, and add an algorithm whitelisting comment to fastapi-add-auth's JWT decode call.

**Files:**
- Modify: `skills/shared-validation-patterns/SKILL.md:556`
- Modify: `skills/fastapi-add-auth/SKILL.md:148-154`

**Acceptance Criteria:**
- [ ] `shared-validation-patterns/SKILL.md` has `min_length=12` (not `min_length=8`)
- [ ] `fastapi-add-auth/SKILL.md` has a comment above `algorithms=[ALGORITHM]` explaining it is a security whitelist

**Verify:** `grep "min_length=12" skills/shared-validation-patterns/SKILL.md && grep "whitelist" skills/fastapi-add-auth/SKILL.md` → one match each

**Steps:**

- [ ] **Step 1: Fix min_length in shared-validation-patterns**

In `skills/shared-validation-patterns/SKILL.md`, find line 556:

```python
    password: str = Field(..., min_length=8)
```

Replace with:

```python
    password: str = Field(..., min_length=12)
```

- [ ] **Step 2: Verify min_length change**

Run: `grep -n "min_length" skills/shared-validation-patterns/SKILL.md`

Expected: line showing `min_length=12`; no remaining `min_length=8`

- [ ] **Step 3: Add PyJWT algorithm whitelist comment**

In `skills/fastapi-add-auth/SKILL.md`, find the `decode_access_token` function body (around line 148–154):

```python
def decode_access_token(token: str) -> str | None:
    """Decode and validate a JWT token. Returns the subject or None."""
    try:
        payload = jwt.decode(token, api_settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        return None
```

Replace with:

```python
def decode_access_token(token: str) -> str | None:
    """Decode and validate a JWT token. Returns the subject or None."""
    try:
        # algorithms is a security whitelist — never omit or use ["none"]; omitting allows algorithm confusion attacks
        payload = jwt.decode(token, api_settings.SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        return None
```

- [ ] **Step 4: Verify algorithm comment**

Run: `grep -n "whitelist" skills/fastapi-add-auth/SKILL.md`

Expected: one line containing "whitelist" near the `jwt.decode` call

- [ ] **Step 5: Commit**

```bash
git add skills/shared-validation-patterns/SKILL.md skills/fastapi-add-auth/SKILL.md
git commit -m "fix(audit): fix password min_length to 12 and add PyJWT algorithm whitelist comment"
```

---

### Task 2: better-auth v1.5 + Drizzle ORM rc.1 Accuracy

**Goal:** Note that `@better-auth/drizzle` is a separate package in nextjs-add-auth, and extend the Drizzle RC callout in both database skills with the rc.1 casing API breaking change.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md:140`
- Modify: `skills/nextjs-add-database/SKILL.md:49`
- Modify: `skills/nestjs-add-database/SKILL.md:49`

**Acceptance Criteria:**
- [ ] `nextjs-add-auth/SKILL.md` callout names `@better-auth/drizzle` as a separate package
- [ ] `nextjs-add-database/SKILL.md` RC callout mentions rc.1 casing API change
- [ ] `nestjs-add-database/SKILL.md` RC callout mentions rc.1 casing API change

**Verify:** `grep "@better-auth/drizzle" skills/nextjs-add-auth/SKILL.md && grep "casing" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md` → matches in all three files

**Steps:**

- [ ] **Step 1: Update better-auth Drizzle adapter note in nextjs-add-auth**

In `skills/nextjs-add-auth/SKILL.md`, find line 140:

```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Adapters for Drizzle and Kysely are available — see [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

Replace with:

```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Since better-auth v1.5, the Drizzle adapter ships as a separate package (`@better-auth/drizzle` — install alongside `drizzle-orm`); the Kysely adapter remains bundled. See [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

- [ ] **Step 2: Verify nextjs-add-auth change**

Run: `grep "@better-auth/drizzle" skills/nextjs-add-auth/SKILL.md`

Expected: one match on the database callout line

- [ ] **Step 3: Extend Drizzle RC callout in nextjs-add-database**

In `skills/nextjs-add-database/SKILL.md`, find line 49:

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use.
```

Replace with:

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use. In rc.1, the `casing` option was removed from the `drizzle()` instance; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 4: Verify nextjs-add-database change**

Run: `grep "casing" skills/nextjs-add-database/SKILL.md`

Expected: one match mentioning rc.1 casing change

- [ ] **Step 5: Extend Drizzle RC callout in nestjs-add-database**

In `skills/nestjs-add-database/SKILL.md`, find line 49:

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use.
```

Replace with:

```
> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use. In rc.1, the `casing` option was removed from the `drizzle()` instance; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 6: Verify nestjs-add-database change**

Run: `grep "casing" skills/nestjs-add-database/SKILL.md`

Expected: one match mentioning rc.1 casing change

- [ ] **Step 7: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
git commit -m "fix(audit): note @better-auth/drizzle separate package and Drizzle rc.1 casing API change"
```

---

### Task 3: pnpm Native Addon Build Permissions

**Goal:** Add `pnpm.onlyBuiltDependencies` config step to nestjs-add-auth so bcrypt's native build isn't silently skipped by pnpm 10.

**Files:**
- Modify: `skills/nestjs-add-auth/SKILL.md` (Dependencies section, lines 17–21)

**Acceptance Criteria:**
- [ ] `nestjs-add-auth/SKILL.md` Dependencies section includes a step to add `"pnpm": { "onlyBuiltDependencies": ["bcrypt"] }` to `package.json` before running `pnpm add`

**Verify:** `grep "onlyBuiltDependencies" skills/nestjs-add-auth/SKILL.md` → one match

**Steps:**

- [ ] **Step 1: Add pnpm native build config step**

In `skills/nestjs-add-auth/SKILL.md`, find the Dependencies section (around line 17):

```markdown
## Dependencies

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
```
```

Replace with:

```markdown
## Dependencies

`bcrypt` is a native Node addon — pnpm 10 blocks native builds by default. Before installing, add the following to `package.json` (top-level, alongside `"scripts"`):

```json
"pnpm": {
  "onlyBuiltDependencies": ["bcrypt"]
}
```

Then install:

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt bcrypt
pnpm add -D @types/passport-jwt @types/bcrypt
```
```

- [ ] **Step 2: Verify the change**

Run: `grep -n "onlyBuiltDependencies" skills/nestjs-add-auth/SKILL.md`

Expected: one line with `"onlyBuiltDependencies": ["bcrypt"]`

- [ ] **Step 3: Commit**

```bash
git add skills/nestjs-add-auth/SKILL.md
git commit -m "fix(audit): add pnpm onlyBuiltDependencies for bcrypt native build in nestjs-add-auth"
```

---

### Task 4: TypeScript 6 tsconfig Explicit `types` Field

**Goal:** Add explicit `"types": []` to the vite-react-scaffold tsconfig so TypeScript 6's changed default (empty array instead of all visible `@types`) doesn't silently drop global type packages.

**Files:**
- Modify: `skills/vite-react-scaffold/SKILL.md:808-814`

**Acceptance Criteria:**
- [ ] `vite-react-scaffold/SKILL.md` tsconfig includes `"types": []`

**Verify:** `grep '"types"' skills/vite-react-scaffold/SKILL.md` → at least one match in the tsconfig block

**Steps:**

- [ ] **Step 1: Add `"types"` field to tsconfig**

In `skills/vite-react-scaffold/SKILL.md`, find the tsconfig block (around line 790–813):

```json
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src", "vite-env.d.ts", "vite.config.ts"]
}
```

Replace with:

```json
    "paths": {
      "@/*": ["./src/*"]
    },
    "types": [] // TypeScript 6 default; add @types/* package names here if globally-visible types are needed
  },
  "include": ["src", "vite-env.d.ts", "vite.config.ts"]
}
```

- [ ] **Step 2: Verify the change**

Run: `grep -n '"types"' skills/vite-react-scaffold/SKILL.md`

Expected: one match inside the tsconfig block

- [ ] **Step 3: Commit**

```bash
git add skills/vite-react-scaffold/SKILL.md
git commit -m "fix(audit): add explicit types field to vite-react-scaffold tsconfig for TypeScript 6"
```

---

### Task 5: Version Bump and CHANGELOG

**Goal:** Bump plugin version from `2.5.0` to `2.6.0` and record all Round 6 changes in `CHANGELOG.md`.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.6.0"`
- [ ] `CHANGELOG.md` has `[2.6.0]` entry dated 2026-05-07

**Verify:** `grep '"version"' .claude-plugin/plugin.json && grep '\[2.6.0\]' CHANGELOG.md` → both match

**Steps:**

- [ ] **Step 1: Bump plugin version**

In `.claude-plugin/plugin.json`, find:

```json
  "version": "2.5.0",
```

Replace with:

```json
  "version": "2.6.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

In `CHANGELOG.md`, find the existing `[2.5.0]` entry and insert the new entry above it:

```markdown
## [2.6.0] — 2026-05-07

### Fixed
- `shared-validation-patterns`: password `min_length` corrected from 8 to 12 to match all auth skill policies
- `fastapi-add-auth`: added algorithm whitelist comment to `jwt.decode()` — explains why `algorithms=` must never be omitted or broadened
- `nextjs-add-auth`: noted `@better-auth/drizzle` ships as a separate package since better-auth v1.5
- `nextjs-add-database`, `nestjs-add-database`: extended Drizzle v1 RC callout with rc.1 casing API breaking change and migration guide link
- `nestjs-add-auth`: added `pnpm.onlyBuiltDependencies` step for bcrypt — pnpm 10 blocks native builds by default
- `vite-react-scaffold`: added explicit `"types": []` to tsconfig — TypeScript 6 changed default from all visible `@types` to empty array

```

- [ ] **Step 3: Verify both changes**

Run: `grep '"version"' .claude-plugin/plugin.json && grep '\[2.6.0\]' CHANGELOG.md`

Expected: `"version": "2.6.0"` and `## [2.6.0] — 2026-05-07`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump version to 2.6.0"
```
