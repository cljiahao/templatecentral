<!-- ref: audit/implementation.md
     loaded-by: audit/SKILL.md
     prereq: Project identified. Do not invoke this file directly — it is loaded at runtime by the /tc-audit skill. -->
## Mindset — fresh eyes

Approach every file as if you have never seen this project before. Do not carry assumptions from previous audit sessions or conversations. The goal is to find what is wrong, not confirm what already passed.

**Universal standards — no exceptions**: All skills must be jurisdiction-neutral, industry-neutral, and free of region-, country-, ethnicity-, gender-, and race-specific content. Security guidance follows **OWASP** (Top 10 web, LLM Top 10, Agentic Top 10) as the universal standard. Apply government-grade security rigour — principle of least privilege, defence-in-depth, audit logging, strong authentication — without referencing any specific government, country, or compliance regulation by name. When in doubt, ask: "Would this guidance apply equally in any country, to any developer, on any project?"

Priority order:
1. **Accuracy** — is this correct for the current ecosystem as of today?
2. **Security** — are there vulnerabilities, insecure defaults, or missing controls? Evaluate against OWASP; apply government-grade rigour generically.
3. **Quality** — SRP, SoC, DRY, YAGNI, token reduction, readability
4. **AIDLC/SDLC alignment** — does the skill guide users toward safe, maintainable development lifecycle practices?

---

## Step 0 — Ecosystem research

**CRITICAL — model knowledge cutoff**: The AI assistant running this audit has a training cutoff of **August 2025**. Today's date may be a year or more beyond that. Treat all ecosystem state — framework versions, library APIs, security advisories, OWASP rankings — as potentially stale until confirmed by a web search. You MUST NOT rely on training data alone for ecosystem state; always follow the cache protocol below.

### 0a — Check the research cache

Read `.claude/audit-ecosystem-research.md` at the project root.

**If the file does not exist, or the `last-scanned` date is more than 30 days before today:**

→ Proceed to **0b** (run full web scan). Do not skip this even if you believe your training data is recent enough — the cache is the authoritative source.

**If the file exists and `last-scanned` is within the last 30 days:**

→ Load the cached findings. Print:
```
Using cached ecosystem research from <last-scanned date>. Skipping web scan.
```
→ Skip to **0c** (apply findings).

---

### 0b — Run full web scan (only when cache is missing or stale)

Use WebSearch and/or WebFetch to check for changes **since the date in the cache** (or the last 12 months if no cache exists). For each item below, record the current stable version, any breaking changes, deprecations, new APIs, or security advisories.

**Frameworks and runtimes**
- Next.js — major/minor releases, App Router changes, deprecated APIs, proxy/middleware changes
- NestJS + `@nestjs/platform-fastify` — major/minor releases, Fastify adapter changes
- FastAPI + Starlette — major/minor releases, breaking Pydantic v2 changes, async patterns
- pnpm — config file changes, workspace.yaml behavior, `allowBuilds` / `blockExoticSubdeps` behavior

**Libraries**
- Zod — API changes, new methods, deprecations
- better-auth — breaking changes, new session/OIDC behavior
- Drizzle ORM — release status, API changes, migration tooling
- argon2 / argon2-cffi — parameter recommendation changes
- `@nestjs/throttler` — API changes, helper function changes
- slowapi — rate limiting behavior, proxy-aware configuration
- TanStack Query — v5/v6 status, API changes, deprecated hooks (`isLoading`, `onSuccess`/`onError` on useQuery)
- Vite + `@vitejs/plugin-react` — major version, bundler changes (Rolldown/Oxc), Babel removal status

**Security standards**
- OWASP Top 10 (web) — new ranking or new category
- OWASP LLM Top 10 — version update
- OWASP Top 10 for Agentic Applications — new guidance
- NIST SP 800-63B — any updated authenticator assurance guidance
- AWS Responsible AI Lens — new dimensions or updated guidance

**Claude Code harness engineering**
Check for changes to: hook events (confirmed count), hook handler types (command/http/mcp_tool/prompt/agent), new hook options (asyncRewake, async, args[]), skill scoping priority order, Stop hook block-cap behavior, PreCompact/PostCompact capabilities, new settings.json fields (worktree, sandbox, skillListingBudgetFraction, etc.), AGENTS.md open standard (AAIF) status.

**Claude Code harness engineering — community consensus & team recommendations**
Beyond the official changelog, scan for emerging harness-engineering practice and grade each finding by source strength:

- Official team guidance: Anthropic engineering blog, Claude Code docs and release notes — hook patterns, skill design, context management, settings best practices
- Community practice: `claude-code` GitHub issues/discussions with high engagement, and reputable practitioner write-ups on hooks, skill scoping, AGENTS.md structure, and compaction recovery

Grade every finding before recording it:

| Grade | Bar | Audit action |
|-------|-----|--------------|
| `RECOMMENDED` | explicit Anthropic team guidance | becomes a targeted Step 3H check this run |
| `CONSENSUS` | ≥3 independent credible sources agree | becomes a targeted Step 3H check this run |
| `EMERGING` | single credible source | record and track; do NOT act on it yet |

Also record anti-patterns the community has converged on avoiding. A `RECOMMENDED` or `CONSENSUS` pattern missing from the scaffolds' harness templates is a Step 3H finding; an `EMERGING` one is noted in the report only.

**Loop engineering — community/team practice**
- Loop engineering — current community/team practice on agent loop design (goals, termination, budgets, scheduled self-prompting); grade per the table above

**Reference: AWS AIDLC**
Check the AWS AI Development Lifecycle (AIDLC) guidance for any new controls or patterns relevant to AI-assisted development workflows — particularly around prompt injection, model output validation, and agent trust boundaries.

**After completing all searches**, write the results to `.claude/audit-ecosystem-research.md` in this exact format:

