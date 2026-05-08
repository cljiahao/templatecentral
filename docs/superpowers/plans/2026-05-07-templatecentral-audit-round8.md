# templateCentral Round 8 Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close five accuracy and policy gaps identified in the Round 8 fresh-eyes audit across templateCentral's skills.

**Architecture:** Targeted text edits to SKILL.md files only — no new files, no structural changes. Each task is self-contained and grep-verified.

**Tech Stack:** templateCentral plugin (SKILL.md markdown files), plugin.json, CHANGELOG.md

---

## File Map

| File | Task | Change |
|------|------|--------|
| `skills/fastapi-scaffold/SKILL.md` | 1 | Remove `Asia/Singapore` timezone + `tzdata` from apt |
| `skills/nextjs-scaffold/SKILL.md` | 1 | Remove `Asia/Singapore` + `tzdata` + COPY localtime/timezone lines |
| `skills/nestjs-scaffold/SKILL.md` | 1 | Same as nextjs-scaffold |
| `skills/vite-react-scaffold/SKILL.md` | 1 | Remove `Asia/Singapore` + `tzdata` |
| `skills/shared-add-ai-security/SKILL.md` | 2 | Replace `gpt-4o-2024-11-20` with annotated placeholder |
| `skills/nextjs-add-auth/SKILL.md` | 3 | Remove `better-auth ≥1.6` and `better-auth 1.6` version markers |
| `skills/fastapi-scaffold/SKILL.md` | 4 | `python-json-logger>=3.3.0,<4.0` → `python-json-logger>=4.0` (×2) |
| `skills/shared-add-logging/SKILL.md` | 4 | Same (×1) |
| `.claude-plugin/plugin.json` | 5 | `2.7.0` → `2.8.0` |
| `CHANGELOG.md` | 5 | New `[2.8.0]` entry |

---

### Task 1: Singapore Timezone Removal

**Goal:** Remove hardcoded `Asia/Singapore` timezone from all four scaffold Dockerfiles so containers default to UTC.

**Files:**
- Modify: `skills/fastapi-scaffold/SKILL.md` (lines 174–176)
- Modify: `skills/nextjs-scaffold/SKILL.md` (lines 310–313, 364–365)
- Modify: `skills/nestjs-scaffold/SKILL.md` (lines 184–187, 258, 261–262)
- Modify: `skills/vite-react-scaffold/SKILL.md` (lines 253–256)

**Acceptance Criteria:**
- [ ] No `Asia/Singapore` remains in any skill file
- [ ] `tzdata` is removed from apt/apk install commands in all four scaffolds
- [ ] COPY lines for `/etc/localtime` and `/etc/timezone` removed from nextjs-scaffold and nestjs-scaffold final stages
- [ ] Each scaffold retains a `# TZ defaults to UTC` comment

**Verify:** `grep "Asia/Singapore" skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Verify current state**

Run: `grep -n "Asia/Singapore\|tzdata" skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md`

Expected: matches on all four files showing `Asia/Singapore` and `tzdata`

- [ ] **Step 2: Update fastapi-scaffold (Debian/apt)**

In `skills/fastapi-scaffold/SKILL.md`, find lines 165–181:

```
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR ${APP_DIR}

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends tzdata dumb-init \
    && ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && groupadd -g ${APP_GID} ${APP_GROUPNAME} \
```

Replace with:

```
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
# TZ defaults to UTC — override via TZ env var in your deploy config if needed

WORKDIR ${APP_DIR}

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends dumb-init \
    && groupadd -g ${APP_GID} ${APP_GROUPNAME} \
```

- [ ] **Step 3: Update nextjs-scaffold (Alpine)**

In `skills/nextjs-scaffold/SKILL.md`, find lines 306–315:

```
ENV NEXT_TELEMETRY_DISABLED=1

WORKDIR ${APP_DIR}

RUN apk add --no-cache tzdata dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && cp /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

Replace with:

