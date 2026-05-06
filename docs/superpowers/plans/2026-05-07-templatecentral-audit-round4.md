# templateCentral Round 4 Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix drifting version pins, fill missing version constraints in rules files, and add security guidance current for May 2026.

**Architecture:** Markdown-only edits across 8 existing files. No new files. No new abstractions. Task 1 (cleanup) and Task 2 (additions) are independent and can run in any order; Task 3 (version bump) must follow both.

**Tech Stack:** Markdown, `.claude/rules/*.md`, `skills/**/*.md`, `AGENTS.md`, `CHANGELOG.md`.

---

### Task 1: Version Cleanup

**Goal:** Remove one drifting patch-level version pin and tighten two rules files with missing version constraints.

**Files:**
- Modify: `AGENTS.md` (line 117)
- Modify: `.claude/rules/nextjs.md` (line 8)
- Modify: `.claude/rules/fastapi.md` (line 3)
- Modify: `skills/fastapi-add-auth/SKILL.md` (line 276)

**Acceptance Criteria:**
- [ ] `AGENTS.md` contains no `16.2.4` or `15.5.9` strings
- [ ] `.claude/rules/nextjs.md` Stack line includes `Node.js ≥20.9.0`
- [ ] `.claude/rules/fastapi.md` Stack line reads `Pydantic ≥2.9.0` and includes `Starlette 1.0`
- [ ] `skills/fastapi-add-auth/SKILL.md` contains no `slowapi>=` string

**Verify:** `grep -n "16\.2\.4\|15\.5\.9\|slowapi>=\|Pydantic v2" AGENTS.md .claude/rules/fastapi.md skills/fastapi-add-auth/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Remove patch-level Next.js pin from AGENTS.md**

Find this exact line in `AGENTS.md` (line 117):
```
- **Next.js**: Always keep `next` on a current version — critical security patches release regularly. Minimum safe: **16.2.4+** or **15.5.9+** (15.x). Run `shared-update-agent` to keep it current.
```

Replace with:
```
- **Next.js**: Always keep `next` on a current version — critical security patches release regularly. Run `shared-update-agent` to keep it current.
```

- [ ] **Step 2: Add Node.js ≥20.9.0 to nextjs rules Stack line**

Find this exact line in `.claude/rules/nextjs.md` (line 8):
```
Stack: Next.js 16, React 19, TypeScript 6, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `nextjs-add-auth` skill (better-auth). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

Replace with:
```
Stack: Next.js 16, React 19, TypeScript 6, Node.js ≥20.9.0, shadcn/ui (new-york), Tailwind CSS 4, TanStack Query, React Hook Form + Zod. Auth added via `nextjs-add-auth` skill (better-auth). Package manager: **pnpm** (pinned in `packageManager` field — do not use npm or yarn).
```

- [ ] **Step 3: Update Pydantic version and add Starlette to fastapi rules Stack line**

Find this exact line in `.claude/rules/fastapi.md` (line 3):
```
Stack: FastAPI 0.136+, Python 3.13, Pydantic v2 (camelCase schemas), Uvicorn, Ruff, pytest, Docker.
```

Replace with:
```
Stack: FastAPI 0.136+, Python 3.13, Pydantic ≥2.9.0 (camelCase schemas), Starlette 1.0, Uvicorn, Ruff, pytest, Docker.
```

- [ ] **Step 4: Remove slowapi version pin from fastapi-add-auth**

Find this exact line in `skills/fastapi-add-auth/SKILL.md` (line 276):
```
Industry best practice: max 3 failed auth attempts per 15 minutes. Add `slowapi>=0.1.9` to `requirements.txt`, then:
```

Replace with:
```
Industry best practice: max 3 failed auth attempts per 15 minutes. Add `slowapi` to `requirements.txt`, then:
```

- [ ] **Step 5: Verify**

Run: `grep -n "16\.2\.4\|15\.5\.9\|slowapi>=\|Pydantic v2" AGENTS.md .claude/rules/fastapi.md skills/fastapi-add-auth/SKILL.md`

Expected: no output

Also verify the additions landed correctly:
```bash
grep "Node.js" .claude/rules/nextjs.md
grep "Pydantic ≥2.9.0\|Starlette 1.0" .claude/rules/fastapi.md
```
Expected: one match each.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md .claude/rules/nextjs.md .claude/rules/fastapi.md skills/fastapi-add-auth/SKILL.md
git commit -m "fix(audit): remove drifting version pins and tighten rules constraints

