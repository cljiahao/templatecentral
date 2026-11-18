<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md; standards/drift-check/implementation.md → standards/SKILL.md
     prereq: Stack known. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline

**Target.** Sonar way on new code: 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%. Cognitive complexity 15 is the rule threshold behind "0 new issues".

## Modes

```bash
bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --static   # default
bash "<skill-dir>/general/quality-baseline.sh" <project-dir> --full --label after
bash "<skill-dir>/general/quality-baseline.sh" --compare <before-file> [<after-file>]
```

From the drift-check skill the path is `<skill-dir>/../migrate/general/quality-baseline.sh`. Run it once per package of a monorepo; for FastAPI activate the project's virtualenv first.

- `--static` counts files and lines. It runs no project script, test or hook and no tool, uses no network and installs nothing. Use it before any approval and in drift-check. Git reads the tree and may run filters that the user's git config defines. Neither mode intentionally writes to the project; the last row reports any write.
- `--full` runs the project's lint, typecheck and tests (project code executes) and installs the pinned tools named in the script header into its own scratch directory (network). Run it only after the user's yes: the Phase 2 gate's full adoption, the quality pass, or drift-check Step 5. Each tool is limited to 10 minutes. `--keep-coverage <dir>` also copies the Cobertura XML to `<dir>/cobertura.xml`; the directory must be outside the project and its parent must exist.

`--compare` reads two saved `--full` tables, or one table with before and after columns, and prints a verdict per metric. It exits 1 when lint or type findings, tests failed, suppressions, exclusions, duplication or complexity rose, when coverage or the configured thresholds fell, or when a number measured before is no longer measured. A metric `n/a` before is accepted only when that run records the tool as absent, and it prints `newly measured`. Each table also lists every gate configuration file (lint, format, type-check, test-runner, coverage, duplication, Sonar, mutation and secret-scan configs, `package.json`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `lefthook.yml`, CI workflow and pipeline files) with a SHA-256 prefix, never its content; secret-named files and `.env*` are skipped. `--compare` prints a `Gate configuration changed` section with each file added, removed or changed. When that section is non-empty and no number got worse it prints a `REVIEW:` line and exits 3; exit 1 wins over 3. On exit 3 the agent shows the list and, for each changed file, states what changed and why, and never describes a threshold, scope or rule change as neutral. When suppressions rose, the output repeats that a user-approved suppression is recorded by the user retaking the baseline with the reason. Exit 2 is a usage or input error: a table without the gate configuration section (retake the baseline with this version), a `--static` table, a malformed value, a before number that is `n/a` for any other reason, before and after taken at the same clean commit, or a before commit that is not an ancestor of the after commit. A `type errors` row that is `n/a (failed: …)`, such as a mypy crash, exits 1 when it is in the after table and 2 when it is in the before table. A fall in the test total (`N failed of M`) is `WORSE`: a deliberate, user-confirmed consolidation is recorded by the user retaking the baseline, not by the agent. A duplicate metric row, a `no git` table inside a repository, tables with commit hashes when no repository can be found, or a commit that is not in the repository exits 2; a failed tool prints `n/a (failed: …)`, which is never an absent tool. Suppressions count occurrences, not lines, skip `vendor/`, and may count a string literal that contains a marker. Exclusions count entries, so a new item in an existing list or rules object rises the count; an ESLint rule counts as off only as a rule value of `off` or `0`. Each table records `git head` and `git tree` (clean or dirty), or `no git`; `QB_REPO` names the repository for the ancestor check. The last row says `unchanged`, `unchanged in git; the run wrote ignored files: …` (logs or caches the project's own tests wrote; report them), or `CHANGED (…)`; on `CHANGED` stop and show the files it names.

## Read the output

- A number is the measurement. `n/a (reason)` means the tool or its input is absent or was not run; record it as it is, never estimate it, and name the missing tool in the report.
- `complexity over 15` for FastAPI is cyclomatic (Ruff C901), a proxy for Sonar's cognitive rule.
- `test cases` is a static count; a parametrized case counts once.
- The versions row lists the pins; an `after` run uses the same ones.

## Record

Note what later steps adapt to and never replace: test sharding, a coverage threshold above 80% (keep it), an existing Sonar or quality pipeline (read its config; call no remote service), workspace layout, another git-hook manager. `docs/quality-baseline.md` stays under 60 lines: it is the saved compare table (`before`, `after`, `verdict`). Drift-check compares against its `after` column.

## Not measured

The exclusion count is a best-effort count of known forms; the gate configuration change list is what catches the rest, so read every file it names by hand.

Known uncounted forms: vitest or jest entries built from a variable, spread or regex literal, and jest `watchPathIgnorePatterns` and `transformIgnorePatterns`; ESLint rule objects held in a variable and flat-config `ignores` built from a variable or spread; Biome `recommended: false`; `mypy.ini` `ignore_errors`; `.c8rc*`, `.nycrc.yml` and `codecov.yml` ignores; `pyrightconfig.json` ignores and `typeCheckingMode: off`; `conftest.py` `collect_ignore`; `[tool.pylint] disable` in array form; lowered thresholds (`fail_under`, `coverageThreshold`); scope narrowing (coverage `include` or `source`, vitest `coverage.include`, tsconfig `include`, `strict: false`); unquoted regex literals inside a list.
