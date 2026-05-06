# templateCentral Round 2 Audit — Design Spec

**Date:** 2026-05-06
**Scope:** Full templateCentral project (48 skills) — breaking changes first, then IM8/security gaps
**Approach:** Option B — parallel agents grouped by concern

---

## Background

Round 1 addressed IM8 security headers, NestJS Jest→Vitest migration, pino logging, AI security skill, and CI hardening. This round addresses breaking changes introduced by ecosystem updates since August 2025 and remaining IM8 compliance gaps.

---

## Group 1: Vite 8 + React Router v7.15 Breaking Changes

**Agent scope:** All `vite-react-*` skills

### Changes

**1. `build.rolldownOptions` rename**
- File: `skills/vite-react-scaffold/SKILL.md`
- Change: `build.rollupOptions` → `build.rolldownOptions` in vite.config.ts verbatim block
- Reason: Vite 8 replaced Rollup with Rolldown as the production bundler; the old key is silently ignored

**2. `@vitejs/plugin-react` v6 version pin**
- File: `skills/vite-react-scaffold/SKILL.md`
- Change: Pin to `@vitejs/plugin-react@^6.0.0` in package.json verbatim block
- Reason: v6 ships Oxc-based transforms replacing Babel; the baseline scaffold config needs no option changes (no custom transforms), only the version bump

**3. React Router v7.15 stable API — remove `unstable_` prefixes**
- Files: `skills/vite-react-scaffold/SKILL.md`, `skills/vite-react-add-auth/SKILL.md`, `skills/vite-react-code-standards/SKILL.md`
- Change: Remove `unstable_` prefix from any `unstable_useViewTransitionState`, `unstable_flushSync`, `unstable_dataStrategy`, or similar exports used in verbatim blocks
- Reason: React Router v7.15.0 promoted all `unstable_*` APIs to stable

**4. `json()` helper deprecation**
- Files: `skills/vite-react-scaffold/SKILL.md`, `skills/vite-react-add-auth/SKILL.md`
- Change: Replace `import { json } from 'react-router-dom'` + `return json(data)` with `return Response.json(data)` (Web standard) or `return data(payload)` (typed loader pattern)
- Reason: `json()` is deprecated in React Router v7.x in favour of the Web Platform Response API

---

## Group 2: FastAPI 0.132+ Content-Type Enforcement

**Agent scope:** `fastapi-add-test`, `fastapi-add-endpoint`

### Changes

**1. Test client JSON body requests**
- File: `skills/fastapi-add-test/SKILL.md`
- Change: All `client.post(url, data=json.dumps(payload))` patterns → `client.post(url, json=payload)`; ensure no verbatim block uses raw `-d` body without the `json=` kwarg
- Reason: FastAPI 0.132+ enforces `Content-Type: application/json` for JSON endpoints; `TestClient` with `json=payload` sets this automatically; `data=` does not

**2. `curl` examples and endpoint snippets**
- File: `skills/fastapi-add-endpoint/SKILL.md`
- Change: All `curl -d '{...}'` examples → `curl -H "Content-Type: application/json" -d '{...}'`
- Reason: Same enforcement — without the header, the request returns 422

---

## Group 3: IM8 / Security Gaps

**Agent scope:** `nextjs-add-auth`, `shared-add-logging`, `AGENTS.md`, all four scaffold skills

### Changes

**1. IM8 AS-6 — hashing algorithm preference**
- File: `skills/nextjs-add-auth/SKILL.md`
- Change: Add one-line note alongside the bcrypt usage: "bcrypt is acceptable; Argon2id (`argon2` package) is preferred for new projects per IM8 AS-6 and OWASP"
- Reason: IM8 AS-6 and current OWASP guidance rank Argon2id > scrypt > PBKDF2 > bcrypt

**2. IM8 LM-1 — log isolation**
- File: `skills/shared-add-logging/SKILL.md`
- Change: Add one sentence under the Production section: "Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch) — writing to local disk only fails IM8 LM-1"
- Reason: IM8 LM-1 requires logs to be stored in a system isolated from the application host

**3. IM8 AS-12 — file upload malware scanning**
- File: `AGENTS.md` (templateCentral root), Security & secrets section
- Change: Add one sentence: "If adding file uploads, scan with ClamAV or a cloud scanning service (e.g. AWS GuardDuty Malware Protection) before writing to storage — IM8 AS-12 requirement"
- Reason: No existing skill covers file upload security; this ensures the note surfaces when users read the root AGENTS.md

**4. IM8 AS-8 — secrets vault in production**
- Files: `skills/nextjs-scaffold/SKILL.md`, `skills/fastapi-scaffold/SKILL.md`, `skills/nestjs-scaffold/SKILL.md`, `skills/vite-react-scaffold/SKILL.md` — specifically the generated project `AGENTS.md` template block in each
- Change: Add one paragraph to the Security section of each generated `AGENTS.md` template: "In production, read secrets from AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager — not from flat `.env` files. Flat env files are for local development only."
- Reason: IM8 AS-8 requires secrets management via a vault; this ensures every scaffolded project carries the governance note without forcing a provider choice

---

## Execution Plan

Three parallel agents:
1. **Vite agent** — Group 1 changes (vite-react-scaffold, vite-react-add-auth, vite-react-code-standards)
2. **FastAPI agent** — Group 2 changes (fastapi-add-test, fastapi-add-endpoint)
3. **IM8 agent** — Group 3 changes (nextjs-add-auth, shared-add-logging, AGENTS.md, four scaffold AGENTS.md templates)

All agents run in isolation worktrees, merge to main on completion.

---

## Success Criteria

- `vite-react-scaffold` vite.config.ts uses `build.rolldownOptions` and `@vitejs/plugin-react@^6.0.0`
- No `unstable_` prefixed React Router imports in any vite-react verbatim block
- No `json()` from react-router-dom in any vite-react verbatim block
- All FastAPI test snippets use `json=payload` not `data=json.dumps(payload)`
- All FastAPI curl examples include `-H "Content-Type: application/json"`
- `nextjs-add-auth` documents Argon2id preference
- `shared-add-logging` documents log isolation requirement
- `AGENTS.md` root documents file upload malware scanning
- All four scaffold skills' generated AGENTS.md templates include secrets vault note