```markdown
---
last-scanned: YYYY-MM-DD
expires-after-days: 30
---

# Ecosystem Research Cache

> Auto-generated by /tc-audit Step 0. Edit only to correct errors; the next full scan overwrites this file.

## Scan date: YYYY-MM-DD

## Frameworks and runtimes

### Next.js
<current stable version and findings>

### NestJS + @nestjs/platform-fastify
<current stable version and findings>

### FastAPI + Starlette
<current stable version and findings>

### pnpm
<current stable version and findings>

## Libraries

### Zod
<current stable version and findings>

### better-auth
<current stable version and findings>

### Drizzle ORM
<current stable version and findings>

### argon2 / argon2-cffi
<current stable version and findings>

### @nestjs/throttler
<current stable version and findings>

### slowapi
<current stable version and findings>

### TanStack Query
<current stable version and findings>

### Vite + @vitejs/plugin-react
<current stable version and findings>

## Security standards

### OWASP Top 10 (web)
<current version and findings>

### OWASP LLM Top 10
<current version and findings>

### OWASP Top 10 for Agentic Applications
<current version and findings>

### NIST SP 800-63B
<current version and findings>

### AWS Responsible AI Lens
<current version and findings>

### AWS AIDLC
<current version and findings>

## Claude Code Harness Engineering
<hook events, hook types, new options, skill scoping, Stop cap, settings.json fields — current as of scan date>

### Community consensus & team recommendations
<graded findings: RECOMMENDED (official team guidance) / CONSENSUS (≥3 independent sources) / EMERGING (single credible source — track only), each with sources; plus community-converged anti-patterns>
```

---

### 0c — Apply findings

From the cache (whether freshly written or previously cached), extract all findings. Record them as a numbered list before proceeding to Step 1. Any finding here becomes a targeted check in Step 2.

---

## Step 1 — Mechanical checks (run the lint script)

```bash
bash scripts/lint-skills.sh skills/
```

Any failures here must be fixed before proceeding to semantic review. The lint script is the single source of truth for greppable anti-patterns. If it passes, record "Mechanical: PASS" and continue.

---

## Conventions Compliance

> **Lint-enforced as of v4.7.0 — no separate pass needed.**
>
> Conventions checks C1–C6 are now fully covered by `scripts/lint-skills.sh`:
> - **C1** (description ≤ 150 chars) → `check_skillmd_description_length`
> - **C2** (ref file headers) → `check_ref_file_headers`
> - **C3** (no duplicate content) / **C5** (SKILL.md body ≤ 30 lines) → `check_skillmd_body_length`
> - **C4** (nesting depth ≤ 3) → `check_nesting_depth`
> - **C6** (jurisdiction neutrality) → `check_no_jurisdiction_specific`
>
> Run Step 1 (`bash scripts/lint-skills.sh skills/`). If lint passes, conventions compliance passes. No separate C1–C6 pass is needed.

---

## Step 2 — Semantic review

Read each file below **in full** and apply the checklist beneath it. Do not skim. Mark each file as CLEAN or list specific issues with the line reference.

### Checklist applied to every SKILL.md

Apply these questions to every file. If the check is not applicable to that skill (e.g. no password hashing in a UI skill), mark it N/A.

**Accuracy** ← primary
- [ ] Are all API calls, imports, and CLI commands current for the stack version in `.claude/rules/*.md`?
- [ ] Does anything in this file conflict with the ecosystem research findings from Step 0?
- [ ] Does the skill reference a library method, flag, config key, or CLI option that no longer exists or has changed?
- [ ] Are any patterns shown as "current" actually deprecated or superseded?

**Security** ← primary
- [ ] Is all user input validated at the boundary (Zod / Pydantic) before use?
- [ ] Are passwords hashed with argon2id — not bcrypt, not SHA, not MD5?
- [ ] Are JWTs verified with an explicit algorithm whitelist?
- [ ] Is rate limiting mentioned where the skill adds an authentication endpoint?
- [ ] If the code reads `request.ip` or `X-Forwarded-For`, is `TRUST_PROXY` documented for both one-hop (ALB → App) and two-hop (ALB → Traefik → App) topologies?
- [ ] Are error responses free of stack traces, internal paths, or DB query text?
- [ ] Are security headers complete for scaffold skills (HSTS, CSP, X-Frame-Options, Referrer-Policy, Permissions-Policy, X-XSS-Protection)?
- [ ] Is the content jurisdiction- and industry-neutral — no country-specific regulations, government schemes, or compliance frameworks?
- [ ] Are version numbers absent from the skill body (SSOT: versions belong in `.claude/rules/*.md` only)?
- [ ] Is there any CVE identifier present? Replace with "security advisory" language.

**Code quality** ← secondary
- [ ] **SRP** — does the skill do one thing? Are mixed concerns present (e.g. a scaffold skill that also teaches auth patterns)?
- [ ] **SoC** — are layers cleanly separated in code examples (routing vs business logic, validation vs persistence)?
- [ ] **DRY** — is the same guidance or code block repeated across sections without need?
- [ ] **YAGNI** — is there guidance for features that users of this skill will never need from this entry point?
- [ ] **Token efficiency** — targeted checks:
  - Any reference file exceeding 200 lines? Flag for splitting.
  - Inline comments that restate what the surrounding code clearly shows? Delete them.
  - Code examples demonstrating > 3 files where 1–2 would suffice? Trim.
  - The same instruction stated in two different forms within 15 lines? Collapse to one.
  - Introductory prose before a code block that already has self-explanatory comments? Delete the prose.

**AIDLC / SDLC alignment** ← secondary
- [ ] Does the skill guide users toward testable, reviewable outputs (not just "run this command")?
- [ ] Are generated files structured for auditability — clear naming, separation of secrets from config, no magic globals?
- [ ] For AI-adjacent skills (`add/ai-security/`): does guidance align with current AWS AIDLC and OWASP Agentic guidance on prompt boundaries, output validation, and agent trust?

---

### FastAPI stack

Read each file in full, apply checklist above:

- [ ] `skills/scaffold/fastapi/config-files.md`
- [ ] `skills/scaffold/fastapi/source-files.md`
- [ ] `skills/add/auth/fastapi.md`
- [ ] `skills/add/database/python.md` ← stack router
- [ ] `skills/add/database/python/sqlalchemy.md`
- [ ] `skills/add/database/python/sqlalchemy-iam.md`
- [ ] `skills/add/database/python/beanie.md`
- [ ] `skills/add/endpoint/fastapi.md`
- [ ] `skills/add/integration/fastapi.md`
- [ ] `skills/add/test/fastapi.md`
- [ ] `skills/add/error-handling/fastapi.md`
- [ ] `skills/add/logging/fastapi.md`
- [ ] `skills/add/pagination/fastapi.md`
- [ ] `skills/add/mutation-testing/python.md`
- [ ] `skills/migrate/database/fastapi.md`
- [ ] `skills/standards/code-standards/fastapi.md`
- [ ] `skills/standards/validation-patterns/fastapi.md`

