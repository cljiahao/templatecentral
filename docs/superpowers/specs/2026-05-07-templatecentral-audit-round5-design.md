# templateCentral Round 5 Audit — Design Spec

**Goal:** Enforce Node.js ≥24 as single source of truth across all rules and scaffold output, fix Next.js 16 async Request API compliance, correct FastAPI and Drizzle accuracy gaps, and update Vite 8 scaffold for the Babel-free plugin-react v6.

**Approach:** Four independent groups targeting disjoint file sets, followed by a version bump task. Same pattern as Rounds 3–4.

**Architecture:** Markdown-only changes across existing skill and rules files. No new files. No new abstractions.

---

## Context and Rationale

### Single source of truth for version pins

Established in Round 3: major version pins belong in `.claude/rules/*.md` only. Scaffold SKILL.md files must not hardcode runtime version numbers — they drift stale with no mechanism to update. When an agent runs a scaffold skill, it reads the rules file first and should derive the correct version from there. Scaffold instructions reference the rules; they do not duplicate them.

### No CVE identifiers, no patch-level pins

CVE tracking belongs in `shared-drift-check` Step 6 (dynamic `pnpm audit` / `pip-audit`). Skills document patterns; security advisories are a CI/runtime concern.

### No IM8 attribution

templateCentral is general-purpose across public and private sector internationally. Security guidance is valid industry practice regardless of regulatory framework.

---

## Group 1 — SSOT Node Cleanup

**Files:**
- Modify: `.claude/rules/nextjs.md`
- Modify: `.claude/rules/nestjs.md`
- Modify: `.claude/rules/vite-react.md`
- Modify: `skills/nextjs-scaffold/SKILL.md`
- Modify: `skills/nestjs-scaffold/SKILL.md`
- Modify: `skills/vite-react-scaffold/SKILL.md`

### Rules file changes

| File | Current | Change |
|------|---------|--------|
| `.claude/rules/nextjs.md` | `Node.js ≥20.9.0` | `Node.js ≥24` |
| `.claude/rules/nestjs.md` | No Node version in Stack line | Add `Node.js ≥24` |
| `.claude/rules/vite-react.md` | No Node version in Stack line | Add `Node.js ≥24` |

FastAPI rules are unchanged — Python stack, no Node dependency.

### Scaffold instruction changes

In `nextjs-scaffold/SKILL.md`, `nestjs-scaffold/SKILL.md`, and `vite-react-scaffold/SKILL.md`: wherever the scaffold currently specifies a hardcoded Node version in a Dockerfile, CI config, or `package.json` `engines` field, replace the literal version with a rules-reference instruction.

**Dockerfile pattern:**

Replace any literal `FROM node:XX-alpine` or `FROM node:XX-slim` with:

> "Base image: use the Node version from the stack's `.claude/rules/<stack>.md` with the `-alpine` variant for minimal image size (e.g. `FROM node:24-alpine`). When the stack rules Node version changes, update the rules file — not this scaffold."

**CI config pattern (GitHub Actions / similar):**

Replace any literal `node-version: 'XX'` with:

> "Node version: use the version specified in the stack rules file (e.g. `node-version: '24'`)."

**`package.json` engines pattern:**

Replace any literal `"node": ">=XX"` with:

> "`engines.node`: set to the minimum Node version from the stack rules (e.g. `">=24"`)."

**Result:** Future Node LTS bumps require touching only the three rules files. Nothing in scaffold SKILL.md files changes.

---

## Group 2 — Next.js 16 Correctness

**Files:**
- Audit + fix: `skills/nextjs-scaffold/SKILL.md`
- Audit + fix: `skills/nextjs-add-auth/SKILL.md`
- Audit + fix: `skills/nextjs-add-api-route/SKILL.md`
- Audit + fix: `skills/nextjs-add-feature/SKILL.md`
- Audit + fix: `skills/nextjs-add-page/SKILL.md`
- Modify: `skills/nextjs-code-standards/SKILL.md`

### 2a — Async Request API compliance

Next.js 16 removed all synchronous access to Request APIs. Any scaffolded code using the sync form will produce TypeScript errors and runtime failures.

**Required patterns in generated code:**

| Sync (broken in Next.js 16) | Async (correct) |
|-----------------------------|-----------------|
| `const cookieStore = cookies()` | `const cookieStore = await cookies()` |
| `const headersList = headers()` | `const headersList = await headers()` |
| `{ params }: { params: { slug: string } }` | `{ params }: { params: Promise<{ slug: string }> }` + `const { slug } = await params` |
| `{ searchParams }: { searchParams: { q: string } }` | `{ searchParams }: { searchParams: Promise<{ q: string }> }` + `const { q } = await searchParams` |

**Task:** Grep every `nextjs-*` SKILL.md for the sync patterns. Fix any instances found. All server components and route handlers that use these APIs must `await` them.

**`nextjs-code-standards/SKILL.md` addition:**

Add to the standards:

> "All Next.js Request APIs (`cookies()`, `headers()`, route `params`, and `searchParams`) return Promises in Next.js 16 — always `await` them. Sync access is a TypeScript error and runtime failure."

### 2b — better-auth `oidc-provider` removal note

The `oidc-provider` plugin was removed in better-auth 1.6 and replaced by `@better-auth/oauth-provider`. The templateCentral scaffold uses better-auth as an auth client (not an OIDC provider), so no code changes are needed. Add one callout in `skills/nextjs-add-auth/SKILL.md`:

> "If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use `@better-auth/oauth-provider` — the `oidc-provider` plugin was removed in better-auth 1.6."

No CVE reference, no version pin — package name change only.

---

## Group 3 — FastAPI and Drizzle Accuracy

**Files:**
- Audit + fix: `skills/fastapi-add-test/SKILL.md`
- Audit + fix: `skills/fastapi-scaffold/SKILL.md`
- Modify: `skills/fastapi-code-standards/SKILL.md`
- Audit + fix: `skills/nextjs-add-database/SKILL.md`
- Audit + fix: `skills/nestjs-add-database/SKILL.md`

### 3a — FastAPI strict Content-Type

FastAPI 0.132 made `strict_content_type=True` the default. Endpoints that accept JSON bodies now return 415 for requests missing `Content-Type: application/json`. Tests using `httpx` with `json=data` are already correct (httpx sets the header automatically). The risk is test helpers or curl examples using `content=json.dumps(data)` without the explicit header.

**Task:** Grep `fastapi-add-test/SKILL.md` and `fastapi-scaffold/SKILL.md` for `content=` calls and bare curl examples. Fix any missing `Content-Type` headers. Add to `fastapi-code-standards/SKILL.md`:

> "Always use `json=data` in test clients (not `content=json.dumps(data)`) — FastAPI requires `Content-Type: application/json` by default, and `json=` sets it automatically."

### 3b — Drizzle v1 RC status

Drizzle ORM v1.0.0 is still in RC (not yet final stable release). Any language calling it "stable v1" is inaccurate.

**Task:** Grep `nextjs-add-database/SKILL.md` and `nestjs-add-database/SKILL.md` for "stable v1" or "v1.0 stable" language. Replace with:

> "Drizzle ORM v1 (currently in release candidate — verify stable release at [drizzle.team](https://drizzle.team) before production use)."

Also audit for `drizzle-zod` package imports — in Drizzle v1, the `drizzle-zod` standalone package is deprecated. Import from `drizzle-orm/zod` instead:

```ts
// Deprecated
import { createInsertSchema } from 'drizzle-zod'

// Correct (Drizzle v1+)
import { createInsertSchema } from 'drizzle-orm/zod'
```

If either database skill still generates `drizzle-zod` imports, correct them.

---

## Group 4 — Vite 8 Accuracy

**Files:**
- Audit + fix: `skills/vite-react-scaffold/SKILL.md`

### `@vitejs/plugin-react` v6 — Babel removal

`@vitejs/plugin-react` v6 (the version used with Vite 8) replaced Babel with Oxc for React Refresh transforms. Babel is no longer a dependency.

**Task 1:** If the scaffold generates a `babel.config.js` or includes `@babel/core` in `devDependencies`, remove both.

**Task 2:** If the scaffold generates a `vite.config.ts` that imports `viteTsconfigPaths()` from `vite-tsconfig-paths`, replace with the Vite 8 built-in:

```ts
// Remove: import viteTsconfigPaths from 'vite-tsconfig-paths'
// Replace with built-in resolve option:
resolve: {
  tsconfigPaths: true,
}
```

**Task 3:** Add to the scaffold setup notes:

> "`@vitejs/plugin-react` v6 uses Oxc — no Babel config or `@babel/core` needed. To use the React Compiler, add `@rolldown/plugin-babel` with `reactCompilerPreset` instead of configuring Babel directly."

---

## Group 5 — Version Bump and CHANGELOG

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

Bump version from `2.4.0` to `2.5.0`. Add `[2.5.0]` entry dated 2026-05-07 covering all four groups.

---

## What Is Not Changing

- No IM8 labels added anywhere
- No CVE identifiers hardcoded
- No patch-level version pins in skill files
- No AI-DLC references
- No changes to pnpm version (staying on pnpm 10)
- FastAPI Python version references unchanged (already accurate)
- NestJS 12 not referenced (not yet released; Q3 2026 target)

---

## Acceptance Criteria

- [ ] `.claude/rules/nextjs.md`, `.claude/rules/nestjs.md`, `.claude/rules/vite-react.md` all reference `Node.js ≥24`
- [ ] No hardcoded `node:20`, `node:22`, or `node:18` literals in scaffold SKILL.md files
- [ ] No sync `cookies()`, `headers()`, `params`, `searchParams` in any `nextjs-*` SKILL.md
- [ ] `nextjs-code-standards/SKILL.md` notes async-only Request APIs
- [ ] `nextjs-add-auth/SKILL.md` notes `@better-auth/oauth-provider` for OIDC
- [ ] `fastapi-code-standards/SKILL.md` notes `json=data` for test clients
- [ ] No `drizzle-zod` package imports in any database skill
- [ ] No "stable v1" Drizzle language in database skills
- [ ] `vite-react-scaffold/SKILL.md` references Oxc-based plugin-react; no Babel config generated
- [ ] `vite-react-scaffold/SKILL.md` uses `resolve.tsconfigPaths: true` instead of `vite-tsconfig-paths` plugin
- [ ] `plugin.json` version is `2.5.0`
- [ ] CHANGELOG has `[2.5.0]` entry dated 2026-05-07
- [ ] `grep -rn "IM8" skills/ AGENTS.md .claude/` returns zero output
