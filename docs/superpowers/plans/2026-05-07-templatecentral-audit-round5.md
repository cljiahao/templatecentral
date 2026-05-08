# templateCentral Round 5 Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce Node.js ≥24 as single source of truth across all rules and scaffold output, fix Next.js 16 async Request API note, correct FastAPI and Drizzle accuracy gaps, and update Vite 8 scaffold for the Babel-free plugin-react v6.

**Architecture:** Markdown-only changes across existing skill and rules files. No new files. No new abstractions. Tasks 1–4 are independent and can run in any order; Task 5 (version bump) must follow all four.

**Tech Stack:** Markdown, `.claude/rules/*.md`, `skills/**/*.md`, `.claude-plugin/plugin.json`, `CHANGELOG.md`.

---

### Task 1: SSOT Node Cleanup

**Goal:** Update all three rules files to `Node.js ≥24` and replace hardcoded Node version literals in scaffold SKILL.md files with rules-reference instructions.

**Files:**
- Modify: `.claude/rules/nextjs.md`
- Modify: `.claude/rules/nestjs.md`
- Modify: `.claude/rules/vite-react.md`
- Modify: `skills/nextjs-scaffold/SKILL.md`
- Modify: `skills/nestjs-scaffold/SKILL.md`
- Modify: `skills/vite-react-scaffold/SKILL.md`

**Acceptance Criteria:**
- [ ] `.claude/rules/nextjs.md` Stack line says `Node.js ≥24` (not `≥20.9.0`)
- [ ] `.claude/rules/nestjs.md` Stack line includes `Node.js ≥24`
- [ ] `.claude/rules/vite-react.md` Stack line includes `Node.js ≥24`
- [ ] No `>=22`, `>=20`, or `>=18` node engine pins remain in scaffold SKILL.md files
- [ ] No `node:24.14-alpine3.23` or other patch-pinned Node image tags in scaffold SKILL.md files
- [ ] All three scaffold SKILL.md files reference the rules file as source of truth for the Node version

**Verify:**
```bash
grep "Node.js" .claude/rules/nextjs.md .claude/rules/nestjs.md .claude/rules/vite-react.md
grep -n ">=22\|>=20\|>=18\|24\.14\|22\." skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
```
Expected: three `Node.js ≥24` matches; zero matches from second grep.

**Steps:**

- [ ] **Step 1: Update `.claude/rules/nextjs.md` Node version**

Find this exact line in `.claude/rules/nextjs.md`:
```
Stack: Next.js 16, React 19, TypeScript 6, Node.js ≥20.9.0, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `nextjs-add-auth` skill (better-auth). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

Replace with:
```
Stack: Next.js 16, React 19, TypeScript 6, Node.js ≥24, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `nextjs-add-auth` skill (better-auth). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

- [ ] **Step 2: Add Node version to `.claude/rules/nestjs.md`**

Find this exact line in `.claude/rules/nestjs.md`:
```
Stack: NestJS 11, Fastify adapter, Zod + nestjs-zod, Swagger, TypeScript 6, Jest, Docker.
```

Replace with:
```
Stack: NestJS 11, Fastify adapter, Zod + nestjs-zod, Swagger, TypeScript 6, Node.js ≥24, Jest, Docker.
```

- [ ] **Step 3: Add Node version to `.claude/rules/vite-react.md`**

Find this exact line in `.claude/rules/vite-react.md`:
```
Stack: Vite 8, React 19, TypeScript 6, shadcn/ui (new-york), Tailwind CSS 4, React Router 7, TanStack Query 5, React Hook Form + Zod, Vitest + Testing Library, Docker (Nginx). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

Replace with:
```
Stack: Vite 8, React 19, TypeScript 6, Node.js ≥24, shadcn/ui (new-york), Tailwind CSS 4, React Router 7, TanStack Query 5, React Hook Form + Zod, Vitest + Testing Library, Docker (Nginx). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

- [ ] **Step 4: Fix nextjs-scaffold engines comment and pin**

In `skills/nextjs-scaffold/SKILL.md`, find this exact block:
```
**Engines field to include in package.json** (Node.js 22 is Active LTS as of 2026-04-30):
```json
{
  "engines": { "node": ">=22.0.0" }
}
```
```

Replace with:
```
**Engines field to include in package.json** (use the Node version from `.claude/rules/nextjs.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```
```

- [ ] **Step 5: Fix nextjs-scaffold Dockerfile ARG pins**

In `skills/nextjs-scaffold/SKILL.md`, find this exact block:
```
ARG NODE=node:24.14-alpine3.23
ARG NODE_BUILD=node:24.14-alpine3.23
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

FROM ${NODE_BUILD} AS base
```

