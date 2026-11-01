<!-- ref: standards/code-standards/comments.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Comment Hygiene (all stacks)

Shared doctrine for `code-standards/<stack>.md`; applies to `#`, `//`, docstrings and JSDoc.

### The doctrine

1. **Explain WHY, not WHAT.** Intent, a constraint, or a non-obvious rationale. Never restate the next line (`// increment i`).
2. **Prefer own-line comments; use trailing comments sparingly.** A short trailing *why*-note is fine; delete one that restates the line.
3. **No commented-out code.** Delete it — version control has the history.
4. **No change-narration.** Never `// was X, now Y`, `added`, `removed`, `updated`, `renamed`, `refactored`, `per review`, dates, or ticket refs in code. A comment describes the code *as it is*; history goes in the commit message / PR.
5. **Public-API docs document the contract.** Docstrings / JSDoc on exports state inputs, outputs, behavior and why — not a walkthrough of the implementation.

**Keep:** purpose comments, non-obvious "why", `TODO`/`FIXME` with context, and *scoped* tooling directives that state their reason (`// eslint-disable-next-line <rule> -- <why>`, `@ts-expect-error <why>`, `# noqa: <code>`, `# type: ignore[<code>]`). Blanket or unused suppressions are not kept.

### Enforcement (seeded per stack)

- **TypeScript (Next.js, NestJS, Vite+React)** — `eslint.config.*`, all at `error` (fails lint/CI) unless noted:
  - `no-inline-comments` (with an `ignorePattern` for `eslint-`/`@ts-`/`prettier-`/coverage directives) — tenet 2; `sonarjs/no-commented-code` — tenet 3.
  - `linterOptions.reportUnusedDisableDirectives` + `reportUnusedInlineConfigs` — stale suppressions and redundant inline config fail.
  - `@eslint-community/eslint-plugin-eslint-comments` `recommended` (no blanket `eslint-disable`, paired/non-aggregating/non-duplicate directives) + `require-description` (every directive needs `-- <why>`; `eslint-enable` exempt) + `disable-enable-pair` with `allowWholeFile`.
  - `@typescript-eslint/ban-ts-comment` (already on via typescript-eslint `recommended`): `@ts-ignore`/`@ts-nocheck` banned, `@ts-expect-error` needs a description.
  - `sonarjs/todo-tag` / `fixme-tag` downgraded to `warn`, so `TODO`/`FIXME` with context stays allowed.
- **FastAPI (Python)** — Ruff `select` in `pyproject.toml`: `ERA` (tenet 3), `PGH003`/`PGH004` (blanket `# type: ignore` / `# noqa`), `RUF100` (unused `noqa`), `TD005` (bare `TODO`/`FIXME` with no description).
- **Deliberately not enabled:** ESLint `no-warning-comments` (duplicates the sonarjs tag rules), `spaced-comment`/`multiline-comment-style` (deprecated in core, moved to `@stylistic`), `capitalized-comments` (pure style, high churn); Ruff `FIX` (bans every TODO/FIXME), `TD001` (rejects `FIXME`), `TD002`/`TD003` (mandatory author/issue link), `TD004`/`TD006`/`TD007` (formatting only).
- **All stacks:** tenets 1 and 5 are judgment calls, enforced by the `templatecentral:standards (code-standards)` review pass and the seeded `AGENTS.md` rule.

### Mechanical enforcement — change-narration + oversized blocks

Tenet 4 is a pattern match, so it is enforced mechanically.

**Canonical pattern list:** `skills/scaffold/shared/template/.claude/comment-hygiene-patterns.txt` (copied to `.claude/comment-hygiene-patterns.txt`). Every enforcement surface (PostToolUse hook, lefthook command, CI job) reads it at runtime.

- **Change-narration keywords** (`was`, `added`, `removed`, `changed`, `updated`, `renamed`, `moved`, `refactored`, `per review`, `as requested`) are anchored to comment-start and apply to plain `#`/`//` lines and doc-comment blocks (`/** */`, `"""..."""`) alike.
- **Date and ticket/issue-reference patterns** (`YYYY-MM-DD`, `ABC-123`, `#1234`) are lower-precision (`ABC-123` vs. `UTF-8`, `SHA-256`): active in the two warn-only tiers, excluded from the CI hard gate.
- **Comment-block length** (a run of plain `#`/`//` lines exceeding 5 lines) is flagged as advisory only, never in CI and never on doc-comment blocks.
- **Three tiers**, warn-only except the last: a PostToolUse hook, a lefthook command at `git commit`, and a hard CI gate on the PR diff (bypass label `skip-comment-check`) that fires only on the 10 keyword patterns.

**Secrets in comments** are caught by the gitleaks pre-commit and CI scans, which read whole files.
