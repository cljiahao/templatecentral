# templateCentral Round 2 Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Vite 8 + React Router v7.15 breaking changes and close remaining IM8 security documentation gaps across templateCentral's skill files.

**Architecture:** Two independent task groups — (1) version pin corrections in vite-react-scaffold, (2) one-line IM8 compliance notes added to six files. No new files created. FastAPI files were pre-audited and confirmed correct (already use `json=payload`; no changes needed).

**Tech Stack:** Markdown skill files only — no code compilation required. Verification via `grep`.

---

## Pre-verified: FastAPI Content-Type

Both `skills/fastapi-add-test/SKILL.md` and `skills/fastapi-add-endpoint/SKILL.md` already use `client.post(url, json=payload)` throughout. No changes needed. The `.claude/rules/fastapi.md` confirms the stack targets FastAPI 0.136+ (Content-Type enforcement already accounted for).

---

### Task 1: Vite 8 + React Router v7.15 version pins

**Goal:** Update `vite-react-scaffold/SKILL.md` to pin `@vitejs/plugin-react@^6.0.0` and bump the React Router floor to `^7.15.0`.

**Files:**
- Modify: `skills/vite-react-scaffold/SKILL.md:23` (react-router version)
- Modify: `skills/vite-react-scaffold/SKILL.md:27` (plugin-react version pin)

**Acceptance Criteria:**
- [ ] `react-router@^7.15.0` appears on the pnpm add line (was `^7.14.2`)
- [ ] `@vitejs/plugin-react@^6.0.0` appears on the pnpm add -D line (was unpinned)
- [ ] No other changes to the file

**Verify:**
```bash
grep -n "react-router\|plugin-react" skills/vite-react-scaffold/SKILL.md | grep "pnpm add"
```
Expected output:
```
23:pnpm add react react-dom react-router@^7.15.0 @tanstack/react-query \
27:pnpm add -D vite @vitejs/plugin-react@^6.0.0 typescript \
```

**Steps:**

- [ ] **Step 1: Edit line 23 — react-router version bump**

In `skills/vite-react-scaffold/SKILL.md`, change:
```
pnpm add react react-dom react-router@^7.14.2 @tanstack/react-query \
```
to:
```
pnpm add react react-dom react-router@^7.15.0 @tanstack/react-query \
```

- [ ] **Step 2: Edit line 27 — add plugin-react version pin**

In `skills/vite-react-scaffold/SKILL.md`, change:
```
pnpm add -D vite @vitejs/plugin-react typescript \
```
to:
```
pnpm add -D vite @vitejs/plugin-react@^6.0.0 typescript \
```

- [ ] **Step 3: Verify**

```bash
grep -n "react-router\|plugin-react" skills/vite-react-scaffold/SKILL.md | grep "pnpm add"
```
Expected: lines 23 and 27 match the values above. No other lines changed.

- [ ] **Step 4: Commit**

```bash
git add skills/vite-react-scaffold/SKILL.md
git commit -m "fix(vite-react): pin @vitejs/plugin-react@^6.0.0 and react-router@^7.15.0"
```

---

### Task 2: IM8 security documentation gaps

**Goal:** Add seven targeted one-line notes across six files — AS-6 hashing preference, LM-1 log isolation, AS-12 file upload scanning, and AS-8 secrets vault (four scaffold AGENTS.md templates).

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md:537` (after last Security Rules bullet)
- Modify: `skills/shared-add-logging/SKILL.md:856` (before `## Validate`)
- Modify: `AGENTS.md:120` (after last Security & secrets bullet)
- Modify: `skills/nextjs-scaffold/SKILL.md:2550` (after "No secrets in code" bullet in generated AGENTS.md template)
- Modify: `skills/fastapi-scaffold/SKILL.md:1765` (after "No secrets in code" bullet in generated AGENTS.md template)
- Modify: `skills/nestjs-scaffold/SKILL.md:1486` (after "No secrets in code" bullet in generated AGENTS.md template)
- Modify: `skills/vite-react-scaffold/SKILL.md:2992` (after "No secrets in code" bullet in generated AGENTS.md template)

**Acceptance Criteria:**
- [ ] `nextjs-add-auth` Security Rules section mentions Argon2id and IM8 AS-6
- [ ] `shared-add-logging` mentions LM-1 and log isolation to a separate system
- [ ] `AGENTS.md` root Security & secrets section mentions IM8 AS-12 and malware scanning for file uploads
- [ ] All four scaffold skills' generated AGENTS.md templates mention IM8 AS-8 and secrets vault

**Verify:**
```bash
grep -n "AS-6\|Argon2id" skills/nextjs-add-auth/SKILL.md
grep -n "LM-1\|CloudWatch" skills/shared-add-logging/SKILL.md
grep -n "AS-12\|malware" AGENTS.md
grep -rn "AS-8\|Secrets Manager" skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
```
Expected: each grep returns at least one match.

**Steps:**

- [ ] **Step 1: nextjs-add-auth — IM8 AS-6 hashing note**

In `skills/nextjs-add-auth/SKILL.md`, find the `## Security Rules` section. After the line:
```
- **Rate limiting is mandatory for production** — add rate limiting on auth endpoints before going live (IM8 AS-4).
```
Add:
```
- **Password hashing (IM8 AS-6)**: better-auth uses bcrypt by default (acceptable). For any custom hashing outside better-auth, prefer Argon2id (`argon2` package) — ranked above bcrypt by OWASP and IM8 AS-6.
```

