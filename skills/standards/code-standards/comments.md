<!-- ref: standards/code-standards/comments.md
     loaded-by: standards/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
## Comment Hygiene (all stacks)

Shared policy for `code-standards/<stack>.md`; applies to `#`, `//`, docstrings and JSDoc.

### Comment policy

1. **Default is no comment.** Names and structure carry the meaning. Fix an unclear name before adding a comment.
2. **One short line, above the code.** A needed comment is one line on its own line above the function or block it explains. Never trailing, never mid-expression, no parenthetical asides.
3. **State the non-obvious reason or constraint** at a high level. Never what the code does, never the change history (`was X, now Y`, `added`, `removed`, `refactored`, dates, ticket references).
4. **Cite a decision record by id only**: `// ADR-0049`. Do not restate the decision. This is the one allowed reference form; ticket and issue references stay banned.
5. **Docstrings / JSDoc only on public API surfaces** whose contract is not clear from the signature and types: one summary line, no parameter-by-parameter restating of types.
6. **No commented-out code.** Version control has the history.

Allowed beyond the policy, each for a stated reason:

- `TODO`/`FIXME` with context: tracked work must stay visible.
- Real licence headers (`Copyright`, `SPDX-License-Identifier`, `Licensed under`): legally required text. A block that merely mentions "license" is not exempt.
- Directive comments (`eslint-*`, `@ts-*`, `noqa`, `type:`, `istanbul`/`c8`, `/// <reference>`, shebangs): tool input, not prose; they follow the suppression policy below.
- SHA-pin version annotations (`uses: x@<40-hex> # v1.2.3`): the pin is unreadable without the tag, and the trailing form is the one Dependabot/Renovate maintain.
- Tests may use `assert`: ruff `S101` is ignored per-file for `test/**`, the tool-standard setup, not a workaround.

### Suppression policy

Fix the code first. A suppression is a last resort, only for a confirmed third-party false positive, on the narrowest scope (one line, one rule id), with the reason in a comment on the line above. Never use one to turn a gate green. This covers `eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`, `pyright: ignore`, `NOSONAR`, coverage ignore pragmas and lint, coverage or Sonar exclusions. `NOSONAR` and blanket or file-level disables are not allowed, and a stale suppression is removed. Whether to add the one allowed suppression is the user's decision; once they approve it, the baseline `before` table is retaken after that single change with the reason recorded.

### Enforcement (seeded per stack)

- **TypeScript (Next.js, NestJS, Vite+React)** — `eslint.config.*`, all at `error` (fails lint/CI) unless noted:
  - `no-inline-comments` (with an `ignorePattern` for `eslint-`/`@ts-`/`prettier-`/coverage directives) — policy 2; `sonarjs/no-commented-code` — policy 6.
  - `linterOptions.reportUnusedDisableDirectives` + `reportUnusedInlineConfigs` — stale suppressions and redundant inline config fail.
  - `@eslint-community/eslint-plugin-eslint-comments` `recommended` (no blanket `eslint-disable`, paired/non-aggregating/non-duplicate directives) + `require-description` (every directive needs `-- <why>`; `eslint-enable` exempt) + `disable-enable-pair` with `allowWholeFile`.
  - `@typescript-eslint/ban-ts-comment` (on via typescript-eslint `recommended`): `@ts-ignore`/`@ts-nocheck` banned, `@ts-expect-error` needs a description.
  - `sonarjs/todo-tag` / `fixme-tag` downgraded to `warn`, so `TODO`/`FIXME` with context stays allowed.
- **FastAPI (Python)** — Ruff `select` in `pyproject.toml`: `ERA` (policy 6), `PGH003`/`PGH004` (blanket `# type: ignore` / `# noqa`), `RUF100` (unused `noqa`), `TD005` (bare `TODO`/`FIXME`). Python has no inline-comment lint rule; the hook and the template-tree gate (`scripts/check-template-comments.sh`) cover trailing comments.
- **Deliberately not enabled:** ESLint `no-warning-comments`, `spaced-comment`/`multiline-comment-style`, `capitalized-comments`; Ruff `FIX`, `TD001`–`TD004`, `TD006`, `TD007`.
- **Review-only (not machine-checked):** policy 1 (default none), the *quality* of a reason under policy 3, and whether a docstring is needed under policy 5. These rest on the `templatecentral:standards (code-standards)` review pass and the seeded `AGENTS.md` rule.

### Mechanical enforcement

**Canonical pattern list:** `skills/scaffold/shared/template/.claude/comment-hygiene-patterns.txt` (copied to `.claude/comment-hygiene-patterns.txt`). Every enforcement surface (PostToolUse hook, lefthook command, CI job) reads it at runtime.

- **Change-narration keywords** (`was`, `added`, `removed`, `changed`, `updated`, `renamed`, `moved`, `refactored`, `per review`, `as requested`) are anchored to comment-start and apply to plain `#`/`//` lines and doc-comment blocks alike.
- **Date and ticket-reference patterns** (`YYYY-MM-DD`, `ABC-123`, `#1234`) are lower-precision (`ABC-123` vs. `UTF-8`, `SHA-256`): warn-only tiers, excluded from the CI hard gate. `ADR-NNNN` is exempt from the ticket pattern.
- **Hook-only advisory checks** (`post-edit-comment-check`, never blocking; string-aware, so `"a // b"` is not a comment): trailing comments (policy 2; directives and SHA-pin annotations excluded), runs of more than one comment line and `/* */`/JSDoc/docstring bodies longer than one line (real licence headers excluded; policy 2 and 5), parenthetical asides, and an ADR id followed by prose (policy 4). Commented-out calls like `// fn(a, b)` are not read as asides.
- **Gate scope** (`scripts/check-template-comments.sh`, run in CI): the same scan over ts/js/py template sources, ts/js/py code fences in the `add` and `scaffold` guides, and `.yml`/`.yaml` template files (a `#` is a comment only at line start or after whitespace, and `|`/`>` block-scalar bodies are skipped; a `# vX` annotation after a `@<40-hex>` pin, bare or quoted, stays allowed). Exemptions are per line, with a stated reason, in `scripts/check-template-comments.exempt`.
- **Known limits** (the scanner is line-based, not a parser): JSX text is recognised only on a line that starts with a tag, so `<p>see //foo</p>` is text but a bare text line `see //foo` reads as a comment; text after a `{` on such a line is scanned as code; a `//` comment directly after a word and colon (`a://`) reads as a URL; in YAML, a block scalar is detected from a header line ending in `|` or `>` (with optional `-`, `+` or an indent digit), so a flow-style or multi-line quoted scalar that spans lines is scanned as plain lines, and an apostrophe after a non-alphanumeric character opens a quote that can hide a trailing comment.
- **Three tiers**, warn-only except the last: a PostToolUse hook, a lefthook command at `git commit`, and a hard CI gate on the PR diff (bypass label `skip-comment-check`) that fires only on the 10 keyword patterns.

**Secrets in comments** are caught by the gitleaks pre-commit and CI scans, which read whole files.
