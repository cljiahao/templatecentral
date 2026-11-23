#!/usr/bin/env bash
# Duplicate-test check: check-duplicate-tests.sh [project-dir]. Offline and read-only; nothing installed, no network.
# Reads every test file of the project (Vitest/Jest-style TS/JS, pytest and unittest), finds the test cases with a real
# parser (typescript from the project's own node_modules for TS/JS, python ast and tokenize for Python), and compares
# case bodies as token sequences: comments, whitespace and the test title never count.
# Rule 1 (fails): two cases with the same body token sequence AND the same context, in one file or two. Fix: delete one.
#   The context is what can change what the body does: the imports, constants, helpers and fixtures the body names (and,
#   transitively, what those name), at the top level and in each enclosing describe or class; every setup and teardown
#   hook, mock, patch, autouse fixture, loop header and loop data around the case; the case's own decorators, parameters
#   and parameter table; for pytest, every conftest.py up to the project root. A top-level statement the body does not
#   name (an unrelated import or constant) is not context. Relative import paths count as project paths, so './a' in
#   two folders is two modules. Titles never count.
# Rule 2 (fails at SHAPE_GROUP_MIN or more, NOTE below that): cases of one file whose bodies match once every string,
#   number and boolean is replaced by a placeholder, with the same context. Fix: one parameterised test (it.each,
#   test.each, pytest.mark.parametrize). Bodies under MIN_BODY_TOKENS tokens are skipped here, never for rule 1.
# A parameterised case (it.each, it.for, parametrize) is compared with its table as part of the key: two cases with the
#   same table and body fail. A table that repeats one row fails too.
# A case that passes a named handler the same file does not define (it('a', handler)) is counted and gets a NOTE.
# Known limits, accepted: a no-op statement or a reordered body defeats rule 1, and the same shape split across files
#   defeats rule 2. The check finds copy-paste, not every semantic duplicate.
# Helpers print one record per case: kind, file, line, token count, exact key, shape key (tab-separated).
# Exit 0 clean (or an empty project that declares no tests), 1 findings, 2 cannot run (missing node, python3 or
#   typescript, unparsable file, a file name with a tab or newline, test files that hold no test case, a declared test
#   script or config with no test file found, test cases that were read but none compared).
# There is no inline ignore and no environment switch; the only way to stop the check is to not run it.
set -uo pipefail
export LC_ALL=C

# Rule 1 bodies shorter than this still count. Rule 2 skips bodies shorter than this many tokens: 30 tokens is about
# one call, one assignment and one assert, so shorter bodies are one-assert tests that a table would not simplify.
MIN_BODY_TOKENS=30
# Rule 2 fails when a file holds at least this many same-shape cases; two cases only print a NOTE.
SHAPE_GROUP_MIN=3
# Folders never read at any depth, plus any folder holding a pyvenv.cfg.
SKIP_ANY='node_modules .git .venv venv __pycache__ site-packages .mypy_cache .pytest_cache .ruff_cache'
# Build output and tool folders skipped only at the project root: src/env or src/out can hold real tests.
SKIP_ROOT='.next .nuxt dist build out coverage env .turbo .claude .tox'
# Build output skipped at any depth when it sits beside a package.json or pyproject.toml, because compiled tests repeat their source.
SKIP_PACKAGE='dist build out coverage .next .turbo'

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
for d in $SKIP_ANY; do
  if [ "$first" -eq 1 ]; then first=0; else prune_args+=(-o); fi
  prune_args+=(-name "$d")
done
root_glob=$(printf '%s' "$root" | sed 's/[][*?\\]/\\&/g')
for d in $SKIP_ROOT; do
  prune_args+=(-o -path "$root_glob/$d")
done

find "$root" \( -name node_modules -o -name .git \) -prune -o -name pyvenv.cfg -type f -print > "$wd/venvs" 2> /dev/null || die "cannot walk $root"
root_real=$(cd "$root" && pwd -P) || die "cannot resolve $root"

# Test files (regular files and symlinks), NUL-separated: two lists, one per language.
find "$root" \( "${prune_args[@]}" \) -prune -o \( -type f -o -type l \) \( \
  -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' -o -name '*.test.mjs' -o -name '*.test.cjs' -o -name '*.test.mts' -o -name '*.test.cts' \
  -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' -o -name '*.spec.mjs' -o -name '*.spec.cjs' -o -name '*.spec.mts' -o -name '*.spec.cts' \
  -o -name '*-test.ts' -o -name '*-test.tsx' -o -name '*-test.js' -o -name '*-test.jsx' -o -name '*-test.mjs' -o -name '*-test.cjs' -o -name '*-test.mts' -o -name '*-test.cts' \
  -o -name '*-spec.ts' -o -name '*-spec.tsx' -o -name '*-spec.js' -o -name '*-spec.jsx' -o -name '*-spec.mjs' -o -name '*-spec.cjs' -o -name '*-spec.mts' -o -name '*-spec.cts' \
  -o -name '*.cy.ts' -o -name '*.cy.tsx' -o -name '*.cy.js' -o -name '*.cy.jsx' -o -name '*.cy.mjs' -o -name '*.test-d.ts' -o -name '*.test-d.tsx' \
  -o -path '*/__tests__/*.ts' -o -path '*/__tests__/*.tsx' -o -path '*/__tests__/*.js' -o -path '*/__tests__/*.jsx' -o -path '*/__tests__/*.mjs' -o -path '*/__tests__/*.cjs' -o -path '*/__tests__/*.mts' -o -path '*/__tests__/*.cts' \
  \) -print0 2> /dev/null | sort -z > "$wd/ts.raw" || die "cannot walk $root"
