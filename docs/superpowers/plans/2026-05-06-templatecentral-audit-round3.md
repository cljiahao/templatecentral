# templateCentral Round 3 Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove hardcoded CVE notes and all IM8-specific labels from templateCentral's skill files, keeping security guidance intact but vendor/policy-neutral, and verify OWASP references are current.

**Architecture:** Four sequential tasks touching disjoint file sets (except Task 2 which follows Task 1 on `nextjs-add-auth/SKILL.md`). All changes are Markdown string replacements — no code compilation, no tests required. Verification is `grep`-based. A final version bump task closes the round.

**Tech Stack:** Markdown skill files only. Verification via `grep`. No npm/pnpm/pip involved.

---

### Task 1: CVE Note Removals

**Goal:** Delete three hardcoded CVE/version-pin blocks from database and auth skills.

**Files:**
- Modify: `skills/nestjs-add-database/SKILL.md` (line 56)
- Modify: `skills/nextjs-add-database/SKILL.md` (line 56)
- Modify: `skills/nextjs-add-auth/SKILL.md` (line 74)

**Acceptance Criteria:**
- [ ] `drizzle-orm 0.45.2` string is gone from both database skill files
- [ ] `better-auth` CVE block is gone from `nextjs-add-auth/SKILL.md`
- [ ] No other content in those files changed

**Verify:**
```bash
grep -n "drizzle-orm 0.45\|better-auth.*1\.6\|Versions prior" skills/nestjs-add-database/SKILL.md skills/nextjs-add-database/SKILL.md skills/nextjs-add-auth/SKILL.md
```
Expected: no output (zero matches).

**Steps:**

- [ ] **Step 1: Remove Drizzle CVE block from nestjs-add-database**

In `skills/nestjs-add-database/SKILL.md`, find and delete the entire line (including surrounding blank line):

```
> **Security**: drizzle-orm 0.45.2 fixed a SQL injection vulnerability in `sql.identifier()` and `sql.as()`. Use `>=0.45.2`.
```

The file context around it (lines 54–58) currently reads:
```
```
[blank line]
> **Security**: drizzle-orm 0.45.2 fixed a SQL injection vulnerability in `sql.identifier()` and `sql.as()`. Use `>=0.45.2`.
[blank line]
### A2. Add Database Scripts
```

After deletion it should read:
```
```
[blank line]
### A2. Add Database Scripts
```

- [ ] **Step 2: Remove Drizzle CVE block from nextjs-add-database**

In `skills/nextjs-add-database/SKILL.md`, apply the identical deletion — same block, same surrounding context.

- [ ] **Step 3: Remove better-auth CVE block from nextjs-add-auth**

In `skills/nextjs-add-auth/SKILL.md`, find and delete this entire line (including surrounding blank line):

```
> **Security**: Versions prior to 1.6.9 have multiple CVEs (auth bypass, prototype pollution, SSRF). Always install `better-auth@latest` (≥ 1.6.9) — never pin to an older version.
```

The file context around it (lines 71–76) currently reads:
```
pnpm add better-auth@latest
```
[blank line]
> **Security**: Versions prior to 1.6.9 have multiple CVEs (auth bypass, prototype pollution, SSRF). Always install `better-auth@latest` (≥ 1.6.9) — never pin to an older version.
[blank line]
### 2. Write `src/lib/auth.ts` (verbatim — do not generate)
```

After deletion it should read:
```
pnpm add better-auth@latest
```
[blank line]
### 2. Write `src/lib/auth.ts` (verbatim — do not generate)
```

- [ ] **Step 4: Verify**

```bash
grep -n "drizzle-orm 0.45\|better-auth.*1\.6\|Versions prior" skills/nestjs-add-database/SKILL.md skills/nextjs-add-database/SKILL.md skills/nextjs-add-auth/SKILL.md
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add skills/nestjs-add-database/SKILL.md skills/nextjs-add-database/SKILL.md skills/nextjs-add-auth/SKILL.md
git commit -m "fix(skills): remove hardcoded CVE notes from database and auth skills"
```