**FastAPI-specific additional checks** (apply to the above):
- [ ] `SecurityHeadersMiddleware` includes HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, and X-XSS-Protection
- [ ] `TRUST_PROXY` env var gates `ProxyHeadersMiddleware` and `ForwardedHostMiddleware`
- [ ] `slowapi` rate limiter is mentioned for auth endpoints with a `TRUST_PROXY` note
- [ ] Pydantic v2 syntax used (not v1 `validator`, `__fields__`, etc.)
- [ ] Async route handlers preferred (`async def`) over sync (`def`) for I/O-bound operations
- [ ] Starlette ≥1.0.1 in `requirements.txt` — a published security advisory (GHSA-86qp-5c8j-p5mr, BadHost: malformed Host header auth-bypass) was patched in 1.0.1; current stable is 1.2.1. Prefer endpoint-level `Depends()`/`Security()` over middleware path-matching for auth-critical routes.

---

### NestJS stack

Read each file in full, apply checklist above:

- [ ] `skills/scaffold/nestjs/config-files.md`
- [ ] `skills/scaffold/nestjs/source-files.md`
- [ ] `skills/add/auth/nestjs.md`
- [ ] `skills/add/database/typescript.md` ← stack router (NestJS + Next.js)
- [ ] `skills/add/database/typescript/nestjs-drizzle.md`
- [ ] `skills/add/database/typescript/nestjs-kysely.md`
- [ ] `skills/add/database/typescript/nestjs-mongoose.md`
- [ ] `skills/add/endpoint/nestjs.md`
- [ ] `skills/add/integration/nestjs.md`
- [ ] `skills/add/test/nestjs.md`
- [ ] `skills/add/error-handling/nestjs.md`
- [ ] `skills/add/logging/nestjs.md`
- [ ] `skills/add/pagination/nestjs.md`
- [ ] `skills/add/mutation-testing/typescript.md`
- [ ] `skills/migrate/database/nestjs.md`
- [ ] `skills/standards/code-standards/nestjs.md`
- [ ] `skills/standards/validation-patterns/nestjs.md`

**NestJS-specific additional checks**:
- [ ] Fastify adapter used — no Express-specific APIs (`req.body` without Fastify types, `res.send`, etc.)
- [ ] Helmet config includes `referrerPolicy: { policy: 'strict-origin-when-cross-origin' }`
- [ ] `onSend` hook sets `Permissions-Policy` and `Cache-Control`; no `Pragma` or `Expires` headers
- [ ] `TRUST_PROXY` env var wires into `FastifyAdapter({ trustProxy })`
- [ ] `ThrottlerModule` uses `minutes()` helper (not raw ms) for readability
- [ ] `@nestjs/throttler` rate limiting note references `TRUST_PROXY` requirement
- [ ] `nestjs-zod` used for DTOs — not `class-validator` / `class-transformer`
- [ ] `allowBuilds` in `pnpm-workspace.yaml` (not `.npmrc` or `package.json#pnpm`)
- [ ] `JwtStrategy` constructor includes `algorithms: ['HS256']` — prevents algorithm confusion attacks
- [ ] Test code examples use `vi.fn()` / `vi.spyOn()` (Vitest) — not `jest.fn()` / `jest.spyOn()` (Jest)
- [ ] ESLint config template uses only `globals.node` — `globals.jest` must not appear (project uses Vitest with `globals: false`)
- [ ] `@nestjs/platform-fastify ≥11.1.19` — a published security advisory (Fastify URL-encoding middleware bypass) is fixed in ≥11.1.14; Fastify v5 requires ≥11.1.19. Flag any project pinned below `^11.1.19` that may resolve to a vulnerable version.

---

### Next.js stack

Read each file in full, apply checklist above:

- [ ] `skills/scaffold/nextjs/config-files.md`
- [ ] `skills/scaffold/nextjs/source-files.md`
- [ ] `skills/add/auth/nextjs.md`
- [ ] `skills/add/database/typescript/nextjs-drizzle.md`
- [ ] `skills/add/database/typescript/nextjs-kysely.md`
- [ ] `skills/add/database/typescript/nextjs-mongoose.md`
- [ ] `skills/add/endpoint/nextjs.md`
- [ ] `skills/add/feature/nextjs.md`
- [ ] `skills/add/form/nextjs.md`
- [ ] `skills/add/integration/nextjs.md`
- [ ] `skills/add/page/nextjs.md`
- [ ] `skills/add/test/nextjs.md`
- [ ] `skills/add/error-handling/nextjs.md`
- [ ] `skills/add/logging/nextjs.md`
- [ ] `skills/add/pagination/nextjs.md`
- [ ] `skills/add/mutation-testing/typescript.md`
- [ ] `skills/migrate/database/nextjs.md`
- [ ] `skills/standards/code-standards/nextjs.md`
- [ ] `skills/standards/validation-patterns/nextjs.md`

**Next.js-specific additional checks**:
- [ ] `proxy.ts` used for auth proxy — not `middleware.ts` (deprecated in Next.js 16)
- [ ] Route Handlers use `async` APIs for `cookies()`, `headers()`, `params`, `searchParams`
- [ ] `next.config.ts` security headers include HSTS, CSP, X-Frame-Options, Referrer-Policy, Permissions-Policy, X-XSS-Protection
- [ ] `TRUST_PROXY` env var gates `getAppOrigin()` utility (`X-Forwarded-Proto` / `X-Forwarded-Host`)
- [ ] `better-auth` session config documented — `expiresIn`, `updateAge`, `cookieCache`
- [ ] `allowBuilds` in `pnpm-workspace.yaml` (not `.npmrc` or `package.json#pnpm`)
- [ ] `z.flattenError()` used — not deprecated `.flatten()`

---

### Vite + React stack

Read each file in full, apply checklist above:

