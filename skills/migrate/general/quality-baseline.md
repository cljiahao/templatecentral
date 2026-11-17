<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md
     prereq: Stack known and no project file written yet. Also read by standards/drift-check/implementation.md. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline (measure only)

Measure the project as it stands; change no source, config or CI file. Run from the project root, or from each package of a monorepo, and report per package.

**Target.** SonarQube's default gate on new code: no new issues, all security hotspots reviewed, coverage ≥ 80%, duplication ≤ 3%. Cognitive complexity 15 is the rule threshold behind "no new issues".

**Rules of the run.** Use the project's own scripts first (`package.json`, `Makefile`, `pyproject.toml`); use the stack default below only when the project has none. A missing tool or command is `n/a`, never a guess. Limit each command to 10 minutes and record `timeout`. Delete run artefacts (`coverage/`, caches, reports) unless git already ignores them.

## Commands

| Metric | TypeScript stacks (pnpm) | FastAPI |
|---|---|---|
| Lint | project lint script with `--format json` | `ruff check --output-format json` |
| Types | `tsc --noEmit` | `pyright` (or the project's `mypy`) |
| Tests and runtime | project test script | `python -m pytest -q` |
| Coverage | `vitest run --coverage` (or `jest --coverage`) | `python -m pytest --cov` (needs `pytest-cov`) |
| Test files (globs) | `**/*.test.ts(x)`, `**/*.spec.ts(x)`, `**/__tests__/**`, `test/**`, `tests/**` | `**/test_*.py`, `**/*_test.py`, `test/**`, `tests/**` |
| Complexity (> 15) | the project's `sonarjs/cognitive-complexity` if configured; else a scratch run: `git archive HEAD` into `$TMPDIR`, `pnpm add -D --ignore-workspace eslint typescript-eslint eslint-plugin-sonarjs` there, a config setting that one rule to 15, `eslint -f json` | `ruff check --isolated --select C901 --config 'lint.mccabe.max-complexity = 15' --output-format json` (cyclomatic proxy, not cognitive) |
| Duplication | `pnpm dlx jscpd@<exact version> --reporters json --output "$TMPDIR/jscpd" --ignore "**/node_modules/**,**/dist/**" src`; pick one release at least two weeks old and record it | same command on the source directory |

If a run errors on a flag, read the installed tool's `--help` and adapt; do not skip the metric.

## Counts

- **Test:source LOC ratio:** non-blank lines in files matching the test globs ÷ non-blank lines in the other tracked source files (`git ls-files`), excluding generated code, fixtures, snapshots and lockfiles.
- **Suppressions:** occurrences of `eslint-disable`, `noqa`, `type: ignore`, `@ts-expect-error`, `@ts-ignore`, `NOSONAR`, `istanbul ignore`, `c8 ignore`, `pragma: no cover`.
- **Exclusions:** lint ignores, coverage excludes (`coverage.exclude`, `collectCoverageFrom`, `coverageThreshold`, `[tool.coverage] omit`) and Sonar excludes (`sonar.exclusions`, `sonar.coverage.exclusions`, `sonar.cpd.exclusions`).
- **Comment noise:** (a) block comments of 2 or more lines, and runs of 3 or more consecutive line comments, outside the file's leading licence header; (b) comments with a parenthetical of 40 or more characters; (c) comments of 2 or more lines that contain an ADR id, or that share 8 consecutive words with an ADR file.
- **Sonar:** read `sonar-project.properties`, the pipeline step and any local report on disk (`.scannerwork/`); call no remote service.

## Existing setup

Record what later steps adapt to and never replace: test sharding or matrix jobs, a coverage threshold above 80% (keep it), an existing Sonar or quality pipeline, workspace layout, another git-hook manager.

## Report

Print one table (metric, value) per package, then the exclusions and up to five worst offenders per category with file paths. `implementation.md` writes it to `docs/quality-baseline.md` after the gate (under 60 lines); this guide never writes it. After a quality pass, re-run every measurement and add an `after` column; a metric that moved the wrong way is a regression.