---

### Task 2: IM8 Label Sweep — Auth Skills

**Goal:** Remove all IM8 codes and attributions from the three auth skills, keeping the security guidance intact.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md` (6 locations)
- Modify: `skills/nestjs-add-auth/SKILL.md` (3 locations)
- Modify: `skills/fastapi-add-auth/SKILL.md` (3 locations)

**Acceptance Criteria:**
- [ ] No `IM8` string remains in any of the three files
- [ ] Rate limiting guidance, password length guidance, and Argon2id note are all still present
- [ ] NIST SP 800-63B reference is retained in all inline comments where it appeared alongside IM8

**Verify:**
```bash
grep -n "IM8" skills/nextjs-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md
```
Expected: no output.

**Steps:**

- [ ] **Step 1: nextjs-add-auth — 6 replacements**

In `skills/nextjs-add-auth/SKILL.md`, make these exact string replacements:

**1a.** Line 96 — password min length comment:
- Old: `minPasswordLength: 12, // IM8 AS-5 / NIST SP 800-63B minimum`
- New: `minPasswordLength: 12, // NIST SP 800-63B minimum`

**1b.** Line 120 — session expiry comment:
- Old: `expiresIn: 30 * 24 * 60 * 60, // 30 days (AAL1) — IM8 AS-11: AAL2 systems reduce to 43200 (12h) + 30-min inactivity; AAL3 use 28800 (8h) + 15-min inactivity`
- New: `expiresIn: 30 * 24 * 60 * 60, // 30 days (AAL1) — AAL2 systems reduce to 43200 (12h) + 30-min inactivity; AAL3 use 28800 (8h) + 15-min inactivity`

**1c.** Line 511 — rate limiting prose:
- Old: `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes. better-auth does not include built-in rate limiting — add it at the infrastructure layer (CDN/WAF/API Gateway) or in \`proxy.ts\` middleware using \`@upstash/ratelimit\` (Redis-backed, edge-compatible):`
- New: `Industry best practice: max 3 failed auth attempts per 15 minutes. better-auth does not include built-in rate limiting — add it at the infrastructure layer (CDN/WAF/API Gateway) or in \`proxy.ts\` middleware using \`@upstash/ratelimit\` (Redis-backed, edge-compatible):`

**1d.** Line 520 — inline comment in code block:
- Old: `// Rate limit sign-in attempts (IM8 AS-4: max 3/15 min)`
- New: `// Rate limit sign-in attempts (max 3/15 min)`

**1e.** Line 537 — Security Rules bullet:
- Old: `- **Rate limiting is mandatory for production** — add rate limiting on auth endpoints before going live (IM8 AS-4).`
- New: `- **Rate limiting is mandatory for production** — add rate limiting on auth endpoints before going live.`

**1f.** Line 538 — Argon2id bullet:
- Old: `- **Password hashing (IM8 AS-6)**: better-auth uses bcrypt by default (acceptable). For any custom hashing outside better-auth, prefer Argon2id (\`argon2\` package) — ranked above bcrypt by OWASP and IM8 AS-6.`
- New: `- **Password hashing**: better-auth uses bcrypt by default (acceptable). For any custom hashing outside better-auth, prefer Argon2id (\`argon2\` package) — ranked above bcrypt by OWASP.`

- [ ] **Step 2: nestjs-add-auth — 3 replacements**

In `skills/nestjs-add-auth/SKILL.md`, make these exact string replacements:

**2a.** Line 56 — password schema comment:
- Old: `password: z.string().min(12), // 12-char minimum — IM8 AS-5 / NIST SP 800-63B baseline`
- New: `password: z.string().min(12), // 12-char minimum — NIST SP 800-63B baseline`

**2b.** Line 303 — rate limiting prose:
- Old: `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes. Install \`@nestjs/throttler\`:`
- New: `Industry best practice: max 3 failed auth attempts per 15 minutes. Install \`@nestjs/throttler\`:`

