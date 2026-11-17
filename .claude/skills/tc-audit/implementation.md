<!-- ref: tc-audit/implementation.md
     loaded-by: tc-audit/SKILL.md
     prereq: Project identified. Do not invoke this file directly — it is loaded at runtime by the /tc-audit skill. -->
## Mindset

Read every file as if you had never seen the project. Priority: accuracy, security (OWASP), quality, lifecycle fit. Skills stay jurisdiction-, industry- and region-neutral.

The audit judges what the plugin **generates**, not only what the skill markdown says. Steps 1 and 2 are mechanical and measured; read files (Step 3) only where they point.

---

## Step 1 — Lint

```bash
bash scripts/lint-skills.sh skills/
```

Fix every failure first. The lint script is the single source of truth for greppable anti-patterns.

---

## Step 2 — Measure generated outcomes

```bash
bash scripts/measure-outcomes.sh
```

Static, no installs: one table per stack template (`skills/scaffold/*/template`) with comment lines, multi-line and parenthetical comments, suppressions (`eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`, `NOSONAR`, coverage pragmas), test files and cases versus source files and LOC, lint/coverage/Sonar exclusions, and whether each CI template carries sharding/parallel settings and the `diff-cover` 80% gate. Exit 1 means a number crossed a threshold at the top of the script.

Target is SonarQube's default gate on new code: cognitive complexity ≤ 15, duplication ≤ 3%, coverage ≥ 80%. A failing number is a finding: fix the template, never loosen a threshold to pass. Tighten a threshold whenever the real numbers drop well under it.

### 2b — Deeper check (optional; needs network and installs)

Scaffold one stack into a temp directory with `templatecentral:scaffold`, then run its lint, typecheck and tests (`pnpm run check`, `pnpm exec vitest --run --coverage`; FastAPI: `ruff check`, `python -m pyright src/`, `pytest --cov`). Record wall-clock time per command and flag any that is slow or any warning. Rotate the stack each audit. Skip it when offline.

---

## Step 3 — Semantic review (choose what to read)

Do not read everything. Read, in full, only:

1. Files changed since the last audit (`git log --since` / `git diff <last-audit-tag>..HEAD -- skills`).
2. Files a Step 1 or Step 2 finding points at.
3. One file per stack from `skills/scaffold/<stack>/template/` and its `source-files.md`, rotating each audit, plus the leaf of any `skills/add/*` capability whose template changed.

Apply to each file:

- **Accuracy**: commands, imports, config keys and versions match `.claude/rules/*.md`; nothing deprecated shown as current. Verify any version-sensitive fact (framework majors, advisories, OWASP lists, Claude Code hook behaviour) against current official docs; do not rely on model memory.
- **Security**: input validated at the boundary, argon2id hashing, JWT algorithm whitelist, rate limiting on auth endpoints, no stack traces in errors, security headers and anti-clickjacking defaults consistent across the three API stacks, `TRUST_PROXY` documented for one- and two-hop topologies, authz deny-by-default, no CVE ids, no versions in skill bodies (versions live in `.claude/rules/*.md`).
- **Quality**: SRP, DRY, YAGNI; reference files over 200 lines flagged (not split during the audit); comments that restate code deleted; same instruction not repeated within 15 lines.
- **Template code**: code lives in real template trees (`template*/` plus `template.manifest`, copied by `skills/scaffold/shared/tc-copy.sh`); flag any fenced copy of a template file that reappears in markdown.

Mark each file CLEAN or list issues with line references.

### 3H — Harness checks (guard real failures only)

`scripts/lint-skills.sh` and `scripts/test-harness-kit.sh` cover hook wiring. Check these by hand only when the hook templates changed:

