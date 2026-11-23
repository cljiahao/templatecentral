#!/usr/bin/env bash
# Duplicate-test check: check-duplicate-tests.sh [project-dir]. Offline and read-only; nothing installed, no network.
# Reads every test file of the project (Vitest/Jest-style TS/JS and pytest), finds the test cases with a real parser
# (the project's own typescript for TS/JS, python3 ast and tokenize for pytest), and compares case bodies as token
# sequences: comments, whitespace and the test title never count.
# Rule 1 (fails): two cases with the same body token sequence, in one file or two. Fix: delete one.
# Rule 2 (fails at SHAPE_GROUP_MIN or more, NOTE below that): cases of one file whose bodies match once every string,
#   number and boolean is replaced by a placeholder. Fix: one parameterised test (it.each, test.each,
#   pytest.mark.parametrize). Bodies under MIN_BODY_TOKENS tokens are skipped here, never for rule 1.
# A case already parameterised (it.each, test.each, parametrize) is never compared: its table differs per row.
# Two cases only match when their setup matches too: enclosing beforeEach/afterEach/vi.*/jest.* statements and the
# callback parameters for TS/JS; decorators, fixture arguments, class setup methods and conftest.py files for pytest.
# Helpers print one record per case: file, line, token count, exact key, shape key (tab-separated).
# Exit 0 clean (or no test files), 1 findings, 2 cannot run (missing node, python3 or typescript, unparsable file).
# There is no inline ignore and no environment switch; the only way to stop the check is to not run it.
set -uo pipefail
export LC_ALL=C

# Rule 1 bodies shorter than this still count. Rule 2 skips bodies shorter than this many tokens: 30 tokens is about
# one call, one assignment and one assert, so shorter bodies are one-assert tests that a table would not simplify.
MIN_BODY_TOKENS=30
# Rule 2 fails when a file holds at least this many same-shape cases; two cases only print a NOTE.
SHAPE_GROUP_MIN=3
# Folders never read (any depth), plus any folder holding a pyvenv.cfg.
SKIP_DIRS='node_modules .next .nuxt dist build out coverage .venv venv env __pycache__ .git .turbo .claude .tox .mypy_cache .pytest_cache .ruff_cache site-packages'

die() {
  printf 'check-duplicate-tests: %s\n' "$1" >&2
  exit 2
}

[ "$#" -le 1 ] || die "one project folder at most"
HERE=$(cd "$(dirname "$0")" 2> /dev/null && pwd) || die "cannot find the script folder"
TARGET=${1:-$HERE/..}
[ -d "$TARGET" ] || die "not a folder: $TARGET"
root=$(cd "$TARGET" 2> /dev/null && pwd) || die "cannot enter $TARGET"

for tool in awk find mktemp rm sort; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done

wd=
trap '[ -z "$wd" ] || rm -rf "$wd"' EXIT
wd=$(mktemp -d "${TMPDIR:-/tmp}/duplicate-tests.XXXXXX") || die "cannot create a temporary folder (mktemp failed)"
[ -d "$wd" ] || die "cannot create a temporary folder (mktemp returned no folder)"

prune_args=()
first=1
for d in $SKIP_DIRS; do
  if [ "$first" -eq 1 ]; then first=0; else prune_args+=(-o); fi
  prune_args+=(-name "$d")
done

find "$root" -name pyvenv.cfg -type f > "$wd/venvs" 2> /dev/null || die "cannot walk $root"

