# templateCentral Audit 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify every verbatim block matches the deleted `templates/` baseline (git-recovered), update all stacks to April 2026 accuracy, and correct all plugin references across 46 skills.

**Architecture:** Two parallel tracks (template fidelity via git-recovery + April 2026 web research) feed into a consolidation step, then five parallel fix agents apply all changes. A plugin audit micro-agent runs alongside Phase 1.

**Tech Stack:** templateCentral plugin — 46 SKILL.md files, AGENTS.md, `.claude/rules/`. No application code — only Markdown edits.

---

### Task 0: Phase 1 — 10 Parallel Research Agents

**Goal:** Collect all findings (template divergences, April 2026 breaking changes, plugin ref issues) before touching any file.

**Files:**
- Read: `skills/nextjs-scaffold/SKILL.md`, `skills/fastapi-scaffold/SKILL.md`, `skills/nestjs-scaffold/SKILL.md`, `skills/vite-react-scaffold/SKILL.md`
- Read (git history): deleted templates from commit `591ce19`
- Read: all 46 `skills/*/SKILL.md`, `AGENTS.md`

**Acceptance Criteria:**
- [ ] R1–R4 each return a structured findings list (missing files / extra files / verbatim content divergences)
- [ ] W1–W5 each return a structured findings list (breaking changes, deprecated APIs, CVEs since Aug 2025)
- [ ] P1 returns a findings list (wrong plugin refs, stale commands, docs/superpowers refs, skill-recreating-plugin patterns)

**Verify:** All 10 agents complete and return non-empty findings reports

**Steps:**

- [ ] **Step 1: Mark task in-progress**

- [ ] **Step 2: Dispatch all 10 agents in parallel**

Dispatch the following agents simultaneously (one message, multiple Agent tool calls):

---

**R1 — nextjs template fidelity:**

```
You are auditing the templateCentral plugin. Your ONLY job is to compare the deleted nextjs template files (recovered from git) against the current nextjs-scaffold/SKILL.md verbatim blocks. DO NOT make any edits.

Repo: /Users/clarence/Desktop/templateCentral

STEP 1 — Recover deleted template files:
Run these commands to get the content of each deleted template file:
  git show 591ce19:templates/nextjs/tsconfig.json
  git show 591ce19:templates/nextjs/next.config.ts
  git show 591ce19:templates/nextjs/Dockerfile
  git show 591ce19:templates/nextjs/docker-entrypoint.sh
  git show 591ce19:templates/nextjs/.dockerignore
  git show 591ce19:templates/nextjs/.gitignore
  git show 591ce19:templates/nextjs/.env.example
  git show 591ce19:templates/nextjs/postcss.config.mjs
  git show 591ce19:templates/nextjs/components.json
  git show 591ce19:templates/nextjs/vitest.config.ts
  git show 591ce19:templates/nextjs/src/app/globals.css
  git show 591ce19:templates/nextjs/src/app/layout.tsx
  git show 591ce19:templates/nextjs/src/app/api/route.ts
  git show 591ce19:templates/nextjs/src/app/api/health/route.ts
  git show 591ce19:templates/nextjs/test/api/health.test.ts
  git show 591ce19:templates/nextjs/src/lib/constants/env.ts
  git show 591ce19:templates/nextjs/src/lib/constants/routes.ts
  git show 591ce19:templates/nextjs/src/integrations/factories.ts
  git show 591ce19:templates/nextjs/src/integrations/error.ts

STEP 2 — Read current skill:
Read /Users/clarence/Desktop/templateCentral/skills/nextjs-scaffold/SKILL.md fully.

STEP 3 — Compare:
For each file recovered in Step 1, find the corresponding verbatim block in the skill. Report:
  A) Files in the deleted template that have NO verbatim block in the skill (missing)
  B) Verbatim blocks in the skill that differ from the deleted template in a way that looks like a BUG (not an intentional improvement — e.g., wrong import path, removed required field, broken syntax)
  C) Intentional improvements are OK — e.g., added dashboard layout, new widgets. Flag these separately as "intentional change" not "bug".

Also check: does the skill's Directory Structure listing include all files that were in the deleted template?

Return a structured report:
  MISSING FILES: [list]
  VERBATIM BUGS: [file: description of divergence]
  INTENTIONAL CHANGES: [file: what changed]
  STRUCTURE GAPS: [files in template not listed in Directory Structure]
```

