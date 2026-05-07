# Changelog

All notable changes to templatecentral are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [2.13.0] — 2026-05-07

### Fixed
- `nestjs-scaffold`: added `Referrer-Policy: strict-origin-when-cross-origin` to Helmet config — `@fastify/helmet` does not set this header by default
- `nestjs-scaffold`: added `Permissions-Policy: camera=(), microphone=(), geolocation=()` to `onSend` hook — was missing while Next.js scaffold had it
- `nestjs-scaffold`: removed legacy `Pragma: no-cache` and `Expires: 0` from `onSend` hook — both deprecated in HTTP/1.1+; `Cache-Control` is sufficient
- `fastapi-scaffold`: added `Permissions-Policy` to `_SECURITY_HEADERS` — brings FastAPI in line with Next.js and NestJS scaffolds
- `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold`: moved `blockExoticSubdeps` from `.npmrc` to `pnpm-workspace.yaml` — in pnpm 11, `.npmrc` is auth/registry-only; supply-chain protection was silently ignored
- `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold`: added `pnpm-workspace.yaml*` to Dockerfile `COPY` line and `.dockerignore` exception list — pnpm config absent during Docker `pnpm install` was losing security settings
- `nestjs-add-auth`: updated `allowBuilds` guidance to use `pnpm-workspace.yaml` — `package.json#pnpm` field is no longer read by pnpm 11
- All three Node rules files (`.claude/rules/nestjs.md`, `nextjs.md`, `vite-react.md`): updated `allowBuilds` location reference to `pnpm-workspace.yaml`
- `fastapi-add-auth`: noted that `TRUST_PROXY` must be set for per-client rate limiting with `slowapi` when behind a reverse proxy
- `nestjs-add-auth`: noted same TRUST_PROXY dependency for `ThrottlerGuard` / Fastify `trustProxy` interaction
- `shared-drift-check`, `shared-update-agent`: replaced "CVE" identifiers with "security advisory" — prevents identifier drift in skills

### Changed
- `nestjs-scaffold`: removed `@nestjs/common` and `@nestjs/core` version pins from install command; removed `@fastify/helmet` version pin — version floors belong in rules, not skills
- `vite-react-scaffold`: removed `react-router`, `@hookform/resolvers`, `@vitejs/plugin-react` version pins from install command — arbitrary preferences, not functional constraints
- `nextjs-add-auth`: removed `better-auth@^1.6.9` pin — install unpinned; version belongs in rules if a floor is needed

---

## [2.12.0] — 2026-05-07

### Added
- `fastapi-scaffold`: `SecurityHeadersMiddleware` — zero-dependency ASGI middleware setting HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, and X-XSS-Protection on every HTTP response; wired via `configure_security_headers()` called before CORS in `start_application()`

### Fixed
- `nextjs-add-auth`: pinned `better-auth@^1.6.9` (was `@latest`) — removes non-deterministic installs; resolves to current stable
- All scaffolds: migrated pnpm native-addon config from `"onlyBuiltDependencies": [...]` array syntax (pnpm 10) to `"allowBuilds": { "<pkg>": true }` object syntax (pnpm 11)

---

## [2.11.0] — 2026-05-07

