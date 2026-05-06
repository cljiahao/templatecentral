# templateCentral Round 3 Audit — Design Spec

**Goal:** Remove CVE/version notes that violate templateCentral's no-CVE policy, strip all IM8-specific labels across the entire skill set (keeping the guidance, removing the attribution), and correct OWASP Top 10 references to the 2025 ranking.

**Approach:** Three parallel agent groups targeting disjoint file sets — no merge conflicts.

**Architecture:** Markdown-only changes across existing skill files. No new files. No new abstractions. Three independent concerns executed in parallel.

---

## Context and Rationale

### Why no CVE notes in skills

CVE tracking belongs in `shared-drift-check` Step 6 (dynamic `pnpm audit` / `pip-audit`), which runs against the installed dependency tree at any point in time. Hardcoding CVE identifiers or minimum version pins in skill files causes silent staleness — the note ages out of date with no mechanism to update it. Skills should document patterns and guidance; security advisories are a CI/runtime concern.

### Why no IM8 labels

templateCentral is a general-purpose scaffolding plugin used across industries — public sector, private sector, and internationally. IM8 is a Singapore government ICT&SS policy. Labelling guidance with IM8 codes (AS-6, AS-8, AS-12, LM-1) is misleading to non-government users and unnecessary — the guidance itself (Argon2id, log isolation, malware scanning, secrets management) is valid industry best practice regardless of regulatory framework.

### Why no cloud vendor prescriptions for production secrets

templateCentral scaffolds local development projects. Prescribing which cloud secrets manager (AWS, Azure, GCP) a team should use in production is an org-level deployment decision, not a scaffold concern. The scaffold correctly documents `.env` for local development; production secrets management should be noted as a concern without specifying a vendor.

---

## Group 1 — CVE Note Removals

**Files:** `skills/nestjs-add-database/SKILL.md`, `skills/nextjs-add-database/SKILL.md`, `skills/nextjs-add-auth/SKILL.md`

**Changes:**

### nestjs-add-database + nextjs-add-database

Remove the following block (identical in both files, near the installation steps):

```
> **Security**: drizzle-orm 0.45.2 fixed a SQL injection vulnerability in `sql.identifier()` and `sql.as()`. Use `>=0.45.2`.
```

No replacement — the guidance to use the latest package manager resolution is sufficient.

### nextjs-add-auth

Remove the following block (after the `pnpm add better-auth@latest` line):

```
> **Security**: Versions prior to 1.6.9 have multiple CVEs (auth bypass, prototype pollution, SSRF). Always install `better-auth@latest` (≥ 1.6.9) — never pin to an older version.
```

The `pnpm add better-auth@latest` on the preceding line already enforces the latest version; the note is redundant and violates CVE policy.

---

## Group 2 — IM8 Label Removal (Full Sweep)

Self-review of the codebase found IM8 references across 9 files — not just the Round 2 additions. This group cleans all of them. The security guidance is retained throughout; only the IM8 codes and attributions are removed.

**Files:** `skills/nextjs-add-auth/SKILL.md`, `skills/nestjs-add-auth/SKILL.md`, `skills/fastapi-add-auth/SKILL.md`, `skills/shared-add-logging/SKILL.md`, `AGENTS.md`, `skills/nextjs-scaffold/SKILL.md`, `skills/fastapi-scaffold/SKILL.md`, `skills/nestjs-scaffold/SKILL.md`, `skills/vite-react-scaffold/SKILL.md`, `skills/shared-add-ai-security/SKILL.md`

**Changes per file:**

### nextjs-add-auth/SKILL.md (5 IM8 references)

| Line | Current | Replace with |
|------|---------|--------------|
| 96 | `// IM8 AS-5 / NIST SP 800-63B minimum` | `// NIST SP 800-63B minimum` |
| 120 | `// 30 days (AAL1) — IM8 AS-11: AAL2 systems reduce to 43200...` | `// 30 days (AAL1) — AAL2 systems reduce to 43200 (12h) + 30-min inactivity; AAL3 use 28800 (8h) + 15-min inactivity` |
| 511 | `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes.` | `Industry best practice: max 3 failed auth attempts per 15 minutes.` |
| 520 | `// Rate limit sign-in attempts (IM8 AS-4: max 3/15 min)` | `// Rate limit sign-in attempts (max 3/15 min)` |
| 537 | `...before going live (IM8 AS-4).` | `...before going live.` |
| 538 | `- **Password hashing (IM8 AS-6)**: ...ranked above bcrypt by OWASP and IM8 AS-6.` | `- **Password hashing**: ...ranked above bcrypt by OWASP.` |

### nestjs-add-auth/SKILL.md (3 IM8 references)

| Line | Current | Replace with |
|------|---------|--------------|
| 56 | `// 12-char minimum — IM8 AS-5 / NIST SP 800-63B baseline` | `// 12-char minimum — NIST SP 800-63B baseline` |
| 303 | `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes.` | `Industry best practice: max 3 failed auth attempts per 15 minutes.` |
| 328 | `...before going live (IM8 AS-4).` | `...before going live.` |