---

**R2 — fastapi template fidelity:**

```
You are auditing the templateCentral plugin. Your ONLY job is to compare deleted fastapi template files (recovered from git) against the current fastapi-scaffold/SKILL.md verbatim blocks. DO NOT make any edits.

Repo: /Users/clarence/Desktop/templateCentral

STEP 1 — Recover deleted template files:
  git show 591ce19:templates/fastapi/Dockerfile
  git show 591ce19:templates/fastapi/docker-entrypoint.sh
  git show 591ce19:templates/fastapi/.dockerignore
  git show 591ce19:templates/fastapi/.gitignore
  git show 591ce19:templates/fastapi/.env.example
  git show 591ce19:templates/fastapi/pyproject.toml
  git show 591ce19:templates/fastapi/src/.env.default
  git show 591ce19:templates/fastapi/src/main.py
  git show 591ce19:templates/fastapi/src/app.py
  git show 591ce19:templates/fastapi/src/error_handler.py
  git show 591ce19:templates/fastapi/src/core/config.py
  git show 591ce19:templates/fastapi/src/core/exceptions.py
  git show 591ce19:templates/fastapi/src/core/logging.py
  git show 591ce19:templates/fastapi/src/core/directory_manager.py
  git show 591ce19:templates/fastapi/src/core/json/logging.json
  git show 591ce19:templates/fastapi/src/api/routes.py
  git show 591ce19:templates/fastapi/src/api/tags.py
  git show 591ce19:templates/fastapi/src/api/routers/example.py
  git show 591ce19:templates/fastapi/src/api/schemas/base.py
  git show 591ce19:templates/fastapi/src/api/schemas/request/example.py
  git show 591ce19:templates/fastapi/src/api/schemas/response/example.py
  git show 591ce19:templates/fastapi/src/api/services/example.py
  git show 591ce19:templates/fastapi/test/conftest.py
  git show 591ce19:templates/fastapi/test/test_api/test_example.py
  git show 591ce19:templates/fastapi/test/test_api/test_health.py

STEP 2 — Read current skill:
Read /Users/clarence/Desktop/templateCentral/skills/fastapi-scaffold/SKILL.md fully.

STEP 3 — Compare (same criteria as R1).

Return structured report: MISSING FILES / VERBATIM BUGS / INTENTIONAL CHANGES / STRUCTURE GAPS
```

---

**R3 — nestjs template fidelity:**

```
You are auditing the templateCentral plugin. Your ONLY job is to compare deleted nestjs template files (recovered from git) against the current nestjs-scaffold/SKILL.md verbatim blocks. DO NOT make any edits.

Repo: /Users/clarence/Desktop/templateCentral

STEP 1 — Recover deleted template files:
  git show 591ce19:templates/nestjs/Dockerfile
  git show 591ce19:templates/nestjs/docker-entrypoint.sh
  git show 591ce19:templates/nestjs/.dockerignore
  git show 591ce19:templates/nestjs/.gitignore
  git show 591ce19:templates/nestjs/.env.example
  git show 591ce19:templates/nestjs/.prettierrc
  git show 591ce19:templates/nestjs/eslint.config.mjs
  git show 591ce19:templates/nestjs/nest-cli.json
  git show 591ce19:templates/nestjs/tsconfig.json
  git show 591ce19:templates/nestjs/tsconfig.build.json
  git show 591ce19:templates/nestjs/src/main.ts
  git show 591ce19:templates/nestjs/src/app.module.ts
  git show 591ce19:templates/nestjs/src/config/env.config.ts
  git show 591ce19:templates/nestjs/src/config/index.ts
  git show 591ce19:templates/nestjs/src/common/utils/date.utils.ts
  git show 591ce19:templates/nestjs/src/common/utils/string.utils.ts
  git show 591ce19:templates/nestjs/src/modules/base/base.module.ts
  git show 591ce19:templates/nestjs/src/modules/base/base.service.ts
  git show 591ce19:templates/nestjs/test/app.e2e-spec.ts
  git show 591ce19:templates/nestjs/test/jest-e2e.json

STEP 2 — Read current skill:
Read /Users/clarence/Desktop/templateCentral/skills/nestjs-scaffold/SKILL.md fully.

STEP 3 — Compare (same criteria as R1). Also check the package.json in the git template:
  git show 591ce19:templates/nestjs/package.json

Return structured report: MISSING FILES / VERBATIM BUGS / INTENTIONAL CHANGES / STRUCTURE GAPS
```