- **Hook delivery**: PostToolUse hooks capture output and return `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":...}}`, always exit 0. Plain stdout on exit 0 never reaches Claude.
- **Stop hook**: runs tests, prints to stderr and exits 2 only on failure, and exits 0 first when `stop_hook_active` is true. The block cap is a backstop; never raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in seeds.
- **Exec form and timeouts**: every hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/..."]` (array-valued `command` never fires) and sets `timeout`.
- **Guards**: `.env*` edit block (case-insensitive, `.env.example` allowed, reads `tool_input.file_path`), prompt-injection check, `--no-verify` block (reads `tool_input.command`). SubagentStop exits 0 for `stop_hook_active` and read-only agent types.
- **Fail-closed gates**: `verify-harness.sh` fails on a missing/empty/unparseable manifest; the deps gate has no bypass and rejects pnpm-native suppressions; local gitleaks is blocking (`gitleaks git --pre-commit --staged`, no `|| true`).
- **Migrate parity**: `migrate` Phase 4 runs harness-kit Steps A–E, and `harness.json` hashes are written after the final AGENTS.md edit.
- **Skills**: seeded project skills are directories (`.claude/skills/<name>/SKILL.md`); `CLAUDE.md` is one line, `@AGENTS.md`; scaffolded AGENTS.md has a `## Skills Security` section.

---

## Step 4 — Report, fix, re-audit

Report findings by severity: **HIGH** (incorrect, insecure, breaks user code), **MEDIUM** (outdated, missing guidance), **LOW** (style, token cost), then the CLEAN files.

Fix HIGH and MEDIUM; a minor fix (one file, ≤ 10 lines) needs no confirmation, a larger one is described and confirmed first. Fix LOW directly. After fixing, re-run Steps 1 and 2 and re-read the files you changed. Repeat until only LOW findings remain.

No CHANGELOG entry or version bump comes with an audit. A release happens when the owner asks.

---

## Step 5 — Update audit infrastructure

If the audit surfaced a new class of issue, make it recur-proof:

- Greppable → add a `check_*` function to `scripts/lint-skills.sh` (header, collect hits, report; mark TIMELESS or ECOSYSTEM-ERA), call it at the bottom, confirm it passes.
- Measurable on generated output → add a metric and threshold to `scripts/measure-outcomes.sh` and a case to its test.
- Judgment only → add one checklist line to this file.

---

## Step 6 — Repo harness and docs

```bash
head -1 AGENTS.md | grep -q 'templateCentral: plugin@' && echo OK || echo "FAIL: AGENTS.md marker"
grep -q '^@AGENTS.md' CLAUDE.md && echo OK || echo "FAIL: CLAUDE.md"
for f in .claude/settings.json .claude/harness.json; do [ -f "$f" ] && echo "OK: $f" || echo "FAIL: $f missing"; done
bash scripts/validate-manifest.sh
```

Markers: the AGENTS.md line-1 `@X.Y.Z` is a migration schema floor pinned at `HARNESS_SCHEMA_VERSION` in `lint-skills.sh`; never bump it on a normal release. `templatecentral_version` tracks `.claude-plugin/plugin.json`.

Narrative docs (`README.md`, `EXAMPLES.md`, `AGENTS.md` capability row, `CONTRIBUTING.md`, `FUTURE.md`, `SECURITY.md`): verify counts and command names mechanically (`ls skills/*/SKILL.md | wc -l`, `ls skills/add/`), and draft replacements for stale spans for the user to approve.

---

## Ecosystem refresh (on demand)

### 0b — Full web scan

Run only when the owner asks, or when `.github/workflows/ecosystem-refresh.yml` runs. Use WebSearch/WebFetch for current stable versions, breaking changes, deprecations and advisories of: Next.js, NestJS + `@nestjs/platform-fastify`, FastAPI + Starlette, pnpm, Zod, better-auth, Drizzle ORM, argon2/argon2-cffi, `@nestjs/throttler`, slowapi, TanStack Query, Vite + `@vitejs/plugin-react`; OWASP Top 10 (web, LLM, Agentic), NIST SP 800-63B, AWS Responsible AI Lens and AIDLC; Claude Code hook events/types, settings fields and AGENTS.md standard status. Grade harness-practice findings `RECOMMENDED` (official guidance), `CONSENSUS` (≥ 3 independent sources) or `EMERGING` (one source; record only).

Write the result to `.claude/audit-ecosystem-research.md`: frontmatter `last-scanned: YYYY-MM-DD` and `expires-after-days: 30`, a `# Ecosystem Research Cache` heading, then one `###` section per item above under `## Frameworks and runtimes`, `## Libraries`, `## Security standards`, `## Claude Code Harness Engineering`. Write placeholders as `{name}`; avoid `<` tags, `]:`, ZWJ emoji, 4-space indents, links, images and code fences (`scripts/check-research-content.py` rejects them).
