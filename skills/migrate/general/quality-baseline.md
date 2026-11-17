<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Stack known and no project file written yet. Also read by standards/drift-check/implementation.md. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline (measure only)

Measure the project as it stands. Change no source, config or CI file. Run from the project root, or from each package of a monorepo, and report per package.

Target: SonarQube's default quality gate on new code: cognitive complexity ≤ 15, duplication ≤ 3%, coverage ≥ 80%.

## Measurements

Use the project's own scripts first (`package.json` scripts, `Makefile`, `pyproject.toml`); fall back to the stack default. A tool that is absent gets `n/a`, never a guess. Cap long runs; record a timeout as `timeout`.

| Metric | How |
|---|---|
| Lint errors and warnings | the project's lint command; counts from its machine-readable output (`--format json`, `--output-format json`) |
| Type errors | the project's typecheck command (`tsc --noEmit`, `pyright`, or `mypy`) |
| Test files, cases, runtime, pass/fail | the project's test command; add coverage when it already runs with it |
| Test:source LOC ratio | non-blank lines in test files ÷ non-blank lines in source files, tracked files only (`git ls-files`), excluding generated code, fixtures and snapshots |
| Suppressions | count of `eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`, `@ts-ignore`, `NOSONAR`, `istanbul ignore`, `c8 ignore`, `pragma: no cover` |
| Exclusions | lint ignores, coverage excludes (`coverageThreshold`, `collectCoverageFrom`, `coverage.exclude`, `[tool.coverage] omit`) and Sonar excludes (`sonar.exclusions`, `sonar.coverage.exclusions`, `sonar.cpd.exclusions`) |
| Comment noise | multi-line block comments, runs of 3 or more line comments, parenthetical comments over one line, comments that restate ADR text instead of citing the id (compare against the project's ADR files) |
| Complexity | functions over 15: `sonarjs/cognitive-complexity` when configured, else Ruff `C901` as a proxy; otherwise `n/a` |
| Duplication | `jscpd` or the Sonar report when present, else `n/a` |
| Sonar | existing `sonar-project.properties`, pipeline step and any local scanner report (`.scannerwork/`); read what is on disk, call no remote service without the user's say |

## Existing setup

Record what the later phases must adapt to, not replace: test sharding or matrix jobs, coverage thresholds above 80% (keep them), an existing Sonar or quality pipeline, a workspace or monorepo layout, another git-hook manager.

## Report file

Write `docs/quality-baseline.md` (migrate only; drift-check never writes it): date, stack, one table of the metrics above, then the exclusions and the worst offenders (up to five files per category, with paths). Keep it under 60 lines.

## Before/after table

After the quality pass, re-run every measurement and print one table: metric, before, after. Append the after column to the report file. A metric that moved the wrong way is a regression: list it and fix its cause.