---

**R4 — vite-react template fidelity:**

```
You are auditing the templateCentral plugin. Your ONLY job is to compare deleted vite-react template files (recovered from git) against the current vite-react-scaffold/SKILL.md verbatim blocks. DO NOT make any edits.

Repo: /Users/clarence/Desktop/templateCentral

STEP 1 — Recover deleted template files:
  git show 591ce19:templates/vite-react/Dockerfile
  git show 591ce19:templates/vite-react/docker-entrypoint.sh
  git show 591ce19:templates/vite-react/.dockerignore
  git show 591ce19:templates/vite-react/.gitignore
  git show 591ce19:templates/vite-react/.env.example
  git show 591ce19:templates/vite-react/.prettierrc
  git show 591ce19:templates/vite-react/eslint.config.mjs
  git show 591ce19:templates/vite-react/vite.config.ts
  git show 591ce19:templates/vite-react/vite-env.d.ts
  git show 591ce19:templates/vite-react/tsconfig.json
  git show 591ce19:templates/vite-react/index.html
  git show 591ce19:templates/vite-react/postcss.config.mjs
  git show 591ce19:templates/vite-react/components.json
  git show 591ce19:templates/vite-react/nginx.conf.template
  git show 591ce19:templates/vite-react/src/main.tsx
  git show 591ce19:templates/vite-react/src/app.tsx
  git show 591ce19:templates/vite-react/src/router.tsx
  git show 591ce19:templates/vite-react/src/styles/globals.css
  git show 591ce19:templates/vite-react/src/lib/constants/env.ts
  git show 591ce19:templates/vite-react/src/lib/constants/routes.ts
  git show 591ce19:templates/vite-react/src/lib/utils/index.ts
  git show 591ce19:templates/vite-react/src/lib/errors/api-error.ts
  git show 591ce19:templates/vite-react/src/test/setup.ts
  git show 591ce19:templates/vite-react/src/pages/home.tsx
  git show 591ce19:templates/vite-react/src/pages/not-found.tsx

STEP 2 — Read current skill:
Read /Users/clarence/Desktop/templateCentral/skills/vite-react-scaffold/SKILL.md fully.

STEP 3 — Compare (same criteria as R1).

Return structured report: MISSING FILES / VERBATIM BUGS / INTENTIONAL CHANGES / STRUCTURE GAPS
```

---

**W1 — Next.js 16 + React 19 + shadcn/ui web research:**

```
You are researching breaking changes for the templateCentral plugin audit. DO NOT edit any files. Search the web and return findings only.

Today's date: 2026-04-29. Training data cutoff: August 2025. Focus on changes AFTER August 2025.

Search for:
1. "Next.js 16 breaking changes changelog" — look for removed APIs, changed defaults, new required config
2. "Next.js 16 App Router changes 2025 2026" — any routing, middleware, or proxy.ts changes
3. "React 19 breaking changes deprecated APIs" — check hook changes, ref forwarding, etc.
4. "shadcn/ui breaking changes 2025 2026" — component API changes, new-york style changes
5. "@types/react 19 breaking changes" — TypeScript type changes
6. "next/image remotePatterns required 2026" — confirm images.domains removal
7. "better-auth 1.0 breaking changes 2025 2026" — CLI changes, adapter changes
8. "better-auth drizzle adapter package name 2026" — confirm @better-auth/drizzle-adapter vs bundled

For each finding, report:
- Package + version where change occurred
- What changed (old API → new API)
- Severity: SECURITY / BREAKING / DEPRECATED / INFO
- Which templateCentral skill file is likely affected

Return a structured FINDINGS list. Be specific — include exact import paths, config keys, function names.
```

---

**W2 — FastAPI + Python ecosystem web research:**