Replace with:
```
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

FROM ${NODE_BUILD} AS base
```

- [ ] **Step 6: Fix nestjs-scaffold engines comment and pin**

In `skills/nestjs-scaffold/SKILL.md`, find this exact block:
```
**Engines field to include in package.json** (Node.js 22 is Active LTS as of 2026-04-30):
```json
{
  "engines": { "node": ">=22.0.0" }
}
```
```

Replace with:
```
**Engines field to include in package.json** (use the Node version from `.claude/rules/nestjs.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```
```

- [ ] **Step 7: Fix nestjs-scaffold Dockerfile ARG pins**

In `skills/nestjs-scaffold/SKILL.md`, find these two lines near the Dockerfile section comments:
```
ARG NODE=node:24.14-alpine3.23
ARG NODE_BUILD=node:24.14-alpine3.23
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
```

Replace with:
```
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
```

- [ ] **Step 8: Fix vite-react-scaffold engines comment and pin**

In `skills/vite-react-scaffold/SKILL.md`, find this exact block:
```
**Engines field to include in package.json** (Vite 8 requires Node.js 22.12+ — see [Vite 8 release notes](https://vitejs.dev/blog/announcing-vite8)):
```json
{
  "engines": { "node": ">=22.12.0" }
}
```
```

Replace with:
```
**Engines field to include in package.json** (use the Node version from `.claude/rules/vite-react.md` — the rules file is the single source of truth; e.g. `">=24"`):
```json
{
  "engines": { "node": ">=24" }
}
```
```

- [ ] **Step 9: Fix vite-react-scaffold Dockerfile ARG pins**

In `skills/vite-react-scaffold/SKILL.md`, find this exact block:
```
ARG NODE=node:24.14-alpine3.23
ARG NODE_BUILD=node:24.14-alpine3.23
ARG NGINX=nginx:1.28.2-alpine3.23
```

Replace with:
```
ARG NODE=node:24-alpine
ARG NODE_BUILD=node:24-alpine
ARG NGINX=nginx:1.28.2-alpine3.23
```

- [ ] **Step 10: Verify**

```bash
grep "Node.js" .claude/rules/nextjs.md .claude/rules/nestjs.md .claude/rules/vite-react.md
grep -n ">=22\|>=20\|24\.14\|22\." skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
```

Expected: three `Node.js ≥24` lines; zero matches from the second grep.

- [ ] **Step 11: Commit**

```bash
git add .claude/rules/nextjs.md .claude/rules/nestjs.md .claude/rules/vite-react.md \
  skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
git commit -m "fix(audit): enforce Node.js >=24 as SSOT across rules and scaffold output

- rules/{nextjs,nestjs,vite-react}.md: add/update Node.js >=24 in Stack lines
- {nextjs,nestjs,vite-react}-scaffold: engines.node >=24; Dockerfile ARG uses node:24-alpine
- scaffold instructions now reference rules file instead of hardcoding version"
```

---

### Task 2: Next.js 16 Correctness

**Goal:** Document async-only Next.js 16 Request APIs in code standards, and add the better-auth OIDC provider migration note to the auth skill.

**Files:**
- Modify: `skills/nextjs-code-standards/SKILL.md`
- Modify: `skills/nextjs-add-auth/SKILL.md`

**Acceptance Criteria:**
- [ ] `nextjs-code-standards/SKILL.md` Security section includes async-only Request API rule
- [ ] `nextjs-add-auth/SKILL.md` includes `@better-auth/oauth-provider` callout for OIDC

**Verify:**
```bash
grep "Request APIs\|await.*cookies\|await.*headers" skills/nextjs-code-standards/SKILL.md
grep "oauth-provider\|oidc-provider" skills/nextjs-add-auth/SKILL.md
```
Expected: one match each.

**Steps:**

- [ ] **Step 1: Add async Request API rule to nextjs-code-standards**

In `skills/nextjs-code-standards/SKILL.md`, find this exact block (end of Security section):
```
### Least Privilege
- Return only the fields the client needs — NEVER send full DB records to the browser
- NEVER log tokens, passwords, or PII
```

Replace with:
```
### Least Privilege
- Return only the fields the client needs — NEVER send full DB records to the browser
- NEVER log tokens, passwords, or PII

### Request APIs (Next.js 16)
- All Next.js Request APIs (`cookies()`, `headers()`, route `params`, and `searchParams`) return Promises in Next.js 16 — always `await` them. Sync access is a TypeScript error and runtime failure.
```

- [ ] **Step 2: Add OIDC provider note to nextjs-add-auth**

In `skills/nextjs-add-auth/SKILL.md`, find this exact line:
```
Full provider list: https://www.better-auth.com/docs/authentication/social-sign-on
```