```
ENV NEXT_TELEMETRY_DISABLED=1
# TZ defaults to UTC — override via TZ env var in your deploy config if needed

WORKDIR ${APP_DIR}

RUN apk add --no-cache dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

Then find lines 364–365 (in the final production stage COPY block):

```
COPY --from=base /etc/localtime /etc/localtime
COPY --from=base /etc/timezone /etc/timezone
```

Delete both lines entirely.

- [ ] **Step 4: Update nestjs-scaffold (Alpine)**

In `skills/nestjs-scaffold/SKILL.md`, find lines 184–189:

```
RUN apk add --no-cache tzdata dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && cp /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

Replace with:

```
# TZ defaults to UTC — override via TZ env var in your deploy config if needed
RUN apk add --no-cache dumb-init ca-certificates \
    && apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

Then find line 258:

```
# OS-level setup from the Alpine base stage (user, timezone, certs, dumb-init)
```

Replace with:

```
# OS-level setup from the Alpine base stage (user, certs, dumb-init)
```

Then find lines 261–262 (in the final production stage COPY block):

```
COPY --from=base /etc/localtime /etc/localtime
COPY --from=base /etc/timezone /etc/timezone
```

Delete both lines entirely.

- [ ] **Step 5: Update vite-react-scaffold (Alpine)**

In `skills/vite-react-scaffold/SKILL.md`, find lines 253–258:

```
RUN apk add --no-cache tzdata \
    && apk upgrade --no-cache \
    && cp /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

Replace with:

```
# TZ defaults to UTC — override via TZ env var in your deploy config if needed
RUN apk upgrade --no-cache \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}
```

- [ ] **Step 6: Verify**

Run: `grep "Asia/Singapore" skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md`

Expected: no output

Run: `grep "tzdata" skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md`

Expected: no output

Run: `grep "TZ defaults to UTC" skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md`

Expected: one match per file

- [ ] **Step 7: Commit**

```bash
git add skills/fastapi-scaffold/SKILL.md skills/nextjs-scaffold/SKILL.md skills/nestjs-scaffold/SKILL.md skills/vite-react-scaffold/SKILL.md
git commit -m "fix(audit): remove hardcoded Asia/Singapore timezone from all scaffold Dockerfiles — containers default to UTC"
```

---

### Task 2: Model Snapshot Version Pin

**Goal:** Replace the literal `gpt-4o-2024-11-20` model snapshot in `shared-add-ai-security` with a placeholder-annotated example that preserves the teaching point without encoding a drifting date.

**Files:**
- Modify: `skills/shared-add-ai-security/SKILL.md` (lines 132–136, 264–265)

**Acceptance Criteria:**
- [ ] No `gpt-4o-2024-11-20` remains in the file
- [ ] LLM03 bad example updated from `'gpt-4'` to `'gpt-4o'`
- [ ] Both occurrences replaced with `gpt-4o-2024-08-06` annotated `// example only — use your provider's current snapshot`

