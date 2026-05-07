# templateCentral Round 9 Audit — Design Spec

**Date:** 2026-05-07
**Scope:** Post-Round-8 accuracy, security, and policy gap closure across templateCentral

---

## Goal

Close four targeted gaps identified in the Round 9 fresh-eyes audit: Drizzle RC warning restoration, Ruff/PyJWT version pin removal, and full argon2id migration replacing bcrypt across both auth skills and code standards.

---

## Design Sections

### 1. Drizzle ORM RC Warning Restoration

**`skills/nextjs-add-database/SKILL.md`** and **`skills/nestjs-add-database/SKILL.md`**

v1.0.0-rc.2 was released May 5, 2026 — v1.0 stable has not shipped. The Round 7 decision to remove the RC warning was premature. The casing API guidance (removed from `drizzle()` instance, now applied at schema level via `snakeCase`/`camelCase` imports) remains accurate and is retained.

Fix: restore the RC callout in both files, updating tone to reflect rc.2:

> **Drizzle ORM v1 (release candidate)**: v1.0 is still pre-release — verify stable release at [drizzle.team](https://drizzle.team) before production use. The `casing` option was removed from the `drizzle()` instance in v1; casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers — see the [Drizzle v1 migration guide](https://orm.drizzle.team/docs/v1-migration-guide) if upgrading from 0.x.

---

### 2. Version Pins in Skills

**`skills/fastapi-code-standards/SKILL.md`** (line 84) and **`skills/fastapi-add-auth/SKILL.md`** (line 19)

Two SSOT policy violations — versions in SKILL.md files instead of `.claude/rules/*.md`.

**Ruff Python target:** Current text says "Python 3.12" — Ruff's target Python version is project-configurable in `ruff.toml` and should not be pinned in a global standard. The stack uses Python 3.13 (per `fastapi.md` rules). Replace: `- **Ruff** — linting + isort (line-length 88, Python 3.12).` → `- **Ruff** — linting + isort (line-length 88, target version configured in \`ruff.toml\`).`

**PyJWT version pin:** Current text says `PyJWT[crypto]>=2.12.0`. Version floor belongs in `.claude/rules/fastapi.md`, not in the skill. Replace with `PyJWT[crypto]`.

---

### 3. argon2id Migration

**`skills/fastapi-add-auth/SKILL.md`**, **`skills/nestjs-add-auth/SKILL.md`**, **`skills/fastapi-code-standards/SKILL.md`**

Both auth skills added argon2id as a guidance note in Round 7 but retained bcrypt as the actual implementation. Completing the migration: argon2id becomes the implementation. bcrypt references are removed. argon2id is memory-hard, resistant to GPU-based brute-force, and the current OWASP Password Storage Cheat Sheet and NIST SP 800-63B recommendation.

#### fastapi-add-auth

**Dependencies** — replace bcrypt with argon2-cffi:
```
- `PyJWT[crypto]` — JWT encoding/decoding
- `argon2-cffi` — Password hashing (argon2id algorithm; OWASP/NIST SP 800-63B recommended)
- `email-validator` — Pydantic EmailStr validation
```

**`core/security.py`** — replace `hash_password` and `verify_password`. The 72-byte limit check is bcrypt-specific and is removed (argon2 has no such constraint):
```python
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_ph = PasswordHasher()  # argon2id, OWASP-recommended defaults

def hash_password(password: str) -> str:
    return _ph.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return _ph.verify(hashed_password, plain_password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
```

**Rules section** — replace bcrypt guidance:
`Always hash passwords with argon2id (\`argon2-cffi\` package) — never store plaintext. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).`

#### nestjs-add-auth

**Dependencies** — update `onlyBuiltDependencies` from `bcrypt` to `argon2`; remove `@types/bcrypt` (argon2 ships its own types):
```json
"pnpm": {
  "onlyBuiltDependencies": ["argon2"]
}
```
```bash
pnpm add @nestjs/passport @nestjs/jwt passport passport-jwt argon2
pnpm add -D @types/passport-jwt
```

**`AuthService`** — replace bcrypt calls with argon2 (defaults to argon2id):
```typescript
import * as argon2 from 'argon2';

// register:
const hashedPassword = await argon2.hash(dto.password);  // argon2id by default

// verify (login):
const valid = await argon2.verify(user.hashedPassword, dto.password);
```

**Rules section** — replace bcrypt guidance:
`Always hash passwords with argon2id — never store plaintext. Use the \`argon2\` npm package. Memory-hard and resistant to GPU-based brute-force (OWASP and NIST SP 800-63B recommendation).`

#### fastapi-code-standards

Line 127 — replace bcrypt standard:
`Hash passwords with \`argon2id\` (\`argon2-cffi\` package) — never store plaintext. Do not use \`passlib\` (unmaintained).`

---

### 4. Version Bump + CHANGELOG

- `.claude-plugin/plugin.json`: `2.8.0` → `2.9.0`
- `CHANGELOG.md`: new `[2.9.0] — 2026-05-07` entry:

```markdown
## [2.9.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: restored Drizzle ORM v1 release-candidate warning — v1.0.0-rc.2 (May 2026); stable not yet shipped
- `fastapi-code-standards`: removed hardcoded Python 3.12 target from Ruff note — target version is project-configurable in ruff.toml
- `fastapi-add-auth`: removed PyJWT version pin from dependencies list — version belongs in rules, not skills

### Changed
- `fastapi-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2-cffi`) — removes bcrypt 72-byte limit constraint; OWASP/NIST SP 800-63B recommended algorithm
- `nestjs-add-auth`: migrated password hashing from bcrypt to argon2id (`argon2` npm) — updated `onlyBuiltDependencies` from `bcrypt` to `argon2`; removed `@types/bcrypt`
- `fastapi-code-standards`: updated password hashing standard from bcrypt to argon2id
```

---

## Constraints

- No CVE identifiers in SKILL.md files
- No version pins in SKILL.md files (versions belong only in `.claude/rules/*.md`)
- No IM8 attribution
- No Singapore-specific content
- pnpm version reference in nestjs-add-auth left as-is (pnpm 10 — explicitly deferred)
- No new features or refactoring beyond what each fix requires