Replace with:
```
Full provider list: https://www.better-auth.com/docs/authentication/social-sign-on

> **OIDC provider (token issuer)**: If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use `@better-auth/oauth-provider` — the `oidc-provider` plugin was removed in better-auth 1.6.
```

- [ ] **Step 3: Verify**

```bash
grep "Request APIs\|await.*cookies\|await.*headers" skills/nextjs-code-standards/SKILL.md
grep "oauth-provider\|oidc-provider" skills/nextjs-add-auth/SKILL.md
```

Expected: one match each.

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-code-standards/SKILL.md skills/nextjs-add-auth/SKILL.md
git commit -m "feat(audit): add Next.js 16 async Request API rule and better-auth OIDC note

- nextjs-code-standards: async-only rule for cookies(), headers(), params, searchParams
- nextjs-add-auth: note that @better-auth/oauth-provider replaces oidc-provider plugin (removed in 1.6)"
```

---

### Task 3: FastAPI and Drizzle Accuracy

**Goal:** Add `json=data` guidance to FastAPI code standards (strict Content-Type default), and add Drizzle v1 RC status callout to both database skills.

**Files:**
- Modify: `skills/fastapi-code-standards/SKILL.md`
- Modify: `skills/nextjs-add-database/SKILL.md`
- Modify: `skills/nestjs-add-database/SKILL.md`

**Acceptance Criteria:**
- [ ] `fastapi-code-standards/SKILL.md` Backend testing section notes `json=data` requirement
- [ ] `nextjs-add-database/SKILL.md` Section A includes Drizzle v1 RC callout
- [ ] `nestjs-add-database/SKILL.md` Section A includes Drizzle v1 RC callout

**Verify:**
```bash
grep "json=data" skills/fastapi-code-standards/SKILL.md
grep "release candidate\|drizzle.team" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
```
Expected: one match from first grep; two matches from second grep (one per file).

**Steps:**

- [ ] **Step 1: Add `json=data` guidance to fastapi-code-standards Backend testing**

In `skills/fastapi-code-standards/SKILL.md`, find this exact text:
```
## Backend testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `add-endpoint`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `pytest` from project root before handoff.
```

Replace with:
```
## Backend testing (mandatory)

Same-change pytest for new/changed routers, services, and API domain logic (`test/`, layout per `add-endpoint`). Prefer `TestClient` for HTTP; unit-test pure logic directly. Run `pytest` from project root before handoff.

Use `json=data` in test clients (not `content=json.dumps(data)`) — FastAPI requires `Content-Type: application/json` by default, and `json=` sets it automatically.
```

- [ ] **Step 2: Add Drizzle v1 RC note to nextjs-add-database**

In `skills/nextjs-add-database/SKILL.md`, find this exact line:
```
## Section A: Drizzle (SQL)
```

Replace with:
```
## Section A: Drizzle (SQL)

> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use.
```

- [ ] **Step 3: Add Drizzle v1 RC note to nestjs-add-database**

In `skills/nestjs-add-database/SKILL.md`, find this exact line:
```
## Section A: Drizzle (SQL)
```

Replace with:
```
## Section A: Drizzle (SQL)

> **Drizzle ORM version**: Drizzle ORM v1 is currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use.
```

- [ ] **Step 4: Verify**

```bash
grep "json=data" skills/fastapi-code-standards/SKILL.md
grep "release candidate\|drizzle.team" skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
```

Expected: one match from first grep; two matches from second grep.

- [ ] **Step 5: Commit**

```bash
git add skills/fastapi-code-standards/SKILL.md skills/nextjs-add-database/SKILL.md skills/nestjs-add-database/SKILL.md
git commit -m "feat(audit): add FastAPI json=data guidance and Drizzle v1 RC status note

- fastapi-code-standards: require json=data in test clients (strict Content-Type default)
- {nextjs,nestjs}-add-database: Drizzle ORM v1 is still in release candidate"
```

---

### Task 4: Vite 8 Accuracy

**Goal:** Add a note to vite-react-scaffold explaining that `@vitejs/plugin-react` v6 uses Oxc instead of Babel, so no Babel config or `@babel/core` is needed.

**Files:**
- Modify: `skills/vite-react-scaffold/SKILL.md`

**Acceptance Criteria:**
- [ ] `vite-react-scaffold/SKILL.md` Generation Conventions includes Oxc note for plugin-react v6
- [ ] No `babel.config.js` or `@babel/core` generated anywhere in the scaffold

**Verify:**
```bash
grep "Oxc\|oxc\|babel\|Babel" skills/vite-react-scaffold/SKILL.md
```
Expected: Oxc note present; no `babel.config` or `@babel/core` references.

**Steps:**

- [ ] **Step 1: Add Oxc note after package.json generation instruction**

In `skills/vite-react-scaffold/SKILL.md`, find this exact block:
```
**`package.json`** — generated file; use project name (lowercase kebab-case) as `"name"`. Use the dependency list above and the scripts block below. Set `"packageManager"` to the current pnpm version (`pnpm --version`).
```

Replace with:
```
**`package.json`** — generated file; use project name (lowercase kebab-case) as `"name"`. Use the dependency list above and the scripts block below. Set `"packageManager"` to the current pnpm version (`pnpm --version`).

