<!-- ref: migrate/general/quality-pass.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: The user said yes to the quality pass (`implementation.md`, "Quality pass (opt-in)"). Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality pass (lint alignment, then fixes)

This pass changes user code, tests and config. Fix the code first; the suppression rule is in `comments.md`. Show every batch as a list or diff and get the user's confirmation before you apply it, at each stage below.

**Scratch.** The pass's scratch directory is a new directory in the session scratch area, outside the project. Batch lists, file copies, reports and coverage XML live there.

**Preconditions.** The `before` table is `<scratch>/before.md`, taken in `implementation.md` Phase 3 A before anything changed; when it is absent (marked project), run `<skill-dir>/general/quality-baseline.sh <project-dir> --full --label before --keep-coverage <scratch>/cov-before > <scratch>/before.md` first. Continue only when lint, typecheck and tests passed and `git status` is clean (the migration changes are committed by the user, or on the user's explicit instruction). There is no dirty-tree option: say which condition fails and stop. The pass's own changes stay uncommitted so the user can review them.

**Safety.** Before each batch, write the list of files it will create or modify to the scratch directory, and copy the modified ones there. On failure restore those copies and delete the listed created files. Never use `git restore`, `git checkout`, `git stash` or `git clean` on the user's work. Run no project script without the user's consent.

**Done** means all three hold: lint, typecheck and tests pass; no baseline metric regressed (`quality-baseline.md`); the touched code meets the new-code gate (coverage of at least 80% on changed lines), measured with `diff-cover` at the version pinned in the script header against the XML from the `after` run (`--keep-coverage <scratch>/cov-after`), report in scratch. Coverage on touched lines must not drop, no test is deleted without confirmation, and no suppression, exclusion or threshold change is added. `diff-cover` skips untracked files, so every new untracked file (new tests, extracted modules) is checked separately as fully new code: its line coverage in the XML must be at least 80%; do not stage files to work around this. Security hotspots need a human or the Sonar server: list candidates (crypto, regex, HTTP calls, cookies, SQL string building) in the backlog and do not claim them reviewed. The legacy remainder is not a loop.

## Lint alignment

Merge the scaffold's rules into the existing config (`<skill-dir>/../scaffold/<stack>/template/eslint.config.mjs`, or the Ruff section of `<skill-dir>/../scaffold/fastapi/template/pyproject.toml`), and enable `sonarjs/cognitive-complexity` at 15 (TypeScript) or Ruff `C901` with max-complexity 15 (Python).

- Where the project and the scaffold both set a rule, the stricter wins; a higher complexity limit does not survive.
- Keep project-specific rules. A project ignore survives only for generated or third-party code.
- No config: take the scaffold file. A new lint plugin changes dependencies and the lockfile: ask for its own confirmation, then install it with the project's package manager.
- In a monorepo, align each package's config separately and report per package.

## Stages

Work one directory per batch. Per stage: apply the confirmed batch, run lint, typecheck and tests, allow one fix-and-verify retry. A batch still failing is restored from its scratch copies (see Safety), then the stage stops. Put what is left into the report as a backlog ranked by impact; do not loop.

1. **Lint and type findings.** Fix at the cause. Apply the suppression rule in `comments.md` to each existing one.
2. **Complexity and duplication.** Confirm each refactor before applying it.
3. **Tests** (user code; confirm every deletion and merge). Rules: the test guide loaded with this file. Merge tests of one behaviour into parametrized cases; delete tests that only restate constants, types or framework behaviour (they add no coverage or behaviour value; never delete a test of a real code path). Run coverage before and after each merge or deletion batch; a lower covered-line count for the target files reverts the batch.
4. **Comments.** Apply the comment rules loaded with this file, leaving an ADR id where an ADR explains the code.
5. **Exclusions.** Remove coverage, lint and Sonar exclusions that exist only to pass a gate (confirm the list first); keep one only for generated or third-party code, with the reason beside it. Never lower an existing coverage threshold.

Finish with the close-the-loop step of `implementation.md` Phase 3 A (the `after` run with `--keep-coverage <scratch>/cov-after`, then `--compare`, saved to `docs/quality-baseline.md`); a non-zero compare fails the pass. Print the table with the backlog.