### fastapi-add-auth/SKILL.md (3 IM8 references)

| Line | Current | Replace with |
|------|---------|--------------|
| 51 | `description="...minimum 12 characters (IM8 AS-5 / NIST SP 800-63B)."` | `description="...minimum 12 characters (NIST SP 800-63B)."` |
| 276 | `IM8 AS-4 mandates max 3 failed auth attempts per 15 minutes.` | `Industry best practice: max 3 failed auth attempts per 15 minutes.` |
| 301 | `...before going live (IM8 AS-4).` | `...before going live.` |

### shared-add-logging/SKILL.md (2 IM8 references — header + body)

Change section header from `## Production Requirement (IM8 LM-1)` to `## Production Requirement`.

In the body, remove `IM8 LM-1` references:

Current body:
```
Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only does not satisfy IM8 LM-1, which requires log storage isolated from the application host.
```

Replace with:
```
Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only is not sufficient; production log storage must be isolated from the application host.
```

### AGENTS.md (1 IM8 reference)

Remove `(IM8 AS-12)` from the file upload note. Result:
```
- **File uploads**: Scan uploaded files for malware (ClamAV or a cloud scanning service such as AWS GuardDuty Malware Protection) before writing to storage.
```

### nextjs-scaffold/SKILL.md (2 IM8 references)

| Location | Current | Replace with |
|----------|---------|--------------|
| Line ~215 inline comment | `// HSTS — IM8 AS-10.` | `// HSTS` |
| Generated AGENTS.md template | `- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat \`.env\` files are for local development only.` | `- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat \`.env\` files are for local development only.` |

### fastapi-scaffold/SKILL.md (1 IM8 reference)

Generated AGENTS.md template — same vault note change as above (`.env.default` variant).

### nestjs-scaffold/SKILL.md (3 IM8 references)

| Location | Current | Replace with |
|----------|---------|--------------|
| Line ~785 inline comment | `// correlation ID for IM8 audit trail` | `// correlation ID` |
| Line ~938 inline comment | `strictTransportSecurity: ..., // IM8 AS-10` | `strictTransportSecurity: ...` (remove comment) |
| Generated AGENTS.md template | `- **Secrets in production (IM8 AS-8)**: ...` | `- **Secrets in production**: Use a secrets manager appropriate to your cloud platform — flat \`.env\` files are for local development only.` |

### vite-react-scaffold/SKILL.md (1 IM8 reference)

Generated AGENTS.md template — vault note change (VITE_* variant):

Current:
```
- **Secrets in production (IM8 AS-8)**: Backend secrets must use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Never put backend secrets in `VITE_*` env vars or any client-side code.
```

Replace with:
```
- **Secrets in production**: Backend secrets must use a secrets manager appropriate to your cloud platform. Never put backend secrets in `VITE_*` env vars or any client-side code.
```

### shared-add-ai-security/SKILL.md (1 IM8 reference)

| Location | Current | Replace with |
|----------|---------|--------------|
| Line ~271 inline comment | `// Per-user rate limiting (same pattern as IM8 AS-4 in nextjs-add-auth)` | `// Per-user rate limiting` |

---

## Group 3 — OWASP 2025 Reference Audit

**Files:** All `skills/**/*.md` and `AGENTS.md` containing OWASP references (to be identified by grep).

**Key 2025 changes relevant to templateCentral skills:**

| Item | 2021 Rank | 2025 Rank | Notes |
|------|-----------|-----------|-------|
| Security Misconfiguration | A05 | A02 | Significant rise |
| Supply Chain Risks | — | A03 | New in 2025 |
| Injection | A03 | A05 | Dropped |
| Mishandling Exceptional Conditions | — | A10 | New; replaces 2021 SSRF |

**Process:**
1. `grep -rn "OWASP" skills/ AGENTS.md` to locate all references
2. Read each surrounding context (~5 lines)
3. Update rank numbers and category names where stale
4. No new OWASP sections added — corrections only

---

## What Is Not Changing

- The security guidance content itself — Argon2id, log isolation, malware scanning — is all retained; only labels/attribution change
- No changes to CVE-free skills
- No structural refactoring (deferred)
- No version pins added or removed beyond the three CVE note deletions
- `shared-drift-check` Step 6 (dynamic security audit) remains the canonical home for CVE tracking

---

## Acceptance Criteria

- [ ] No `IM8` string remains anywhere in `skills/**/*.md` or `AGENTS.md` (verify: `grep -rn "IM8" skills/ AGENTS.md`)
- [ ] No CVE identifiers or specific minimum version pins remain in `skills/nestjs-add-database/SKILL.md`, `skills/nextjs-add-database/SKILL.md`, or `skills/nextjs-add-auth/SKILL.md`
- [ ] Security guidance (Argon2id, log isolation, malware scanning, production secrets) is preserved in all affected files
- [ ] Vault note in all four scaffold AGENTS.md templates is vendor-neutral (no AWS/Azure/GCP prescription)
- [ ] Any OWASP references updated to 2025 rankings where they cited 2021 ranks
