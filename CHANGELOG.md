# Changelog

All notable changes to templatecentral are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [4.0.0] — 2026-05-26

### Harness Engineering

All 4 scaffold skills now emit a full harness layer into the scaffolded project.

**Compressed AGENTS.md** — replaced verbose 61-line template with a ~70-line indexed format: Commands section, two-table skill routing (project skills first, plugin skills second), file layout, rules, AI harness section. Subagent blind-spot note added (built-in subagents `/explore`/`/plan` have `omitClaudeMd: true` since v2.1.84 — all routing stays in AGENTS.md, not CLAUDE.md).

**CLAUDE.md = `@AGENTS.md`** — one line. Claude Code expands it fully at session start; `@`-import is officially documented. Verbose generated CLAUDE.md removed.

**Skill scoping model** — scaffolded AGENTS.md explicitly documents the priority chain:

| Level | Location | Invoked as |
|-------|----------|------------|
| Personal | `~/.claude/skills/` | `/name` (overrides project) |
| Project | `.claude/skills/` | `/name` |
| Plugin | `<plugin>/skills/` | `plugin:name` (namespaced, no conflict) |

Agents check `.claude/skills/` first for project-specific workflows, then use `templatecentral:*` for framework-level operations.

**Hook split (PostToolUse vs Stop)** — corrected for all 4 stacks:
- PostToolUse: fast type feedback only. TS stacks: `pnpm exec tsc --noEmit --incremental` (2–5s vs 30s). FastAPI: `python -m pyright src/` (pyright is 2-5x faster than mypy; new community standard).
- Stop hook: full test suite (`pnpm test --run` / `pytest`). Blocking quality gate before Claude finishes a task.

**Seeded project skills** — All 4 scaffold skills seed a `*-verify` project skill at scaffold time (next-verify, nest-verify, api-verify, vite-verify). Next.js also seeds `next-migrate`. Each scaffold step prompts the user to create additional project skills for repeated workflows. `templatecentral:migrate` Phase 4 seeds the same skills when upgrading pre-4.0 projects.

**`harness.json`** — `.claude/harness.json` written at scaffold time with SHA-256 origin hashes of all seeded files. `templatecentral:migrate` Phase 5 reads hashes to report UNCHANGED/MODIFIED/MISSING drift per file.

**`templatecentral:migrate` Phase 4 expanded** — when upgrading pre-4.0 projects: seeds CLAUDE.md, project skills, harness.json alongside settings.json. Phase 5 (new): harness health check.

**`templatecentral:audit` Step 3H** — 10 harness engineering invariant checks (expanded from 7): adds Skills Security section check, `allowed-tools` scoping check, and ghost skill names check. Step 6 (new): repo harness health check. Step 5 gains skill-gap suggestion.

**Skills Security guidance** — All 4 scaffold AGENTS.md templates now include a `## Skills Security` section (Snyk ToxicSkills 2026: 13.4% of published agent skills have critical vulnerabilities; 91% of malicious skills contain prompt injection). Guidance: review SKILL.md before installing, scope `allowed-tools:` tightly, avoid skills with unscoped network access.

### Marketplace Readiness

- README version badge updated to 4.0.0; CONTRIBUTING.md scaffold path corrected to `skills/scaffold/<stack>/`
- Added `LICENSE` (MIT), `SECURITY.md`, `CODE_OF_CONDUCT.md`, `EXAMPLES.md`
- `.github/workflows/ai-review.yml` — Claude AI PR review on every non-draft PR
- `plugin.json` — added `displayName`, `homepage`, `repository`, `license`, `$schema` fields
- `marketplace.json` — corrected skill count to "10 registered skills"

### Repository Dog-Fooding

- Repo AGENTS.md: compressed 229 → 65 lines with skill-scoping model, CLAUDE.md blind-spot note
- Repo `CLAUDE.md` = `@AGENTS.md`
- Repo `.claude/settings.json`: PostToolUse runs `lint-skills.sh` after every edit
- Repo `.claude/harness.json`: version manifest
- `.claude/rules/*.md` paths fixed (`skills/<stack>-*/**` → `skills/**`) — rules were never matching the actual skill directory structure; ghost skill names in rules files updated to current `templatecentral:*` names
- `docs/superpowers/` removed — stale planning artifacts from v3.1.0 development (feature already shipped)
- `CONVENTIONS.md` Section 3: documented new frontmatter fields (`when_to_use`, `paths`, `allowed-tools`, `argument-hint`) from Claude Code v2.1.84+
- `write-skill/SKILL.md`: added `when_to_use`, `disable-model-invocation`, `allowed-tools` guidance