- [ ] `skills/scaffold/vite-react/config-files.md`
- [ ] `skills/scaffold/vite-react/source-files.md`
- [ ] `skills/add/auth/vite-react.md`
- [ ] `skills/add/feature/vite-react.md`
- [ ] `skills/add/form/vite-react.md`
- [ ] `skills/add/integration/vite-react.md`
- [ ] `skills/add/page/vite-react.md`
- [ ] `skills/add/test/vite-react.md`
- [ ] `skills/add/error-handling/vite-react.md`
- [ ] `skills/add/logging/vite-react.md`
- [ ] `skills/add/pagination/vite-react.md`
- [ ] `skills/add/mutation-testing/typescript.md`
- [ ] `skills/standards/code-standards/vite-react.md`
- [ ] `skills/standards/validation-patterns/vite-react.md`

**Vite-specific additional checks**:
- [ ] `pnpm-workspace.yaml` includes `blockExoticSubdeps: true` and `allowBuilds`
- [ ] Dockerfile `COPY` includes `pnpm-workspace.yaml*`
- [ ] `@vitejs/plugin-react` v6 Oxc-based — no `@babel/core` required
- [ ] `z.flattenError()` used — not deprecated `.flatten()`
- [ ] nginx.conf.template includes `Content-Security-Policy` with at least `frame-ancestors 'none'` baseline
- [ ] nginx.conf.template uses `X-Frame-Options "DENY"` (not `SAMEORIGIN`)

---

### Cross-stack and utility skills

Read each file in full, apply checklist above:

- [ ] `skills/add/ai-security/implementation.md`
- [ ] `skills/add/documentation/implementation.md` ← README backfill / enforcement-check capability
- [ ] `skills/standards/code-standards/comments.md` ← shared comment doctrine (loaded first by code-standards)
- [ ] `skills/standards/validation-patterns/patterns.md`
- [ ] `skills/standards/drift-check/implementation.md`
- [ ] `skills/standards/full-stack-pairing/implementation.md`
- [ ] `skills/scaffold/shared/harness-kit.md`
- [ ] `skills/scaffold/shared/documentation-kit.md` ← per-folder README/`.order` generation SSOT
- [ ] `skills/migrate/general/implementation.md`
- [ ] `skills/migrate/nextjs-backend-extraction.md`
- [ ] `skills/migrate/nextjs-backend-extraction/nestjs.md`
- [ ] `skills/migrate/nextjs-backend-extraction/fastapi.md`
- [ ] `skills/build/implementation.md`
- [ ] `skills/test/implementation.md`
- [ ] `skills/review/review/implementation.md`
- [ ] `skills/review/update/implementation.md`
- [ ] `skills/cleanup/remove-example/implementation.md`
- [ ] `skills/cleanup/task-management/implementation.md`
- [ ] `.claude/skills/write-skill/SKILL.md` ← authoring checklist; check it still matches CONVENTIONS.md
- [ ] `.claude/skills/write-skill/implementation.md`
- [ ] `.claude/skills/audit/implementation.md` ← this file; check it is still accurate

**Cross-stack additional checks**:
- [ ] `add/ai-security/implementation.md`: all LLM01–LLM10 sections present (lint now enforces this); OWASP LLM Top 10 version still current; Tier C references OWASP Agentic Top 10
- [ ] `add/logging/*`: no PII, passwords, tokens, or SQL text in log field examples
- [ ] `add/error-handling/*`: error responses contain no stack traces or internal paths; `z.flattenError()` used
- [ ] `standards/validation-patterns/*`: `z.flattenError()` used; password min-length ≥12
- [ ] `standards/drift-check/implementation.md`: `pnpm audit` and `pip-audit` commands still current

---

## Step 3 — Cross-cutting checks

After reading all files, answer these questions from memory (no additional reads needed):

- [ ] **Stack version alignment**: Do the skill bodies align with the versions in `.claude/rules/fastapi.md`, `nestjs.md`, `nextjs.md`, `vite-react.md`? Any skill referencing a feature only available in a newer version than the rules specify?
- [ ] **TRUST_PROXY completeness**: All three API stacks (FastAPI, NestJS, Next.js) document `TRUST_PROXY` for both the one-hop (ALB → App) and two-hop (ALB → Traefik → App) topologies?
- [ ] **Security header parity**: Do all three API scaffolds set the same set of security headers? If one has a header the others don't, flag it.
- [ ] **Ecosystem currency**: Is there anything in the skills that was best practice in 2024 but has since been superseded? (Consider: new OWASP guidance, framework major releases, deprecated packages.)

### Harness engineering checks (Step 3H)

