<!-- ref: migrate/general/quality-pass.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Baseline recorded and the user separately agreed to the quality pass. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality pass (lint alignment, then fixes)

This pass changes user code, tests and config. It adds no suppression and no exclusion, ever: fix the cause. Show every batch as a list or diff and get the user's confirmation before you apply it, at each stage below.

**Preconditions.** Offer the pass only when the baseline lint, typecheck and tests ran and passed and `git status` is clean, which means the migration changes are committed by the user or on the user's explicit instruction to commit. There is no dirty-tree option: otherwise say which condition fails and stop. The pass's own changes stay uncommitted so the user can review them.

**Safety.** Before each batch, copy every file the batch will touch into a fresh scratch directory. On failure restore those copies and delete, by name, the files the batch created. Never use `git restore`, `git checkout`, `git stash` or `git clean` on the user's work. Run lint, typecheck and tests by calling the tool directly, as the commands in `quality-baseline.sh` do; never a project script that contains `--fix` or `--write`.

**Done** means all three hold: lint, typecheck and tests pass; no baseline metric regressed (`quality-baseline.md`); the code the pass touched meets the new-code gate (target in that file): coverage on touched lines with a Cobertura XML report (write it into a scratch directory: vitest `--coverage.reporter=cobertura --coverage.reportsDirectory=<scratch>`, pytest `--cov-report=xml:<scratch>/coverage.xml`) and `diff-cover <xml> --compare-branch=HEAD --fail-under=80`, run through `uvx` or `pipx run` at one exact version you record. Run `git add -N` on new untracked files first, or report them separately. Security hotspots need a human or the Sonar server: list candidates (crypto, regex, HTTP calls, cookies, SQL string building) in the backlog and do not claim them reviewed. The legacy remainder is not a loop.

## Lint alignment

Merge the scaffold's rules into the existing config (`<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs`, or the Ruff section of `<skill-dir>/../scaffold/fastapi/template/pyproject.toml`), and enable `sonarjs/cognitive-complexity` at 15 (TypeScript) or Ruff `C901` with max-complexity 15 (Python) in the project config; the scaffold files on a given branch may not set them yet. The plugin is a dependency change (confirm it first).

- Where the project and the scaffold both set a rule, the stricter wins; a higher complexity limit does not survive.
- Keep project-specific rules. A project ignore survives only for generated or third-party code.
- No config: take the scaffold file. A new lint plugin changes dependencies and the lockfile: ask for its own confirmation, then install it with the project's package manager.
- In a monorepo, align each package's config separately and report per package.

## Stages

Work one directory per batch. Per stage: apply the confirmed batch, run lint, typecheck and tests, allow one fix-and-verify retry. A batch still failing is restored from its scratch copies (see Safety), then the stage stops. Put what is left into the report as a backlog ranked by impact; do not loop.

1. **Lint and type findings.** Fix at the cause. Never add a suppression. Remove each existing one unless it is a confirmed false positive or a third-party constraint; a kept one is one line, one rule, with the reason.
2. **Complexity and duplication.** Confirm each refactor before applying it.
3. **Tests** (user code; confirm every deletion and merge). Rules: the test guide loaded with this file. Merge tests of one behaviour into parametrized cases; delete tests of constants, types and framework behaviour. Run coverage before and after each merge or deletion batch and compare the covered-line count of the target files in the Cobertura report (hits per `<class filename>`); any decrease reverts the batch from its scratch copies.
4. **Comments.** Apply the comment rules loaded with this file, leaving an ADR id where an ADR explains the code.
5. **Exclusions.** Remove coverage, lint and Sonar exclusions that exist only to pass a gate (confirm the list first); keep one only for generated or third-party code, with the reason beside it. Never lower an existing coverage threshold.

Finish with the before/after table and the backlog.