### Added
- `nextjs-scaffold`: new `src/lib/utils/request-origin.ts` — `getAppOrigin()` utility reads `X-Forwarded-Proto`/`X-Forwarded-Host` when `TRUST_PROXY` is set, falls back to direct connection values otherwise
- `nestjs-scaffold`: `TRUST_PROXY` env var wired into `FastifyAdapter({ trustProxy })` at bootstrap — no-op when unset; `*` correctly converts to boolean `true` for Fastify
- `fastapi-scaffold`: `ForwardedHostMiddleware` (fixes `X-Forwarded-Host` gap in uvicorn's `ProxyHeadersMiddleware`) and `configure_proxy_headers()` — both conditional on `TRUST_PROXY`; `TRUST_PROXY` field added to `APISettings`
- All three scaffolds: `TRUST_PROXY=` added to `.env.example` with explanation comment

---

## [2.10.0] — 2026-05-07

### Fixed
- `nestjs-add-database`: migrated all three AuthService replacement blocks (Drizzle, Kysely, Mongoose) from bcrypt to argon2id — resolves functional contradiction with nestjs-add-auth argon2 migration
- `fastapi-add-database`: replaced bcrypt placeholder comment with a reference to `hash_password()` from `core/security.py` — removes algorithm coupling from example code
- `nextjs-add-auth`: removed bcrypt hedge from password hashing rule — argon2id is the clear recommendation
- `shared-add-logging`: updated illustrative auth example from bcrypt.compare to argon2.verify
- `fastapi-code-standards`: removed FastAPI version number from Content-Type note — now version-agnostic

### Changed
- `fastapi-scaffold`, `shared-add-logging`: removed python-json-logger version floor from skills — version now in fastapi rules
- `fastapi-add-database`: removed pymongo version floor from skill — version now in fastapi rules
- `.claude/rules/fastapi.md`: added python-json-logger ≥4.0 and pymongo ≥4.0 to stack definition

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

### Fixed
- `fastapi-scaffold`, `nextjs-scaffold`, `nestjs-scaffold`, `vite-react-scaffold`: removed hardcoded `Asia/Singapore` timezone from Dockerfiles — containers now default to UTC; operators can override via `TZ` env var at deploy time
- `shared-add-ai-security`: replaced hardcoded `gpt-4o-2024-11-20` model snapshot in LLM03 and LLM10 examples with a placeholder annotation — the teaching point (pin a dated snapshot) is preserved without encoding a specific version
- `nextjs-add-auth`: removed `better-auth ≥1.6` and `better-auth 1.6` version markers from `freshAge` and OIDC provider notes — behavioral facts retained, drifting version pins removed
- `fastapi-scaffold`, `shared-add-logging`: updated `python-json-logger` floor from `>=3.3.0,<4.0` to `>=4.0` — v4.1.0 is current stable (March 2026)

---

## [2.7.0] — 2026-05-07

### Fixed
- `nextjs-add-database`, `nestjs-add-database`: retired Drizzle ORM v1 RC warning — v1.0 is now stable; retained casing API guidance and migration guide link
- `nestjs-add-auth`, `fastapi-add-auth`: added argon2id guidance note to Rules — argon2id is the current OWASP/NIST recommendation for new projects; bcrypt remains acceptable
- `shared-add-ai-security`: replaced Singapore-specific NRIC regex and phone country code with generic jurisdiction-neutral PII patterns
- `nextjs-add-auth`: removed hardcoded `v1.5` version pin from better-auth Drizzle adapter note

---

## [2.6.0] — 2026-05-07

### Fixed
- `shared-validation-patterns`: password `min_length` corrected from 8 to 12 to match all auth skill policies
- `fastapi-add-auth`: added algorithm whitelist comment to `jwt.decode()` — explains why `algorithms=` must never be omitted or broadened
- `nextjs-add-auth`: noted `@better-auth/drizzle` ships as a separate package since better-auth v1.5
- `nextjs-add-database`, `nestjs-add-database`: extended Drizzle v1 RC callout with rc.1 casing API breaking change and migration guide link
- `nestjs-add-auth`: added `pnpm.onlyBuiltDependencies` step for bcrypt — pnpm 10 blocks native builds by default
- `vite-react-scaffold`: added explicit `"types": []` to tsconfig — TypeScript 6 changed default from all visible `@types` to empty array

---

## [2.5.0] — 2026-05-07

### Fixed
- **rules/nextjs.md**: Updated `Node.js ≥20.9.0` → `Node.js ≥24` — Node 24 is Active LTS
- **rules/{nestjs,vite-react}.md**: Added `Node.js ≥24` to Stack lines — was missing entirely
- **{nextjs,nestjs,vite-react}-scaffold**: `engines.node` updated to `>=24`; Dockerfile ARG changed from patch-pinned `node:24.14-alpine3.23` to `node:24-alpine` — patch pins belong in CI/CD, not skill templates
- **{nestjs,vite-react}-scaffold**: Dockerfile `NODE` comment corrected — floating major tag, pin to digest in CI for reproducibility

### Added
- **nextjs-code-standards**: Async-only rule for Next.js 16 Request APIs (`cookies()`, `headers()`, `params`, `searchParams`) — sync access is a TypeScript error and runtime failure
- **nextjs-add-auth**: `@better-auth/oauth-provider` replaces the removed `oidc-provider` plugin (better-auth 1.6); added docs link
- **fastapi-code-standards**: `json=data` test client guidance — FastAPI 0.132+ enforces `Content-Type: application/json` by default (`strict_content_type=True`)
- **{nextjs,nestjs}-add-database**: Drizzle ORM v1 RC status callout — not yet final stable release
- **vite-react-scaffold**: Oxc note for `@vitejs/plugin-react` v6 — no Babel config or `@babel/core` required

---

## [2.4.0] — 2026-05-07

### Fixed
- **AGENTS.md**: Removed drifting patch-level Next.js version pin (`16.2.4+` / `15.5.9+`) — major version pins belong in `.claude/rules/*.md` only
- **rules/fastapi.md**: Tightened `Pydantic v2` to `Pydantic ≥2.9.0`; added `Starlette 1.0` to Stack line
- **rules/nextjs.md**: Added `Node.js ≥20.9.0` to Stack line — Next.js 16 dropped Node 18 support
- **fastapi-add-auth**: Removed `slowapi>=0.1.9` patch-level version pin (CVE policy violation)

### Added
- **AGENTS.md**: OWASP A03:2025 Supply Chain framing in supply chain section — supply chain attacks rose to #3 in 2025 ranking
- **shared-add-error-handling**: OWASP A10:2025 Mishandling Exceptional Conditions merged into Security Checklist (unified with existing unhandled-exceptions item)
- **nextjs-add-auth**: better-auth ≥1.6 `freshAge` behavioral note — `freshAge` now measures from `createdAt` not last activity
- **shared-add-ai-security**: AWS Responsible AI Lens section (re:Invent 2025) with all 10 dimensions — complements OWASP LLM Top 10

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