# Test files, NUL-separated and relative to the project: two lists, one per language.
find "$root" \( "${prune_args[@]}" \) -prune -o -type f \( \
  -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' -o -name '*.test.mjs' -o -name '*.test.cjs' -o -name '*.test.mts' -o -name '*.test.cts' \
  -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o -name '*.spec.mjs' -o -name '*.spec.cjs' -o -name '*.spec.mts' -o -name '*.spec.cts' \
  -o -path '*/__tests__/*.ts' -o -path '*/__tests__/*.tsx' -o -path '*/__tests__/*.js' -o -path '*/__tests__/*.jsx' \
  \) -print0 > "$wd/ts.raw" 2> /dev/null || die "cannot walk $root"
find "$root" \( "${prune_args[@]}" \) -prune -o -type f \( -name 'test_*.py' -o -name '*_test.py' \) -print0 > "$wd/py.raw" 2> /dev/null || die "cannot walk $root"

# strip_venvs <raw> <out>: drops files under a virtual environment, writes root-relative NUL-separated names.
strip_venvs() {
  local f dir skip v
  : > "$2"
  while IFS= read -r -d '' f; do
    skip=0
    while IFS= read -r v; do
      dir=${v%/*}
      case "$f" in "$dir"/*) skip=1 ;; esac
    done < "$wd/venvs"
    [ "$skip" -eq 0 ] || continue
    printf '%s\0' "${f#"$root"/}" >> "$2"
  done < "$1"
}
strip_venvs "$wd/ts.raw" "$wd/ts.list"
strip_venvs "$wd/py.raw" "$wd/py.list"

: > "$wd/records"
if [ ! -s "$wd/ts.list" ] && [ ! -s "$wd/py.list" ]; then
  printf 'check-duplicate-tests: no test files found, nothing to compare\n'
  exit 0
fi

if [ -s "$wd/ts.list" ]; then
  command -v node > /dev/null 2>&1 || die "node is missing but the project has TS/JS test files: install Node.js (see .nvmrc or package.json engines) and run again"
  node "$HERE/duplicate-tests-ts.mjs" "$root" "$wd/ts.list" >> "$wd/records" || die "the TypeScript scan failed (see above); fix that first"
fi
if [ -s "$wd/py.list" ]; then
  command -v python3 > /dev/null 2>&1 || die "python3 is missing but the project has pytest files: install Python 3 and run again"
  python3 "$HERE/duplicate_tests_py.py" "$root" "$wd/py.list" >> "$wd/records" || die "the Python scan failed (see above); fix that first"
fi

ncases=$(awk 'END { print NR }' "$wd/records")
if [ "$ncases" -eq 0 ]; then
  printf 'check-duplicate-tests: no test cases found in the test files, nothing to compare\n'
  exit 0
fi

# Records are: file, line, tokens, exact key, shape key. Findings go to stdout, FAIL lines first.
awk -F '\t' -v min="$MIN_BODY_TOKENS" -v group="$SHAPE_GROUP_MIN" '
  function loc(i) { return F[i] ":" L[i] }
  {
    n++
    F[n] = $1; L[n] = $2; T[n] = $3 + 0; E[n] = $4; S[n] = $5
    EC[$4]++
    if (EC[$4] == 1) Eorder[++ne] = $4
    EL[$4, EC[$4]] = n
  }
  END {
    fails = 0
    for (k = 1; k <= ne; k++) {
      e = Eorder[k]
      if (EC[e] < 2) continue
      list = ""
      for (j = 1; j <= EC[e]; j++) list = list (j > 1 ? ", " : "") loc(EL[e, j])
      printf "FAIL %s: %d test cases have the same body (%s). Fix: delete all but one.\n", loc(EL[e, 1]), EC[e], list
      fails++
      dup[e] = 1
    }
    for (i = 1; i <= n; i++) {
      if (T[i] < min || (E[i] in dup)) continue
      key = F[i] SUBSEP S[i]
      if (!((key SUBSEP E[i]) in seen)) {
        seen[key SUBSEP E[i]] = 1
        SC[key]++
        SL[key, SC[key]] = i
        if (SC[key] == 1) Sorder[++ns] = key
      }
    }
    for (k = 1; k <= ns; k++) {
      key = Sorder[k]
      c = SC[key]
      if (c < 2) continue
      list = ""
      for (j = 1; j <= c; j++) list = list (j > 1 ? ", " : "") loc(SL[key, j])
      if (c >= group) {
        printf "FAIL %s: %d test cases in one file differ only in literal values (%s). Fix: merge them into one parameterised test (it.each / test.each, pytest.mark.parametrize).\n", loc(SL[key, 1]), c, list
        fails++
      } else {
        printf "NOTE %s: %d test cases differ only in literal values (%s). Consider one parameterised test when a third case arrives.\n", loc(SL[key, 1]), c, list
      }
    }
    exit fails > 0 ? 1 : 0
  }
' "$wd/records" > "$wd/out"
rc=$?
case "$rc" in 0 | 1) ;; *) die "internal failure while comparing test cases" ;; esac
sort -s -k1,1 "$wd/out"
if [ "$rc" -eq 0 ]; then
  printf 'check-duplicate-tests: ok, %s test cases compared\n' "$ncases"
fi
exit "$rc"
