#!/usr/bin/env bash
# Quality baseline: measure a project, change nothing in it.
# Usage: quality-baseline.sh <project-dir> [--label before|after]
# Prints one markdown table on stdout. Exit 0 when measured, 2 on a usage error.
# Needs bash 3.2+, BSD or GNU coreutils, git; python3 or node reads the JSON/XML reports.
set -u

# Scratch tool versions are pinned so a before run and an after run measure with identical tools.
ESLINT_VERSION=10.15.0
TSESLINT_VERSION=8.73.0
SONARJS_VERSION=4.2.2
JSCPD_VERSION=5.4.3
COMPLEXITY_LIMIT=15
RUN_LIMIT=600

usage() { echo "usage: quality-baseline.sh <project-dir> [--label before|after]" >&2; exit 2; }

LABEL=before
PROJECT=
while [ $# -gt 0 ]; do
  case "$1" in
    --label) [ $# -ge 2 ] || usage; LABEL=$2; shift 2 ;;
    -*) usage ;;
    *) [ -z "$PROJECT" ] || usage; PROJECT=$1; shift ;;
  esac
done
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || usage
case "$LABEL" in before|after) ;; *) usage ;; esac
P=$(cd "$PROJECT" && pwd) || usage

S=$(mktemp -d "${TMPDIR:-/tmp}/qbaseline.XXXXXX") || { echo "cannot create a scratch directory" >&2; exit 2; }
# shellcheck disable=SC2329
cleanup() {
  case "${S:-}" in
    */qbaseline.*) [ -d "$S" ] && rm -rf "$S" ;;
  esac
}
trap cleanup EXIT