- [ ] **PostToolUse hook command**: TS stacks use `pnpm exec tsc --noEmit --incremental 2>&1 | tail -5` (not plain `--noEmit`, not `pnpm test`); FastAPI uses `python -m pyright src/ 2>&1 | tail -5` (not mypy). PostToolUse is feedback-only; hooks exit 0 even on errors so output flows to Claude as context.
- [ ] **Stop hook exits 2 on failure**: The Stop hook must run tests, capture exit code, write output to **stderr** (not stdout), and `exit 2` if tests fail so Claude receives test results and is forced to fix. Pattern: `OUTPUT=$(cmd 2>&1); EC=$?; echo "$OUTPUT" | tail -20 >&2; [ $EC -ne 0 ] && exit 2 || exit 0`. Do NOT pipe through `tail` without capturing exit code (piping exits 0 regardless).
- [ ] **PreToolUse `.env` protection**: Scaffold settings.json includes a `PreToolUse` hook that blocks edits to `.env*` files (exit 2) while allowing `.env.example`. Must read `tool_input.file_path` from stdin JSON (not top-level `file_path`). Matcher is `Edit|Write` (no `MultiEdit` tool exists). FastAPI uses `python3`, TS stacks use `node`.
- [ ] **UserPromptSubmit hook present** (OWASP LLM01): Scaffold settings.json includes a `UserPromptSubmit` hook that pattern-checks incoming prompts for obvious injection phrases (`ignore previous instructions`, `you are now a`, etc.) using args[] exec form; exit 2 blocks the prompt and writes reason to stderr. FastAPI uses `python3`, TS stacks use `node`. Deny list is intentionally minimal — users extend for their domain.
- [ ] **SessionStart hook present (post-compaction recovery)**: Scaffold settings.json includes a `SessionStart` hook (matcher `startup|resume|compact`) running `session-context.sh`, which re-injects AGENTS.md routing context + universal invariants via plain stdout. This is the correct mechanism: `PostCompact` is observability-only (its exit code/stdout is ignored — it CANNOT inject context), so it is not used for re-injection.
- [ ] **Skill scoping priority correct**: Official order per current docs is `Managed/Enterprise > CLI flag > User > Project > Plugin` — when names collide, enterprise overrides personal and personal (`~/.claude/skills/`) overrides project (`.claude/skills/`). Plugin skills are namespaced and never conflict. Scaffold AGENTS.md template instructs agents to check `.claude/skills/` first for project workflows, then `templatecentral:*` for framework-level operations (routing guidance — unaffected by collision priority). Note: this `User > Project` order is for **skills**; **subagent** precedence is the inverse (`Project > User`), so do not state a single unified order across both.
- [ ] **Seeded project skills are directories**: A skill is a directory with `SKILL.md` as the entrypoint (`.claude/skills/<name>/SKILL.md`). Flat `.claude/skills/<name>.md` files are NOT discovered (flat files work only under `.claude/commands/`). Every scaffold/migrate step that seeds a project skill must create the directory form.
- [ ] **Hook types documented**: Five hook handler types exist — `command`, `http`, `mcp_tool` (v2.1.117), `prompt`, `agent` (experimental). Scaffold uses `command` type. Any skill recommending hook setup should reference the correct type field.
- [ ] **Stop hook loop termination**: There is **no official numeric block cap** (the earlier "cap of 8" assumption is unconfirmed in current docs — a runaway Stop hook can loop until the session limit). The only loop guard is `stop_hook_active` (see next bullet) — seeded stop-checks scripts MUST exit 0 when it is true so a failing-test loop terminates on the first re-entry.
- [ ] **Stop hook loop guard**: every seeded stop-checks script exits 0 when `stop_hook_active` is true in stdin JSON before running tests. Per the hooks docs, a Stop hook that exits 2 re-runs Claude; without the guard the hook can loop. TS stacks parse stdin with `node -e`, FastAPI with `python3 -c`. The guard runs FIRST — before any test command.
- [ ] **Compaction recovery via SessionStart, not Pre/PostCompact**: Neither PreCompact nor PostCompact can inject context. Scaffolds use `SessionStart` (source list includes `compact`) — the documented way to restore context after compaction. PreCompact (which can block) is not used.
- [ ] **omitClaudeMd scope**: Only the built-in `Explore` and `Plan` subagents have `omitClaudeMd: true`. All other built-in and custom subagents DO receive CLAUDE.md (and its `@AGENTS.md` import). Scaffold AGENTS.md must still be self-contained because Explore/Plan skip it.
- [ ] **Project skill seeding**: Every scaffold skill seeds a `*-verify` project skill into `.claude/skills/` (next-verify, nest-verify, api-verify, vite-verify). Next.js also seeds `next-migrate`. Migrate Phase 4 seeds the same for all stacks.
- [ ] **Write-more-skills instruction present**: Scaffold instructions include a step asking the user to create additional project skills for repeated workflows.
- [ ] **harness.json origin hashes**: Scaffold includes a step to compute SHA-256 hashes of seeded files and write `.claude/harness.json`. Tracked files must include AGENTS.md, CLAUDE.md, `.claude/settings.json`, and the stack's `*-verify/SKILL.md` skill. Migrate Phase 5 reads these to detect drift.
- [ ] **CLAUDE.md is one line**: Every scaffold and migrate path generates `@AGENTS.md` as the only content of `CLAUDE.md` — never verbose content.
- [ ] **Skills Security section in scaffolded AGENTS.md**: All 4 scaffold AGENTS.md templates include a `## Skills Security` section reminding users to review SKILL.md content before installing third-party skills, scope `allowed-tools:`, and avoid skills that hardcode secrets or make unscoped network calls.
- [ ] **Skill frontmatter uses `allowed-tools:` tightly scoped**: Any SKILL.md that grants tool access scopes it to the minimum required commands (e.g. `Bash(pnpm *)` not `Bash`). No SKILL.md grants unrestricted `Bash` without explicit justification.
- [ ] **Ghost skill names absent**: No skill file references old names (`shared-*-agent`, `nestjs-code-standards`, `fastapi-code-standards`, `nextjs-add-auth`, `shared-audit`). Use `templatecentral:*` or `templatecentral:standards`.
- [ ] **PreToolUse hook uses `args[]` exec form**: Simple hook commands (e.g. `node -e "..."`, `python3 -c "..."`) should use the array exec form `"command": ["node", "-e", "..."]` (v2.1.139+) rather than a shell string. Array form invokes via execve() — no shell interpolation, no injection risk. Complex shell commands that require pipes or conditionals may still use string form, but should be moved to wrapper scripts when possible.
- [ ] **Hook `"if"` field — single rule only**: The `"if"` field exists and holds exactly ONE permission rule (e.g. `Edit(.env*)`); there is no `&&`/`||`/pipe to combine rules or tools. Because of that single-rule limit, scaffolds filter PostToolUse to TS/Python edits **in-script** (reading `tool_input.file_path`) rather than via `if`. `continueOnBlock` does NOT exist in the hooks schema — do not add it.
- [ ] **SubagentStop wired if subagents used**: If a skill spawns subagents, a `SubagentStop` hook should be present. It fires when a subagent finishes, is distinct from `Stop`, and can force review by exiting 2 (stderr → Claude) or emitting `{"decision":"block","reason":"..."}` on stdout. There is **no** `blocking` settings field — control is the hook's exit code / JSON `decision` output. If no subagents are used, no check needed.
- [ ] **skillListingMaxDescChars set**: `settings.json` may pair `skillListingBudgetFraction: 0.02` with `skillListingMaxDescChars: 1536` (default) to cap per-skill description length. Neither field is required, but both should be consistent if one is set. Scaffold should set `skillListingBudgetFraction` and omit `skillListingMaxDescChars` (relying on the 1536-char default) unless a lower cap is needed.
- [ ] **block-`--no-verify` PreToolUse hook present**: Scaffold settings.json includes a `PreToolUse` hook with `matcher: "Bash"` that checks incoming Bash commands and exits 2 if `--no-verify` is found. Must read `tool_input.command` from stdin JSON — **not** top-level `command`. TS stacks use `node` in args[] exec form; FastAPI uses `python3`. Without this hook, an agent can bypass Stop (and all other hooks) by running `git commit --no-verify`.
- [ ] **migrate seeds the FULL harness-kit (scaffold parity)**: `migrate/general` Phase 4 must execute harness-kit Steps **A–E** (incl. B2 git-hook layer, B3 CI, B4 integrity verifier, B5 `/skill-audit`), not just A–B — a migrated project must get the same enforcement layer as a scaffolded one. Its `harness.json` must defer to kit **Step E** (all 9 hooks incl. `skill-usage-log.sh`, `lefthook.yml`, `.gitleaks.toml`, `ci.yml`, `verify/regen-harness.sh`, `skill-audit`), never a hand-maintained partial copy. Phase 5d re-sync + the pre-push hook call `verify-harness.sh`, so B4 MUST be seeded. Flag any "8 scripts" / partial-manifest drift.

