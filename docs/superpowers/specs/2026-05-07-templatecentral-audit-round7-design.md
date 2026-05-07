# templateCentral Round 7 Audit — Design Spec

**Date:** 2026-05-07
**Scope:** Post-Round-6 accuracy and security gap closure across templateCentral

---

## Goal

Close five targeted gaps identified in the Round 7 fresh-eyes audit: Drizzle v1.0 stable promotion, argon2id guidance, NRIC generalization, better-auth version pin removal, and version bump.

---

## Design Sections

### 1. Drizzle v1.0 Stable Promotion

**`skills/nextjs-add-database/SKILL.md:49`** and **`skills/nestjs-add-database/SKILL.md:49`**

Both files have a callout saying "Drizzle ORM v1 is currently in release candidate — verify stable release at drizzle.team before production use." Drizzle v1.0 stable has shipped. The RC hedge is no longer accurate.

Fix: replace the RC warning with a stable-release note. The casing API guidance (removed from `drizzle()` instance, now applied at schema level via `snakeCase`/`camelCase` imports) remains accurate and should be kept. The migration guide link stays for developers upgrading from 0.x. Drop the "verify stable release before production use" language.

---

### 2. argon2id Guidance Note

**`skills/nestjs-add-auth/SKILL.md`** (Rules section) and **`skills/fastapi-add-auth/SKILL.md`** (Security/Rules section)

Both skills use bcrypt as the password hashing implementation. bcrypt remains secure and the implementations are correct. However, argon2id is now the industry-standard recommendation (OWASP Password Storage Cheat Sheet, NIST SP 800-63B 2024 update) — it is memory-hard and more resistant to GPU-based brute-force than bcrypt.

Fix: add a short guidance note to the Rules section of each skill:
- argon2id is the recommended choice for new projects
- bcrypt remains acceptable if already in use or if the environment does not support native addons
- No code changes — guidance note only, no mandate to rewrite existing bcrypt implementations

---

### 3. NRIC Generalization in `shared-add-ai-security`

**`skills/shared-add-ai-security/SKILL.md`** — LLM02 PII redaction pattern

The PII redaction example includes `[/\b[A-Z]\d{7}[A-Z]\b/g, '[NRIC]']` with comment `// Singapore NRIC`. templateCentral is cross-industry and global — a Singapore-specific national ID format as the sole "government ID" example is inappropriate and confusing to developers outside Singapore.

Fix: replace the NRIC entry with a generic national ID pattern and comment noting that the regex should be adapted to the deployment jurisdiction. A simple digit-block pattern (e.g. `\b\d{5,12}\b` with appropriate word-boundary anchoring) covers a wide range of national ID formats as a starting point. The comment must explicitly say "adapt to your jurisdiction."

---

### 4. better-auth Version Pin Removal

**`skills/nextjs-add-auth/SKILL.md:140`**

The database callout says "Since better-auth v1.5, the Drizzle adapter ships as a separate package." better-auth is now at v1.6.9 — the v1.5 marker will keep drifting with each release. The fact itself is now stable (the adapter has been separate for multiple releases).

Fix: remove the version marker. Rewrite as "The Drizzle adapter is a separate package (`@better-auth/drizzle` — install alongside `drizzle-orm`)." Same information, no drifting version pin.

---

### 5. Version Bump + CHANGELOG

- `.claude-plugin/plugin.json`: `2.6.0` → `2.7.0`
- `CHANGELOG.md`: new `[2.7.0] — 2026-05-07` entry covering all Round 7 changes

---

## Constraints

- No CVE identifiers in SKILL.md files
- No version pins in SKILL.md files (versions belong only in `.claude/rules/*.md`)
- No IM8 attribution
- No new features or refactoring beyond what each fix requires
- pnpm version reference in nestjs-add-auth left as-is (out of scope for this round)
