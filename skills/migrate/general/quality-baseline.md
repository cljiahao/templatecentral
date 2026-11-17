<!-- ref: migrate/general/quality-baseline.md
     loaded-by: migrate/general/implementation.md → migrate/SKILL.md; standards/drift-check/implementation.md → standards/SKILL.md
     prereq: Stack known. Writes no project file. Do not invoke this file directly — it is loaded at runtime by the templatecentral:migrate skill. -->

# Quality baseline (measure only)

Measure the project as it stands; change no source, config or CI file. Run from the project root, or from each package of a monorepo, and report per package.

**Target.** Sonar way on new code: 0 new issues, 100% security hotspots reviewed, coverage >= 80%, duplication <= 3%. Cognitive complexity 15 is the rule threshold behind "0 new issues".

**Rules of the run.**
- Call each tool directly, with the arguments below. Never run a project script whose body contains `--fix` or `--write`. Use the project's own lint targets and config, and read its `package.json` or `pyproject.toml` for them.
- Write machine output with `-o <file>` (or the tool's output flag) into `$TMPDIR`, never parse another command's stdout. A missing tool or command is `n/a`, never a guess.
- Limit each command to 10 minutes and record `timeout`. Before and after the run compare `git status --porcelain`; delete only the files the run created.
- Pin the scratch tools to exact versions and record them in the report: for `pnpm add -D --save-exact`, read the resolved versions with `pnpm ls --depth 0`; for jscpd, pick one release at least two weeks old.

## Commands

Set `TMPDIR` to a writable directory first. The `jq` one-liner is the number; if `jq` is missing, use the fallback.

| Metric | TypeScript stacks (pnpm) | FastAPI (virtualenv active) |
|---|---|---|
| Lint | `pnpm exec eslint <project lint targets> -f json -o "$TMPDIR/eslint.json"`; count `jq '[.[].messages\|length]\|add' "$TMPDIR/eslint.json"`; fallback `node -e "console.log(require(process.argv[1]).reduce((n,f)=>n+f.messages.length,0))" "$TMPDIR/eslint.json"` | `ruff check --output-format json -o "$TMPDIR/ruff.json" .`; count `jq length "$TMPDIR/ruff.json"`; fallback `python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$TMPDIR/ruff.json"` |
| Types | `pnpm exec tsc --noEmit` (error count = `error TS` lines) | `pyright` (or the project's `mypy`) |
| Tests and runtime | `pnpm exec vitest run --reporter=json --outputFile="$TMPDIR/vitest.json"`; read `jq '{tests:.numTotalTests,failed:.numFailedTests}'`; time is wall clock | `python -m pytest -q` |
| Coverage | `pnpm exec vitest run --coverage --coverage.reporter=json-summary --coverage.reportsDirectory="$TMPDIR/cov"`; `jq .total.lines.pct "$TMPDIR/cov/coverage-summary.json"` (Jest: `pnpm exec jest --coverage`) | `python -m pytest --cov=<src dir> --cov-report=term --cov-report=xml:"$TMPDIR/cov.xml"` (needs `pytest-cov`) |
| Complexity (> 15) | the project's `sonarjs/cognitive-complexity` if configured; else a scratch run below | `ruff check --isolated --select C901 --config 'lint.mccabe.max-complexity = 15' --output-format json -o "$TMPDIR/c901.json" .` run in the scratch copy; count as for lint (cyclomatic proxy, not cognitive) |
| Duplication | `pnpm dlx jscpd@<exact version> --reporters json --output "$TMPDIR/jscpd" --ignore "**/node_modules/**,**/dist/**" src`; `jq .statistics.total.percentage "$TMPDIR/jscpd/jscpd-report.json"` | `npx jscpd@<exact version> --reporters json --output "$TMPDIR/jscpd" --ignore "**/.venv/**,**/__pycache__/**" <src dir>` (`npx` replaces `pnpm dlx` on a Python project) |

**Scratch copy** (complexity runs; copies the working tree, including uncommitted and untracked files, but not ignored ones):

```bash
mkdir -p "$TMPDIR/scratch" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -x -C "$TMPDIR/scratch"
```

TypeScript: in `$TMPDIR/scratch` run `pnpm add -D --ignore-workspace --save-exact eslint typescript-eslint eslint-plugin-sonarjs`, write `cc.eslint.config.mjs` that sets only `sonarjs/cognitive-complexity` to `['error', 15]` with the `typescript-eslint` parser for `**/*.{ts,tsx}` and ignores `**/node_modules/**` and `**/dist/**`, then `pnpm exec eslint -c cc.eslint.config.mjs . -f json -o "$TMPDIR/cc.json"` and count with `jq '[.[].messages[]\|select(.ruleId=="sonarjs/cognitive-complexity")]\|length' "$TMPDIR/cc.json"`. If the lockfile or install blocks the scratch run, record `n/a`.

## Counts

Exclude lockfiles, generated code, fixtures and snapshots. Run from the package root.

- **Test:source LOC ratio:** with `T='(\.(test|spec)\.tsx?$|(^|/)(__tests__|tests?)/)'` for TypeScript (`T='(^|/)(test_[^/]*|[^/]*_test)\.py$|(^|/)tests?/'` for FastAPI): `t=$(git ls-files | grep -E "$T" | xargs cat | grep -c .)`, `s=$(git ls-files | grep -E '\.(ts|tsx|py)$' | grep -vE "$T" | xargs cat | grep -c .)`, ratio `t/s`.
- **Suppressions:** `git grep -cE 'eslint-disable|noqa|type: ignore|@ts-expect-error|@ts-ignore|NOSONAR|istanbul ignore|c8 ignore|pragma: no cover' -- . ':!*lock*' | awk -F: '{s+=$NF} END{print s+0}'`.
- **Exclusions:** `git grep -nE 'coverage\.exclude|collectCoverageFrom|coverageThreshold|coveragePathIgnorePatterns|\[tool\.coverage|omit *=|sonar\.(coverage\.|cpd\.)?exclusions|ignores *:' -- . ':!*lock*'`; report the lines.
- **Comment noise:** block comments of 2 or more lines and runs of 3 or more consecutive line comments outside the leading licence header; report any other pattern you see (long parentheticals, ADR text repeated in comments) without scoring it.
- **Sonar:** read `sonar-project.properties`, the pipeline step and any local report on disk (`.scannerwork/`); call no remote service.

## Existing setup

Record what later steps adapt to and never replace: test sharding or matrix jobs, a coverage threshold above 80% (keep it), an existing Sonar or quality pipeline, workspace layout, another git-hook manager.

## Report

Print one table (metric, value) per package, then the exclusions and up to five worst offenders per category with file paths, and the tool versions used. `implementation.md` writes it to `docs/quality-baseline.md` (under 60 lines) in Phase 3; this guide never writes it, and a quality pass adds an `after` column there. A metric that moved the wrong way is a regression.