```
You are researching breaking changes for the templateCentral plugin audit. DO NOT edit any files.

Today's date: 2026-04-29. Focus on changes after August 2025.

Search for:
1. "FastAPI 0.115 0.120 0.136 breaking changes changelog" — lifespan changes, response_model changes
2. "Pydantic v2.10+ breaking changes 2025 2026"
3. "PyJWT 2.9+ breaking changes" — any API changes since python-jose migration
4. "Beanie 2.0 motor removed asyncmotorclient migration" — confirm pymongo AsyncMongoClient
5. "pymongo 4.x async client 2025 2026" — confirm AsyncMongoClient import path
6. "pytest-asyncio 0.24+ breaking changes asyncio_mode" — default mode changes
7. "ruff 0.6+ breaking changes linter rules 2025 2026"
8. "SQLAlchemy 2.1 asyncio changes 2026" — any async engine changes
9. "python uvicorn 0.32+ breaking changes"
10. "httpx 0.28+ breaking changes pytest fixtures"

Return structured FINDINGS list with: package, version, old API, new API, severity, affected skill.
```

---

**W3 — NestJS + platform-fastify + nestjs-zod web research:**

```
You are researching breaking changes for the templateCentral plugin audit. DO NOT edit any files.

Today's date: 2026-04-29. Focus on changes after August 2025.

Search for:
1. "NestJS 11 breaking changes changelog 2025 2026"
2. "@nestjs/platform-fastify 11.1.16 CVE security advisory" — confirm the 3 CVEs and exact fix version
3. "nestjs-zod v5 breaking changes" — beyond patchNestJsSwagger removal
4. "Fastify 5 breaking changes NestJS compatibility" — any new Fastify 5 issues
5. "@fastify/helmet v13 breaking changes option names"
6. "pino nestjs-pino 4.x breaking changes 2025 2026"
7. "NestJS swagger @nestjs/swagger 8.x breaking changes"
8. "jest ts-jest 30.x breaking changes 2026"
9. "NestJS 12 release date features" — if released, what breaks
10. "TypeScript 6 NestJS decorators breaking" — experimentalDecorators emitDecoratorMetadata defaults

Return structured FINDINGS list with: package, version, old API, new API, severity, affected skill.
```

---

**W4 — Vite 8 + Tailwind CSS v4 + Zod v4 web research:**

```
You are researching breaking changes for the templateCentral plugin audit. DO NOT edit any files.

Today's date: 2026-04-29. Focus on changes after August 2025.

Search for:
1. "Vite 8 breaking changes changelog 2025 2026"
2. "Tailwind CSS v4 breaking changes utility renames" — full list of renamed/removed utilities
3. "Tailwind CSS v4 postcss plugin @tailwindcss/postcss autoprefixer"
4. "Tailwind CSS v4 important modifier syntax change" — !flex vs flex!
5. "Zod v4 breaking changes deprecated APIs 2026" — full list beyond .flatten() and .strict()
6. "Zod v4 z.treeifyError z.strictObject z.looseObject migration"
7. "@vitejs/plugin-react vs @vitejs/plugin-react-swc 2026" — which is recommended for Vite 8
8. "vitest 3.x breaking changes 2025 2026"
9. "@testing-library/react 16.x breaking changes"
10. "shadcn/ui vite react setup 2026 components.json changes"

Return structured FINDINGS list with: package, version, old API, new API, severity, affected skill.
```

---

**W5 — better-auth + Drizzle + Kysely + TanStack web research:**

```
You are researching breaking changes for the templateCentral plugin audit. DO NOT edit any files.

Today's date: 2026-04-29. Focus on changes after August 2025.

Search for:
1. "better-auth v1 breaking changes 2025 2026 migration guide"
2. "better-auth CLI npx auth generate vs npx better-auth-cli" — exact current command
3. "better-auth drizzle adapter @better-auth/drizzle-adapter package name"
4. "drizzle-orm 0.45+ breaking changes 2025 2026"
5. "drizzle-orm sql.identifier sql.as security CVE fix version"
6. "Kysely 0.28 breaking changes migration imports"
7. "Kysely 0.29+ breaking changes 2025 2026"
8. "@tanstack/react-query v5.60+ breaking changes 2025 2026"
9. "mongoose 8.x breaking changes 2025 2026"
10. "Prisma 6.x breaking changes 2026"

Return structured FINDINGS list with: package, version, old API, new API, severity, affected skill.
```