- [ ] **Step 2: shared-add-logging — IM8 LM-1 log isolation note**

In `skills/shared-add-logging/SKILL.md`, find the `## See Also` section (lines 850–854). After the last `See Also` bullet and before `## Validate`, add a new section:

```markdown
## Production Requirement (IM8 LM-1)

Ship logs to a separate, tamper-evident system (e.g. AWS CloudWatch, Datadog, OpenSearch Ingestion) — writing to local disk only does not satisfy IM8 LM-1, which requires log storage isolated from the application host.
```

- [ ] **Step 3: AGENTS.md root — IM8 AS-12 file upload scanning**

In `AGENTS.md`, in the `## Security & secrets` section, after the line:
```
- Follow each stack's `code-standards` for auth, env vars, and least-privilege responses.
```
Add:
```
- **File uploads (IM8 AS-12)**: Scan uploaded files for malware (ClamAV or a cloud scanning service such as AWS GuardDuty Malware Protection) before writing to storage.
```

- [ ] **Step 4: nextjs-scaffold — IM8 AS-8 secrets vault note in generated AGENTS.md template**

In `skills/nextjs-scaffold/SKILL.md`, find the generated AGENTS.md template block. After the line:
```
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.
```
Add:
```
- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat `.env` files are for local development only.
```

- [ ] **Step 5: fastapi-scaffold — IM8 AS-8 secrets vault note in generated AGENTS.md template**

In `skills/fastapi-scaffold/SKILL.md`, find the generated AGENTS.md template block. After the line:
```
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.
```
Add:
```
- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat `.env` / `.env.default` files are for local development only.
```

- [ ] **Step 6: nestjs-scaffold — IM8 AS-8 secrets vault note in generated AGENTS.md template**

In `skills/nestjs-scaffold/SKILL.md`, find the generated AGENTS.md template block. After the line:
```
- **No secrets in code** — No tokens, passwords, or keys hardcoded. Use env vars; document in `.env.example`.
```
Add:
```
- **Secrets in production (IM8 AS-8)**: Use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Flat `.env` files are for local development only.
```

- [ ] **Step 7: vite-react-scaffold — IM8 AS-8 secrets vault note in generated AGENTS.md template**

In `skills/vite-react-scaffold/SKILL.md`, find the generated AGENTS.md template block. After the line:
```
- **No secrets in code** — No tokens, passwords, or keys in `VITE_*` or any client file. Use server-side or proxy.
```
Add:
```
- **Secrets in production (IM8 AS-8)**: Backend secrets must use AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager in production. Never put backend secrets in `VITE_*` env vars or any client-side code.
```

- [ ] **Step 8: Verify all changes**

```bash
grep -n "AS-6\|Argon2id" skills/nextjs-add-auth/SKILL.md
grep -n "LM-1\|CloudWatch" skills/shared-add-logging/SKILL.md
grep -n "AS-12\|malware" AGENTS.md
grep -rn "AS-8\|Secrets Manager" skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
```
Each grep must return at least one result.

- [ ] **Step 9: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md skills/shared-add-logging/SKILL.md AGENTS.md \
  skills/nextjs-scaffold/SKILL.md skills/fastapi-scaffold/SKILL.md \
  skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
git commit -m "docs(im8): add AS-6/AS-8/AS-12/LM-1 compliance notes across skills"
```

---

### Task 3: Version bump and CHANGELOG

**Goal:** Bump plugin version to 2.3.0 and record Round 2 changes in CHANGELOG.md.

**Files:**
- Modify: `.claude-plugin/plugin.json` (version field)
- Modify: `CHANGELOG.md` (new [2.3.0] entry)

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.3.0"`
- [ ] CHANGELOG has a `[2.3.0]` entry dated 2026-05-06 covering both task groups

**Verify:**
```bash
grep '"version"' .claude-plugin/plugin.json
grep '\[2.3.0\]' CHANGELOG.md
```
Expected: both return a match.

**Steps:**

- [ ] **Step 1: Bump plugin.json version**

In `.claude-plugin/plugin.json`, change:
```json
"version": "2.2.0",
```
to:
```json
"version": "2.3.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

In `CHANGELOG.md`, add a new `[2.3.0]` entry after `[Unreleased]` and before `[2.2.0]`:

```markdown
## [2.3.0] — 2026-05-06

### Fixed
- **Vite+React scaffold**: Pinned `@vitejs/plugin-react@^6.0.0` (Oxc-based transforms, replaces Babel) and bumped `react-router` floor to `^7.15.0` (stable API release — `unstable_*` prefixes removed upstream)

### Added
- **nextjs-add-auth**: IM8 AS-6 note — Argon2id preferred over bcrypt for custom hashing outside better-auth
- **shared-add-logging**: IM8 LM-1 requirement — production logs must ship to a separate tamper-evident system
- **AGENTS.md**: IM8 AS-12 note — file uploads require malware scanning before storage
- **All scaffold skills**: IM8 AS-8 note added to generated project `AGENTS.md` templates — secrets vault required in production
```

- [ ] **Step 3: Verify**

```bash
grep '"version"' .claude-plugin/plugin.json
grep '\[2.3.0\]' CHANGELOG.md
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump to 2.3.0"
```
