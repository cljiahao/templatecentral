<!-- ref: review/review/implementation.md
     loaded-by: review/SKILL.md
     prereq: Review agent workflow. Do not invoke this file directly — it is catted by agents via skills/review/SKILL.md (de-registered agent utility). -->

# Review Agent

Review changed files against two layers: (1) universal code quality principles from the project's `AGENTS.md`, then (2) stack-specific style rules from the stack's `code-standards` skill. Report violations with `file:line` references. Do not auto-fix.

## Stack Detection

Check for `next.config.ts`, `next.config.js`, or `next.config.mjs` → Next.js; `vite.config.ts` or `vite.config.js` → Vite-React; `nest-cli.json` → NestJS; `requirements.txt` containing `fastapi` → FastAPI. If multiple markers are found (monorepo), ask the user which stack to review before continuing.

## Steps

1. Detect stack
2. Read the project's `AGENTS.md` — load the **Code Quality** section (universal rules)
3. Cat the detected stack's code-standards file:
   `cat "<skill-dir>/../standards/code-standards/<detected-stack>.md"`
4. Identify files to review (see **Scoping** below)
5. Review each file against both layers — quality principles first, then style rules
6. Report violations (see **Reporting** below)
7. Update `.claude/review-baseline.md` (see **Baseline** below)

## Scoping

Check for `.claude/review-baseline.md` in the project root before identifying files.

**If the baseline file exists:**
- Read `last-reviewed-commit` from it
- Run `git diff <last-reviewed-commit>..HEAD --name-only` to get committed changes since baseline
- Add any files written or edited this session that are not yet committed
- Deduplicate — this union is your review scope

**If no baseline file exists:**
- Fall back to all files written or edited this session

If the resulting scope is empty (no changes since baseline, no session edits), report `No changes since last review — nothing to check.` and stop. Do not update the baseline.

## Baseline

After completing the review (whether violations were found or not), write or overwrite `.claude/review-baseline.md` in the project root:

```
last-reviewed-commit: <git rev-parse HEAD>
stack: <detected stack>
reviewed-at: <YYYY-MM-DD>
```

If the project has no commits yet, skip writing the baseline.

## What to check

**Layer 1 — Code quality (from AGENTS.md):**
- **YAGNI**: extra code not required by the task (unused helpers, methods, files added speculatively)
- **DRY**: duplicated logic that should be extracted; or logic extracted from a single callsite that should be inlined
- **SRP**: mixed concerns in one function or file (e.g. route handler containing business logic, service containing HTTP response construction)
- **SoC**: layers bleeding into each other (UI doing data fetching, validation mixed with business logic, config hardcoded in implementation)
- **Premature abstractions**: abstracted from only 1–2 callsites — wait for the third
- **Dead code**: commented-out blocks, unused imports, unused variables, TODO stubs
- **Tech debt markers**: `// fix later`, `// temp`, empty catch blocks, swallowed errors
- **Missing boundary validation**: user input, API responses, or env vars not validated with Zod/Pydantic
- **Overly broad responses**: full DB records or internal fields returned when a subset is sufficient
- **Hardcoded secrets**: tokens, passwords, connection strings, or API keys anywhere in code

**Layer 2 — Stack style (from code-standards skill):**
- File naming, export conventions, function vs const patterns
- Component placement, barrel exports, import paths
- Stack-specific security rules (proxy.ts patterns, input validation, etc.)

**Layer 3 — AI/LLM security (only when AI integrations are present):**
- **Prompt injection** (LLM01): user-controlled strings passed to LLM calls without sanitization or structural separation (system vs user content)
- **Excessive agency** (LLM06): agent granted more tools, permissions, or model calls than needed for the task — flag any `Bash`, `Write`, or broad tool grants without scoping
- **Sensitive data leakage** (LLM02): PII, secrets, or internal schema passed to LLM without redaction; full DB records used as prompt context
- **Insecure output handling** (LLM05): LLM output rendered as HTML (XSS), used in SQL (injection), or passed to `eval()` without sanitization

## Reporting

```
Review — Next.js

Quality violations:
- src/features/projects/api/project-service.ts:45 — empty catch block silently swallows error
- src/features/projects/hooks/use-projects.ts:88 — unused helper formatDate never called
- src/features/projects/components/project-list.tsx:12 — returns full DB record to client; strip to needed fields

Style violations:
- src/features/projects/components/project-card.tsx:3 — default export; use named export
- src/features/projects/api/project-service.ts:1 — unused import { useState }

Clean: src/features/projects/types.ts, src/features/projects/constants.ts
```

Rules:
- Every violation: `file:line — rule description`
- List clean files explicitly
- Do not auto-fix
- Do not suggest fixes unless the calling skill requests it

## Callers

Dispatched by: `templatecentral:scaffold` (all stacks, post-scaffold review), `templatecentral:add` (feature), `templatecentral:add` (auth), and any skill that produces a significant code change.

## Changelog
### 1.2.0
- Added baseline scoping: uses `git diff <last-reviewed-commit>..HEAD` instead of full session files after first scaffold review
- Writes/updates `.claude/review-baseline.md` after each review run
### 1.1.0
- Added Layer 1 quality checks (YAGNI, dead code, boundary validation, least privilege, no secrets)
- Updated stack detection to use full skill names
### 1.0.0
- Initial plugin release