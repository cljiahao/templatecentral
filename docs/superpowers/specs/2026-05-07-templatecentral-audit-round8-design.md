# templateCentral Round 8 Audit — Design Spec

**Date:** 2026-05-07
**Scope:** Post-Round-7 accuracy and policy gap closure across templateCentral

---

## Goal

Close five targeted gaps identified in the Round 8 fresh-eyes audit: Singapore timezone removal from all scaffold Dockerfiles, model snapshot version pin removal from shared-add-ai-security, better-auth version marker removal from nextjs-add-auth, python-json-logger v4 compatibility, and version bump.

---

## Design Sections

### 1. Singapore Timezone Removal from Scaffold Dockerfiles

**`skills/fastapi-scaffold/SKILL.md`**, **`skills/nextjs-scaffold/SKILL.md`**, **`skills/nestjs-scaffold/SKILL.md`**, **`skills/vite-react-scaffold/SKILL.md`**

All four scaffold Dockerfiles hardcode `Asia/Singapore` at image build time. This violates the project's cross-industry, non-Singapore-specific policy and is also bad container practice — server timezone is irrelevant for web applications because databases store UTC, user-facing time display is handled by the browser (`Intl` API), and operators who need a specific timezone inject it via `TZ` env var at deploy time.

Fix: remove the `Asia/Singapore` lines entirely. Alpine Linux and Debian both default to UTC without any configuration. Cascade removals per file:

| File | Remove |
|---|---|
| `fastapi-scaffold` (Debian/apt) | `tzdata` from apt-get install; the `ln -sf /usr/share/zoneinfo/Asia/Singapore /etc/localtime` and `echo "Asia/Singapore" > /etc/timezone` lines |
| `nextjs-scaffold` (Alpine) | The `cp /usr/share/zoneinfo/Asia/Singapore` and `echo "Asia/Singapore"` lines; `tzdata` from apk add; `COPY --from=base /etc/localtime` and `COPY --from=base /etc/timezone` lines in final stage |
| `nestjs-scaffold` (Alpine) | Same pattern as nextjs-scaffold |
| `vite-react-scaffold` (Alpine) | The `cp` and `echo` lines; `tzdata` from apk add |

Each scaffold gets a comment near the ENV block: `# TZ defaults to UTC — override via TZ env var in your deploy config if needed`

---

### 2. Model Snapshot Version Pin in `shared-add-ai-security`

**`skills/shared-add-ai-security/SKILL.md`** — LLM03 (line 136) and LLM10 (line 265)

The LLM03 "Supply Chain" section uses `gpt-4o-2024-11-20` as the example of a correctly-pinned model identifier. This is self-defeating: the skill teaches developers to pin dated snapshots, but encodes a specific snapshot that will drift with every provider release cycle. LLM10's token-budget code block repeats the same literal.

Fix: replace the literal snapshot with `gpt-4o-2024-08-06` annotated `// example only — use your provider's current snapshot`. The teaching point (pin a dated snapshot, never use bare aliases like `gpt-4o`) is preserved without encoding a specific date that must be updated each release.

The ❌ bad example in LLM03 is updated from `'gpt-4'` to `'gpt-4o'` — the bare alias form developers actually reach for today.

---

### 3. better-auth Version Markers in `nextjs-add-auth`

**`skills/nextjs-add-auth/SKILL.md`** — lines 138 and 509

Two callouts prefix behavioral facts with a version marker:

- Line 138: `> **better-auth ≥1.6**: freshAge is measured from session createdAt...`
- Line 509: `...the oidc-provider plugin was removed in better-auth 1.6.`

The behavioral facts are accurate and should be retained. The version markers will drift with every release and are no longer meaningful to document (the behavior has been stable across multiple releases).

Fix: drop the version markers, retain the behavior notes verbatim.

- Line 138 becomes: `> \`freshAge\` is measured from session \`createdAt\`, not last activity. If you set a short \`freshAge\` (e.g. 43200 for AAL2 flows), users must re-authenticate after that period regardless of activity — this is the intended behavior for high-security flows.`
- Line 509 becomes: `> **OIDC provider (token issuer)**: If your project needs to act as an OIDC provider (issuing tokens to third-party clients), use \`@better-auth/oauth-provider\` — the \`oidc-provider\` plugin has been removed. See: https://www.better-auth.com/docs/plugins/oauth-provider`

---

### 4. python-json-logger v4 Compatibility

**`skills/fastapi-scaffold/SKILL.md`** (lines 26, 124, 1699) and **`skills/shared-add-logging/SKILL.md`** (line 298)

`python-json-logger>=3.3.0,<4.0` appears in four places. The `<4.0` upper bound now actively blocks v4.1.0, the current stable release (March 2026). Projects scaffolded with this constraint cannot adopt the current major without manually editing their requirements.

Fix: drop the upper bound and raise the floor to `>=4.0` in all four occurrences. No quotes needed when the version specifier has no spaces.

---

### 5. Version Bump + CHANGELOG

- `.claude-plugin/plugin.json`: `2.7.0` → `2.8.0`
- `CHANGELOG.md`: new `[2.8.0] — 2026-05-07` entry covering all Round 8 changes

---

## Constraints

- No CVE identifiers in SKILL.md files
- No version pins in SKILL.md files (versions belong only in `.claude/rules/*.md`) — the model snapshot example uses a placeholder annotation, not a real pin
- No IM8 attribution
- No Singapore-specific content anywhere in the project
- No new features or refactoring beyond what each fix requires
- pnpm version reference in nestjs-add-auth left as-is (explicitly deferred)