---

## Step 4 — Report, fix, and re-audit (loop until clean)

This step is a loop, not a one-shot. Do not update the CHANGELOG or bump the version until the exit condition is met.

### 4a — Report findings

Present all findings grouped by severity:

**HIGH** — incorrect, insecure, or will break user code  
**MEDIUM** — outdated, misleading, or missing important guidance  
**LOW** — style, readability, token reduction  
**CLEAN** — list all files with no findings

### 4b — Fix

- HIGH and MEDIUM: fix immediately. Classify each fix before acting:
  - **Minor** (single file, ≤ 10 lines changed, no architectural impact): fix directly without asking. No plan needed.
  - **Large-scope** (multi-file, architectural change, or > 10 lines): describe the fix and confirm before implementing. A written plan is never required — work directly from the finding description.
- LOW: fix directly without asking.
- After fixing, run the lint script to confirm no mechanical regressions:

```bash
bash scripts/lint-skills.sh skills/
```

### 4c — Re-audit changed files

Re-read every file that was modified in 4b and re-apply the full checklist from Step 2. Do not skip this — fixes sometimes introduce new issues or reveal adjacent problems that were masked by the original finding.

### 4d — Exit condition check

After re-auditing:

- **If any HIGH or MEDIUM findings remain** → return to 4b. Do not proceed.
- **If only LOW findings remain, or all files are CLEAN** → proceed to 4e.

### 4e — Final lint confirmation

```bash
bash scripts/lint-skills.sh skills/
```

Must pass with "All checks passed" before continuing.

### 4f — Update CHANGELOG and version (only reached when 4d passes)

Now that no HIGH or MEDIUM findings remain:

0. **Verify all fixes are committed** — run `git status` and confirm the working tree is clean. Do not write the CHANGELOG entry while uncommitted changes remain; write the entry only after the final commit.
1. Write a `CHANGELOG.md` entry summarising all changes made across all iterations of this audit run — not just the last pass.
2. **Bump the version in `.claude-plugin/plugin.json`** using semver:
   - **patch** (`x.y.Z`): fixes only — corrected outdated code, removed bad patterns, updated docs/examples. Nothing changes for users who don't hit the fixed case.
   - **minor** (`x.Y.0`): new guidance, new checklist items, new reference files, or any additive change a user would notice. No existing skill behaviour removed.
   - **major** (`X.0.0`): breaking — registered skill names changed, skills removed, or the invocation contract changed in a way that breaks existing usage.
3. If any LOW findings were left unfixed (deferred by choice), note them under an `### In Progress` or `### Known` section so they are not lost.

---

## Step 5 — Update audit infrastructure

After fixing all findings, ask: did this audit surface a new **class** of issue — something that could recur in a future skill edit?

If yes, update the infrastructure so it never slips through again:

### New greppable pattern → add to lint script

If the issue is detectable with grep (a specific string, API call, or token), add a new `check_*` function to `scripts/lint-skills.sh`:

```bash
check_no_<pattern_name>() {
  # One sentence: what this catches and why it is wrong.
  # TIMELESS or ECOSYSTEM-ERA: <when to revisit or retire this check>
  header "<Human-readable label>"
  local matches
  matches=$(grep -rn '<pattern>' "$SKILLS_DIR/" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    fail "<Message explaining the fix>"
  else
    pass "No <pattern> found"
  fi
}
```

Then call it in the "Run all checks" section at the bottom of the script, under the correct category (TIMELESS or ECOSYSTEM-ERA).

Run the script to verify the new check passes on the current codebase before committing:

```bash
bash scripts/lint-skills.sh skills/
```

### New semantic pattern → add to this skill

If the issue requires judgment (context-dependent, not detectable by grep alone), add a checklist item to the relevant section of this file (`.claude/skills/audit/implementation.md`):

- Stack-specific issue → add under the appropriate stack section's "additional checks"
- Cross-cutting issue → add under Step 3

Keep the item concise — one checkbox, one line.

### New skill added to the project

If a new `skills/<name>/SKILL.md` was added since the last audit, add it to the correct stack section in Step 2 so it is covered on the next run.

### Missing capability gap

If this audit repeatedly encountered a user need that no `templatecentral:add` capability covers — and it appeared in more than one stack or file — note it explicitly as a skill candidate. Open a `/tc-write-skill` session to draft it.

### After updating infrastructure

Commit the lint script and this skill together with the content fixes, so the audit history is traceable:

```bash
git add scripts/lint-skills.sh .claude/skills/audit/SKILL.md .claude/skills/audit/implementation.md
git commit -m "audit: add <pattern> check to lint script and /tc-audit"
```

---

## Step 6 — Repo harness health check

Run after Step 5 to verify templateCentral's own harness files are intact.

