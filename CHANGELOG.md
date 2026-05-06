# Changelog

All notable changes to templatecentral are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [2.3.0] — 2026-05-06

### Fixed
- **All auth skills**: Removed hardcoded CVE notes for `drizzle-orm` and `better-auth` — CVE tracking belongs in `shared-drift-check` Step 6 (dynamic `pnpm audit` / `pip-audit`), not baked into skill files
- **All skills**: Stripped IM8 policy codes (AS-4, AS-5, AS-6, AS-8, AS-10, AS-11, AS-12, LM-1) from skill files — templateCentral is general-purpose; the security guidance is retained, the Singapore government attribution is removed
- **Four scaffold skills**: Vault note in generated AGENTS.md templates is now vendor-neutral ("use a secrets manager appropriate to your cloud platform") — no prescriptive AWS/Azure/GCP lock-in
- **shared-add-logging**: Log isolation section de-IM8'd; guidance preserved
- **AGENTS.md**: File upload malware scanning note de-IM8'd; guidance preserved

---

## [2.2.0] — 2026-05-06

### Security
- **Next.js scaffold**: Added HTTP security headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, HSTS, CSP baseline) via `next.config.ts` `headers()` — IM8 AS-10
- **NestJS scaffold**: Swagger `/docs` endpoint now disabled in `NODE_ENV=production`; expanded CSP directives (`default-src`, `script-src`, `object-src`, `img-src`)
- **Next.js scaffold**: `https-agent.ts` TLS now defaults to verified in all environments; opt-out via `NODE_TLS_REJECT_UNAUTHORIZED=0` only
- **CI**: `actions/checkout` pinned to SHA (supply chain: OWASP A03:2025); added hardcoded-secret scan job

### Added
- **Next.js scaffold**: `pino` structured logging baked in — `src/lib/logger.ts`, `src/lib/utils/with-logging.ts` (aligns with `shared-add-logging` skill requirements)
- **NestJS scaffold**: Pino `genReqId` for per-request correlation IDs (IM8 audit trail)
- **shared-add-ai-security**: New skill — OWASP LLM Top 10 v2.0 controls (prompt injection, PII redaction, output validation, tool allowlists, token budgets) for A/B/C capability tiers
- **shared-drift-check**: Step 6 — interactive security audit (`pnpm audit` / `pip-audit`) with OSV/NVD vulnerability check
- **AGENTS.md**: SBOM generation guidance (EU CRA / CSA AD-2026-003) and vulnerability scanning commands
- **IM8 AS-6**: Argon2id preference note added to `nextjs-add-auth` Security Rules
- **IM8 AS-8**: Secrets vault note added to all four scaffold generated `AGENTS.md` templates
- **IM8 AS-12**: File upload malware scanning note added to root `AGENTS.md`
- **IM8 LM-1**: Log isolation requirement added to `shared-add-logging` Production Requirement section

### Changed
- **NestJS scaffold**: Migrated from Jest to Vitest (NestJS 11 default); explicit `vitest.config.ts` + `vitest.config.e2e.ts`; `package.json` scripts now specified verbatim
- **NestJS scaffold**: Health endpoint response standardised to lowercase `{ status: 'ok' }` (matches all other stacks)
- **Both scaffolds**: `.dockerignore` trimmed from ~170 lines to ~60 essential patterns
- **Next.js scaffold**: Duplicate health route verbatim blocks consolidated
- **Vite+React scaffold**: Pinned `@vitejs/plugin-react@^6.0.0` (Oxc-based transforms) and bumped `react-router` floor to `^7.15.0` (stable API release)

---

## [2.1.0] — 2026-05-05

### Fixed
- May 2026 accuracy, security, and compliance pass across all skills
- Next.js minimum version bumped to 16.2.4+ / 15.5.9+ (security patches)
- IM8 compliance: bcrypt cost factor, secret validation, rate limiting
- better-auth CVE minimum version enforced
- Zod v4 email error format updated
- Engines fields added to all Node scaffolds (Node ≥22)
- Scaffold verification gates aligned with AGENTS.md
- Dead-end `add-*` skills now include Validate + dispatch routing

---

## [2.0.0]

### Added
- 46-skill plugin with full `plugin.json` + `marketplace.json` manifest
- GitHub install path (`claude plugin marketplace add cljiahao/templatecentral`)
- Shared skills: `drift-check`, `full-stack-pairing`, `task-management`, `update-agent`
- Independent test workflow (Tier 0/1/2) documented in AGENTS.md
- Supply chain and reproducibility rules (pnpm lockfile, Python version pins)

### Changed
- Flat `<stack>-<skill>` directory naming convention
- All scaffolds write `AGENTS.md` + `CLAUDE.md` after verification gates pass

---

## [1.0.0]

### Added
- Initial scaffold skills for Next.js, Vite+React, FastAPI, NestJS
- `add-auth`, `add-database`, `add-test` per stack
- `shared-add-logging`, `shared-add-error-handling`, `shared-validation-patterns`
