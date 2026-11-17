<!-- ref: migrate/general/quality-pass.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Baseline recorded and the user separately agreed to the quality pass. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality pass (lint alignment, then fixes)

This pass changes user code, tests and config. It adds no suppression and no exclusion, ever: fix the cause. Show every batch as a list or diff and get the user's confirmation before you apply it, at each stage below.

**Done** means all three hold: lint, typecheck and tests pass; no baseline metric regressed (`quality-baseline.md`); the code the pass touched meets the new-code gate (target in that file). The legacy remainder is not a loop.

## Lint alignment

Merge the scaffold's rules into the existing config (`<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs`, or the Ruff section of `<skill-dir>/../scaffold/fastapi/template/pyproject.toml`):

- Where the project and the scaffold both set a rule, the stricter wins; a higher complexity limit does not survive.
- Keep project-specific rules. A project ignore survives only for generated or third-party code.
- No config: take the scaffold file. A new lint plugin changes the lockfile: install it with the project's package manager and say so.
- In a monorepo, align each package's config separately and report per package.

## Stages

Work one directory per batch. Per stage: apply the confirmed batch, run lint, typecheck and tests, allow one fix-and-verify retry, then stop the stage. Put what is left into the report as a backlog ranked by impact; do not loop.

1. **Lint and type findings.** Fix at the cause. Remove each existing suppression unless it is a confirmed false positive or a third-party constraint; a kept one is one line, one rule, with the reason.
2. **Complexity and duplication.** Confirm each refactor before applying it.
3. **Tests** (user code; confirm every deletion and merge). Rules: `<skill-dir>/../test/SKILL.md`. Merge tests of one behaviour into parametrized cases; delete tests of constants, types and framework behaviour. Coverage must not drop.
4. **Comments.** Apply `<skill-dir>/../standards/code-standards/comments.md`, leaving an ADR id where an ADR explains the code.
5. **Exclusions.** Remove coverage, lint and Sonar exclusions that exist only to pass a gate (confirm the list first); keep one only for generated or third-party code, with the reason beside it. Never lower an existing coverage threshold.

Finish with the before/after table and the backlog.