```bash
# AGENTS.md exists and has the plugin marker on line 1
head -1 AGENTS.md | grep -q 'templateCentral: plugin@' && echo "OK: AGENTS.md marker" || echo "FAIL: AGENTS.md marker missing"

# CLAUDE.md exists and is @AGENTS.md
[ -f CLAUDE.md ] && grep -q '^@AGENTS.md' CLAUDE.md && echo "OK: CLAUDE.md" || echo "FAIL: CLAUDE.md missing or wrong"

# .claude/settings.json exists
[ -f .claude/settings.json ] && echo "OK: .claude/settings.json" || echo "FAIL: .claude/settings.json missing"

# .claude/settings.json has skillListingBudgetFraction (10+ skill repos need this to cap listing overhead)
[ -f .claude/settings.json ] && grep -q '"skillListingBudgetFraction"' .claude/settings.json && echo "OK: skillListingBudgetFraction set" || echo "FAIL: skillListingBudgetFraction missing — add \"skillListingBudgetFraction\": 0.02 to .claude/settings.json"

# .claude/harness.json exists
[ -f .claude/harness.json ] && echo "OK: .claude/harness.json" || echo "FAIL: .claude/harness.json missing"
```

Any `FAIL` line means a harness file was removed or corrupted. Re-create it from the v4.0.0 spec in `AGENTS.md` → **Working on this repo** section.

---

## Step 7 — Documentation sync

Run last, after all content fixes and the version bump in Step 4f. The goal: every markdown doc and version marker is accurate before the audit closes. Two tracks — handle them differently.

### 7a — Structural markers (auto-update, no approval needed)

These are formulaic — one correct value, derived from `.claude-plugin/plugin.json`. Update them directly to match, then let the lint scripts confirm. The two scripts enforce these automatically, so the audit's job is to fix any the scripts flag:

```bash
bash scripts/lint-skills.sh skills/        # check_harness_version_matches_plugin, check_agents_marker_not_drifted_to_semver
bash scripts/validate-manifest.sh          # README badge, repo harness.json, repo AGENTS.md marker vs plugin.json
```

| Marker | Tracks | Where | Rule |
|--------|--------|-------|------|
| `version` | — | `.claude-plugin/plugin.json` | source of truth (set in Step 4f) |
| README version badge | plugin semver | `README.md` | == plugin.json |
| `templatecentral_version` | plugin semver | repo `.claude/harness.json` + all scaffold/migrate harness.json templates | == plugin.json |
| AGENTS.md line-1 marker `@X.Y.Z` | harness **schema floor** | repo `AGENTS.md` + scaffold/migrate templates | **PINNED** at `HARNESS_SCHEMA_VERSION` (currently 5.0.0); never bump on a normal release |

**Critical distinction:** `templatecentral_version` tracks the plugin's semver (bump every release). The AGENTS.md `@X.Y.Z` marker is a *migration schema floor* read by `migrate` Phase 0 — bumping it on a normal release makes every existing project falsely report "needs migration." It moves only on a deliberate harness-structure change, at which point you bump `HARNESS_SCHEMA_VERSION` in `lint-skills.sh` and the floor markers together. Both lint scripts guard against accidental drift in either direction.

If either script reports a mismatch, fix the flagged file to match `plugin.json` (or revert a drifted floor marker), then re-run until both pass.

### 7b — Narrative docs (flag + draft, user approves)

These carry intentional decisions — don't rewrite blindly. Read each, compare against the current state of the repo, and for anything stale, present a drafted replacement for the user to approve before writing:

| Doc | Check for staleness against |
|-----|------------------------------|
| `README.md` | skill count (registered `skills/*/SKILL.md`), capability list, stack names, command names |
| `EXAMPLES.md` | every `templatecentral:*` reference resolves to a real skill; workflows still valid |
| `AGENTS.md` | `templatecentral:add` capability row matches `skills/add/*` directories exactly |
| `CONTRIBUTING.md` | lint/validate commands and contribution steps still exist |
| `FUTURE.md` | any listed seam/direction that has since shipped (move to CHANGELOG) or changed |
| `SECURITY.md` | supported-version statements, disclosure process |

Verify counts mechanically before claiming a doc is accurate — e.g. `ls skills/*/SKILL.md | wc -l` for the skill count, `ls skills/add/ | grep -v SKILL.md` for the capability list. Report each narrative doc as CLEAN or list the stale span with a proposed fix; apply only after approval.

