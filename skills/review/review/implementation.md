<!-- ref: review/review/implementation.md
     loaded-by: review/SKILL.md
     prereq: Review agent workflow. Do not invoke this file directly — it is catted by agents via skills/review/SKILL.md (de-registered agent utility). -->

# Review Agent

Review changed files against two layers: (1) the quality checks under **What to check** below, plus the project's `AGENTS.md` `## Rules`, then (2) the stack's `code-standards` style rules. Report violations with `file:line` references. Report only; do not edit files; the caller decides what to fix.

## Stack Detection

Read the stack from the `<!-- templateCentral: <stack>@` marker on `AGENTS.md` line 1; absent, detect it from project files (`next.config.*` nextjs; `vite.config.*` without a `next.config.*` vite-react; `nest-cli.json` or `@nestjs/core` in `package.json` nestjs; `fastapi` in `requirements.txt` fastapi), none found: stop and report; ask the user when that is ambiguous (several stacks, as in a monorepo).

## Steps

1. Detect stack
2. Read the project's `AGENTS.md` — load its `## Rules` section for project-specific constraints
3. Cat the shared comment doctrine, then the detected stack's code-standards file:
   `cat "<skill-dir>/../standards/code-standards/comments.md" "<skill-dir>/../standards/code-standards/<detected-stack>.md"`
4. Identify files to review (see **Scoping** below)
5. Review each file against both layers — quality first, then style rules
6. Report violations (see **Reporting** below)
7. Update `.claude/review-baseline.md` (see **Baseline** below)

## Scoping

Run `bash "<skill-dir>/review/review-scope.sh" "<project-dir>" --session <path> ...` with one `--session` per file written or edited this session and not yet committed (none if there are none). It prints the review scope, one project-relative path per line: the files committed since `last-reviewed-commit` in `.claude/review-baseline.md` (not the baseline file itself), plus the session files, without duplicates. A listed path that no longer exists was deleted in the range: skip it, it is not an error. With no baseline file, the scope is the session files. It writes nothing. A `--session` path must exist in the project or be a file deleted since HEAD. A non-zero exit means the project or the baseline is unsafe to use (a shallow clone says to fetch more history): show its message to the user and stop.

**Called by `templatecentral:scaffold`:** the scope is only the files the agent edited by hand during the scaffold: the stack guide's Step 1 and Step 2 edits (project name, branding, settings), the filled-in `docs/CONSTITUTION.md` and the generated READMEs. Files copied unchanged from the plugin's templates are out of scope, even though this session wrote them. Pass only those files as `--session`.

If the scope is empty, report `No changes since last review — nothing to check.` and stop. Do not record the baseline.

## Baseline

After completing the review (whether violations were found or not), run `bash "<skill-dir>/review/review-scope.sh" "<project-dir>" --record-baseline --stack <detected stack>`. It prints the commit it is scoped at on stderr (`scope computed at HEAD`); pass `--at <sha>` with `--record-baseline` to record only when HEAD is still that commit. It replaces `.claude/review-baseline.md` (whole file or not at all) with the current commit, the stack and today's date. A project with no commit yet gets no baseline; that is always the case for the post-scaffold review, so the baseline is first written by the first review after the project's first commit.

## What to check

**Layer 1 — Code quality (plus anything the project's `AGENTS.md` `## Rules` adds).** Lint, typecheck and the secret scan already catch unused imports and variables and hardcoded secrets, and the comments CI gate catches comment patterns only; do not re-check those by eye. Still judge comment hygiene against `standards/code-standards/comments.md`. Look for what no tool sees:
- **Dead code**: commented-out blocks, TODO stubs
- **Tech debt markers**: `// fix later`, `// temp`, empty catch blocks, swallowed errors
- **Mixed concerns**: business logic in a route handler, HTTP response construction in a service, data fetching in UI
- **Missing boundary validation**: user input, API responses, or env vars not validated with Zod/Pydantic
- **Overly broad responses**: full DB records or internal fields returned when a subset is sufficient
- **Cryptography and keys**: hand-rolled or custom crypto instead of a vetted, maintained library; keys held in code instead of loaded from a secrets manager or from environment variables injected from one
- **Log retention and protection**: for an app deployed to production, logs kept only on the app host, with no retention period or protection from alteration
- **Upload scanning**: where untrusted users upload files, uploads stored or served without a malware scan
- **Missing authorization**: every by-id read or write checks the caller owns the record or holds the required role; denial of another user's record returns 404

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
- Report only; do not edit files; the caller decides what to fix
