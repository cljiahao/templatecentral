# templateCentral Round 10 Audit — Design Spec

**Date:** 2026-05-07
**Scope:** Post-Round-9 accuracy, security, and SSOT gap closure across templateCentral

---

## Goal

Close gaps identified in the Round 10 fresh-eyes audit: complete the argon2id migration in `nestjs-add-database` (the functional contradiction left from Round 9), remove remaining bcrypt references from three other files, and enforce SSOT by moving version floors out of SKILL.md files into the rules layer.

---

## Design Sections

### 1. nestjs-add-database: argon2 Migration (3 AuthService Blocks)

**`skills/nestjs-add-database/SKILL.md`**

The skill contains three "Step B — Replace `src/modules/auth/auth.service.ts`" blocks — one per ORM (Drizzle/Postgres, Kysely, Mongoose). All three use bcrypt directly, contradicting the Round 9 argon2id migration in `nestjs-add-auth`. A developer following the intended flow (nestjs-add-auth → nestjs-add-database) ends up with bcrypt hashes despite the rules now mandating argon2id.

`argon2` is already installed via `nestjs-add-auth` — no install instructions are needed in this skill.

**Drizzle/Postgres block (lines 835, 857, 871):**
- `import * as bcrypt from 'bcrypt'` → `import * as argon2 from 'argon2'`
- `await bcrypt.hash(dto.password, 12) // OWASP minimum; increase if server load allows` → `await argon2.hash(dto.password)  // argon2id by default`
- `!(await bcrypt.compare(dto.password, user.hashedPassword))` → `!(await argon2.verify(user.hashedPassword, dto.password))`

**Kysely block (lines 943, 963, 978):** Same pattern; field is `user.hashed_password` (snake_case).
- `import * as bcrypt from 'bcrypt'` → `import * as argon2 from 'argon2'`
- `await bcrypt.hash(dto.password, 12) // OWASP minimum; increase if server load allows` → `await argon2.hash(dto.password)  // argon2id by default`
- `!(await bcrypt.compare(dto.password, user.hashed_password))` → `!(await argon2.verify(user.hashed_password, dto.password))`

**Mongoose block (lines 1026, 1043, 1054):** Same pattern; field is `user.hashedPassword`.
- `import * as bcrypt from 'bcrypt'` → `import * as argon2 from 'argon2'`
- `await bcrypt.hash(dto.password, 12) // OWASP minimum; increase if server load allows` → `await argon2.hash(dto.password)  // argon2id by default`
- `!(await bcrypt.compare(dto.password, user.hashedPassword))` → `!(await argon2.verify(user.hashedPassword, dto.password))`

**Verify:** `grep "bcrypt" skills/nestjs-add-database/SKILL.md` → no output

---

### 2. Residual bcrypt Cleanup (3 Files)

#### `skills/fastapi-add-database/SKILL.md:346`

Placeholder comment in a Beanie (MongoDB) example still references bcrypt:

- Current: `user = User(**payload.model_dump(), hashed_password="...")  # hash with bcrypt in production`
- New: `user = User(**payload.model_dump(), hashed_password="...")  # use hash_password() from core/security.py`

#### `skills/nextjs-add-auth/SKILL.md:540`

Rules section hedges with "bcrypt acceptable" language:

- Current: `- **Password hashing**: better-auth uses bcrypt by default (acceptable). For any custom hashing outside better-auth, prefer Argon2id (\`argon2\` package) — ranked above bcrypt by OWASP.`
- New: `- **Password hashing**: better-auth handles password hashing internally. For any custom hashing outside better-auth, use argon2id (\`argon2\` package) — OWASP and NIST SP 800-63B recommended.`

#### `skills/shared-add-logging/SKILL.md:668,691`

Illustrative auth service logging example uses `bcrypt.compare` with no import:

- Add `import * as argon2 from 'argon2';` after `import { Logger } from 'nestjs-pino';` (line 668)
- `!(await bcrypt.compare(password, user.passwordHash))` → `!(await argon2.verify(user.passwordHash, password))`

---

### 3. Version Pin SSOT Cleanup

**Policy:** version floors belong in `.claude/rules/*.md`, not in SKILL.md files.

#### Remove floors from skills

**`skills/fastapi-scaffold/SKILL.md`** (3 occurrences — lines 26, 124, 1698):
- `python-json-logger>=4.0` → `python-json-logger`

**`skills/shared-add-logging/SKILL.md:298`**:
- `python-json-logger>=4.0` → `python-json-logger`

**`skills/fastapi-add-database/SKILL.md:220`**:
- `pymongo>=4.0` → `pymongo`

**`skills/fastapi-code-standards/SKILL.md:92`** — remove inline FastAPI version reference:
- Current: `FastAPI 0.132+ requires \`Content-Type: application/json\` by default (\`strict_content_type=True\`)`
- New: `FastAPI enforces \`Content-Type: application/json\` by default (\`strict_content_type=True\`)`

#### Add version knowledge to rules

**`.claude/rules/fastapi.md`** — update stack line:
- Current: `Stack: FastAPI 0.136+, Python 3.13, Pydantic ≥2.9.0 (camelCase schemas), Starlette 1.0, Uvicorn, Ruff, pytest, Docker.`
- New: `Stack: FastAPI 0.136+, Python 3.13, Pydantic ≥2.9.0 (camelCase schemas), Starlette 1.0, Uvicorn, Ruff, pytest, Docker. Logging: python-json-logger ≥4.0. MongoDB: pymongo ≥4.0, motor ≥3.0.`

---

### 4. Version Bump + CHANGELOG

- `.claude-plugin/plugin.json`: `2.9.0` → `2.10.0`
- `CHANGELOG.md`: new `[2.10.0] — 2026-05-07` entry:

```markdown
## [2.10.0] — 2026-05-07

### Fixed
- `nestjs-add-database`: migrated all three AuthService replacement blocks (Drizzle, Kysely, Mongoose) from bcrypt to argon2id — resolves functional contradiction with nestjs-add-auth argon2 migration
- `fastapi-add-database`: updated placeholder comment from bcrypt to argon2id reference
- `nextjs-add-auth`: removed bcrypt hedge from password hashing rule — argon2id is the clear recommendation
- `shared-add-logging`: updated illustrative auth example from bcrypt.compare to argon2.verify
- `fastapi-code-standards`: removed FastAPI version number from Content-Type note — now version-agnostic

### Changed
- `fastapi-scaffold`, `shared-add-logging`: removed python-json-logger version floor from skills — version now in fastapi rules
- `fastapi-add-database`: removed pymongo version floor from skill — version now in fastapi rules
- `.claude/rules/fastapi.md`: added python-json-logger ≥4.0 and pymongo ≥4.0 to stack definition
```

---

## Constraints

- No CVE identifiers in SKILL.md files
- No version pins in SKILL.md files (versions belong only in `.claude/rules/*.md`)
- No IM8 attribution
- No Singapore-specific content
- pnpm version kept at pnpm 10 (`onlyBuiltDependencies` syntax unchanged)
- No new features or refactoring beyond what each fix requires
