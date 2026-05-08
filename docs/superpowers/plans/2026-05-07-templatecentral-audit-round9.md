# templateCentral Round 9 Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four accuracy and security gaps in templateCentral post-Round-8: restore the Drizzle ORM RC warning, remove two SSOT-violating version pins, and complete the full argon2id migration replacing bcrypt across both auth skills and code standards.

**Architecture:** All changes are targeted edits to SKILL.md markdown files and plugin metadata. No code is executed — each edit is verifiable via grep. Tasks are ordered: documentation fixes first (Tasks 1–2), security migration second (Task 3), version bump last (Task 4, blocked on 1–3).

**Tech Stack:** Markdown (SKILL.md files), JSON (plugin.json), grep for verification.

---

### Task 1: Drizzle ORM RC Warning Restoration

**Goal:** Restore the release-candidate warning in both database skills so users know Drizzle ORM v1 stable has not shipped.

**Files:**
- Modify: `skills/nextjs-add-database/SKILL.md:49`
- Modify: `skills/nestjs-add-database/SKILL.md:49`

**Acceptance Criteria:**
- [ ] `skills/nextjs-add-database/SKILL.md` callout contains "release candidate" and a link to drizzle.team
- [ ] `skills/nestjs-add-database/SKILL.md` callout contains "release candidate" and a link to drizzle.team
- [ ] Both files retain the full casing API migration note
- [ ] `grep "release candidate" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md` → two lines

**Verify:** `grep "release candidate" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md` → two matching lines

**Steps:**

- [ ] **Step 1: Edit `skills/nextjs-add-database/SKILL.md` line 49**