---

**P1 — Plugin reference audit:**

```
You are auditing the templateCentral plugin for incorrect plugin references. DO NOT make any edits. Read files and report only.

Repo: /Users/clarence/Desktop/templateCentral

STEP 1 — Read ALL skill files:
Run: find /Users/clarence/Desktop/templateCentral/skills -name "SKILL.md" | sort
Then read each one.

Also read:
- /Users/clarence/Desktop/templateCentral/AGENTS.md
- /Users/clarence/Desktop/templateCentral/.claude/rules/nextjs.md
- /Users/clarence/Desktop/templateCentral/.claude/rules/fastapi.md
- /Users/clarence/Desktop/templateCentral/.claude/rules/nestjs.md
- /Users/clarence/Desktop/templateCentral/.claude/rules/vite-react.md

STEP 2 — Check for these patterns:

A) "docs/superpowers" references — any mention of docs/superpowers/* paths (these should not exist in skills — superpowers is an installed plugin, not a local docs folder)

B) Incorrect superpowers slash commands — e.g., `/superpowers:brainstorm`, `/superpowers:write-plan`, `/superpowers:execute-plan`. The installed plugin `obra/superpowers` may use different command syntax. Check what the AGENTS.md says and whether it matches the actual installed plugin commands.

C) Skills that recreate functionality from other plugins — e.g., a skill that implements its own memory system (should reference claude-mem instead), implements its own brainstorm/plan flow (should reference superpowers), implements its own output compression (should reference caveman).

D) Plugin install commands that reference wrong package names:
   - `claude plugin marketplace add JuliusBrussee/caveman` — is this still current?
   - `claude plugin marketplace add obra/superpowers` — is this still current or is it superpowers-extended-cc?
   - `claude plugin marketplace add thedotmack/claude-mem` — is this still current?

E) Any skill that tells users to reference a local path that won't exist in a scaffolded project (e.g., `../templateCentral/...`).

F) AGENTS.md "Task Management Option B" — check if `/superpowers:brainstorm` → `/superpowers:write-plan` → `/superpowers:execute-plan` are the actual commands for the installed superpowers plugin, or if they should be different.

Return a structured report for each finding: FILE / LINE / ISSUE / RECOMMENDED FIX
```

- [ ] **Step 3: Collect all 10 agent reports and record findings for Task 1**

---

### Task 1: Consolidate Phase 1 Findings by Stack

**Goal:** Merge all 10 agent reports into one prioritised findings list per stack, ready to feed into fix agents.

**Files:** No writes — in-session consolidation only

**Acceptance Criteria:**
- [ ] Each stack has a deduplicated findings list sorted by priority (security → structural → accuracy → plugin → token)
- [ ] Each item has: file path, line reference if known, issue description, recommended fix

**Verify:** Consolidated list directly drives the 5 fix agent prompts in Task 2

**Steps:**

- [ ] **Step 1: Read all 10 reports from Task 0**

- [ ] **Step 2: Deduplicate** — if R1 and W1 both flag the same tsconfig issue, merge into one item

- [ ] **Step 3: Classify** each finding:
  - `[SEC]` — security bug or CVE-affected package
  - `[STRUCT]` — structural divergence from deleted template (broken code)
  - `[ACC]` — API accuracy issue (deprecated/removed API call)
  - `[PLUGIN]` — wrong plugin reference
  - `[INFO]` — informational / low-priority

- [ ] **Step 4: Group by stack** (nextjs / fastapi / nestjs / vite-react / shared+AGENTS.md)

- [ ] **Step 5: For each stack, produce a findings block like:**

```
## nextjs findings
[SEC] skills/nextjs-scaffold/SKILL.md — Dockerfile uses node:24.14 but Node 24 is not LTS; Next.js 16 requires >=20.9.0, use node:22-alpine
[ACC] skills/nextjs-add-auth/SKILL.md:L340 — better-auth CLI: `npx @better-auth/cli generate` → `npx auth@latest generate`
[PLUGIN] AGENTS.md:L154 — `/superpowers:brainstorm` syntax may be wrong for installed plugin
...
```

---

### Task 2: Phase 2 — 5 Parallel Fix Agents