> **`@vitejs/plugin-react` v6**: Uses Oxc for React Refresh transforms — no Babel config or `@babel/core` needed. To use the React Compiler, add `@rolldown/plugin-babel` with `reactCompilerPreset` instead of configuring Babel directly.
```

- [ ] **Step 2: Verify**

```bash
grep -n "Oxc\|oxc\|babel\.config\|@babel/core" skills/vite-react-scaffold/SKILL.md
```

Expected: Oxc note present; no `babel.config` or `@babel/core`.

- [ ] **Step 3: Commit**

```bash
git add skills/vite-react-scaffold/SKILL.md
git commit -m "feat(audit): add Oxc note for @vitejs/plugin-react v6 in vite-react-scaffold

plugin-react v6 (Vite 8) uses Oxc — no Babel config or @babel/core required"
```

---

### Task 5: Version Bump and CHANGELOG

**Goal:** Bump plugin version from `2.4.0` to `2.5.0` and record all Round 5 changes in `CHANGELOG.md`.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Blocked by:** Tasks 1, 2, 3, 4

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.5.0"`
- [ ] `CHANGELOG.md` has `[2.5.0]` entry dated 2026-05-07
- [ ] `grep -rn "node:24\.14\|>=22\|>=20\|>=18" skills/` returns zero output (no patch-pinned Node in scaffolds)

**Verify:**
```bash
grep '"version"' .claude-plugin/plugin.json && grep '\[2.5.0\]' CHANGELOG.md
```
Expected:
```
  "version": "2.5.0",
## [2.5.0] — 2026-05-07
```

**Steps:**

- [ ] **Step 1: Bump version in plugin.json**

In `.claude-plugin/plugin.json`, find:
```
"version": "2.4.0",
```

Replace with:
```
"version": "2.5.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

In `CHANGELOG.md`, find:
```
## [Unreleased]

---

## [2.4.0] — 2026-05-07
```

Replace with:
```
## [Unreleased]

---

## [2.5.0] — 2026-05-07

### Fixed
- **rules/nextjs.md**: Updated `Node.js ≥20.9.0` → `Node.js ≥24` — Next.js 16 minimum is Node 22, and Node 24 is Active LTS
- **rules/{nestjs,vite-react}.md**: Added `Node.js ≥24` to Stack lines — was missing entirely
- **{nextjs,nestjs,vite-react}-scaffold**: `engines.node` updated to `>=24`; Dockerfile ARG changed from patch-pinned `node:24.14-alpine3.23` to `node:24-alpine` — patch pins belong in CI/CD, not skill templates

### Added
- **nextjs-code-standards**: Async-only rule for Next.js 16 Request APIs (`cookies()`, `headers()`, `params`, `searchParams`) — sync access is a TypeScript error and runtime failure
- **nextjs-add-auth**: Callout that `@better-auth/oauth-provider` replaces the removed `oidc-provider` plugin (removed in better-auth 1.6)
- **fastapi-code-standards**: `json=data` test client guidance — FastAPI 0.132+ enforces `Content-Type: application/json` by default
- **{nextjs,nestjs}-add-database**: Drizzle ORM v1 RC status callout — not yet final stable release
- **vite-react-scaffold**: Oxc note for `@vitejs/plugin-react` v6 — no Babel config or `@babel/core` required

---

## [2.4.0] — 2026-05-07
```

- [ ] **Step 3: Final clean sweep**

```bash
grep -rn "node:24\.14\|>=22\|>=20\|>=18" skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
grep -rn "IM8" skills/ AGENTS.md .claude/
```

Expected: no output from either command.

- [ ] **Step 4: Verify version bump**

```bash
grep '"version"' .claude-plugin/plugin.json && grep '\[2.5.0\]' CHANGELOG.md
```

Expected:
```
  "version": "2.5.0",
## [2.5.0] — 2026-05-07
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump version to 2.5.0

Round 5 audit: Node.js >=24 SSOT, Next.js 16 async API rules, FastAPI Content-Type, Drizzle RC note, Vite 8 Oxc note."
```
