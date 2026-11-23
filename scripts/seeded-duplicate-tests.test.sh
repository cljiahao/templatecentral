#!/usr/bin/env bash
# scripts/seeded-duplicate-tests.test.sh — tests for the seeded scripts/check-duplicate-tests.sh.
# The TS/JS side needs a typescript package: TEST_TYPESCRIPT_DIR, else a global npm install, else an npm install
# into a temporary folder (the only network use; the seeded check itself never touches the network).
# Usage: bash scripts/seeded-duplicate-tests.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/skills/scaffold/shared/template/scripts"
CHECK="$SCRIPTS/check-duplicate-tests.sh"
FIX="$REPO_ROOT/tests/fixtures/seeded-duplicate-tests"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/dupt.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

find_typescript() {
  local d
  if [ -n "${TEST_TYPESCRIPT_DIR:-}" ] && [ -f "$TEST_TYPESCRIPT_DIR/package.json" ]; then
    printf '%s\n' "$TEST_TYPESCRIPT_DIR"
    return 0
  fi
  if command -v npm > /dev/null 2>&1; then
    d=$(npm root -g 2> /dev/null)/typescript
    if [ -f "$d/package.json" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    mkdir -p "$T/tsinstall"
    if (cd "$T/tsinstall" && npm install --no-audit --no-fund --silent typescript > /dev/null 2>&1) && [ -f "$T/tsinstall/node_modules/typescript/package.json" ]; then
      printf '%s\n' "$T/tsinstall/node_modules/typescript"
      return 0
    fi
  fi
  return 1
}
TSDIR=$(find_typescript) || {
  echo "FAIL: no typescript package found: set TEST_TYPESCRIPT_DIR to a typescript folder, or allow npm install"
  exit 1
}

# project <fixture> — copies a fixture into a fresh project with typescript installed; sets P.
project() {
  P=$(mktemp -d "$T/p.XXXXXX")
  cp -R "$FIX/$1/." "$P/"
  mkdir -p "$P/node_modules"
  ln -s "$TSDIR" "$P/node_modules/typescript"
}

# run <fixture> — sets OUT and EC.
run() {
  project "$1"
  OUT=$(bash "$CHECK" "$P" 2>&1)
  EC=$?
}

# Rule 1, TS/JS: same body, comments and whitespace ignored, title ignored, .skip/.only/.concurrent are cases too.
run ts-exact-dup
check 1 "$EC" "ts rule 1: exit"
has "a.test.ts:5: 2 test cases have the same body (a.test.ts:5, a.test.ts:11)" "$OUT" "ts rule 1: names both locations"
has "Fix: delete all but one" "$OUT" "ts rule 1: names the fix"
run ts-exact-dup-cross-file
check 1 "$EC" "ts rule 1 across files: exit"
has "a.test.ts:4" "$OUT" "ts rule 1 across files: first location"
has "b.spec.ts:4" "$OUT" "ts rule 1 across files: second location"
run ts-clean
check 0 "$EC" "ts clean control: exit"
has "ok, 3 test cases compared" "$OUT" "ts clean control: counts cases"
lacks "FAIL" "$OUT" "ts clean control: no failure"

# Rule 2, TS/JS: NOTE at two, FAIL at the named threshold, per file only.
run ts-shape-2
check 0 "$EC" "ts rule 2 at 2 cases: exit"
has "NOTE a.test.ts:4: 2 test cases differ only in literal values" "$OUT" "ts rule 2 at 2 cases: NOTE"
lacks "FAIL" "$OUT" "ts rule 2 at 2 cases: no failure"
run ts-shape-3
check 1 "$EC" "ts rule 2 at 3 cases: exit"
has "FAIL a.test.ts:4: 3 test cases in one file differ only in literal values (a.test.ts:4, a.test.ts:10, a.test.ts:16)" "$OUT" "ts rule 2 at 3 cases: locations"
has "it.each / test.each, pytest.mark.parametrize" "$OUT" "ts rule 2 at 3 cases: names the fix"
run ts-shape-cross-file
check 0 "$EC" "ts same shape in 3 files: exit"
lacks "NOTE" "$OUT" "ts same shape in 3 files: no note"
lacks "FAIL" "$OUT" "ts same shape in 3 files: no failure"
run ts-nested
check 1 "$EC" "ts nested describe: exit"
has "3 test cases in one file differ only in literal values" "$OUT" "ts nested describe: three cases found at any depth"
has "a.test.ts:7" "$OUT" "ts nested describe: innermost case"

# Already parameterised, different setup, text in strings and comments, trivial bodies.
run ts-parameterised
check 0 "$EC" "ts it.each and test.each never flagged: exit"
has "no test cases found" "$OUT" "ts it.each and test.each are not compared"
run ts-different-setup
check 0 "$EC" "ts same body under different beforeEach: exit"
lacks "FAIL" "$OUT" "ts same body under different beforeEach: no failure"
run ts-in-strings
check 0 "$EC" "ts test text in strings and comments: exit"
has "ok, 1 test cases compared" "$OUT" "ts test text in strings and comments is not a test"
run ts-trivial-shape
check 0 "$EC" "ts trivial same-shape bodies: exit"
lacks "NOTE" "$OUT" "ts trivial same-shape bodies: skipped for rule 2"
run ts-trivial-exact
check 1 "$EC" "ts trivial identical bodies: exit"
has "2 test cases have the same body" "$OUT" "ts trivial identical bodies still fail rule 1"

# Python: same checks.
run py-exact-dup
check 1 "$EC" "py rule 1: exit"
has "test_a.py:4: 2 test cases have the same body (test_a.py:4, test_a.py:11)" "$OUT" "py rule 1: names both locations"
has "Fix: delete all but one" "$OUT" "py rule 1: names the fix"
run py-exact-dup-class
check 1 "$EC" "py rule 1 across test classes: exit"
has "test_a.py:5, test_a.py:11" "$OUT" "py rule 1 across test classes: methods found"
run py-clean
check 0 "$EC" "py clean control: exit"
has "ok, 3 test cases compared" "$OUT" "py clean control: counts functions and class methods"
run py-shape-2
check 0 "$EC" "py rule 2 at 2 cases: exit"
has "NOTE test_a.py:4: 2 test cases differ only in literal values" "$OUT" "py rule 2 at 2 cases: NOTE"
run py-shape-3
check 1 "$EC" "py rule 2 at 3 cases: exit"
has "FAIL test_a.py:4: 3 test cases in one file differ only in literal values (test_a.py:4, test_a.py:12, test_a.py:21)" "$OUT" "py rule 2 at 3 cases: locations, class method included"
has "pytest.mark.parametrize" "$OUT" "py rule 2 at 3 cases: names the fix"
run py-shape-cross-file
check 0 "$EC" "py same shape in 3 files: exit"
lacks "NOTE" "$OUT" "py same shape in 3 files: no note"
run py-parameterised
check 0 "$EC" "py parametrize never flagged: exit"
has "no test cases found" "$OUT" "py parametrize cases are not compared"
run py-different-setup
check 0 "$EC" "py same body with other fixtures: exit"
lacks "FAIL" "$OUT" "py same body with other fixtures: no failure"
run py-in-strings
check 0 "$EC" "py test text in strings and comments: exit"
has "ok, 1 test cases compared" "$OUT" "py test text in strings and comments is not a test"
run py-trivial-shape
check 0 "$EC" "py trivial same-shape bodies: exit"
lacks "NOTE" "$OUT" "py trivial same-shape bodies: skipped for rule 2"
run py-trivial-exact
check 1 "$EC" "py trivial identical bodies: exit"

# Fix control: the flagged project passes once its tests are replaced by distinct ones.
project ts-shape-3
rm "$P/a.test.ts"
cp "$FIX/ts-clean/a.test.ts" "$P/a.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "fixing a flagged project makes the check pass"

# Projects with no tests, skipped folders and virtual environments.
P=$(mktemp -d "$T/p.XXXXXX")
mkdir -p "$P/src"
printf 'export const a = 1;\n' > "$P/src/a.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "no test files: exit"
has "no test files found" "$OUT" "no test files: says so"
project ts-exact-dup
mkdir -p "$P/node_modules/dep" "$P/dist" "$P/.venv" "$P/venv2/lib" "$P/.claude/.harness-base"
cp "$P/a.test.ts" "$P/node_modules/dep/x.test.ts"
cp "$P/a.test.ts" "$P/dist/y.test.ts"
cp "$P/a.test.ts" "$P/.claude/.harness-base/z.test.ts"
printf 'home = /usr/bin\n' > "$P/venv2/pyvenv.cfg"
cp "$FIX/py-exact-dup/test_a.py" "$P/venv2/lib/test_a.py"
cp "$FIX/py-exact-dup/test_a.py" "$P/.venv/test_b.py"
OUT=$(bash "$CHECK" "$P" 2>&1)
has "(a.test.ts:5, a.test.ts:11)" "$OUT" "skipped folders: only the project file is read"
lacks "node_modules" "$OUT" "skipped folders: node_modules not read"
lacks "dist" "$OUT" "skipped folders: build output not read"
lacks "venv" "$OUT" "skipped folders: virtual environments not read"
lacks ".harness-base" "$OUT" "skipped folders: harness copies not read"

# Fail closed: missing runtime, missing typescript, unparsable file, bad input.
BIN="$T/nobin"
mkdir -p "$BIN"
for tool in awk find mktemp rm sort dirname bash cat sed; do
  ln -s "$(command -v "$tool")" "$BIN/$tool"
done
project ts-clean
OUT=$(PATH="$BIN" "$(command -v bash)" "$CHECK" "$P" 2>&1)
check 2 "$?" "missing node: exit"
has "node is missing" "$OUT" "missing node: names the fix"
project py-clean
OUT=$(PATH="$BIN" "$(command -v bash)" "$CHECK" "$P" 2>&1)
check 2 "$?" "missing python3: exit"
has "python3 is missing" "$OUT" "missing python3: names the fix"
P=$(mktemp -d "$T/p.XXXXXX")
cp "$FIX/ts-clean/a.test.ts" "$P/"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "typescript not installed: exit"
has "pnpm install" "$OUT" "typescript not installed: names the fix"
project ts-clean
printf 'it("x", () => { const = ;\n' > "$P/broken.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "unparsable TS file: exit"
has "broken.test.ts:1: does not parse" "$OUT" "unparsable TS file: names the file"
project py-clean
printf 'def test_x(:\n' > "$P/test_broken.py"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "unparsable py file: exit"
has "test_broken.py:1: does not parse" "$OUT" "unparsable py file: names the file"
OUT=$(bash "$CHECK" "$T/does-not-exist" 2>&1)
check 2 "$?" "missing folder: exit"

# No switch from inside the project: ignore comments and environment variables change nothing.
project ts-exact-dup
sed 's|^  it.skip|  // check-duplicate-tests-disable\n  // eslint-disable-next-line\n  it.skip|' "$P/a.test.ts" > "$P/b.tmp"
mv "$P/b.tmp" "$P/a.test.ts"
OUT=$(SKIP_DUPLICATE_TESTS=1 DUPLICATE_TESTS_SKIP=1 CHECK_DUPLICATE_TESTS=0 bash "$CHECK" "$P" 2>&1)
check 1 "$?" "inline comment and environment variables do not switch the check off"

# Timing: 2000 test cases, CPU time (user + system), not wall time.
P=$(mktemp -d "$T/p.XXXXXX")
mkdir -p "$P/node_modules" "$P/pytests"
ln -s "$TSDIR" "$P/node_modules/typescript"
awk 'BEGIN {
  for (f = 1; f <= 20; f++) {
    out = sprintf("%s/f%02d.test.ts", ARGV[1], f)
    print "import { describe, expect, it } from \"vitest\";" > out
    print "describe(\"file " f "\", () => {" > out
    for (i = 1; i <= 50; i++) {
      printf "  it(\"case %d\", () => {\n    const r = compute%d_%d(%d, %d);\n    expect(r.total).toBe(%d);\n    expect(r.items.length).toBe(%d);\n  });\n", i, f, i, i, f, i + f, i * 3 > out
    }
    print "});" > out
    close(out)
  }
  for (f = 1; f <= 20; f++) {
    out = sprintf("%s/pytests/test_f%02d.py", ARGV[1], f)
    for (i = 1; i <= 50; i++) {
      printf "def test_case_%d():\n    r = compute_%d_%d(%d, %d)\n    assert r.total == %d\n    assert len(r.items) == %d\n\n\n", i, f, i, i, f, i + f, i * 3 > out
    }
    close(out)
  }
}' "$P"
count=$(grep -c 'it("case' "$P"/f*.test.ts | awk -F: '{ s += $2 } END { print s }')
pycount=$(grep -c '^def test_' "$P"/pytests/*.py | awk -F: '{ s += $2 } END { print s }')
check 1000 "$count" "timing fixture: TS cases"
check 1000 "$pycount" "timing fixture: py cases"
TIMEFORMAT='%U %S'
CPU=$({ time bash "$CHECK" "$P" > "$T/time.out" 2>&1; } 2>&1)
check 0 "$(grep -c FAIL "$T/time.out")" "timing fixture: clean"
has "ok, 2000 test cases compared" "$(cat "$T/time.out")" "timing fixture: 2000 cases compared"
ok=$(printf '%s\n' "$CPU" | awk '{ print ($1 + $2 < 5) ? "yes" : "no" }')
check yes "$ok" "2000 cases take under 5 seconds of CPU time (user+sys: $CPU)"
echo "2000-case CPU time (user sys): $CPU"

echo "seeded-duplicate-tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