**2c.** Line 328 — Rules bullet:
- Old: `- **Rate limiting is mandatory for production** — add \`@nestjs/throttler\` before going live (IM8 AS-4).`
- New: `- **Rate limiting is mandatory for production** — add \`@nestjs/throttler\` before going live.`

- [ ] **Step 3: fastapi-add-auth — 3 replacements**

In `skills/fastapi-add-auth/SKILL.md`, make these exact string replacements:

**3a.** Line 51 — password field description:
- Old: `password: str = Field(min_length=12, description="User password — minimum 12 characters (IM8 AS-5 / NIST SP 800-63B).")`
- New: `password: str = Field(min_length=12, description="User password — minimum 12 characters (NIST SP 800-63B).")`

**3b.** Line 276 — rate limiting prose:
- Old: `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes. Add \`slowapi>=0.1.9\` to \`requirements.txt\`, then:`
- New: `Industry best practice: max 3 failed auth attempts per 15 minutes. Add \`slowapi>=0.1.9\` to \`requirements.txt\`, then:`

**3c.** Line 301 — Rules bullet:
- Old: `- **Rate limiting is mandatory for production** — add \`slowapi\` before going live (IM8 AS-4).`
- New: `- **Rate limiting is mandatory for production** — add \`slowapi\` before going live.`

- [ ] **Step 4: Verify**

```bash
grep -n "IM8" skills/nextjs-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md
```
Expected: no output.

Also confirm guidance is preserved:
```bash
grep -n "NIST SP 800-63B\|Argon2id\|rate limit\|Rate limit" skills/nextjs-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md | head -20
```
Expected: multiple matches confirming guidance survived.

- [ ] **Step 5: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md skills/nestjs-add-auth/SKILL.md skills/fastapi-add-auth/SKILL.md
git commit -m "fix(skills): strip IM8 labels from auth skills — keep guidance, remove attribution"
```

---

### Task 3: IM8 Label Sweep — Scaffold and Support Skills

**Goal:** Remove all remaining IM8 references from scaffold skills and support skills.

**Files:**
- Modify: `skills/shared-add-logging/SKILL.md` (2 locations — header + body)
- Modify: `AGENTS.md` (1 location)
- Modify: `skills/nextjs-scaffold/SKILL.md` (2 locations)
- Modify: `skills/fastapi-scaffold/SKILL.md` (1 location)
- Modify: `skills/nestjs-scaffold/SKILL.md` (3 locations)
- Modify: `skills/vite-react-scaffold/SKILL.md` (1 location)
- Modify: `skills/shared-add-ai-security/SKILL.md` (1 location)

**Acceptance Criteria:**
- [ ] No `IM8` string remains in any of the seven files
- [ ] Log isolation guidance still present in `shared-add-logging/SKILL.md`
- [ ] File upload malware scanning note still present in `AGENTS.md`
- [ ] All four scaffold vault notes updated to vendor-neutral wording
- [ ] HSTS comments in scaffold files retain "HSTS" but drop IM8 code

**Verify:**
```bash
grep -n "IM8" skills/shared-add-logging/SKILL.md AGENTS.md skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md skills/shared-add-ai-security/SKILL.md
```
Expected: no output.

**Steps:**

- [ ] **Step 1: shared-add-logging — header and body**

In `skills/shared-add-logging/SKILL.md`:

**1a.** Change section header (line 857):
- Old: `## Production Requirement (IM8 LM-1)`
- New: `## Production Requirement`

**1b.** Change body text (line 859):
- Old: `Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only does not satisfy IM8 LM-1, which requires log storage isolated from the application host.`
- New: `Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only is not sufficient; production log storage must be isolated from the application host.`

- [ ] **Step 2: AGENTS.md — file upload note**

In `AGENTS.md`, line 121:
- Old: `- **File uploads (IM8 AS-12)**: Scan uploaded files for malware (ClamAV or a cloud scanning service such as AWS GuardDuty Malware Protection) before writing to storage.`
- New: `- **File uploads**: Scan uploaded files for malware (ClamAV or a cloud scanning service such as AWS GuardDuty Malware Protection) before writing to storage.`