### Security & Accuracy Fixes (audit passes, May 2026)

**HIGH — would break generated code**
- Ghost skill names (~80 files): all `shared-*-agent`, `templatecentral:shared-migrate`, `<stack>-scaffold`, `shared-add-*` forms replaced with correct v4 names
- NestJS Fastify filter: `extends BaseExceptionFilter + super.catch()` → `implements ExceptionFilter` (Fastify incompatible)
- Zod v4 form types: `z.infer` → `z.input` for React Hook Form schemas with `.default()` transforms
- `add/auth/nextjs.md`: `@better-auth/drizzle` (nonexistent) → `@better-auth/drizzle-adapter`

**Security**
- ErrorBoundary production leaks (vite-react, nestjs error-handling): `error.message` / component stack guarded with `DEV` checks
- OWASP LLM Top 10 v2.0 added to `add/ai-security`; LLM07 System Prompt Leakage added; Agentic Top 10 2026 entries added
- NIST SP 800-63B references replaced with "OWASP recommendation" across all auth skills (jurisdiction neutrality)

**Accuracy**
- FastAPI pagination: sync SQLAlchemy as primary path (async was the only runnable path shown but scaffold default is sync)
- NestJS `TRUST_PROXY`: numeric string → `parseInt()` guard for Fastify hop-count mode
- FastAPI `model_post_init(self, _)` → `model_post_init(self, __context: Any)` (correct Pydantic v2 signature)
- Various field path, import, and API name fixes across pagination, logging, error-handling skills

### Mutation Testing

New `templatecentral:add` capability: `mutation` — StrykerJS 7.x (TS stacks) and mutmut 3.5.0 (FastAPI). Report-only by default (`thresholds.break: null`); never blocks builds.

### Audit Pass — 2026-05-26

Full audit against 2026-05-25 ecosystem research cache. All 16 lint checks clean. Single finding:
- **C3/C5 fix**: `write-skill/SKILL.md` body trimmed from 31 → 30 lines (removed blank line after frontmatter closing `---`).

All 4 scaffold stacks verified against harness engineering invariants: PostToolUse hooks, Stop hooks, skill scoping, project skill seeding, harness.json, CLAUDE.md one-liner, Skills Security sections. All 10 invariants pass.

### Lint (scripts/lint-skills.sh)

16 checks total (was 10 in v3). New checks added in v4:
- `check_no_ghost_agent_names` — extended to catch `*-code-standards`, `nextjs-add-auth` old names (TIMELESS)
- `check_no_zod_deprecated_message_key` (ECOSYSTEM-ERA)
- `check_no_middleware_ts` with exclusions for meta-documents
- `check_no_mypy_in_postToolUse` — enforces pyright over mypy (ECOSYSTEM-ERA)
- `check_no_postToolUse_full_test_suite` — test suites belong in Stop hooks (TIMELESS)

---

## [3.2.0] — 2026-05-25

### Fixed — Ecosystem accuracy and correctness audit (3-iteration pass)

Full audit of all 50 skill files against the 2026-05-08 ecosystem research cache. 19 HIGH findings fixed in round 1, 8 new HIGHs surfaced and fixed in round 2, 1 residual HIGH fixed in round 3. Lint passes clean throughout.

