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

### Enforcement

The seeded config is the spec: `eslint.config.*` (TypeScript), ruff `select` in `pyproject.toml` (Python), `.claude/comment-hygiene-patterns.txt`, the `post-edit-comment-check` hook and `scripts/check-template-comments.sh`. Review-only, not machine-checked: policy 1, the quality of a reason under policy 3, and whether a docstring is needed under policy 5.
