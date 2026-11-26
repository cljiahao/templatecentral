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

Static, no installs. One table per stack template (`skills/scaffold/*/template`), counting: comment lines, multi-line and parenthetical comments, trailing inline comments, suppressions (`eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`, `NOSONAR`, coverage pragmas), source LOC, test LOC and the test:source ratio, test cases (an `it.each` counts as one; commented-out cases are skipped), orphan test files, lint/coverage exclusions, Sonar exclusions (`sonar-project.properties` by key, and `-Dsonar.*` or `extraProperties` entries in CI files, with file:line), and whether each CI template has sharding/parallel settings and the `diff-cover` 80% gate. Comments are counted in the detected stack's own files (`.py`, or `.ts`/`.tsx`/`.js`/`.jsx`/`.mjs`/`.cjs`), source, tests and config alike; `.claude/hooks` and `.claude/.harness-base` are never scanned. Exit 1: a number crossed a threshold; exit 2: unusable path or script error.

**Project mode** is a report, not a gate: `bash scripts/measure-outcomes.sh PROJECT_DIR` measures a scaffolded or adopted project, each app (a Python backend and a TS frontend are separate) in its own language, stack detected from project files, `.gitignore` honoured. Every metric prints beside the template reference value and is marked `WARN` outside it; `WARN` never changes the exit code. Exit 1 only for an app with zero test cases or no CI file enforcing `diff-cover --fail-under=80` (one file is enough). A high test:source ratio is a prompt to consolidate duplicate tests, not to delete coverage.

**Ratchet for migrated projects:** `--baseline FILE PROJECT_DIR` records suppressions, multi-line and parenthetical comments, trailing comments, Sonar exclusion entries and the coverage gate as plain `key=value`; `--compare FILE PROJECT_DIR` exits 1 when any of them rises above the baseline or the gate disappears. Record once, then never get worse.

The script does **not** measure cognitive complexity, duplication or coverage. Those are enforced by the lint configs and CI gates the templates ship; the script only checks that the gates are present. Target is SonarQube's default gate on new code: complexity ≤ 15, duplication ≤ 3%, coverage ≥ 80%.

Template thresholds are a ratchet set just above today's numbers, not targets. The test:source ratio is a floor-plus-ceiling band: too low means untested code, too high means tests that outgrew the code. A failing number is a finding: fix the template, never raise a threshold to pass. Lower a threshold when the real numbers fall well under it. Known gap: the FastAPI template carries ~24% comment lines against 3-8% on the TypeScript stacks; the threshold is not tuned to it.

### 2b — Measured outcomes of a scaffolded project (needs network and installs)

One stack per run, rotating: `stack=$(set -- nextjs vite-react nestjs fastapi; shift $((10#$(date +%V) % 4)); echo "$1")`; run all four when the user asks. Scaffold into a temporary directory, install, then measure:

```bash
d=$(mktemp -d "${TMPDIR:-/tmp}/tc-audit.XXXXXX")
TC_STACK="$stack" TC_PART=stack bash skills/scaffold/shared/tc-copy.sh "$d"
(cd "$d" && git init -q && git add -A && git -c user.email=a@a -c user.name=a commit -qm init)
(cd "$d" && if [ -f package.json ]; then pnpm install --ignore-scripts; elif [ -f requirements-dev.txt ]; then python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt; else echo "tc-audit: no package.json and no requirements-dev.txt in $d" >&2; exit 1; fi)
bash skills/migrate/general/quality-baseline.sh "$d" --full --label audit
```

Report the table. Any `n/a` row, a nonzero lint, type or complexity count, a failed test, coverage under 80% or duplication over 3% is a finding against the template. Unmeasured, by design: Sonar security hotspots and every Sonar rule other than cognitive complexity need a Sonar server, which this repo does not run. Skip the step offline.

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

`scripts/lint-skills.sh` covers hook wiring and, in `check_template_security_defaults`, the shipped security defaults (JWT algorithm whitelist, helmet and `SecurityHeadersMiddleware`, `TRUST_PROXY` wiring, DENY and `frame-ancestors 'none'` in all four stacks, `blockExoticSubdeps`, Dockerfile `pnpm-workspace.yaml`, no `class-validator`). `scripts/test-harness-kit.sh` tests the seeded hooks. Check these by hand only when the hook templates changed:

- **Hook delivery**: PostToolUse hooks capture output and return `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":...}}`, always exit 0. Plain stdout on exit 0 never reaches Claude.
- **Stop hook**: runs tests, prints to stderr and exits 2 only on failure, and exits 0 first when `stop_hook_active` is true. The block cap is a backstop; never raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` in seeds.
- **Exec form and timeouts**: every hook is `"command": "<bin>", "args": ["${CLAUDE_PROJECT_DIR}/..."]` (array-valued `command` never fires) and sets `timeout`.
- **Guards**: `.env*` edit block (case-insensitive, `.env.example` allowed, reads `tool_input.file_path`), inline-credential check, `--no-verify` block (reads `tool_input.command`). SubagentStop exits 0 for `stop_hook_active` and read-only agent types.
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

Run `bash scripts/check-doc-sync.sh` (README skill count, `templatecentral:*` references in `EXAMPLES.md`, `AGENTS.md` capability row against `skills/add/`). Versions (README badge, plugin.json, harness.json) are covered by `validate-manifest.sh` above. Read `CONTRIBUTING.md`, `FUTURE.md` and `SECURITY.md` only if the diff touched them, and draft replacements for stale spans for the user to approve.

---

## Ecosystem refresh (on demand)

### 0b — Full web scan

Run only when the owner asks, or when `.github/workflows/ecosystem-refresh.yml` runs. Use WebSearch/WebFetch for current stable versions, breaking changes, deprecations and advisories of: Next.js, NestJS + `@nestjs/platform-fastify`, FastAPI + Starlette, pnpm, Zod, better-auth, Drizzle ORM, argon2/argon2-cffi, `@nestjs/throttler`, slowapi, TanStack Query, Vite + `@vitejs/plugin-react`; OWASP Top 10 (web, LLM, Agentic), NIST SP 800-63B, AWS Responsible AI Lens and AIDLC; Claude Code hook events/types, settings fields and AGENTS.md standard status. Grade harness-practice findings `RECOMMENDED` (official guidance), `CONSENSUS` (≥ 3 independent sources) or `EMERGING` (one source; record only).

Write the result to `.claude/audit-ecosystem-research.md`: frontmatter `last-scanned: YYYY-MM-DD` and `expires-after-days: 30`, a `# Ecosystem Research Cache` heading, then one `###` section per item above under `## Frameworks and runtimes`, `## Libraries`, `## Security standards`, `## Claude Code Harness Engineering`. Write placeholders as `{name}`; avoid `<` tags, `]:`, ZWJ emoji, 4-space indents, links, images and code fences (`scripts/check-research-content.py` rejects them).