find "$root" \( "${prune_args[@]}" \) -prune -o \( -type f -o -type l \) \( -name 'test*.py' -o -name '*_test.py' \) -print0 2> /dev/null | sort -z > "$wd/py.raw" || die "cannot walk $root"

# resolve_link <path>: prints the final target of a symlink chain, or nothing when it dangles.
resolve_link() {
  local p=$1 t n=0
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 20 ] || return 0
    t=$(readlink "$p") || return 0
    case "$t" in /*) p=$t ;; *) p=${p%/*}/$t ;; esac
  done
  [ -f "$p" ] || return 0
  printf '%s/%s\n' "$(cd "${p%/*}" 2> /dev/null && pwd -P)" "${p##*/}"
}

# in_package_output <root-relative path>: succeeds when a folder on the path is build output beside a package.json or pyproject.toml.
in_package_output() {
  local rest=${1%/*} dir='' part
  [ "$rest" != "$1" ] || return 1
  while [ -n "$rest" ]; do
    case "$rest" in */*) part=${rest%%/*} rest=${rest#*/} ;; *) part=$rest rest= ;; esac
    case " $SKIP_PACKAGE " in
      *" $part "*)
        if [ -f "$root/$dir/package.json" ] || [ -f "$root/$dir/pyproject.toml" ]; then return 0; fi
        ;;
    esac
    dir=${dir:+$dir/}$part
  done
  return 1
}

# strip_venvs <raw> <out>: drops files under a virtual environment and unusable symlinks, writes root-relative
# NUL-separated names. A name with a tab or newline would break the tab-separated records: that stops the run.
strip_venvs() {
  local f dir skip v target
  : > "$2"
  while IFS= read -r -d '' f; do
    case "$f" in
      *$'\t'* | *$'\n'*) die "a test file name holds a tab or newline: rename it ($(printf '%s' "$f" | tr '\t\n' '??'))" ;;
    esac
    skip=0
    while IFS= read -r v; do
      dir=${v%/*}
      case "$f" in "$dir"/*) skip=1 ;; esac
    done < "$wd/venvs"
    [ "$skip" -eq 0 ] || continue
    if in_package_output "${f#"$root"/}"; then continue; fi
    if [ -L "$f" ]; then
      target=$(resolve_link "$f")
      case "$target" in
        "$root_real"/*) ;;
        *)
          printf 'NOTE %s: symlink to a file outside the project or to nothing; not read.\n' "${f#"$root"/}" >> "$wd/notes"
          continue
          ;;
      esac
      if [ -s "$wd/real" ] && grep -Fxq -- "$target" "$wd/real"; then continue; fi
    fi
    printf '%s\0' "${f#"$root"/}" >> "$2"
  done < "$1"
}
# declared_tests: prints what declares tests (a package.json test script, a vitest or jest config, a pytest config), or nothing.
declared_tests() {
  local f found=
  while IFS= read -r f; do
    case "${f##*/}" in
      package.json) grep -Eq '"test(:[^"]*)?"[[:space:]]*:' "$f" 2> /dev/null && found="$found ${f#"$root"/}" ;;
      pyproject.toml) grep -Eq '^\[tool\.pytest' "$f" 2> /dev/null && found="$found ${f#"$root"/}" ;;
      setup.cfg | tox.ini) grep -Eq '^\[(tool:)?pytest\]' "$f" 2> /dev/null && found="$found ${f#"$root"/}" ;;
      *) found="$found ${f#"$root"/}" ;;
    esac
  done < <(find "$root" \( "${prune_args[@]}" \) -prune -o -type f \( -name package.json -o -name 'vitest.config.*' -o -name 'jest.config.*' -o -name pytest.ini -o -name pyproject.toml -o -name setup.cfg -o -name tox.ini \) -print 2> /dev/null | sort)
  printf '%s' "${found# }"
}