**Goal:** Apply all consolidated findings to the skill files.

**Files:**
- Modify: all `skills/*/SKILL.md` files with confirmed findings
- Modify: `AGENTS.md` if plugin refs are wrong
- Modify: `.claude/rules/*.md` if stale

**Acceptance Criteria:**
- [ ] Every `[SEC]` and `[STRUCT]` finding addressed
- [ ] Every `[ACC]` finding addressed
- [ ] Every `[PLUGIN]` finding addressed
- [ ] No `docs/superpowers` in any skill
- [ ] No CVE-affected package version in any install command

**Verify:** `grep -r "docs/superpowers" skills/ AGENTS.md` → empty

**Steps:**

- [ ] **Step 1: Dispatch 5 fix agents in parallel**

Each agent receives its stack's findings from Task 1 plus full read access to its skill files.

**F1 prompt template (nextjs):**

```
You are fixing confirmed accuracy/security bugs in the templateCentral plugin. Your scope is ONLY nextjs-* skill files.

Repo: /Users/clarence/Desktop/templateCentral

FINDINGS TO FIX (from audit research — apply ALL of these):
[paste nextjs findings block from Task 1 consolidation]

RULES:
- Fix ONLY what is in the findings list above
- Do NOT reformat, restructure, or improve style
- Do NOT add new features or sections
- Do NOT change intentional improvements that were flagged as such in template fidelity check
- Make minimal surgical edits — change only the specific lines needed
- If a finding says "remove X", remove only X — don't refactor surrounding code
- Read each file fully before editing to understand context

FILES IN SCOPE:
- /Users/clarence/Desktop/templateCentral/skills/nextjs-scaffold/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-auth/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-database/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-page/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-feature/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-api-route/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-component/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-form/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-integration/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-add-test/SKILL.md
- /Users/clarence/Desktop/templateCentral/skills/nextjs-code-standards/SKILL.md

Return: summary of every change made (file, line, what changed, why).
```

Use the same template for F2 (fastapi-* files), F3 (nestjs-* files), F4 (vite-react-* files), F5 (shared-* + AGENTS.md + .claude/rules/).

- [ ] **Step 2: Collect all 5 fix agent reports**

---

### Task 3: Final Verification and Commit

**Goal:** Confirm all fixes landed correctly, run post-fix checks, commit.

**Files:** No new writes — read-only verification then git commit

**Acceptance Criteria:**
- [ ] `grep -r "docs/superpowers" skills/ AGENTS.md` → empty
- [ ] `grep -r "motor" skills/fastapi-add-database/SKILL.md` → only in comments, not in imports or requirements.txt blocks
- [ ] `grep -r "patchNestJsSwagger" skills/` → empty
- [ ] `grep -r "python-jose" skills/` → empty
- [ ] `grep -rn "AsyncIOMotorClient" skills/` → empty
- [ ] Git diff shows only expected skill files modified

**Verify:** All greps above return empty (or expected results)

**Steps:**

- [ ] **Step 1: Run verification greps**

```bash
grep -r "docs/superpowers" /Users/clarence/Desktop/templateCentral/skills/ /Users/clarence/Desktop/templateCentral/AGENTS.md
grep -r "patchNestJsSwagger" /Users/clarence/Desktop/templateCentral/skills/
grep -r "python-jose" /Users/clarence/Desktop/templateCentral/skills/
grep -rn "AsyncIOMotorClient" /Users/clarence/Desktop/templateCentral/skills/
grep -n "motor" /Users/clarence/Desktop/templateCentral/skills/fastapi-add-database/SKILL.md
```

All should return empty (or comment-only for `motor`).

- [ ] **Step 2: Review git diff**

```bash
git diff --stat
```

Confirm only skill files and AGENTS.md modified — no config files, no docs other than the plan itself.

- [ ] **Step 3: Commit**

```bash
git add skills/ AGENTS.md .claude/rules/
git commit -m "$(cat <<'EOF'
fix(audit3): template fidelity + April 2026 accuracy + plugin ref corrections

- Verified all verbatim blocks against deleted templates/
- Updated package versions and APIs for April 2026
- Corrected plugin install commands and reference syntax
- Removed any docs/superpowers references from skills

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
