<!-- ref: migrate/general/quality-pass.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Baseline recorded and the user chose the full pass. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality pass (lint alignment, then fixes)

Goal: the project meets the quality target in `quality-baseline.md` with no workaround. Fix the cause. Never add a suppression, ignore or exclusion to get green.

## Lint alignment

Merge the scaffold's quality rules into the project's existing lint config:

- Source: `<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs` (TypeScript stacks) or `<skill-dir>/../scaffold/fastapi/template/pyproject.toml` (Ruff section).
- Keep every project-specific rule and ignore the user wrote; show the merged diff and ask before replacing a rule the project sets differently.
- A project with no lint config takes the scaffold file as is.
- Add any missing lint plugin to the dev dependencies with the project's package manager.

Then fix the new findings at the cause.

## Order

Stop after each stage if lint, typecheck or tests fail, and fix before the next. In a large project, work one directory at a time and let the user stop between batches. Delete user code only after the user confirms.

1. **Lint and type findings.** Review every existing suppression: remove it where the cause can be fixed; keep one only with a stated reason.
2. **Complexity and duplication.** Split functions over the complexity limit; merge duplicated blocks into one shared unit.
3. **Test consolidation.** Follow `<skill-dir>/../test/SKILL.md` for the test rules. Merge tests of the same behaviour into parametrized cases. Delete tests of constants, types and framework behaviour. Fewer tests, same coverage: re-run coverage and confirm it did not drop.
4. **Comments.** Apply `<skill-dir>/../standards/code-standards/comments.md`. Where an ADR explains the code, leave the ADR id as a pointer.
5. **Exclusions.** Remove coverage, lint and Sonar exclusions that exist only to pass a gate, then add tests or fix the code until the gate passes. Keep an exclusion only for generated or third-party code, with the reason beside it.

Keep an existing coverage threshold above 80%; never lower one.
