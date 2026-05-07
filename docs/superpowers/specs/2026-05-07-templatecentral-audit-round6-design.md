# templateCentral Round 6 Audit — Design Spec

**Date:** 2026-05-07
**Scope:** Post-Round-5 accuracy and security gap closure across the full templateCentral plugin

---

## Goal

Close the remaining accuracy and security gaps identified in the Round 6 fresh-eyes audit. Five targeted groups of changes — no refactoring, no new features.

---

## Design Sections

### 1. Security Accuracy

**1a. Password `min_length` mismatch — `skills/shared-validation-patterns/SKILL.md`**

Line 556 has `password: str = Field(..., min_length=8)`. All auth skills enforce a 12-character minimum. Fix: change `min_length=8` to `min_length=12` so the shared validation pattern matches the enforced policy.

**1b. PyJWT algorithm whitelisting comment — `skills/fastapi-add-auth/SKILL.md`**

The `jwt.decode()` call correctly passes `algorithms=[ALGORITHM]` as an explicit whitelist, but there is no explanation. Without context, a future developer may remove or broaden the list, which opens the door to algorithm confusion attacks (e.g., accepting `none` or `RS256` with an HS256 secret). Fix: add a one-line comment above the `algorithms=` argument explaining that this is a security-critical whitelist — omitting it or using `algorithms=["none"]` allows signature bypass.

---

### 2. better-auth v1.5 + Drizzle ORM rc.1 Accuracy

**2a. Drizzle adapter separate package — `skills/nextjs-add-auth/SKILL.md`**

Since better-auth v1.5, the Drizzle adapter is a separate package (`@better-auth/drizzle`). The current text around line 140 says "Adapters for Drizzle and Kysely are available" without mentioning the separate install. Fix: update the note to name `@better-auth/drizzle` explicitly and include it in the install command shown in Section B.

**2b. Drizzle ORM rc.1 casing API breaking change — `skills/nextjs-add-database/SKILL.md` + `skills/nestjs-add-database/SKILL.md`**

Round 5 added a callout about Drizzle v1 RC status. The rc.1 release removed the `casing` option from the `drizzle()` instance call — casing is now applied at the schema level via imported `snakeCase`/`camelCase` helpers. Fix: extend the existing RC callout with one sentence noting this specific breaking change and referencing the Drizzle migration guide.

---

### 3. pnpm Native Addon Build Permissions

**`skills/nestjs-add-auth/SKILL.md`**

The skill installs `bcrypt` (a native Node addon requiring a compile step) but the scaffolded `package.json` does not include the `pnpm.onlyBuiltDependencies` key. In pnpm 10, native builds are blocked by default unless the package is explicitly listed. Without it, `bcrypt` silently fails to build and crashes at runtime. Fix: add `"pnpm": { "onlyBuiltDependencies": ["bcrypt"] }` to the `package.json` additions shown in the skill.

---

### 4. TypeScript 6 `tsconfig` Explicit `types` Field

**`skills/vite-react-scaffold/SKILL.md`**

TypeScript 6 changed the default for `compilerOptions.types` from "all visible `@types` packages" to `[]` (empty array). The scaffolded `tsconfig.json` has no explicit `types` field. On TS6 projects this silently removes access to any globally-available type packages. Fix: add `"types": []` explicitly to the scaffolded tsconfig. This matches the TS6 default, makes the intent clear, and serves as a prompt for developers to add any `@types/*` packages they need globally.

---

### 5. Version Bump + CHANGELOG

- `.claude-plugin/plugin.json`: `2.5.0` → `2.6.0`
- `CHANGELOG.md`: new `[2.6.0] — 2026-05-07` entry covering all Round 6 changes

---

## Constraints

- Version pins belong only in `.claude/rules/*.md` — never hardcode versions in SKILL.md files
- No CVE identifiers in skills
- No IM8 attribution
- No new features or refactoring beyond what each fix requires