**FastAPI**
- `add/database/python/beanie.md` — Replaced non-existent `AsyncMongoClient` (was `from pymongo import AsyncMongoClient`) with `AsyncMotorClient` from `motor.motor_asyncio`; added `motor` to requirements; fixed incorrect "Motor is no longer required" note; replaced Beanie 1.x `indexes = ["email"]` string syntax with correct `Annotated[EmailStr, Indexed(unique=True)]` field annotation; fixed `User.find_all()` (doesn't exist) → `User.find().to_list()`; narrowed bare `except Exception` to `except (ValueError, TypeError)` on ObjectId conversion
- `add/auth/fastapi.md` — Added `TRUST_PROXY: int` to `APISettings` and `.env` template; added concrete `.env` example next to rate-limit TRUST_PROXY warning so the fix is actionable
- `add/database/python/sqlalchemy-iam.md` — Fixed broken step numbering (A2 → A5 gap); now uses a consistent A1–A10 sequence
- `add/error-handling/fastapi.md` — Added prominent migration note explaining the response envelope change (default FastAPI `detail` format vs. custom `fieldErrors` envelope) so existing tests aren't silently broken; added note that the standalone `app = FastAPI(...)` example is a reference, not a file replacement
- `add/pagination/fastapi.md` — Corrected all file paths from non-existent `src/lib/` to correct `src/core/`; fixed `from core.database import get_session` → `from database.session import get_db`; added sync/async clarification notes; replaced `from core.exceptions import InvalidInputError` (undefined) with `HTTPException`; fixed `hasMore` → `has_more` with `serialization_alias='hasMore'`; removed conflicting flat `Query()` params — route now uses `Depends(PaginationParams)` consistently; fixed `scalar()` nullable → `scalar() or 0`

**NestJS**
- `add/module/implementation.md` — Added explicit `import { beforeEach, describe, expect, it } from 'vitest'` to Step 9 test template (was missing all vitest globals with `globals: false`)
- `add/test/nestjs.md` — Added vitest imports to all three test templates (Controller, Service, E2E); Service template had `vi` but was missing `describe`/`it`/`expect`/`beforeEach`
- `scaffold/nestjs/source-files.md` — Added `expect` to vitest import in `test/app.e2e-spec.ts` template
- `add/logging/nestjs.md` — Fixed Tier 1 `main.ts` snippet that dropped `FastifyAdapter` entirely (would silently switch app from Fastify to Express); fixed broken `trustProxy: !!process.env.TRUST_PROXY` coercion (now uses canonical two-line pattern that correctly handles `"false"`, `"0"`, and `"*"` values); added `BaseExceptionFilter` import to `HttpExceptionFilter`; fixed stale `See Also` skill aliases

**Next.js**
- `add/error-handling/nextjs.md` — Fixed `await auth()` with no arguments (TypeError) → `await auth.api.getSession({ headers: _request.headers })`
- `add/logging/nextjs.md` — Fixed invalid export syntax `export { GET: _GET as GET }` → `export { _GET as GET }`; fixed verification comment field name mismatch (`query_name` → `name`)
- `add/database/typescript/nextjs-kysely.md` — Added Zod `safeParse` + structured 400 response on POST (was using throwing `.parse()` with no try/catch); changed `selectAll()` → `.select(['id', 'email', 'name'])` in both API route and Server Component examples; changed `.returningAll()` → `.returning(['id', 'email', 'name'])`
- `add/database/typescript/nextjs-mongoose.md` — Added `.select('name email -_id')` to `User.find()` calls in both API route and Server Component examples

**Vite + React / Cross-stack**
- `standards/validation-patterns/patterns.md` — Fixed `z.email().toLowerCase()` crash (`.toLowerCase()` does not exist on `ZodEmail`) → `.transform(v => v.toLowerCase())`; fixed `z.uuid('...')` and `z.url('...')` invalid message-arg form for Zod v4
- `standards/validation-patterns/vite-react.md` — Fixed `z.infer` → `z.input` for form value types (avoids type errors when transforms are present); replaced raw `{...register(...)}` on `<input>` elements with `Form` + `FormField` + `CustomFormField` widget pattern
- `add/pagination/vite-react.md` — Made `usePagination` hook generic over `T` (was typed as `any`); updated `fetchFn` generic to include full `pagination` shape so `nextPage` and `hasMore` work correctly at runtime; added `z.flattenError` on `safeParse` failure

**Repository**
- `AGENTS.md` — Removed `thedotmack/claude-mem` recommendation (its UserPromptSubmit hook blocks user input); updated pnpm minimum from `≥10.33.2` to `≥11` (required for `allowBuilds` object form in `pnpm-workspace.yaml`)
- `.gitignore` — Added `.claude/settings.local.json` (machine-specific, not project config)

---

## [3.1.0] — 2026-05-13

### Added — Next.js Backend Extraction Migration

New skill path under `templatecentral:migrate` for extracting a Next.js BFF into a standalone backend service.

**New files:**
- `skills/migrate/nextjs-backend-extraction.md` — stack router: detects target backend (NestJS / FastAPI) from user intent and cats the appropriate leaf
- `skills/migrate/nextjs-backend-extraction/nestjs.md` — fully self-contained 10-phase NestJS migration guide
- `skills/migrate/nextjs-backend-extraction/fastapi.md` — fully self-contained 10-phase FastAPI migration guide

**What it does (10 phases):**
1. Assessment — scans `src/app/api/` routes and `src/integrations/` import graph; prints a structured report
2. Scope confirmation gate — user confirms before any files change
3. Scaffold sibling backend at `../[project-name]-api`
4. Migrate API routes → NestJS controllers/services/modules or FastAPI routers/services/schemas
5. Migrate integrations (API-route-imported only; frontend-only entries stay in Next.js)
6. Migrate database (NestJS: Drizzle or Mongoose; FastAPI: gated ORM choice — SQLAlchemy or Beanie)
7. Migrate auth (`proxy.ts` stays in Next.js; new backend auth module added)
8. Rewire Next.js as pure frontend (`NEXT_PUBLIC_API_URL`, delete `src/app/api/`)
9. Update CORS config and both `AGENTS.md` files
10. Verify: `pnpm build && pnpm test` both projects (FastAPI: `pytest`)

**Updated:**
- `skills/migrate/SKILL.md` — added backend-extraction routing case; updated description
- `skills/audit/implementation.md` — added 3 new reference files to the audit checklist

---

## [3.0.0] — 2026-05-09

### Breaking — Skill Registry Overhaul (57 → 6 registered skills)

All registered skill names have changed. Any saved invocations using the old names (`templatecentral:fastapi-add-auth`, `templatecentral:nestjs-add-test`, etc.) must be updated to use the new consolidated entry points below.

**New registered skills (6 total):**
| Skill | Replaces |
|---|---|
| `templatecentral:add` | `fastapi-add-auth/database/test/integration`, `nestjs-add-auth/database/module/test/integration`, `nextjs-add-auth/database/api-route/component/page/feature/form/test/integration`, `vite-react-add-auth/component/page/feature/form/test/integration`, `shared-add-auth/database/test/integration/logging/error-handling/pagination/ai-security`, `shared-add-database-python`, `shared-add-database-typescript` |
| `templatecentral:scaffold` | `fastapi-scaffold`, `nestjs-scaffold`, `nextjs-scaffold`, `vite-react-scaffold` |
| `templatecentral:standards` | `fastapi-code-standards`, `nestjs-code-standards`, `nextjs-code-standards`, `vite-react-code-standards`, `shared-code-standards`, `shared-validation-patterns`, `shared-drift-check`, `shared-full-stack-pairing` |
| `templatecentral:migrate` | `shared-migrate`, `shared-migrate-database` |
| `templatecentral:audit` | `shared-audit` |
| `templatecentral:write-skill` | (new) |

**De-registered as agent utilities (not user-invocable):** `build`, `test`, `review`, `cleanup` — agents cat these directly; they no longer appear in the skill listing.

### Changed — Architecture

- **Nested reference file architecture**: All implementation content moved out of registered SKILL.md routers into reference files under `skills/add/<capability>/<stack>.md` and `skills/add/<capability>/<stack>/<variant>.md`. Registered skills detect context and `cat` the right file; they contain no implementation prose.
- **3-level chain** for database (SKILL.md → stack router → ORM variant); **2-level chain** for all other capabilities (SKILL.md → stack file).
- **Progressive context loading**: Only ~6 skill descriptions load at session start (~300 tokens). Full implementation loads only when a skill is invoked.
- **CONVENTIONS.md** added at `skills/CONVENTIONS.md` — single source of truth for all skill authoring rules, nesting depth, description limits, and ref header format.
- **`skills/write-skill/SKILL.md`** added — authoring checklist enforcing conventions at creation time.
- **C1–C6 conventions checks** added to `shared-audit` → `templatecentral:audit`: description ≤150 chars, ref headers, SKILL.md body ≤30 lines, nesting depth ≤3, no duplicate content, jurisdiction neutrality (C6).

### Changed — Audit (`audit/implementation.md` v2.1.0)

- **Universal standards mandate**: All skills must be jurisdiction-neutral, industry-neutral, and free of region/country/ethnicity/gender/race-specific content. Security guidance follows OWASP (Top 10 web, LLM Top 10, Agentic Top 10) as the universal standard. Government-grade rigour (least privilege, defence-in-depth, audit logging, strong authentication) applied generically without naming any specific regulation.
- **Training cutoff**: Step 0 now states "August 2025" explicitly; all ecosystem state treated as potentially stale until confirmed by web search.
- **C6 — Jurisdiction neutrality check**: grep pattern added to catch known jurisdiction-specific framework names in skill files.
- **Step 4b**: minor fixes (single file, ≤10 lines) → fix directly, no plan required; large-scope → confirm first.
- **Step 4f**: changelog gate — verify `git status` is clean before writing the CHANGELOG entry.
- **Token efficiency**: expanded from one checkbox to five concrete sub-checks (line count, redundant comments, over-scaffolded examples, duplicate instructions, redundant prose).

### Fixed

- `add/database/python.md`, `add/database/typescript.md`: removed jurisdiction-specific compliance framework names (HIPAA, PCI) from database detection signal examples; replaced with generic high-security signal language (`regulated`, `iam`, `no-password`, `audit-logging`).
- `scripts/lint-skills.sh`: updated all `shared-audit` exclusion patterns to `audit/implementation` following path rename; added `audit/implementation.md` exclusion to jurisdiction check.

### Removed

- 31 retired skill directories (all replaced by reference files under the new nested structure).
- All completed planning and spec documents under `docs/superpowers/plans/` and `docs/superpowers/specs/` — superseded by current architecture.

---

## [2.13.1] — 2026-05-08

### Security
- `nestjs-add-auth`: `JwtStrategy` constructor now includes `algorithms: ['HS256']` — prevents algorithm confusion attacks where `passport-jwt` could accept unexpected signing algorithms
- `nextjs-add-auth`: `request.ip` in Upstash rate-limiting example now has a `TRUST_PROXY` note — without it, all clients share the reverse-proxy IP as the rate-limit key, making per-client limiting ineffective; one-hop (`TRUST_PROXY=true`) and two-hop (`TRUST_PROXY=2`) topologies documented

### Fixed
- **NestJS stack — Vitest migration (completing 2.2.0)**: `.claude/rules/nestjs.md`, `nestjs-add-module`, `nestjs-code-standards` updated "Jest" → "Vitest"; `nestjs-add-test` migrated `jest.fn()` → `vi.fn()`, `jest.spyOn()` → `vi.spyOn()` with `import { vi } from 'vitest'`; `jest-e2e.json` reference replaced with `vitest.config.e2e.ts`
- `nestjs-add-auth`: `ttl: 900_000` → `ttl: minutes(15)` using `@nestjs/throttler` `minutes()` helper — semantically equivalent, more readable
- `nestjs-scaffold`: `...globals.jest` removed from ESLint config template — project uses Vitest with `globals: false`; the Jest spread was unused and misleading; `@nestjs/platform-fastify` floor note moved to `.claude/rules/nestjs.md` per SSOT policy
- `vite-react-scaffold`: `Strict-Transport-Security` header added to nginx.conf — security header parity with NestJS and Next.js scaffolds
- `nestjs-add-database`, `nextjs-add-database`: Drizzle v1 "release-candidate" caveat removed — v1.0 is stable (released mid-2025)
- `shared-add-ai-security`: OWASP Top 10 for Agentic Applications (2026) reference added for Capability C systems; `z.array(z.string().url())` → `z.array(z.url())` (Zod v4 top-level form)
- `shared-add-error-handling`, `shared-add-logging`, `shared-validation-patterns`: `error.flatten()` → `z.flattenError(error)` throughout; `z.string().datetime()` → `z.iso.datetime()`; `import { z }` added where missing; password min-length updated to 12 in `shared-validation-patterns`

### Added
- `scripts/lint-skills.sh`: new mechanical lint script — 10 checks (timeless: CVE identifiers, jurisdiction-specific content, hardcoded secrets; ecosystem-era: version pins, bcrypt references, deprecated Zod `.flatten()`, `middleware.ts`, HTTP/1.0 cache headers, Jest APIs in Vitest projects, `globals.jest` in ESLint templates, timing-unsafe stored-secret comparisons, deprecated Zod v4 string-format methods)
- `skills/shared-audit/SKILL.md`: new structured audit skill — 5-step workflow (ecosystem research cache → mechanical lint → per-file semantic review → fix loop → infrastructure update); covers all 49 skills across 5 stacks
- `.github/workflows/validate-skills.yml`: `lint-patterns` job calling `bash scripts/lint-skills.sh skills/`; `scripts/**` added to path triggers
- `.claude/audit-ecosystem-research.md`: ecosystem research cache file (30-day TTL) — prevents redundant web scans on consecutive audit runs

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