**Verify:** `grep "2024-11-20" skills/shared-add-ai-security/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Update LLM03 section**

In `skills/shared-add-ai-security/SKILL.md`, find lines 131–137:

```
```ts
// ❌ Never
const model = 'gpt-4';

// ✅ Always
const model = 'gpt-4o-2024-11-20';  // pinned snapshot
```
```

Replace with:

```
```ts
// ❌ Never
const model = 'gpt-4o';  // bare alias — behaviour changes without notice

// ✅ Always — pin a specific dated snapshot from your provider's model catalogue
const model = 'gpt-4o-2024-08-06';  // example only — use your provider's current snapshot
```
```

- [ ] **Step 2: Update LLM10 section**

In `skills/shared-add-ai-security/SKILL.md`, find lines 263–269:

```
```ts
// Always set max_tokens — never allow uncapped completions
const response = await openai.chat.completions.create({
  model: 'gpt-4o-2024-11-20',
  messages,
  max_tokens: 1000,    // explicit cap — never omit
  temperature: 0.7,
});
```
```

Replace with:

```
```ts
// Always set max_tokens — never allow uncapped completions
const response = await openai.chat.completions.create({
  model: 'gpt-4o-2024-08-06',  // example only — use your provider's current snapshot
  messages,
  max_tokens: 1000,    // explicit cap — never omit
  temperature: 0.7,
});
```
```

- [ ] **Step 3: Verify**

Run: `grep "2024-11-20" skills/shared-add-ai-security/SKILL.md`

Expected: no output

Run: `grep "2024-08-06" skills/shared-add-ai-security/SKILL.md`

Expected: two matches (LLM03 and LLM10)

Run: `grep "example only" skills/shared-add-ai-security/SKILL.md`

Expected: two matches

- [ ] **Step 4: Commit**

```bash
git add skills/shared-add-ai-security/SKILL.md
git commit -m "fix(audit): replace gpt-4o-2024-11-20 model pin with annotated placeholder in shared-add-ai-security"
```

---

### Task 3: better-auth Version Markers

**Goal:** Remove `better-auth ≥1.6` and `better-auth 1.6` version markers from `nextjs-add-auth` while preserving the behavioral notes they prefix.

**Files:**
- Modify: `skills/nextjs-add-auth/SKILL.md` (lines 138, 509)

**Acceptance Criteria:**
- [ ] Line 138 no longer contains `better-auth ≥1.6`
- [ ] Line 509 no longer contains `better-auth 1.6`
- [ ] Both behavioral facts (`freshAge` measured from `createdAt`; `oidc-provider` removed) are retained

**Verify:** `grep "better-auth.*[0-9]\+\.[0-9]" skills/nextjs-add-auth/SKILL.md` → no output

**Steps:**

- [ ] **Step 1: Update freshAge callout (line 138)**

In `skills/nextjs-add-auth/SKILL.md`, find line 138:

```
> **better-auth ≥1.6**: `freshAge` is measured from session `createdAt`, not last activity. If you set a short `freshAge` (e.g. 43200 for AAL2 flows), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.
```

Replace with:

```
> `freshAge` is measured from session `createdAt`, not last activity. If you set a short `freshAge` (e.g. 43200 for AAL2 flows), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.
```

- [ ] **Step 2: Update OIDC callout (line 509)**

In `skills/nextjs-add-auth/SKILL.md`, find line 509:

```
> **OIDC provider (token issuer)**: If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use `@better-auth/oauth-provider` — the `oidc-provider` plugin was removed in better-auth 1.6. See: https://www.better-auth.com/docs/plugins/oauth-provider
```

Replace with:

```
> **OIDC provider (token issuer)**: If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use `@better-auth/oauth-provider` — the `oidc-provider` plugin has been removed. See: https://www.better-auth.com/docs/plugins/oauth-provider
```

- [ ] **Step 3: Verify**

Run: `grep "better-auth.*[0-9]\+\.[0-9]" skills/nextjs-add-auth/SKILL.md`

Expected: no output

Run: `grep "freshAge.*createdAt\|oidc-provider.*removed" skills/nextjs-add-auth/SKILL.md`

Expected: two matches (behavioral facts retained)

- [ ] **Step 4: Commit**

```bash
git add skills/nextjs-add-auth/SKILL.md
git commit -m "fix(audit): remove better-auth version markers from nextjs-add-auth — behavioral notes retained"
```

---

### Task 4: python-json-logger v4 Compatibility

**Goal:** Replace `python-json-logger>=3.3.0,<4.0` with `python-json-logger>=4.0` in all four occurrences across two files so scaffolded projects can adopt v4.1.0 (current stable).

**Files:**
- Modify: `skills/fastapi-scaffold/SKILL.md` (lines 26, 124, 1699)
- Modify: `skills/shared-add-logging/SKILL.md` (line 298)

**Acceptance Criteria:**
- [ ] All four occurrences updated to `python-json-logger>=4.0`
- [ ] No occurrence of `<4.0` remains in either file

**Verify:** `grep "python-json-logger" skills/fastapi-scaffold/SKILL.md skills/shared-add-logging/SKILL.md` → all matches show `>=4.0`, none show `<4.0`

**Steps:**

- [ ] **Step 1: Update fastapi-scaffold line 26 (pip install command)**

In `skills/fastapi-scaffold/SKILL.md`, find line 26:

```
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart "python-json-logger>=3.3.0,<4.0"
```

Replace with:

```
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart python-json-logger>=4.0
```

- [ ] **Step 2: Update fastapi-scaffold line 124 (requirements.txt block)**

In `skills/fastapi-scaffold/SKILL.md`, find line 124:

```
python-json-logger>=3.3.0,<4.0
```

Replace with:

```
python-json-logger>=4.0
```

- [ ] **Step 3: Update fastapi-scaffold line 1699 (pip install duplicate)**

In `skills/fastapi-scaffold/SKILL.md`, find line 1699:

```
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart "python-json-logger>=3.3.0,<4.0"
```

Replace with:

```
pip install fastapi uvicorn[standard] pydantic pydantic-settings python-dotenv python-multipart python-json-logger>=4.0
```

- [ ] **Step 4: Update shared-add-logging line 298**

In `skills/shared-add-logging/SKILL.md`, find line 298:

```
- `python-json-logger>=3.3.0,<4.0` in `requirements.txt`
```

Replace with:

```
- `python-json-logger>=4.0` in `requirements.txt`
```

- [ ] **Step 5: Verify**

Run: `grep "python-json-logger" skills/fastapi-scaffold/SKILL.md skills/shared-add-logging/SKILL.md`

Expected: four matches, all showing `>=4.0`, none showing `<4.0` or `3.3.0`

- [ ] **Step 6: Commit**

```bash
git add skills/fastapi-scaffold/SKILL.md skills/shared-add-logging/SKILL.md
git commit -m "fix(audit): bump python-json-logger floor to >=4.0 — v4.1.0 is current stable (March 2026)"
```

---

### Task 5: Version Bump and CHANGELOG

**Goal:** Bump plugin version from `2.7.0` to `2.8.0` and record all Round 8 changes in `CHANGELOG.md`.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `plugin.json` version is `"2.8.0"`
- [ ] `CHANGELOG.md` has `[2.8.0]` entry dated 2026-05-07

**Verify:** `grep '"version"' .claude-plugin/plugin.json && grep '\[2.8.0\]' CHANGELOG.md` → both match

**Steps:**

- [ ] **Step 1: Bump plugin version**

In `.claude-plugin/plugin.json`, find:

```json
  "version": "2.7.0",