## Changelog
### 2.9.0
- Step 2 cross-stack file list gains `skills/add/documentation/implementation.md` and `skills/scaffold/shared/documentation-kit.md` — the per-folder README/`.order` governance feature added its own capability + shared kit but the audit's own file inventory was never updated to cover them.
### 2.8.0
- Harness kit extracted: 3H bullet updated — all scaffolds + migrate now load `scaffold/shared/harness-kit.md` (single source); verify the kit itself, then per-stack deltas. Step 2 cross-stack file list gains `skills/scaffold/shared/harness-kit.md`.
### 2.7.0
- Conventions Compliance C1–C6 block replaced with a short lint-enforcement note: these checks are now fully covered by `scripts/lint-skills.sh` (`check_skillmd_description_length`, `check_ref_file_headers`, `check_skillmd_body_length`, `check_nesting_depth`, `check_no_jurisdiction_specific`). Run Step 1; no separate pass needed.
- Step 0b community-consensus block: added loop-engineering research bullet — current community/team practice on agent loop design (goals, termination, budgets, scheduled self-prompting); graded per RECOMMENDED/CONSENSUS/EMERGING table.
- Duplicate `### 2.4.0` changelog heading removed (was duplicated on two consecutive lines).
- Utility skill category paths (`build/`, `test/`, `review/`, `cleanup/`) now documented as the canonical cat-path contract for de-registered agent utilities; Step 2 cross-stack file list confirms the correct paths.
### 2.6.0
- Step 0b: added "Claude Code harness engineering — community consensus & team recommendations" research item — scans official Anthropic guidance and community sources (claude-code GitHub discussions, practitioner write-ups) for harness-engineering practice, graded RECOMMENDED / CONSENSUS / EMERGING; RECOMMENDED and CONSENSUS findings become targeted Step 3H checks, EMERGING is tracked only. Cache template gained a matching subsection.
### 2.5.0
- Added Step 7 — Documentation sync: two-track doc maintenance (auto-update structural version markers; flag + draft narrative docs). Runs every audit so markdown and version markers can't silently drift.
- Scoped-skills enforcement: lint now requires every seeded `*-verify`/`*-migrate` skill to declare a tightly-scoped `allowed-tools:` (`check_seeded_skills_scope_tools`) and bans unscoped `Bash` grants (`check_no_unscoped_bash_grant`). All seeded skills updated to model least-agency (OWASP Agentic ASI02).
- Harness-completeness enforcement: `check_scaffold_seeds_complete_harness` lint-enforces that every scaffold + migrate `settings.json` template seeds the full hook set AND the `permissions.deny` secret-Read block (the Step 3H manual checklist is now backstopped by lint). Adoption/retrofit routing surfaced in `AGENTS.md` + `README.md`.
- Defense-in-depth: scaffolds now seed `permissions.deny` for `Read(.env*)`/`Read(./secrets/**)` — the Edit/Write PreToolUse guard only blocked writes; an agent could still read secrets.
- **Full harness parity:** scaffolds + migrate seed a **7-event** `.claude/hooks/` script kit (8 scripts: `protect-files`, `block-no-verify` with git-guards, `user-prompt-guard` with LLM02 credential detection, `post-edit-typecheck`, `post-tool-failure`, `stop-checks`, `subagent-stop`, `session-context`). When auditing a scaffold's harness, verify: the 7 events (PreToolUse, UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, SessionStart); PostToolUse filters to source-file edits **in-script** (no `if` field used — it allows only a single rule; and no `continueOnBlock` — not a real key); JSON parsing uses the runtime guaranteed per stack (Node for TS / python3 for FastAPI) so guards fail safe; `SessionStart` (source `compact`) re-injects context — PostCompact is observability-only and cannot inject; all scaffolds + migrate load `scaffold/shared/harness-kit.md` (single source); verify the kit itself, then per-stack deltas. Enforced by `check_scaffold_seeds_complete_harness`.
- Step 5 / lint: added `check_harness_version_matches_plugin` (harness.json `templatecentral_version` templates == plugin.json) and `check_agents_marker_not_drifted_to_semver` (AGENTS.md schema-floor marker must stay <= `HARNESS_SCHEMA_VERSION`, guarding migrate Phase 0).
- `validate-manifest.sh`: added DOC SYNC section — README badge, repo `.claude/harness.json`, and repo AGENTS.md marker checked against `plugin.json`.
- Documented the `templatecentral_version` (plugin semver) vs AGENTS.md `@X.Y.Z` marker (harness schema floor) distinction; introduced `HARNESS_SCHEMA_VERSION` constant in `lint-skills.sh`.
### 2.4.0
- Step 3H: added block-`--no-verify` PreToolUse hook check — scaffold must block `git ... --no-verify` via `tool_input.command` (not top-level `command`); without it agents can bypass Stop and all other hooks
- Step 5: added `check_no_toplevel_command_in_hooks` to lint script — catches hooks that read bash command from top-level `d.command` instead of `d.tool_input.command`
### 2.3.0
- Step 6: added `skillListingBudgetFraction` health check — 10+ skill repos should set `"skillListingBudgetFraction": 0.02` in `.claude/settings.json` to cap skill-listing context overhead
- Harness check list now at 15 items (PostToolUse feedback hook awareness)
### 2.2.0
- Step 4f: added semver decision rules for version bump (patch = fixes only, minor = additive, major = breaking skill name/contract changes)
### 2.1.0
- Added universal-standards philosophy to Mindset: OWASP as the stated security standard, government-grade rigour applied generically, explicit prohibition on country/region/ethnicity/gender-specific content
- Hardened Step 0 training-cutoff note: "August 2025" named explicitly; all ecosystem state treated as stale until web-searched
- Added C6 — Jurisdiction neutrality check: grep for known jurisdiction-specific framework names (IM8, PDPA, GDPR, HIPAA, PCI-DSS, etc.) in skill files
- Expanded Token efficiency checklist item from one line to five concrete sub-checks (line count, redundant comments, over-scaffolded examples, duplicate instructions, redundant prose)
- Step 4b: added explicit "minor = fix directly / large-scope = confirm first" classification; stated no written plan is ever required for audit findings
- Step 4f: added pre-changelog gate — verify working tree is clean before writing CHANGELOG entry
### 2.0.0
- Updated all Step 2 file lists from 33 old skill paths to new 10-skill nested structure (`add/`, `scaffold/`, `standards/`, `migrate/`, etc.)
- Fixed C4 depth check: `NF > 4` → `NF > 5` to accommodate the deeper nested layout
- Updated git commit command in Step 5 from `shared-audit/` to `audit/`
- Updated AIDLC checklist reference from `shared-add-ai-security` to `add/ai-security/`
### 1.6.0
- Added `check_no_globals_jest_in_vitest_projects` to lint script (ECOSYSTEM-ERA: catches `globals.jest` in ESLint config templates — Node stacks use Vitest with `globals: false`; `globals.jest` is unused and misleading)
- Added NestJS-specific checklist item: ESLint config must not include `globals.jest` when using Vitest
### 1.5.0
- Added `check_no_jest_apis_in_skills` to lint script (ECOSYSTEM-ERA: catches `jest.fn()`, `jest.spyOn()`, `jest-e2e.json` in skill code examples — all Node stacks use Vitest)
- Added NestJS-specific checklist item: test examples must use `vi.fn()` / `vi.spyOn()` (Vitest), not Jest APIs
### 1.4.0
- Added `algorithms: ['HS256']` whitelist check to NestJS-specific additional checks
- Added `check_no_zod_string_format_methods` to lint script (ECOSYSTEM-ERA: catches deprecated `z.string().url()`, `z.string().datetime()` etc. in Zod v4)
### 1.3.0
- Added "Mindset" preamble — fresh eyes, no carry-over assumptions, explicit priority order (accuracy → security → quality → AIDLC)
- Added Step 0 — Ecosystem research; WebSearch/WebFetch for 6-month ecosystem changes across all stack packages and security standards before reading any skill files; AWS AIDLC reference included
- Checklist expanded: accuracy items now cross-reference Step 0 findings; security items add trust proxy topology detail; structural section renamed to "Code quality" with SRP, SoC, DRY, YAGNI, and token efficiency named explicitly; new "AIDLC/SDLC alignment" section added
### 1.2.0
- Step 4 rewritten as an iterative loop (4a–4f) — CHANGELOG and version bump gated behind exit condition; re-audit of changed files mandatory
### 1.1.0
- Added Step 5 — audit infrastructure self-update
### 1.0.0
- Initial release — structured per-file semantic audit covering all 49 skills