- AGENTS.md: remove patch-level Next.js 16.2.4/15.5.9 pin (policy violation)
- rules/nextjs.md: add Node.js >=20.9.0 (Next.js 16 minimum, was missing)
- rules/fastapi.md: Pydantic v2 -> >=2.9.0, add Starlette 1.0
- fastapi-add-auth: remove slowapi>=0.1.9 version pin (policy violation)"
```

---

### Task 2: Security Additions

**Goal:** Add four security guidance updates current for May 2026 — OWASP A03/A10:2025, better-auth v1.6 session behavior, and AWS Responsible AI Lens.

**Files:**
- Modify: `AGENTS.md` (supply chain section, line ~123)
- Modify: `skills/shared-add-error-handling/SKILL.md` (Security Checklist, line ~32)
- Modify: `skills/nextjs-add-auth/SKILL.md` (after session config block, line ~136)
- Modify: `skills/shared-add-ai-security/SKILL.md` (before Rules section, line ~309)

**Acceptance Criteria:**
- [ ] `AGENTS.md` supply chain section references OWASP A03:2025
- [ ] `skills/shared-add-error-handling/SKILL.md` Security Checklist has OWASP A10:2025 bullet
- [ ] `skills/nextjs-add-auth/SKILL.md` has better-auth `freshAge` callout near session config
- [ ] `skills/shared-add-ai-security/SKILL.md` has AWS Responsible AI Lens section with all 10 dimensions

**Verify:**
```bash
grep "A03:2025" AGENTS.md
grep "A10:2025" skills/shared-add-error-handling/SKILL.md
grep "freshAge" skills/nextjs-add-auth/SKILL.md
grep "Responsible AI Lens" skills/shared-add-ai-security/SKILL.md
```
→ one match each

**Steps:**

- [ ] **Step 1: Add OWASP A03:2025 framing to AGENTS.md supply chain section**

Find this exact text in `AGENTS.md` (line 123):
```
## Supply chain & reproducibility

- **Node projects**:
```

Replace with:
```
## Supply chain & reproducibility

Supply chain attacks are OWASP A03:2025 — the third most critical web application risk category. Maintain an SBOM and run `pnpm audit` / `pip-audit` in CI on every dependency update.

- **Node projects**:
```

- [ ] **Step 2: Add OWASP A10:2025 bullet to shared-add-error-handling Security Checklist**

Find this exact line in `skills/shared-add-error-handling/SKILL.md` (line 32 — last bullet in Security Checklist):
```
- [ ] **Environment-based detail levels** — Development: include stack traces; Production: generic messages only
```

Replace with:
```
- [ ] **Environment-based detail levels** — Development: include stack traces; Production: generic messages only
- [ ] **Unhandled exceptions (OWASP A10:2025)** — Never let exceptions surface raw to clients — stack traces and internal messages are an OWASP A10:2025 violation. All error handlers must return generic user-facing messages; log full detail server-side only
```

- [ ] **Step 3: Add better-auth freshAge callout to nextjs-add-auth**

The session config block closes at line 135 with `` ``` `` followed by a blank line, then the Database note at line 138. Find this exact text in `skills/nextjs-add-auth/SKILL.md`:

```
  plugins: [nextCookies()], // must be last
});
```

(end of the auth config code block). The text immediately after the closing fence is:

```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions
```

Find this exact string:
```
> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Adapters for Drizzle and Kysely are available — see [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

Replace with:
```
> **better-auth ≥1.6**: `freshAge` is measured from session `createdAt`, not last activity. If you set a short `freshAge` (e.g. 43200 for AAL2 flows), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.