```

Replace with:

```json
  "version": "2.8.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

In `CHANGELOG.md`, insert above the existing `## [2.7.0]` entry:

```markdown
## [2.8.0] — 2026-05-07

### Fixed
- `fastapi-scaffold`, `nextjs-scaffold`, `nestjs-scaffold`, `vite-react-scaffold`: removed hardcoded `Asia/Singapore` timezone from Dockerfiles — containers now default to UTC; operators can override via `TZ` env var at deploy time
- `shared-add-ai-security`: replaced hardcoded `gpt-4o-2024-11-20` model snapshot in LLM03 and LLM10 examples with a placeholder annotation — the teaching point (pin a dated snapshot) is preserved without encoding a specific version
- `nextjs-add-auth`: removed `better-auth ≥1.6` and `better-auth 1.6` version markers from `freshAge` and OIDC provider notes — behavioral facts retained, drifting version pins removed
- `fastapi-scaffold`, `shared-add-logging`: updated `python-json-logger` floor from `>=3.3.0,<4.0` to `>=4.0` — v4.1.0 is current stable (March 2026)

```

- [ ] **Step 3: Verify**

Run: `grep '"version"' .claude-plugin/plugin.json && grep '\[2.8.0\]' CHANGELOG.md`

Expected: `"version": "2.8.0"` and `## [2.8.0] — 2026-05-07`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): bump version to 2.8.0"
```