Find this exact line:
```
> **Drizzle ORM v1**: The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

Replace with:
```
> **Drizzle ORM v1 (release candidate)**: v1.0 is still pre-release — verify stable release at [drizzle.team](https://drizzle.team) before production use. The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 2: Edit `skills/nestjs-add-database/SKILL.md` line 49**

Find this exact line (identical text to nextjs):
```
> **Drizzle ORM v1**: The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

Replace with:
```
> **Drizzle ORM v1 (release candidate)**: v1.0 is still pre-release — verify stable release at [drizzle.team](https://drizzle.team) before production use. The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.
```

- [ ] **Step 3: Verify**

Run: `grep "release candidate" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md`

Expected output: two lines, each containing `release candidate` and `drizzle.team`.

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
git commit -m "fix(skills): restore Drizzle ORM v1 RC warning in database skills — rc.2 still pre-release"
```

---

### Task 2: Remove Version Pins from SKILL.md Files

**Goal:** Remove two SSOT violations — Ruff's hardcoded Python 3.12 target in `fastapi-code-standards` and the PyJWT version floor in `fastapi-add-auth`.

**Files:**
- Modify: `skills/fastapi-code-standards/SKILL.md:84`
- Modify: `skills/fastapi-add-auth/SKILL.md:19`

**Acceptance Criteria:**
- [ ] `fastapi-code-standards/SKILL.md` Ruff line says "target version configured in `ruff.toml`" — no "Python 3.12"
- [ ] `fastapi-add-auth/SKILL.md` dependency line shows `PyJWT[crypto]` with no `>=` version floor

**Verify:**
```bash
grep "Python 3.12" skills/fastapi-code-standards/SKILL.md        # expect: no output
grep 'PyJWT\[crypto\]>=' skills/fastapi-add-auth/SKILL.md        # expect: no output
grep "ruff\.toml" skills/fastapi-code-standards/SKILL.md          # expect: one match
grep 'PyJWT\[crypto\]' skills/fastapi-add-auth/SKILL.md           # expect: one match (no >=)
```

**Steps:**

- [ ] **Step 1: Edit `skills/fastapi-code-standards/SKILL.md` line 84**

Find this exact line:
```
- **Ruff** — linting + isort (line-length 88, Python 3.12).
```

Replace with:
```
- **Ruff** — linting + isort (line-length 88, target version configured in `ruff.toml`).
```

- [ ] **Step 2: Edit `skills/fastapi-add-auth/SKILL.md` line 19**

Find this exact line:
```
- `PyJWT[crypto]>=2.12.0` — JWT encoding/decoding
```

Replace with:
```
- `PyJWT[crypto]` — JWT encoding/decoding
```

- [ ] **Step 3: Verify**

```bash
grep "Python 3.12" skills/fastapi-code-standards/SKILL.md        # expect: no output
grep 'PyJWT\[crypto\]>=' skills/fastapi-add-auth/SKILL.md        # expect: no output
grep "ruff\.toml" skills/fastapi-code-standards/SKILL.md          # expect: one match
grep 'PyJWT\[crypto\]' skills/fastapi-add-auth/SKILL.md           # expect: one match
```

- [ ] **Step 4: Commit**

```bash
git add skills/fastapi-code-standards/SKILL.md skills/fastapi-add-auth/SKILL.md
git commit -m "fix(skills): remove version pins from SKILL.md — Ruff Python target and PyJWT floor"
```

---

### Task 3: Full argon2id Migration

**Goal:** Replace bcrypt with argon2id as the actual implementation in both auth skills and update the fastapi code standard; remove the bcrypt hedge from all rules sections.

**Files:**
- Modify: `skills/fastapi-add-auth/SKILL.md` (dependency list line 20, `core/security.py` block lines 118–138, rules line 300)
- Modify: `skills/nestjs-add-auth/SKILL.md` (dependency section lines 18–31, AuthService import line 169, hash call line 178, rules line 336)
- Modify: `skills/fastapi-code-standards/SKILL.md:127` (auth standard)

**Acceptance Criteria:**
- [ ] `grep "bcrypt" skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md` → no output
- [ ] `fastapi-add-auth/SKILL.md` dependency list shows `argon2-cffi`
- [ ] `fastapi-add-auth/SKILL.md` `core/security.py` block uses `PasswordHasher` from `argon2` — no `bcrypt.hashpw`, no 72-byte limit check
- [ ] `nestjs-add-auth/SKILL.md` `onlyBuiltDependencies` contains `"argon2"`
- [ ] `nestjs-add-auth/SKILL.md` install command uses `argon2`; `@types/bcrypt` removed
- [ ] `nestjs-add-auth/SKILL.md` AuthService imports `argon2` and uses `argon2.hash(dto.password)`
- [ ] All three rules sections reference argon2id, not bcrypt

**Verify:**
```bash
grep "bcrypt" skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md
# expect: no output

grep "argon2" skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md
# expect: multiple matches across all three files
```

**Steps:**

- [ ] **Step 1: Update dependency list in `skills/fastapi-add-auth/SKILL.md`**

Find this exact line (currently line 20):
```
- `bcrypt` — Password hashing (use directly; passlib is unmaintained and incompatible with bcrypt ≥ 4.1.1)
```

Replace with:
```
- `argon2-cffi` — Password hashing (argon2id algorithm; OWASP/NIST SP 800-63B recommended)
```

- [ ] **Step 2: Replace `core/security.py` hashing block in `skills/fastapi-add-auth/SKILL.md`**

Find this exact block (starting at line 118 inside the code fence):
```
import bcrypt
import jwt
from fastapi import HTTPException

from core.config import api_settings

ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    """Hash a plaintext password."""
    if len(password.encode()) > 72:
        raise HTTPException(status_code=400, detail="Password must be 72 characters or fewer")
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(12)).decode("utf-8")  # cost 12 — OWASP minimum


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    if len(plain_password.encode()) > 72:
        return False  # bcrypt 5.0 raises ValueError for >72 bytes; no valid hash exists
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
```

Replace with:
```
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
import jwt

from core.config import api_settings

ALGORITHM = "HS256"

_ph = PasswordHasher()  # argon2id, OWASP-recommended defaults


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return _ph.verify(hashed_password, plain_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
```

- [ ] **Step 3: Replace rules line in `skills/fastapi-add-auth/SKILL.md`**

Find this exact line (currently line 300):
```
- Always hash passwords with `bcrypt` — never store plaintext. For new projects, prefer `argon2id` (OWASP and NIST SP 800-63B recommendation) — it is memory-hard and more resistant to GPU-based attacks than bcrypt. Use the `argon2-cffi` package for Python; bcrypt remains acceptable if already in use.
```

Replace with:
```
- Always hash passwords with argon2id (`argon2-cffi` package) — never store plaintext. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).
```

- [ ] **Step 4: Update dependency section in `skills/nestjs-add-auth/SKILL.md`**

Find this exact block (lines 18–31):
```
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

Replace with:
```
`argon2` is a native Node addon — pnpm 10 blocks native builds by default. Before installing, add the following to `package.json` (top-level, alongside `"scripts"`):

```json
"pnpm": {
  "onlyBuiltDependencies": ["argon2"]
}
```

Then install:

```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt argon2
pnpm add -D @types/passport-jwt
```
```

- [ ] **Step 5: Update AuthService import in `skills/nestjs-add-auth/SKILL.md`**

Find this exact line (currently line 169):
```
import * as bcrypt from 'bcrypt';
```

Replace with:
```
import * as argon2 from 'argon2';
```

- [ ] **Step 6: Update `bcrypt.hash` call in `skills/nestjs-add-auth/SKILL.md`**

Find this exact line (currently line 178):
```
    const hashedPassword = await bcrypt.hash(dto.password, 12); // OWASP minimum; increase if server load allows
```

Replace with:
```
    const hashedPassword = await argon2.hash(dto.password);  // argon2id by default
```

- [ ] **Step 7: Replace rules line in `skills/nestjs-add-auth/SKILL.md`**

Find this exact line (currently line 336):
```
- Always hash passwords with `bcrypt` — never store plaintext. For new projects, prefer `argon2id` (OWASP and NIST SP 800-63B recommendation) — it is memory-hard and more resistant to GPU-based attacks than bcrypt. Use the `argon2` npm package; bcrypt remains acceptable if already in use.
```

Replace with:
```
- Always hash passwords with argon2id — never store plaintext. Use the `argon2` npm package. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).
```

- [ ] **Step 8: Update auth standard in `skills/fastapi-code-standards/SKILL.md`**

Find this exact line (currently line 127):
```
- Hash passwords with `bcrypt` directly — NEVER store plaintext passwords (`passlib` is unmaintained and incompatible with bcrypt ≥ 4.1.1)
```

Replace with:
```
- Hash passwords with `argon2id` (`argon2-cffi` package) — never store plaintext. Do not use `passlib` (unmaintained).
```

- [ ] **Step 9: Verify no bcrypt remains**

```bash
grep "bcrypt" skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md
```
Expected: no output.

```bash
grep "argon2" skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md
```
Expected: multiple matches across all three files.

- [ ] **Step 10: Commit**

```bash
git add skills/fastapi-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-code-standards/SKILL.md
git commit -m "feat(skills): complete argon2id migration — replace bcrypt in fastapi-add-auth, nestjs-add-auth, fastapi-code-standards"
```

---

### Task 4: Version Bump and CHANGELOG

**Goal:** Bump plugin version from `2.8.0` to `2.9.0` and add the Round 9 CHANGELOG entry documenting all five changes.

**Files:**
- Modify: `.claude-plugin/plugin.json:3`
- Modify: `CHANGELOG.md` (insert new entry before `## [2.8.0]`)

**Acceptance Criteria:**
- [ ] `plugin.json` `"version"` field is `"2.9.0"`
- [ ] `CHANGELOG.md` contains a `[2.9.0] — 2026-05-07` section with three Fixed items and three Changed items
- [ ] `CHANGELOG.md` existing `[2.8.0]` entry is unchanged

**Verify:**
```bash
grep '"version"' .claude-plugin/plugin.json    # expect: "version": "2.9.0"
grep '\[2\.9\.0\]' CHANGELOG.md               # expect: one match
grep '\[2\.8\.0\]' CHANGELOG.md               # expect: still present
```

**Steps:**

- [ ] **Step 1: Update version in `.claude-plugin/plugin.json`**

Find:
```
  "version": "2.8.0",
```

Replace with:
```
  "version": "2.9.0",
```

- [ ] **Step 2: Add CHANGELOG entry in `CHANGELOG.md`**

Find this exact text (currently line 11–13):
```

---

## [2.8.0] — 2026-05-07
```

Replace with:
```

---

## [2.9.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: restored Drizzle ORM v1 release-candidate warning — v1.0.0-rc.2 (May 2026); stable not yet shipped
- `fastapi-code-standards`: removed hardcoded Python 3.12 target from Ruff note — target version is project-configurable in ruff.toml
- `fastapi-add-auth`: removed PyJWT version pin from dependencies list — version belongs in rules, not skills

### Changed
- `fastapi-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2-cffi`) — removes bcrypt 72-byte limit constraint; OWASP/NIST SP 800-63B recommended algorithm
- `nestjs-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2` npm) — updated `onlyBuiltDependencies` from `bcrypt` to `argon2`; removed `@types/bcrypt`
- `fastapi-code-standards`: updated password hashing standard from bcrypt to argon2id

---

## [2.8.0] — 2026-05-07
```

- [ ] **Step 3: Verify**

```bash
grep '"version"' .claude-plugin/plugin.json    # expect: "version": "2.9.0"
grep '\[2\.9\.0\]' CHANGELOG.md               # expect: one match
grep '\[2\.8\.0\]' CHANGELOG.md               # expect: still present (unchanged)
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump version to 2.9.0, add Round 9 CHANGELOG entry"
```