- [ ] **Step 3: nextjs-scaffold — HSTS comment and vault note**

In `skills/nextjs-scaffold/SKILL.md`:

**3a.** Line 215 — HSTS comment:
- Old: `          // HSTS — IM8 AS-10. Only active over HTTPS; Next.js strips this header over HTTP automatically.`
- New: `          // HSTS — only active over HTTPS; Next.js strips this header over HTTP automatically.`

**3b.** Line 2551 — generated AGENTS.md template vault note:
- Old: `- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat \`.env\` files are for local development only.`
- New: `- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat \`.env\` files are for local development only.`

- [ ] **Step 4: fastapi-scaffold — vault note**

In `skills/fastapi-scaffold/SKILL.md`, line 1766:
- Old: `- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat \`.env\` / \`.env.default\` files are for local development only.`
- New: `- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat \`.env\` / \`.env.default\` files are for local development only.`

- [ ] **Step 5: nestjs-scaffold — correlation ID comment, HSTS comment, vault note**

In `skills/nestjs-scaffold/SKILL.md`:

**5a.** Line 785 — correlation ID comment:
- Old: `        genReqId: () => crypto.randomUUID(), // correlation ID for IM8 audit trail`
- New: `        genReqId: () => crypto.randomUUID(), // correlation ID`

**5b.** Line 938 — HSTS inline comment:
- Old: `    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true }, // IM8 AS-10`
- New: `    strictTransportSecurity: { maxAge: 31536000, includeSubDomains: true },`

**5c.** Line 1487 — generated AGENTS.md template vault note:
- Old: `- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat \`.env\` files are for local development only.`
- New: `- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat \`.env\` files are for local development only.`

- [ ] **Step 6: vite-react-scaffold — vault note**

In `skills/vite-react-scaffold/SKILL.md`, line 2993:
- Old: `- **Secrets in production (IM8 AS-8)**: Backend secrets must use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Never put backend secrets in \`VITE_*\` env vars or any client-side code.`
- New: `- **Secrets in production**: Backend secrets must use a secrets manager appropriate to your cloud platform. Never put backend secrets in \`VITE_*\` env vars or any client-side code.`

- [ ] **Step 7: shared-add-ai-security — inline comment**

In `skills/shared-add-ai-security/SKILL.md`, line 271:
- Old: `// Per-user rate limiting (same pattern as IM8 AS-4 in nextjs-add-auth)`
- New: `// Per-user rate limiting`

- [ ] **Step 8: Verify**

```bash
grep -n "IM8" skills/shared-add-logging/SKILL.md AGENTS.md skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md skills/shared-add-ai-security/SKILL.md
```
Expected: no output.

Confirm guidance preserved:
```bash
grep -n "malware\|tamper-evident\|HSTS\|Secrets in production\|rate limit" skills/shared-add-logging/SKILL.md AGENTS.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md | head -20
```
Expected: multiple matches.

- [ ] **Step 9: Commit**

```bash
git add skills/shared-add-logging/SKILL.md AGENTS.md skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md skills/shared-add-ai-security/SKILL.md
git commit -m "fix(skills): strip IM8 labels from scaffold and support skills — vendor-neutral wording"
```

---

### Task 4: OWASP 2025 Reference Audit

**Goal:** Verify all OWASP references in skill files are current for the 2025 ranking; correct any that cite stale 2021 rank numbers.

**Files:** All files containing `OWASP` (determined by grep at runtime).

**Acceptance Criteria:**
- [ ] No references to 2021-specific rank numbers (e.g. "A03 Injection", "A05 Security Misconfiguration") that conflict with 2025 ranking
- [ ] `shared-add-ai-security` OWASP LLM Top 10 v2.0 reference is unchanged (LLM list is separate from Web Top 10)

**Key 2025 changes to check for:**

| 2021 | 2025 | Category |
|------|------|----------|
| A03 | A05 | Injection |
| A05 | A02 | Security Misconfiguration |
| A10 | removed | SSRF (now subsumed) |
| — | A03 | Supply Chain |
| — | A10 | Mishandling Exceptional Conditions |

