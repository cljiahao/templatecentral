<!-- ref: standards/code-standards/comments.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Comment Hygiene (all stacks)

Shared doctrine for `code-standards/<stack>.md`. Language-neutral — applies to `#`, `//`, docstrings, and JSDoc alike.

### The doctrine

1. **Explain WHY, not WHAT.** A comment captures intent, a constraint, or a non-obvious rationale. Never restate what the next line already says (`// increment i`, `# return the result`).
2. **Prefer own-line comments; use trailing comments sparingly.** Put the comment on its own line above the code. A short trailing *why*-note is acceptable; delete any trailing comment that merely restates the line.
3. **No commented-out code.** Delete it — version control has the history. Dead code left "for reference" rots and misleads.
4. **No change-narration.** Never `// was X, now Y`, `added`, `removed`, `updated`, `renamed`, `refactored`, `per review`, dates, or ticket refs in code. A comment describes the code *as it is*; edit history belongs in the commit message / PR description.
5. **Public-API docs document the contract.** Docstrings / JSDoc on exported functions, classes, and endpoints state inputs, outputs, behavior, and why it exists — not a line-by-line walkthrough of the implementation.

**Keep:** purpose comments, non-obvious "why", `TODO`/`FIXME` with context, and *scoped* tooling directives that state their reason (`// eslint-disable-next-line <rule> -- <why>`, `@ts-expect-error <why>`, `# noqa: <code>`, `# type: ignore[<code>]`). Blanket or unused suppressions are not kept.

### Why (consensus basis)

Tenets 1, 3, 4, 5 are near-universal (PEP 8, Google/Airbnb style guides, Ruff `ERA`, SonarQube, *Clean Code*). Tenet 2 is deliberately "sparingly, not banned" as *doctrine* — PEP 8 permits inline comments used sparingly and ESLint's `no-inline-comments` is opt-in. templatecentral opts in: the TS stacks ship it as a hard gate (`error`, not `warn`) alongside `sonarjs/no-commented-code`, so a fresh scaffold enforces own-line comments rather than merely nudging.

### Enforcement (seeded per stack)

- **TypeScript (Next.js, NestJS, Vite+React)** — `eslint.config.*`, all at `error` (fails lint/CI) unless noted:
  - `no-inline-comments` (with an `ignorePattern` for `eslint-`/`@ts-`/`prettier-`/coverage directives) — tenet 2; `sonarjs/no-commented-code` — tenet 3.
  - `linterOptions.reportUnusedDisableDirectives` + `reportUnusedInlineConfigs` — stale suppressions and redundant inline config fail ([ESLint docs](https://eslint.org/docs/latest/use/configure/configuration-files#configuring-linter-options); core defaults are `warn`/`off`).
  - `@eslint-community/eslint-plugin-eslint-comments` `recommended` (no blanket `eslint-disable`, paired/non-aggregating/non-duplicate directives) + `require-description` (every directive needs `-- <why>`; `eslint-enable` exempt) + `disable-enable-pair` with `allowWholeFile`. Its `no-unused-disable` is deprecated in favour of the core option above.
  - `@typescript-eslint/ban-ts-comment` (already on via typescript-eslint `recommended`): `@ts-ignore`/`@ts-nocheck` banned, `@ts-expect-error` needs a description.
  - `sonarjs/todo-tag` / `fixme-tag` downgraded to `warn` — `sonarjs` `recommended` sets them to `error`, which would block the `TODO`/`FIXME`-with-context this doctrine keeps.
- **FastAPI (Python)** — Ruff `select` in `pyproject.toml`: `ERA` (tenet 3), `PGH003`/`PGH004` (blanket `# type: ignore` / `# noqa`), `RUF100` (unused `noqa`), `TD005` (bare `TODO`/`FIXME` with no description).
- **Deliberately not enabled:** ESLint `no-warning-comments` (duplicates the sonarjs tag rules), `spaced-comment`/`multiline-comment-style` (deprecated in core, moved to `@stylistic`), `capitalized-comments` (pure style, high churn); Ruff `FIX` (bans every TODO/FIXME), `TD001` (rejects `FIXME`), `TD002`/`TD003` (mandatory author/issue link), `TD004`/`TD006`/`TD007` (formatting only).
- **All stacks:** tenets 1, 4, 5 are judgment calls — the `templatecentral:standards (code-standards)` review pass and the seeded `AGENTS.md` rule are the enforcement surface a linter cannot cover.

### Mechanical enforcement — change-narration + oversized blocks

Tenets 1 and 5 stay judgment calls — no linter can reliably tell WHY from WHAT, or judge whether a docstring documents its contract well. Tenet 4 (no change-narration) is different: it's a keyword/pattern match, not a semantic judgment, so it gets real mechanical enforcement.

**Canonical pattern list:** `skills/scaffold/shared/comment-hygiene-patterns.txt` in templateCentral's own repo (scaffolded projects get it copied to `.claude/comment-hygiene-patterns.txt`). This is the only authored copy — every enforcement surface (a PostToolUse hook, a lefthook command, a CI job) reads it at runtime rather than hardcoding its own regex.

- **Change-narration keywords** (`was`, `added`, `removed`, `changed`, `updated`, `renamed`, `moved`, `refactored`, `per review`, `as requested`) are anchored to comment-start to minimize false positives. They apply to every comment form — plain `#`/`//` lines and structured doc-comment blocks (`/** */`, `"""..."""`) alike. A "short-lived" narration problem doesn't stop being one just because it's sitting in a docstring instead of a line comment.
- **Date and ticket/issue-reference patterns** (`YYYY-MM-DD`, `ABC-123`, `#1234`) are lower-precision — a real ticket code and a legitimate technical term (`ABC-123` vs. `UTF-8`, `SHA-256`, `RFC-7231`) can be structurally identical, and anchoring doesn't help when the collision is the comment's very first word. They stay active in the two warn-only tiers as an advisory signal, but are excluded from the CI hard gate — a blocking check can't carry that false-positive rate.
- **Comment-block length** (a run of plain `#`/`//` lines exceeding 5 lines) is flagged as likely non-concise — advisory only, never a CI failure, and never applied to structured doc-comment blocks (those are tenet 5's territory, expected to run longer).
- **Three enforcement tiers**, all warn-only except the last: a live PostToolUse hook (feedback the instant a file is edited), a warn-only lefthook command (a backstop at `git commit`), and a hard CI gate on the PR diff (bypassable via a `skip-comment-check` label) — this last one only fires on the 10 high-precision keyword patterns, never on the length heuristic or the 3 lower-precision date/ticket/issue patterns.

**Secrets in comments** are covered by the existing gitleaks pre-commit + CI scan (`lefthook.yml`'s `secret-scan` command, `.github/workflows/ci.yml`'s "Secret scan (gitleaks)" step) — those scan entire file text, comments included, so no separate mechanism exists here.