> **Database**: By default, better-auth uses stateless JWE-encrypted cookie sessions — no database required. For production features (session revocation, multi-device logout, audit logs), add a database adapter after running `nextjs-add-database`. Adapters for Drizzle and Kysely are available — see [better-auth database docs](https://www.better-auth.com/docs/concepts/database).
```

- [ ] **Step 4: Add AWS Responsible AI Lens section to shared-add-ai-security**

Find this exact text in `skills/shared-add-ai-security/SKILL.md` (line 309):
```
## Rules

- Apply controls proportional to capability: A (simple) needs LLM01, 02, 05, 10; B (RAG) adds LLM08; C (agentic) adds LLM06
```

Replace with:
```
## AWS Responsible AI Lens

The AWS Responsible AI Lens (re:Invent 2025) defines 10 dimensions for evaluating production AI systems. Use it alongside OWASP LLM Top 10 for pre-launch reviews:

- **Controllability** — ability to override, retrain, or shut down the model
- **Privacy** — data minimization, consent, and PII handling
- **Security** — prompt injection, adversarial input, model extraction defense
- **Safety** — preventing harmful outputs across user populations
- **Veracity** — factual accuracy, hallucination detection, grounding
- **Robustness** — performance under distribution shift and edge inputs
- **Fairness** — equitable outcomes across demographic groups
- **Explainability** — traceability from input to output decision
- **Transparency** — disclosure of AI involvement to end users
- **Governance** — audit trails, policy enforcement, accountability

No single framework covers everything — OWASP LLM Top 10 focuses on attack vectors; the Responsible AI Lens focuses on systemic trustworthiness. Run both checklists before shipping AI features to production.

## Rules

- Apply controls proportional to capability: A (simple) needs LLM01, 02, 05, 10; B (RAG) adds LLM08; C (agentic) adds LLM06
```

- [ ] **Step 5: Verify all four additions**

```bash
grep "A03:2025" AGENTS.md
grep "A10:2025" skills/shared-add-error-handling/SKILL.md
grep "freshAge" skills/nextjs-add-auth/SKILL.md
grep "Responsible AI Lens" skills/shared-add-ai-security/SKILL.md
```

Expected: one match per command.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md skills/shared-add-error-handling/SKILL.md skills/nextjs-add-auth/SKILL.md skills/shared-add-ai-security/SKILL.md
git commit -m "feat(audit): add May 2026 security guidance updates

- AGENTS.md: add OWASP A03:2025 supply chain framing
- shared-add-error-handling: add OWASP A10:2025 unhandled exceptions checklist item
- nextjs-add-auth: add better-auth >=1.6 freshAge behavioral note
- shared-add-ai-security: add AWS Responsible AI Lens (10 dimensions)"
```

---

### Task 3: Version Bump and CHANGELOG

**Goal:** Bump plugin version to 2.4.0 and record Round 4 changes in CHANGELOG.md.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.4.0"`
- [ ] CHANGELOG has `[2.4.0]` entry dated 2026-05-07
- [ ] Final `grep -rn "16\.2\.4\|15\.5\.9\|slowapi>=\|IM8" skills/ AGENTS.md .claude/` returns zero output

**Verify:** `grep '"version"' .claude-plugin/plugin.json && grep '\[2.4.0\]' CHANGELOG.md` → both return a match

**Steps:**

- [ ] **Step 1: Bump version in plugin.json**

Find in `.claude-plugin/plugin.json`:
```
"version": "2.3.0",
```

Replace with:
```
"version": "2.4.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

Find in `CHANGELOG.md`:
```
## [Unreleased]

---

## [2.3.0] — 2026-05-06
```

Replace with:
```
## [Unreleased]

---

## [2.4.0] — 2026-05-07

### Fixed
- **AGENTS.md**: Removed drifting patch-level Next.js version pin (`16.2.4+` / `15.5.9+`) — major version pins belong in `.claude/rules/*.md` only
- **rules/fastapi.md**: Tightened `Pydantic v2` to `Pydantic ≥2.9.0`; added `Starlette 1.0` to Stack line
- **rules/nextjs.md**: Added `Node.js ≥20.9.0` to Stack line — Next.js 16 dropped Node 18 support
- **fastapi-add-auth**: Removed `slowapi>=0.1.9` patch-level version pin (CVE policy violation)

### Added
- **AGENTS.md**: OWASP A03:2025 Supply Chain framing in supply chain section — supply chain attacks rose to #3 in 2025 ranking
- **shared-add-error-handling**: OWASP A10:2025 Mishandling Exceptional Conditions added to Security Checklist
- **nextjs-add-auth**: better-auth ≥1.6 `freshAge` behavioral note — `freshAge` now measures from `createdAt` not last activity
- **shared-add-ai-security**: AWS Responsible AI Lens section (re:Invent 2025) with all 10 dimensions — complements OWASP LLM Top 10

---

## [2.3.0] — 2026-05-06
```

- [ ] **Step 3: Final clean sweep**

Run the full IM8 + version pin grep to confirm zero violations:

```bash
grep -rn "IM8" skills/ AGENTS.md .claude/
grep -rn "16\.2\.4\|15\.5\.9\|slowapi>=" skills/ AGENTS.md
```

Expected: no output from either command.

- [ ] **Step 4: Verify version bump**

```bash
grep '"version"' .claude-plugin/plugin.json && grep '\[2.4.0\]' CHANGELOG.md
```

Expected:
```
  "version": "2.4.0",
## [2.4.0] — 2026-05-07
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump version to 2.4.0

Round 4 audit: version pin cleanup and May 2026 security guidance additions."
```