: > "$wd/notes"
: > "$wd/real"
# Paths of the regular test files first, so a symlink to one of them is skipped, not compared with itself.
for raw in "$wd/ts.raw" "$wd/py.raw"; do
  while IFS= read -r -d '' f; do
    [ ! -L "$f" ] || continue
    printf '%s/%s\n' "$(cd "${f%/*}" 2> /dev/null && pwd -P)" "${f##*/}" >> "$wd/real"
  done < "$raw"
done
strip_venvs "$wd/ts.raw" "$wd/ts.list"
strip_venvs "$wd/py.raw" "$wd/py.list"

: > "$wd/records"
if [ ! -s "$wd/ts.list" ] && [ ! -s "$wd/py.list" ]; then
  cat "$wd/notes"
  declared=$(declared_tests)
  if [ -n "$declared" ]; then
    die "no test files found, but the project declares tests ($declared): searched $root for *.test.*, *.spec.*, *-test.*, *-spec.*, *.cy.ts(x), *.test-d.ts, __tests__/*, test*.py and *_test.py, skipping $SKIP_ANY and, at the project root, $SKIP_ROOT; move the tests under a searched name or fix the layout"
  fi
  printf 'check-duplicate-tests: nothing to check, no test files and no declared test script or config\n'
  exit 0
fi

if [ -s "$wd/ts.list" ]; then
  command -v node > /dev/null 2>&1 || die "node is missing but the project has TS/JS test files: install Node.js (see .nvmrc or package.json engines) and run again"
  node "$HERE/duplicate-tests-ts.mjs" "$root" "$wd/ts.list" >> "$wd/records" || die "the TypeScript scan failed (see above); fix that first"
fi
if [ -s "$wd/py.list" ]; then
  py=python3
  [ ! -x "$root/.venv/bin/python3" ] || py="$root/.venv/bin/python3"
  command -v "$py" > /dev/null 2>&1 || die "python3 is missing but the project has Python test files: install Python 3 and run again"
  "$py" "$HERE/duplicate_tests_py.py" "$root" "$wd/py.list" >> "$wd/records" || die "the Python scan failed (see above); fix that first"
fi

ncases=$(awk 'END { print NR }' "$wd/records")
if [ "$ncases" -eq 0 ]; then
  die "test files exist but hold no test case the check recognises: the check would pass without reading anything"
fi

# Records are: kind (C compared, R repeated table row, U unresolved handler, T no body), file, line, tokens, exact key, shape key.
# Findings go to stdout, FAIL lines first.
awk -F '\t' -v min="$MIN_BODY_TOKENS" -v group="$SHAPE_GROUP_MIN" '
  function loc(i) { return F[i] ":" L[i] }
  {
    if ($1 == "T") {
      bodyless++
      next
    }
    if ($1 == "U") {
      unresolved++
      printf "NOTE %s:%s: the case passes a named handler that is not defined in this file; counted, not compared.\n", $2, $3
      next
    }
    if ($1 == "R") {
      printf "FAIL %s:%s: the parameter table repeats a row, so one case runs twice. Fix: delete the repeated row.\n", $2, $3
      rows++
      next
    }
    if ($1 != "C") next
    compared++
    n++
    F[n] = $2; L[n] = $3; T[n] = $4 + 0; E[n] = $5; S[n] = $6
    EC[$5]++
    if (EC[$5] == 1) Eorder[++ne] = $5
    EL[$5, EC[$5]] = n
  }
  END {
    fails = rows + 0
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
        printf "FAIL %s: %d test cases in one file differ only in literal values. Fix: merge them into one parameterised test (it.each / test.each, pytest.mark.parametrize) with one row per case. Cases: %s.\n", loc(SL[key, 1]), c, list
        fails++
      } else {
        printf "NOTE %s: %d test cases differ only in literal values (%s). Consider one parameterised test when a third case arrives.\n", loc(SL[key, 1]), c, list
      }
    }
    print compared + 0, unresolved + 0, bodyless + 0 > "/dev/stderr"
    exit fails > 0 ? 1 : 0
  }
' "$wd/records" > "$wd/out" 2> "$wd/count"
rc=$?
case "$rc" in 0 | 1) ;; *) die "internal failure while comparing test cases" ;; esac
read -r ncompared nunresolved nbodyless < "$wd/count"
cat "$wd/notes" "$wd/out" | sort -s -k1,1
if [ "$ncompared" -eq 0 ]; then
  if [ "$nunresolved" -gt 0 ]; then
    die "$ncases test cases were read but none could be compared ($nunresolved name a handler the file does not define, $nbodyless have no body, such as todo): inline the test bodies so the check can read them"
  fi
  die "$ncases test cases were read but none has a body to compare (todo or pending cases): write the test bodies, or the check has nothing to read"
fi
if [ "$rc" -eq 0 ]; then
  printf 'check-duplicate-tests: ok, %s test cases compared, %s read\n' "$ncompared" "$ncases"
fi
exit "$rc"