**Verify:**
```bash
grep -rn "OWASP" skills/ AGENTS.md
```

**Steps:**

- [ ] **Step 1: Locate all OWASP references**

Run:
```bash
grep -rn "OWASP" skills/ AGENTS.md
```

Review each match. For each reference, check whether it cites a specific rank number (e.g. "A03", "A05") tied to the 2021 list.

- [ ] **Step 2: Assess and update**

For each reference found:
- If it says just "OWASP" or "OWASP minimum" without a rank number → no change needed
- If it says "OWASP LLM Top 10" → no change needed (separate list, v2.0 is current)
- If it cites "A03 Injection" → update to "A05 Injection (OWASP 2025)"
- If it cites "A05 Security Misconfiguration" → update to "A02 Security Misconfiguration (OWASP 2025)"
- If it cites "A10 SSRF" → update to note SSRF is no longer a standalone 2025 category

**Expected result based on pre-audit:** All current OWASP references use the generic term without rank numbers. If this holds, Step 2 requires no edits — document this finding in the commit message.

- [ ] **Step 3: Commit (conditional)**

If changes were made:
```bash
git add <changed files>
git commit -m "fix(skills): update OWASP Top 10 references to 2025 ranking"
```

If no changes needed:
```bash
git commit --allow-empty -m "chore(audit): OWASP 2025 reference audit — no rank-specific references found, no changes needed"
```

---

### Task 5: Version Bump and CHANGELOG

**Goal:** Bump plugin version to 2.3.0 and record Round 3 changes in CHANGELOG.md.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.3.0"`
- [ ] CHANGELOG has `[2.3.0]` entry dated 2026-05-06

**Verify:**
```bash
grep '"version"' .claude-plugin/plugin.json && grep '\[2.3.0\]' CHANGELOG.md
```
Expected: both return a match.

**Steps:**

- [ ] **Step 1: Read current plugin.json version**

Read `.claude-plugin/plugin.json` to confirm current version is `"2.2.0"` before editing.

- [ ] **Step 2: Bump plugin.json**

In `.claude-plugin/plugin.json`, change:
```json
"version": "2.2.0",
```
to:
```json
"version": "2.3.0",
```

- [ ] **Step 3: Read current CHANGELOG.md top**

Read the first 30 lines of `CHANGELOG.md` to find the correct insertion point (after `[Unreleased]` and before `[2.2.0]`).

- [ ] **Step 4: Add CHANGELOG entry**

In `CHANGELOG.md`, insert a new `[2.3.0]` entry immediately after the `[Unreleased]` section header and before the `[2.2.0]` entry:

```markdown
## [2.3.0] — 2026-05-06

### Fixed
- **All auth skills**: Removed hardcoded CVE notes for `drizzle-orm` and `better-auth` — CVE tracking belongs in `shared-drift-check` Step 6 (dynamic `pnpm audit` / `pip-audit`), not baked into skill files
- **All skills**: Stripped IM8 policy codes (AS-4, AS-5, AS-6, AS-8, AS-10, AS-11, AS-12, LM-1) from skill files — templateCentral is general-purpose; the security guidance is retained, the Singapore government attribution is removed
- **Four scaffold skills**: Vault note in generated AGENTS.md templates is now vendor-neutral ("use a secrets manager appropriate to your cloud platform") — no prescriptive AWS/Azure/GCP lock-in
- **shared-add-logging**: Log isolation section header and body de-IM8'd; guidance preserved
- **AGENTS.md**: File upload malware scanning note de-IM8'd; guidance preserved
```

- [ ] **Step 5: Verify**

```bash
grep '"version"' .claude-plugin/plugin.json && grep '\[2.3.0\]' CHANGELOG.md
```
Expected: both return a match.

- [ ] **Step 6: Final IM8 sweep verification**

```bash
grep -rn "IM8" skills/ AGENTS.md
```
Expected: **zero output**. If any matches remain, fix them before committing.

- [ ] **Step 7: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump to 2.3.0"
```