have() { command -v "$1" >/dev/null 2>&1; }
ROWS=
row() { ROWS="${ROWS}| $1 | $2 |
"; }

# limited <out-file> <cmd...>: run in the project dir, stdin closed, output to a file, killed after RUN_LIMIT seconds.
# Sets RC; 124 means timeout.
limited() {
  local out=$1; shift
  ( cd "$P" && exec "$@" ) </dev/null >"$out" 2>&1 &
  local pid=$!
  ( sleep "$RUN_LIMIT"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; : >"$out.timeout" ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid"; RC=$?
  pkill -P "$watcher" 2>/dev/null; kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  if [ -f "$out.timeout" ]; then RC=124; fi
  return 0
}

# jval <kind> <file>: print a number from a JSON or XML report, empty when unreadable.
jval() {
  [ -f "$2" ] || return 0
  if have python3; then
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, re, sys
k, f = sys.argv[1], sys.argv[2]
try:
    if k == "eslint":
        print(sum(len(x["messages"]) for x in json.load(open(f))))
    elif k == "sonar":
        print(sum(1 for x in json.load(open(f)) for m in x["messages"] if m.get("ruleId") == "sonarjs/cognitive-complexity"))
    elif k == "list":
        print(len(json.load(open(f))))
    elif k == "jscpd":
        print(json.load(open(f))["statistics"]["total"]["percentage"])
    elif k == "vitest":
        d = json.load(open(f)); print(d["numFailedTests"], d["numTotalTests"])
    elif k == "pyright":
        print(json.load(open(f))["summary"]["errorCount"])
    elif k == "cobertura":
        m = re.search(r'<coverage[^>]*line-rate="([0-9.]+)"', open(f).read(4000)); print(round(float(m.group(1)) * 100, 2))
    elif k == "junit":
        t = re.search(r"<testsuite\s[^>]*>", open(f).read()).group(0)
        a = lambda n: int(re.search(n + r'="(\d+)"', t).group(1))
        print(a("failures") + a("errors"), a("tests"))
except Exception:
    pass
PY
  elif have node; then
    node - "$1" "$2" <<'JS' 2>/dev/null
const fs = require("fs");
const [k, f] = process.argv.slice(2);
try {
  const txt = fs.readFileSync(f, "utf8");
  const j = () => JSON.parse(txt);
  if (k === "eslint") console.log(j().reduce((n, x) => n + x.messages.length, 0));
  else if (k === "sonar") console.log(j().reduce((n, x) => n + x.messages.filter((m) => m.ruleId === "sonarjs/cognitive-complexity").length, 0));
  else if (k === "list") console.log(j().length);
  else if (k === "jscpd") console.log(j().statistics.total.percentage);
  else if (k === "vitest") console.log(j().numFailedTests, j().numTotalTests);
  else if (k === "pyright") console.log(j().summary.errorCount);
  else if (k === "cobertura") console.log(Math.round(parseFloat(txt.slice(0, 4000).match(/<coverage[^>]*line-rate="([0-9.]+)"/)[1]) * 10000) / 100);
  else if (k === "junit") {
    const t = txt.match(/<testsuite\s[^>]*>/)[0];
    const a = (n) => parseInt(t.match(new RegExp(n + '="(\\d+)"'))[1], 10);
    console.log(a("failures") + a("errors"), a("tests"));
  }
} catch (e) { /* unreadable report: print nothing */ }
JS
  fi
}

# Tracked and untracked-but-not-ignored files that still exist, NUL separated.
# Falls back to find when the project is not a git repository.
list_files() {
  if ( cd "$P" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; then
    ( cd "$P" && git ls-files -z --cached --others --exclude-standard )
  else
    ( cd "$P" && find . -type f -not -path './node_modules/*' -not -path './.venv/*' -not -path './.git/*' -print0 )
  fi
}

is_git() { ( cd "$P" && git rev-parse --is-inside-work-tree ) >/dev/null 2>&1; }

status_snapshot() { if is_git; then ( cd "$P" && git status --porcelain -z --untracked-files=all ) | tr '\0' '\n'; fi; }

# copy_tree <dest>: working-tree copy, including uncommitted and untracked files, excluding ignored ones.
copy_tree() {
  mkdir -p "$1" || return 1
  list_files | ( cd "$P" && tar --null -T - -cf - 2>/dev/null ) | tar -x -C "$1"
}

STACK=unknown
if [ -f "$P/package.json" ]; then STACK=typescript
elif [ -f "$P/pyproject.toml" ] || ls "$P"/requirements*.txt >/dev/null 2>&1; then STACK=python
fi

SRC=
for d in src app lib; do [ -d "$P/$d" ] && { SRC=$d; break; }; done
[ -n "$SRC" ] || SRC=.

BEFORE=$(status_snapshot)

NA_NOSTACK="n/a (no package.json, pyproject.toml or requirements file)"
LINT=$NA_NOSTACK TYPES=$NA_NOSTACK TESTS=$NA_NOSTACK TESTRC=$NA_NOSTACK SECS=$NA_NOSTACK COV=$NA_NOSTACK CPLX=$NA_NOSTACK DUP=$NA_NOSTACK
TOOLS=

# ---------------------------------------------------------------- TypeScript
measure_typescript() {
  local nm="n/a (no pnpm)"
  have pnpm || { LINT=$nm; TYPES=$nm; TESTS=$nm; TESTRC=$nm; SECS=$nm; COV=$nm; return; }
  nm="n/a (dependencies not installed: no node_modules)"
  [ -d "$P/node_modules" ] || { LINT=$nm; TYPES=$nm; TESTS=$nm; TESTRC=$nm; SECS=$nm; COV=$nm; return; }

  # Lint: the tool is called directly, never through a project script.
  if ls "$P"/eslint.config.* >/dev/null 2>&1; then
    limited "$S/eslint.log" pnpm exec eslint . -f json -o "$S/eslint.json"
    local n; n=$(jval eslint "$S/eslint.json")
    if [ -n "$n" ]; then LINT=$n; else LINT="n/a (eslint failed, exit $RC)"; fi
  else LINT="n/a (no eslint.config.*)"; fi

  # Types: tsc has no machine-readable output; count its own `error TS` lines from the captured file.
  if [ -f "$P/tsconfig.json" ]; then
    limited "$S/tsc.log" pnpm exec tsc --noEmit
    if [ "$RC" -eq 124 ]; then TYPES="n/a (timeout)"
    elif [ "$RC" -eq 0 ]; then TYPES=0
    elif grep -q 'error TS' "$S/tsc.log"; then TYPES=$(grep -c 'error TS' "$S/tsc.log")
    else TYPES="n/a (tsc failed, exit $RC)"; fi
  else TYPES="n/a (no tsconfig.json)"; fi

  # Tests and coverage in one run.
  local t0 t1
  t0=$(date +%s)
  if grep -q '"vitest"' "$P/package.json"; then
    limited "$S/test.log" pnpm exec vitest run --coverage --coverage.reporter=cobertura --coverage.reportsDirectory="$S/cov" --reporter=json --outputFile="$S/vitest.json"
    t1=$(date +%s)
    local r; r=$(jval vitest "$S/vitest.json")
    if [ -n "$r" ]; then TESTS="${r% *} failed of ${r#* }"; else TESTS="n/a (no test report, exit $RC)"; fi
  elif grep -q '"jest"' "$P/package.json"; then
    limited "$S/test.log" pnpm exec jest --coverage --coverageReporters=cobertura --coverageDirectory="$S/cov" --json --outputFile="$S/jest.json"
    t1=$(date +%s)
    local jt
    jt=$(jval vitest "$S/jest.json")   # jest --json uses the same numFailedTests / numTotalTests keys
    if [ -n "$jt" ]; then TESTS="${jt% *} failed of ${jt#* }"; else TESTS="n/a (no test report, exit $RC)"; fi
  else
    TESTS="n/a (no vitest or jest in package.json)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return
  fi
  if [ "$RC" -eq 124 ]; then TESTRC="timeout"; else TESTRC=$RC; fi
  SECS=$((t1 - t0))
  local c; c=$(jval cobertura "$S/cov/cobertura-coverage.xml")
  if [ -n "$c" ]; then COV="$c%"; else COV="n/a (no coverage report; is a coverage provider installed?)"; fi
}

complexity_typescript() {
  have pnpm || { CPLX="n/a (no pnpm)"; return; }
  local cc="$S/cc"
  copy_tree "$cc" || { CPLX="n/a (could not copy the working tree)"; return; }
  # A minimal manifest: the scratch run needs the three lint packages and no project dependency.
  rm -f "$cc/pnpm-lock.yaml" "$cc/pnpm-workspace.yaml" "$cc/package-lock.json" "$cc/yarn.lock"
  printf '{"name":"qbaseline-scratch","private":true}\n' >"$cc/package.json"
  cat >"$cc/cc.eslint.config.mjs" <<CFG
import tseslint from 'typescript-eslint';
import sonarjs from 'eslint-plugin-sonarjs';
export default [
  { ignores: ['**/node_modules/**', '**/dist/**', '**/.next/**', '**/coverage/**', '**/build/**', '**/*.d.ts'] },
  {
    files: ['**/*.{ts,tsx,js,jsx,mjs,cjs}'],
    languageOptions: { parser: tseslint.parser, parserOptions: { ecmaFeatures: { jsx: true } } },
    plugins: { sonarjs },
    rules: { 'sonarjs/cognitive-complexity': ['error', ${COMPLEXITY_LIMIT}] },
  },
];
CFG
  ( cd "$cc" && pnpm add -D --ignore-workspace --ignore-scripts --save-exact "eslint@$ESLINT_VERSION" "typescript-eslint@$TSESLINT_VERSION" "eslint-plugin-sonarjs@$SONARJS_VERSION" ) </dev/null >"$S/cc-install.log" 2>&1 \
    || { CPLX="n/a (could not install the scratch lint tools)"; return; }
  ( cd "$cc" && pnpm exec eslint -c cc.eslint.config.mjs --no-inline-config . -f json -o "$S/cc.json" ) </dev/null >"$S/cc-run.log" 2>&1
  local n; n=$(jval sonar "$S/cc.json")
  if [ -n "$n" ]; then CPLX=$n; else CPLX="n/a (complexity run failed)"; fi
}

# ---------------------------------------------------------------- Python
py_bin() { # py_bin <tool>: project virtualenv first, then PATH
  if [ -x "$P/.venv/bin/$1" ]; then echo "$P/.venv/bin/$1"; elif have "$1"; then command -v "$1"; fi
}

measure_python() {
  local ruff py
  ruff=$(py_bin ruff)
  py=$(py_bin python); [ -n "$py" ] || py=$(py_bin python3)

  if [ -n "$ruff" ]; then
    limited "$S/ruff.log" "$ruff" check --output-format json -o "$S/ruff.json" .
    local n; n=$(jval list "$S/ruff.json")
    if [ -n "$n" ]; then LINT=$n; else LINT="n/a (ruff failed, exit $RC)"; fi
    TOOLS="${TOOLS}$("$ruff" --version 2>/dev/null); "
  else LINT="n/a (ruff not installed)"; fi

  local pyright mypy
  pyright=$(py_bin pyright); mypy=$(py_bin mypy)
  if [ -n "$pyright" ] && { [ -f "$P/pyrightconfig.json" ] || grep -q 'tool.pyright' "$P/pyproject.toml" 2>/dev/null; }; then
    limited "$S/pyright.json" "$pyright" --outputjson
    local n; n=$(jval pyright "$S/pyright.json")
    if [ -n "$n" ]; then TYPES=$n; else TYPES="n/a (pyright failed, exit $RC)"; fi
  elif [ -n "$mypy" ] && { [ -f "$P/mypy.ini" ] || grep -q 'tool.mypy' "$P/pyproject.toml" 2>/dev/null; }; then
    limited "$S/mypy.log" "$mypy" .
    if [ "$RC" -eq 124 ]; then TYPES="n/a (timeout)"; else TYPES=$(grep -c ': error:' "$S/mypy.log"); fi
  else TYPES="n/a (no configured type checker on PATH or in .venv)"; fi

  if [ -z "$py" ]; then TESTS="n/a (no python)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return; fi
  if ! "$py" -c 'import pytest' >/dev/null 2>&1; then TESTS="n/a (pytest not installed)"; TESTRC=$TESTS; SECS=$TESTS; COV=$TESTS; return; fi
  local covarg="--cov=$SRC" t0 t1
  "$py" -c 'import pytest_cov' >/dev/null 2>&1 || covarg=
  t0=$(date +%s)
  # shellcheck disable=SC2086
  PYTHONDONTWRITEBYTECODE=1 COVERAGE_FILE="$S/.coverage" limited "$S/pytest.log" "$py" -m pytest --junitxml="$S/junit.xml" -q -p no:cacheprovider $covarg --cov-report="xml:$S/coverage.xml"
  t1=$(date +%s)
  local r; r=$(jval junit "$S/junit.xml")
  if [ -n "$r" ]; then TESTS="${r% *} failed of ${r#* }"; else TESTS="n/a (no test report, exit $RC)"; fi
  if [ "$RC" -eq 124 ]; then TESTRC="timeout"; else TESTRC=$RC; fi
  SECS=$((t1 - t0))
  if [ -z "$covarg" ]; then COV="n/a (pytest-cov not installed)"
  else
    local c; c=$(jval cobertura "$S/coverage.xml")
    if [ -n "$c" ]; then COV="$c%"; else COV="n/a (no coverage report)"; fi
  fi
}

complexity_python() {
  local ruff; ruff=$(py_bin ruff)
  [ -n "$ruff" ] || { CPLX="n/a (ruff not installed)"; return; }
  local cc="$S/cc"
  copy_tree "$cc" || { CPLX="n/a (could not copy the working tree)"; return; }
  ( cd "$cc" && "$ruff" check --isolated --select C901 --config "lint.mccabe.max-complexity = $COMPLEXITY_LIMIT" --output-format json -o "$S/c901.json" . ) </dev/null >"$S/c901.log" 2>&1
  local n; n=$(jval list "$S/c901.json")
  if [ -n "$n" ]; then CPLX="$n (cyclomatic proxy)"; else CPLX="n/a (ruff C901 run failed)"; fi
}

# ---------------------------------------------------------------- Duplication
measure_duplication() {
  local runner
  if have pnpm && [ "$STACK" = typescript ]; then runner="pnpm dlx"
  elif have npx; then runner="npx --yes"
  elif have pnpm; then runner="pnpm dlx"
  else DUP="n/a (no pnpm or npx)"; return; fi
  # shellcheck disable=SC2086
  limited "$S/jscpd.log" $runner "jscpd@$JSCPD_VERSION" --reporters json --output "$S/jscpd" \
    --ignore '**/node_modules/**,**/.next/**,**/dist/**,**/coverage/**,**/.venv/**,**/__pycache__/**' "$SRC"
  local n; n=$(jval jscpd "$S/jscpd/jscpd-report.json")
  if [ -n "$n" ]; then DUP="$n%"; else DUP="n/a (jscpd failed, exit $RC)"; fi
}

# ---------------------------------------------------------------- Static counts
TESTRE='(\.(test|spec)\.[cm]?[jt]sx?$|(^|/)(__tests__|tests?)/|(^|/)test_[^/]*\.py$|_test\.py$)'
CODERE='\.([cm]?[jt]sx?|py)$'
SKIPRE='(\.d\.ts$|(^|/)(__snapshots__|generated|fixtures|node_modules|dist|\.next|\.venv)/)'
SUPPRESS='eslint-disable|noqa|type: ignore|@ts-expect-error|@ts-ignore|NOSONAR|istanbul ignore|c8 ignore|pragma: no cover'
EXCLUDE='coverage\.exclude|collectCoverageFrom|coveragePathIgnorePatterns|\[tool\.coverage|^[[:space:]]*omit[[:space:]]*=|sonar\.(coverage\.|cpd\.)?exclusions|^[[:space:]]*ignores[[:space:]]*:'
THRESH='coverageThreshold|thresholds|fail_under|fail-under'
CASERE='^[[:space:]]*((it|test)(\.[a-z]+)?\(|(async )?def test_)'

count_static() {
  local f tl=0 sl=0 cases=0 supp=0 excl=0 thr=0 n
  while IFS= read -r -d '' f; do
    [ -f "$P/$f" ] || continue
    if printf '%s' "$f" | grep -Eq "$CODERE" && ! printf '%s' "$f" | grep -Eq "$SKIPRE"; then
      n=$(grep -c . "$P/$f" 2>/dev/null); n=${n:-0}
      if printf '%s' "$f" | grep -Eq "$TESTRE"; then
        tl=$((tl + n))
        n=$(grep -cE "$CASERE" "$P/$f" 2>/dev/null); cases=$((cases + ${n:-0}))
      else
        sl=$((sl + n))
      fi
      n=$(grep -cE "$SUPPRESS" "$P/$f" 2>/dev/null); supp=$((supp + ${n:-0}))
    fi
    case "$(basename "$f")" in
      vitest.config.*|jest.config.*|package.json|pyproject.toml|.coveragerc|sonar-project.properties|eslint.config.*|.eslintignore|pytest.ini|setup.cfg)
        n=$(grep -cE "$EXCLUDE" "$P/$f" 2>/dev/null); excl=$((excl + ${n:-0}))
        n=$(grep -cE "$THRESH" "$P/$f" 2>/dev/null); thr=$((thr + ${n:-0})) ;;
    esac
  done < <(list_files)
  TESTLOC=$tl SRCLOC=$sl CASES=$cases SUPP=$supp EXCL=$excl THR=$thr
  if [ "$sl" -gt 0 ]; then RATIO=$(awk -v t="$tl" -v s="$sl" 'BEGIN { printf "%.2f", t / s }'); else RATIO="n/a (no source lines)"; fi
}

# ---------------------------------------------------------------- Run
case "$STACK" in
  typescript) measure_typescript; complexity_typescript
    TOOLS="${TOOLS}eslint $ESLINT_VERSION, typescript-eslint $TSESLINT_VERSION, eslint-plugin-sonarjs $SONARJS_VERSION, jscpd $JSCPD_VERSION" ;;
  python) measure_python; complexity_python
    TOOLS="${TOOLS}jscpd $JSCPD_VERSION" ;;
esac
[ "$STACK" = unknown ] || measure_duplication
count_static

AFTER=$(status_snapshot)
if [ "$BEFORE" = "$AFTER" ]; then TREE="unchanged"; else TREE="CHANGED (a measurement wrote into the project; inspect git status)"; fi

row "stack" "$STACK"
row "lint findings" "$LINT"
row "type errors" "$TYPES"
row "tests failed" "$TESTS"
row "test exit status" "$TESTRC"
row "test seconds" "$SECS"
row "line coverage" "$COV"
row "complexity over $COMPLEXITY_LIMIT" "$CPLX"
row "duplication" "$DUP"
row "test LOC" "$TESTLOC"
row "source LOC" "$SRCLOC"
row "test:source ratio" "$RATIO"
row "test cases (static count; a parametrized case counts once)" "$CASES"
row "suppressions (code files)" "$SUPP"
row "coverage, lint and Sonar exclusions" "$EXCL"
row "coverage thresholds configured" "$THR"
row "scratch tool versions" "${TOOLS:-n/a}"
row "project tree after the run" "$TREE"

printf '| Metric | %s |\n|---|---|\n%s' "$LABEL" "$ROWS"
exit 0
