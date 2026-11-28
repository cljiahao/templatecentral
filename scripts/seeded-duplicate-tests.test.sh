#!/usr/bin/env bash
# scripts/seeded-duplicate-tests.test.sh — tests for the seeded scripts/check-duplicate-tests.sh.
# The TS/JS side needs typescript. TC_TEST_TYPESCRIPT_DIR names a typescript folder; otherwise the exact version pinned
# in skills/scaffold/shared/versions.txt is installed once into $TMPDIR/tc-test-typescript-<version> and reused. A
# global typescript is never used, so the result does not depend on the machine. The install is the only network use.
# Usage: bash scripts/seeded-duplicate-tests.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/skills/scaffold/shared/template/scripts"
CHECK="$SCRIPTS/check-duplicate-tests.sh"
FIX="$REPO_ROOT/tests/fixtures/seeded-duplicate-tests"
VERSIONS="$REPO_ROOT/skills/scaffold/shared/versions.txt"

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
  local want cache
  if [ -n "${TC_TEST_TYPESCRIPT_DIR:-}" ]; then
    [ -f "$TC_TEST_TYPESCRIPT_DIR/package.json" ] || return 1
    printf '%s\n' "$TC_TEST_TYPESCRIPT_DIR"
    return 0
  fi
  want=$(awk '$1 == "npm" && $2 == "typescript" { v = $3; sub(/^[^0-9]*/, "", v); print v; exit }' "$VERSIONS")
  [ -n "$want" ] || return 1
  cache="${TMPDIR:-/tmp}/tc-test-typescript-$want"
  if ! grep -q "\"version\": \"$want\"" "$cache/node_modules/typescript/package.json" 2> /dev/null; then
    command -v npm > /dev/null 2>&1 || return 1
    mkdir -p "$cache"
    printf '{"name":"tc-test-typescript","private":true}\n' > "$cache/package.json"
    (cd "$cache" && npm install --no-audit --no-fund --silent --cache "$cache/npmcache" "typescript@$want" > /dev/null 2>&1) || return 1
    grep -q "\"version\": \"$want\"" "$cache/node_modules/typescript/package.json" 2> /dev/null || return 1
  fi
  printf '%s\n' "$cache/node_modules/typescript"
}
TSDIR=$(find_typescript) || {
  echo "FAIL: no typescript package: set TC_TEST_TYPESCRIPT_DIR to a typescript folder, or allow the pinned npm install"
  exit 1
}

# project <fixture> — copies a fixture into a fresh project with typescript installed; sets P.
project() {
  P=$(mktemp -d "$T/p.XXXXXX")
  cp -R "$FIX/$1/." "$P/"
  git init -q "$P"
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
has "FAIL a.test.ts:4: 3 test cases in one file differ only in literal values." "$OUT" "ts rule 2 at 3 cases: message"
has "Cases: a.test.ts:4, a.test.ts:10, a.test.ts:16." "$OUT" "ts rule 2 at 3 cases: names every case with file and line"
has "merge them into one parameterised test (it.each / test.each, pytest.mark.parametrize) with one row per case" "$OUT" "ts rule 2 at 3 cases: names the fix"
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
check 0 "$EC" "ts it.each and test.each with different tables: exit"
has "ok, 4 test cases compared" "$OUT" "ts it.each and test.each are compared"
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
has "FAIL test_a.py:4: 3 test cases in one file differ only in literal values." "$OUT"
has "Cases: test_a.py:4, test_a.py:12, test_a.py:21." "$OUT" "py rule 2 at 3 cases: locations, class method included"
has "pytest.mark.parametrize" "$OUT" "py rule 2 at 3 cases: names the fix"
run py-shape-cross-file
check 0 "$EC" "py same shape in 3 files: exit"
lacks "NOTE" "$OUT" "py same shape in 3 files: no note"
run py-parameterised
check 0 "$EC" "py parametrize with different tables: exit"
has "ok, 3 test cases compared" "$OUT" "py parametrize cases are compared"
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
check 0 "$?" "empty project: exit"
has "nothing to check" "$OUT" "empty project: says so, not a pass of compared tests"
lacks "compared" "$OUT" "empty project: no compared count"
project ts-exact-dup
printf 'dist\n.claude\n' > "$P/.gitignore"
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
for tool in awk find mktemp rm sort dirname bash cat sed readlink grep tr; do
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


# ---------------------------------------------------------------------------------------------------------------
# Round 1. Every context element has a clean twin: same body, different context. If the element were dropped from the
# key, the pair would be flagged and the twin test would fail. ctx-*-same is the positive control: all equal, flagged.
twin() { # twin <fixture> <description>
  run "$1"
  check 0 "$EC" "$2: exit"
  lacks "FAIL" "$OUT" "$2: no failure"
  lacks "NOTE" "$OUT" "$2: no note"
  has "ok, 2 test cases compared" "$OUT" "$2: both cases read"
}
twin ctx-ts-import "ts context: file import differs ('./a' vs './b')"
twin ctx-ts-result-modules "ts context: same const result = f() from different modules"
twin ctx-ts-describe-const "ts context: describe-level const svc = makeA() vs makeB()"
twin ctx-ts-snapshot "ts context: same-named component snapshot tests from different modules"
twin ctx-ts-loop "ts context: loop header differs"
twin ctx-ts-loop-data "ts context: loop data differs"
twin ctx-ts-mock "ts context: top-level vi.mock path differs"
twin ctx-ts-testuse "ts context: test.use option differs"
twin ctx-ts-toplevel "ts context: top-level statement differs"
twin ctx-ts-hook "ts context: afterEach hook differs"
twin ctx-ts-params "ts context: callback parameter differs"
run ctx-ts-same
check 1 "$EC" "ts positive control, everything equal: exit"
has "2 test cases have the same body (x.test.ts:4, y.test.ts:4)" "$OUT" "ts positive control: flagged"
twin ctx-py-fixture "py context: file-local fixture of the same name returns different objects"
twin ctx-py-class-attr "py context: class attribute svc = A() vs B()"
twin ctx-py-class-decorator "py context: class decorator @patch('a.x') vs @patch('b.x')"
twin ctx-py-import "py context: same result = f() from different modules"
twin ctx-py-loop "py context: loop header differs"
twin ctx-py-loop-data "py context: loop data differs"
twin ctx-py-conftest "py context: conftest.py differs"
twin ctx-py-setup-method "py context: unittest setUp differs"
twin ctx-py-decorator "py context: own decorator differs"
twin ctx-py-toplevel "py context: top-level statement differs"
run ctx-py-same
check 1 "$EC" "py positive control, everything equal: exit"
has "2 test cases have the same body (test_x.py:10, test_y.py:10)" "$OUT" "py positive control: flagged"
# Relative imports in two folders are two modules; the same import in one folder is one module.
P=$(mktemp -d "$T/p.XXXXXX")
mkdir -p "$P/a" "$P/b" "$P/node_modules"
ln -s "$TSDIR" "$P/node_modules/typescript"
printf "import { it } from 'vitest';\nimport { f } from './f';\nit('x', () => {\n  const r = f();\n  r.go(1);\n  r.go(2);\n});\n" > "$P/a/x.test.ts"
cp "$P/a/x.test.ts" "$P/b/x.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "ts same relative import in two folders is two modules: exit"
printf "from f import f\n\n\ndef test_x():\n    r = f()\n    r.go(1)\n    r.go(2)\n" > "$P/a/test_x.py"
printf "from .f import f\n\n\ndef test_x():\n    r = f()\n    r.go(1)\n    r.go(2)\n" > "$P/b/test_x.py"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "py absolute vs relative import is not the same module: exit"
cp "$P/a/test_x.py" "$P/b/test_x.py"
printf "from .f import f\n\n\ndef test_x():\n    r = f()\n    r.go(1)\n    r.go(2)\n" > "$P/a/test_x.py"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "py relative import in two folders is two modules: exit"

# Detection: things that used to slip through.
detect() { # detect <fixture> <description> <needle>
  run "$1"
  check 1 "$EC" "$2: exit"
  has "$3" "$OUT" "$2: flagged"
}
detect det-ts-alias "ts import alias (it as t)" "2 test cases have the same body (a.test.ts:3, a.test.ts:7)"
detect det-ts-jest-globals "ts @jest/globals import" "2 test cases have the same body"
detect det-ts-namespace "ts namespace import (v.it, v.test)" "2 test cases have the same body"
detect det-ts-handler "ts it('a', handler) with same-file handlers" "2 test cases have the same body"
run det-ts-handler-unresolved
check 2 "$EC" "ts unresolved named handler only: exit 2, nothing could be compared"
has "NOTE a.test.ts:3: the case passes a named handler that is not defined in this file; counted, not compared." "$OUT" "ts unresolved named handler: NOTE"
has "2 test cases were read but none could be compared" "$OUT" "ts unresolved named handler: names the problem"
lacks "ok," "$OUT" "ts unresolved named handler: never reads as ok"
detect det-ts-in-if "ts tests inside an if block" "2 test cases have the same body"
detect det-ts-in-try "ts tests inside a try block" "2 test cases have the same body"
detect det-ts-in-helper "ts tests registered by a helper function" "2 test cases have the same body"
detect det-py-testcase "py unittest.TestCase subclass not named Test*" "2 test cases have the same body"
detect det-py-camel "py camelCase testFoo" "2 test cases have the same body"
detect det-py-names "py test file named testing_a.py" "2 test cases have the same body"
detect det-py-in-if "py tests inside an if block" "2 test cases have the same body"
detect det-py-in-try "py tests inside a try block" "2 test cases have the same body"
run det-ts-names
check 1 "$EC" "ts file names (e2e-spec, -spec, -test, mts, cts, js, jsx, mjs): exit"
has "8 test cases have the same body" "$OUT" "ts file names: all eight files read"
run zero-cases-ts
check 2 "$EC" "ts test file with zero cases: exit"
has "hold no test case" "$OUT" "ts zero cases: names the problem"
run zero-cases-py
check 2 "$EC" "py test file with zero cases: exit"

# Typescript resolution is bounded and checked.
P=$(mktemp -d "$T/p.XXXXXX")
mkdir -p "$P/parent/node_modules" "$P/parent/proj"
ln -s "$TSDIR" "$P/parent/node_modules/typescript"
cp "$FIX/ts-clean/a.test.ts" "$P/parent/proj/"
OUT=$(NODE_PATH="$P/parent/node_modules" bash "$CHECK" "$P/parent/proj" 2>&1)
check 2 "$?" "typescript only in a parent folder and NODE_PATH is not used: exit"
has "typescript not found under" "$OUT" "typescript only in a parent folder: names the fix"
project ts-clean
rm "$P/node_modules/typescript"
mkdir -p "$P/node_modules/typescript"
printf '{"name":"typescript","version":"7.0.0"}\n' > "$P/node_modules/typescript/package.json"
printf 'module.exports = {};\n' > "$P/node_modules/typescript/index.js"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "unsupported typescript 7: exit"
has "typescript 7.0.0" "$OUT" "unsupported typescript: names the version found"
has "5.x to 6.x" "$OUT" "unsupported typescript: names the supported range"
lacks "    at " "$OUT" "unsupported typescript: no stack trace"
lacks "TypeError" "$OUT" "unsupported typescript: no TypeError"
project ts-clean
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "pinned typescript works from a project node_modules"
# The same run with the CI markers set.
OUT=$(CI=true GITHUB_ACTIONS=true bash "$CHECK" "$P" 2>&1)
check 0 "$?" "check ignores CI markers: exit"

# Python interpreter: a planted project .venv/bin/python3 is never run, and the version is named in parse errors.
project py-clean
mkdir -p "$P/.venv/bin"
printf '#!/bin/sh\ntouch "%s/used-venv-python"\nprintf "FAKE\\n"\nexit 0\n' "$T" > "$P/.venv/bin/python3"
chmod +x "$P/.venv/bin/python3"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "planted .venv python: exit"
if [ -f "$T/used-venv-python" ]; then used=yes; else used=no; fi
check no "$used" "planted .venv/bin/python3 is never run"
PARSE_MSG=$(bash "$CHECK" "$(project py-clean; printf 'def test_x(:\n' > "$P/test_broken.py"; echo "$P")" 2>&1)
has "under Python 3" "$PARSE_MSG" "py parse error names the interpreter version"
has "put a newer python3 first on the path" "$PARSE_MSG" "py parse error: the fix names the python3 the gate resolves from the path"
lacks ".venv" "$PARSE_MSG" "py parse error: no project venv is named, the gate never uses one"

# Odd file names, symlinks, unreadable files, NUL bytes.
project ts-clean
printf "it('x', () => { expect(1).toBe(1); });\n" > "$P/a$(printf '\t')b.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "tab in a test file name: exit"
has "tab or newline" "$OUT" "tab in a test file name: names the problem"
project ts-clean
printf "it('x', () => { expect(1).toBe(1); });\n" > "$P/a
b.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "newline in a test file name: exit"
project ts-clean
ln -s a.test.ts "$P/link.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 0 "$?" "symlink to a test file already read is not compared with itself: exit"
has "ok, 3 test cases compared" "$OUT" "symlink to a test file: read once"
project ts-clean
mkdir -p "$P/src"
cp "$FIX/ts-exact-dup/a.test.ts" "$P/src/shared.ts"
ln -s src/shared.ts "$P/alias.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 1 "$?" "symlinked test file with an in-project target is followed: exit"
has "alias.test.ts" "$OUT" "symlinked test file: reported under the link name"
project ts-clean
mkdir -p "$T/outside"
cp "$FIX/ts-exact-dup/a.test.ts" "$T/outside/o.ts"
ln -sf "$T/outside/o.ts" "$P/out.test.ts"
ln -s missing.ts "$P/dangling.test.ts"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "symlinks to outside the project or to nothing: the gate fails"
has "is a symlink to a file outside the project or to nothing, so its tests cannot be read" "$OUT" "symlink outside the project or dangling: names the file and the fix"
if [ "$(id -u)" -ne 0 ]; then
  project ts-clean
  chmod 000 "$P/a.test.ts"
  OUT=$(bash "$CHECK" "$P" 2>&1)
  check 2 "$?" "unreadable TS test file: exit"
  has "cannot read a.test.ts" "$OUT" "unreadable TS test file: names the file"
  project py-clean
  chmod 000 "$P/test_a.py"
  OUT=$(bash "$CHECK" "$P" 2>&1)
  check 2 "$?" "unreadable py test file: exit"
  has "cannot read test_a.py" "$OUT" "unreadable py test file: names the file"
fi
project py-clean
printf 'def test_nul():\n    a = 1\0\n' > "$P/test_nul.py"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "NUL byte in a py file: exit"
has "test_nul.py: contains a NUL byte" "$OUT" "NUL byte: names the file"
lacks "Traceback" "$OUT" "NUL byte: no traceback"

# Line splitting: only \n ends a line. Vertical tab, form feed and U+2028 inside strings must not shift columns.
P=$(mktemp -d "$T/p.XXXXXX")
python3 - "$P" <<'EOF'
import sys
body = "def test_%s():\n    s = 'é\x0b\x0c é'\n    r = compute(s, 'ü')\n    assert r.total == 'é'\n    assert r.items == [' ']\n    assert r.ok\n"
open(sys.argv[1] + "/test_a.py", "w", encoding="utf-8").write("from lib import compute\n\n\n" + body % "one" + "\n\n" + body % "two")
EOF
OUT=$(bash "$CHECK" "$P" 2>&1)
check 1 "$?" "py odd line separators and non-ASCII text: exit"
has "2 test cases have the same body" "$OUT" "py odd line separators: duplicates still found"

# No switch from inside the project: ignore comments and environment variables change nothing.
project ts-exact-dup
sed 's|^  it.skip|  // check-duplicate-tests-disable\n  // eslint-disable-next-line\n  it.skip|' "$P/a.test.ts" > "$P/b.tmp"
mv "$P/b.tmp" "$P/a.test.ts"
OUT=$(SKIP_DUPLICATE_TESTS=1 DUPLICATE_TESTS_SKIP=1 CHECK_DUPLICATE_TESTS=0 bash "$CHECK" "$P" 2>&1)
check 1 "$?" "inline comment and environment variables do not switch the check off"

# ---------------------------------------------------------------------------------------------------------------
# Round 2. Each major fix has a positive case (must fail) and a clean control (must pass, both cases read).
newp() { # newp — empty project with typescript installed; sets P.
  P=$(mktemp -d "$T/p.XXXXXX")
  git init -q "$P"
  mkdir -p "$P/node_modules"
  ln -s "$TSDIR" "$P/node_modules/typescript"
}
ts_case() { # ts_case <file> <extra top-level text> <expected number> — one case; the body differs only in the number.
  mkdir -p "${1%/*}"
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\n%sit('x', () => {\n  const r = f(1);\n  expect(r.a).toBe(%s);\n  expect(r.b).toBe(3);\n});\n" "$2" "$3" > "$1"
}
py_case() { # py_case <file> <extra top-level text> <expected number>
  mkdir -p "${1%/*}"
  printf "from f import f\n%s\n\ndef test_x():\n    r = f(1)\n    assert r.a == %s\n    assert r.b == 3\n" "$2" "$3" > "$1"
}
verdict() { # verdict <want-exit> <description> — runs the check on $P
  OUT=$(bash "$CHECK" "$P" 2>&1)
  EC=$?
  check "$1" "$EC" "$2: exit"
}

# Major 1: build-output and tool folder names are skipped at the project root only.
for d in env out build dist coverage; do
  newp
  ts_case "$P/src/$d/a.test.ts" "" 2
  ts_case "$P/src/$d/b.test.ts" "" 2
  verdict 1 "ts duplicates under src/$d"
  has "2 test cases have the same body (src/$d/a.test.ts:3, src/$d/b.test.ts:3)" "$OUT" "ts duplicates under src/$d: flagged"
  ts_case "$P/src/$d/b.test.ts" "" 9
  verdict 0 "ts clean control under src/$d"
  has "ok, 2 test cases compared" "$OUT" "ts clean control under src/$d: both read"
  newp
  py_case "$P/src/$d/test_a.py" "" 2
  py_case "$P/src/$d/test_b.py" "" 2
  verdict 1 "py duplicates under src/$d"
  has "2 test cases have the same body" "$OUT" "py duplicates under src/$d: flagged"
  py_case "$P/src/$d/test_b.py" "" 9
  verdict 0 "py clean control under src/$d"
  has "ok, 2 test cases compared" "$OUT" "py clean control under src/$d: both read"
done
newp
printf 'env\ncoverage\n' > "$P/.gitignore"
ts_case "$P/env/a.test.ts" "" 2
ts_case "$P/env/b.test.ts" "" 2
ts_case "$P/coverage/a.test.ts" "" 2
ts_case "$P/coverage/b.test.ts" "" 2
ts_case "$P/src/c.test.ts" "" 7
verdict 0 "env and coverage that git ignores are not read"
lacks "FAIL" "$OUT" "env and coverage that git ignores: nothing read"
newp
ts_case "$P/src/vendor/node_modules/pkg/a.test.ts" "" 2
ts_case "$P/src/vendor/node_modules/pkg/b.test.ts" "" 2
verdict 0 "node_modules is skipped at any depth"
lacks "FAIL" "$OUT" "node_modules at depth: nothing read"

# Major 2: a top-level statement the body does not name is not context.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" $'import \'z\';\nconst k = 1;\n' 2
verdict 1 "ts unrelated import and const in the second file"
has "2 test cases have the same body (a.test.ts:3, b.test.ts:5)" "$OUT" "ts unrelated statements: flagged"
ts_case "$P/b.test.ts" $'const k = 1;\nfunction helper() { return k; }\n' 2
verdict 1 "ts unrelated const and function in the second file"
ts_case "$P/a.test.ts" $'const f2 = 1;\n' 2
ts_case "$P/b.test.ts" $'const f2 = 2;\n' 2
verdict 1 "ts different values of an unreferenced const"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst k = 1;\nit('x', () => {\n  const r = f(k);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" > "$P/a.test.ts"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst k = 2;\nit('x', () => {\n  const r = f(k);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" > "$P/b.test.ts"
verdict 0 "ts clean control: the const the body names differs"
has "ok, 2 test cases compared" "$OUT" "ts clean control, named const differs: both read"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst k = 1;\nconst m = k + 1;\nit('x', () => {\n  const r = f(m);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" > "$P/a.test.ts"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst k = 5;\nconst m = k + 1;\nit('x', () => {\n  const r = f(m);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" > "$P/b.test.ts"
verdict 0 "ts clean control: a const the named const is built from differs"
newp
py_case "$P/test_a.py" "" 2
py_case "$P/test_b.py" $'import os\nK = 1\n' 2
verdict 1 "py unrelated import and constant in the second file"
has "2 test cases have the same body (test_a.py:4, test_b.py:6)" "$OUT" "py unrelated statements: flagged"
printf "from f import f\nK = 1\n\n\ndef test_x():\n    r = f(K)\n    assert r.a == 2\n    assert r.b == 3\n" > "$P/test_a.py"
printf "from f import f\nK = 2\n\n\ndef test_x():\n    r = f(K)\n    assert r.a == 2\n    assert r.b == 3\n" > "$P/test_b.py"
verdict 0 "py clean control: the constant the body names differs"
has "ok, 2 test cases compared" "$OUT" "py clean control, named constant differs: both read"

# Major 3: parameterised cases are compared with their table in the key.
newp
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nit.each([[1, 2], [3, 4]])('a %%i', (a, b) => {\n  const r = f(a);\n  expect(r.a).toBe(b);\n  expect(r.b).toBe(3);\n});\nit.each([[1, 2], [3, 4]])('b %%i', (a, b) => {\n  const r = f(a);\n  expect(r.a).toBe(b);\n  expect(r.b).toBe(3);\n});\n" > "$P/a.test.ts"
verdict 1 "ts two it.each blocks with the same table and body"
has "2 test cases have the same body (a.test.ts:3, a.test.ts:8)" "$OUT" "ts same table and body: flagged"
sed "s/\[3, 4\]\])('b /[3, 5]])('b /" "$P/a.test.ts" > "$P/c.tmp" && mv "$P/c.tmp" "$P/a.test.ts"
verdict 0 "ts clean control: second table differs"
has "ok, 2 test cases compared" "$OUT" "ts clean control, table differs: both read"
sed 's/it.each/it.for/' "$P/a.test.ts" > "$P/c.tmp" && mv "$P/c.tmp" "$P/a.test.ts"
verdict 0 "ts it.for with different tables"
sed 's/\[3, 5\]\])/[3, 4]])/' "$P/a.test.ts" > "$P/c.tmp" && mv "$P/c.tmp" "$P/a.test.ts"
verdict 1 "ts two it.for blocks with the same table and body"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nit.each([[1, 2], [3, 4], [1, 2]])('a %%i', (a, b) => {\n  expect(f(a).a).toBe(b);\n});\n" > "$P/a.test.ts"
rm "$P/b.test.ts" 2> /dev/null
verdict 1 "ts one table repeating a row"
has "a.test.ts:3: the parameter table repeats a row" "$OUT" "ts repeated row: names the case"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nit.each\`\n  a | b\n  \${1} | \${2}\n\`('t', ({ a, b }) => {\n  expect(f(a).a).toBe(b);\n});\nit.each\`\n  a | b\n  \${1} | \${2}\n\`('t', ({ a, b }) => {\n  expect(f(a).a).toBe(b);\n});\n" > "$P/a.test.ts"
verdict 1 "ts two tagged-template tables, same table and body"
newp
printf "import pytest\nfrom f import f\n\n\n@pytest.mark.parametrize(\"x\", [1, 2])\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n\n\n@pytest.mark.parametrize(\"x\", [1, 2])\ndef test_b(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n" > "$P/test_a.py"
verdict 1 "py two parametrize tests with the same table and body"
has "2 test cases have the same body (test_a.py:6, test_a.py:13)" "$OUT" "py same table and body: flagged"
sed '12s/\[1, 2\]/[1, 3]/' "$P/test_a.py" > "$P/c.tmp" && mv "$P/c.tmp" "$P/test_a.py"
verdict 0 "py clean control: second table differs"
has "ok, 2 test cases compared" "$OUT" "py clean control, table differs: both read"
printf "import pytest\nfrom f import f\n\n\n@pytest.mark.parametrize(\"x\", [1, 2, 1])\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n" > "$P/test_a.py"
verdict 1 "py one table repeating a row"
has "test_a.py:6: the parameter table repeats a row" "$OUT" "py repeated row: names the case"

# Minor 4: nothing compared is never a pass.
newp
printf '{"scripts":{"test":"vitest run"}}\n' > "$P/package.json"
verdict 2 "package.json test script, no test files"
has "declares tests (package.json)" "$OUT" "test script, no files: names what declares tests"
has "searched" "$OUT" "test script, no files: names what was searched"
newp
printf '[pytest]\ntestpaths = tests\n' > "$P/pytest.ini"
verdict 2 "pytest.ini, no test files"
newp
printf 'export default {};\n' > "$P/vitest.config.ts"
verdict 2 "vitest config, no test files"
newp
printf '[tool.pytest.ini_options]\naddopts = "-q"\n' > "$P/pyproject.toml"
verdict 2 "pyproject pytest section, no test files"
newp
printf '{"scripts":{"build":"tsc"}}\n' > "$P/package.json"
verdict 0 "package.json without a test script, no test files"
has "nothing to check" "$OUT" "no declared tests: distinct line"

# Minor 5: more test file forms and call aliases.
for name in x.cy.ts x.cy.tsx x.test-d.ts __tests__/x.cjs __tests__/x.cts __tests__/x.mts; do
  newp
  ts_case "$P/$name" "" 2
  ts_case "$P/${name/x./y.}" "" 2
  verdict 1 "duplicates in $name form"
  has "2 test cases have the same body" "$OUT" "duplicates in $name form: flagged"
done
for alias in xit xtest fit; do
  newp
  printf "import { f } from './f';\nit('x', () => {\n  const r = f(1);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n%s('y', () => {\n  const r = f(1);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" "$alias" > "$P/a.test.ts"
  verdict 1 "$alias is a test case"
  has "2 test cases have the same body" "$OUT" "$alias: flagged"
done
for alias in xdescribe fdescribe; do
  newp
  printf "import { f } from './f';\nit('x', () => {\n  const r = f(1);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n%s('s', () => {\n  it('y', () => {\n    const r = f(1);\n    expect(r.a).toBe(2);\n    expect(r.b).toBe(3);\n  });\n});\n" "$alias" > "$P/a.test.ts"
  verdict 1 "$alias is a suite"
  has "2 test cases have the same body" "$OUT" "$alias: flagged"
done

# ---------------------------------------------------------------------------------------------------------------
# Round 3. Statements that run around a case are context; package build output is skipped; more forms.
for pair in "process.env.MODE = 'a';|process.env.MODE = 'b';" "global.fetch = a;|global.fetch = b;"; do
  one=${pair%%|*}
  two=${pair##*|}
  newp
  printf "import { describe, expect, it } from 'vitest';\nimport { run } from './run';\ndescribe('A', () => {\n  %s\n  it('x', () => {\n    const r = run();\n    expect(r.ok).toBe(true);\n    expect(r.n).toBe(3);\n  });\n});\ndescribe('B', () => {\n  %s\n  it('x', () => {\n    const r = run();\n    expect(r.ok).toBe(true);\n    expect(r.n).toBe(3);\n  });\n});\n" "$one" "$two" > "$P/x.test.ts"
  verdict 0 "ts describe-level statement differs ($one)"
  has "ok, 2 test cases compared" "$OUT" "ts describe-level statement differs ($one): both read"
  printf "import { describe, expect, it } from 'vitest';\nimport { run } from './run';\ndescribe('A', () => {\n  %s\n  it('x', () => {\n    const r = run();\n    expect(r.ok).toBe(true);\n    expect(r.n).toBe(3);\n  });\n});\ndescribe('B', () => {\n  %s\n  it('x', () => {\n    const r = run();\n    expect(r.ok).toBe(true);\n    expect(r.n).toBe(3);\n  });\n});\n" "$one" "$one" > "$P/x.test.ts"
  verdict 1 "ts describe-level statement the same ($one)"
done
newp
ts_case "$P/a.test.ts" "process.env.MODE = 'a';"$'\n' 2
ts_case "$P/b.test.ts" "process.env.MODE = 'b';"$'\n' 2
verdict 0 "ts file-level assignment differs"
ts_case "$P/b.test.ts" "process.env.MODE = 'a';"$'\n' 2
verdict 1 "ts file-level assignment the same"

py_cls() { # py_cls <file> <value-a> <value-b>
  printf 'import os\nfrom f import f\n\n\nclass TestA:\n    os.environ["MODE"] = "%s"\n\n    def test_x(self):\n        r = f(1)\n        assert r.a == 2\n        assert r.b == 3\n\n\nclass TestB:\n    os.environ["MODE"] = "%s"\n\n    def test_x(self):\n        r = f(1)\n        assert r.a == 2\n        assert r.b == 3\n' "$2" "$3" > "$1"
}
newp
py_cls "$P/test_a.py" a b
verdict 0 "py class-level assignment differs"
has "ok, 2 test cases compared" "$OUT" "py class-level assignment differs: both read"
py_cls "$P/test_a.py" a a
verdict 1 "py class-level assignment the same"
newp
py_case "$P/test_a.py" 'import os
os.environ["MODE"] = "a"' 2
py_case "$P/test_b.py" 'import os
os.environ["MODE"] = "b"' 2
verdict 0 "py module-level assignment differs"
has "ok, 2 test cases compared" "$OUT" "py module-level assignment differs: both read"
py_case "$P/test_b.py" 'import os
os.environ["MODE"] = "a"' 2
verdict 1 "py module-level assignment the same"

ts_bare() { # ts_bare <file> — like ts_case but imports a package, so the same body in two folders has the same context.
  mkdir -p "${1%/*}"
  printf "import { expect, it } from 'vitest';\nimport { f } from 'lib';\nit('x', () => {\n  const r = f(1);\n  expect(r.a).toBe(2);\n  expect(r.b).toBe(3);\n});\n" > "$1"
}
# Round 4, major 1: inside a git work tree the file list is what git tracks plus what it does not ignore.
newp
mkdir -p "$P/src"
printf '{}\n' > "$P/src/package.json"
ts_case "$P/src/build/a.test.ts" "" 2
ts_case "$P/src/build/b.test.ts" "" 2
git -C "$P" add -A
verdict 1 "ts tracked tests under src/build beside a package.json"
has "src/build/a.test.ts:3" "$OUT" "ts tracked tests beside a package.json: read"
lacks "not a git repository" "$OUT" "git work tree: no build-output note"
ts_case "$P/src/build/b.test.ts" "" 9
verdict 0 "ts clean control: tracked tests under src/build differ"
has "ok, 2 test cases compared" "$OUT" "ts clean control, tracked tests under src/build: both read"
newp
printf '{}\n' > "$P/package.json"
printf 'dist\n' > "$P/.gitignore"
ts_bare "$P/dist/a.test.ts"
ts_bare "$P/dist/b.test.ts"
ts_bare "$P/src/c.test.ts"
verdict 0 "ts ignored dist copies of a test"
has "ok, 1 test cases compared" "$OUT" "ts ignored dist copies: only the source is read"
newp
printf '[project]\nname = "p"\n' > "$P/pyproject.toml"
printf 'build\n' > "$P/.gitignore"
py_case "$P/build/test_a.py" "" 2
py_case "$P/test_c.py" "" 2
verdict 0 "py ignored build copy of a test"
has "ok, 1 test cases compared" "$OUT" "py ignored build copy: only the source is read"
newp
rm -rf "$P/.git"
ts_case "$P/a.test.ts" "" 2
verdict 0 "outside a git work tree"
has "NOTE build output was not filtered because the project is not a git repository" "$OUT" "outside a git work tree: names the gap"
newp
rm -rf "$P/.git"
printf '{}\n' > "$P/package.json"
ts_case "$P/dist/a.test.ts" "" 2
ts_case "$P/dist/b.test.ts" "" 2
verdict 1 "outside a git work tree, build output is read"

# Round 4, minor 3: a symlink to a test file that git ignores still counts once.
newp
printf 'dist\n' > "$P/.gitignore"
ts_case "$P/dist/a.test.ts" "" 2
mkdir -p "$P/src"
ln -s ../dist/a.test.ts "$P/src/l.test.ts"
verdict 0 "symlink to an ignored test file"
has "ok, 1 test cases compared" "$OUT" "symlink to an ignored test file: the link is read once"

# A project with only body-less cases says so.
newp
printf "import { it } from 'vitest';\nit.todo('later');\nit.todo('sooner');\n" > "$P/a.test.ts"
verdict 2 "only it.todo cases"
has "none has a body" "$OUT" "only it.todo cases: the message says so"
lacks "does not define" "$OUT" "only it.todo cases: not blamed on handlers"

# More file forms.
for f in a.cy.js a.cy.jsx a.cy.mjs a.test-d.tsx; do
  newp
  ts_case "$P/${f%%.*}.x/$f" "" 2
  ts_case "$P/${f%%.*}.x/b.${f#*.}" "" 2
  verdict 1 "ts duplicates in $f"
done

# A table named by a constant in the same file is checked for repeated rows; ids= is not part of the key.
newp
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst rows = [[1, 2], [1, 2]];\nit.each(rows)('a %%i', (a, b) => {\n  const r = f(a);\n  expect(r.a).toBe(b);\n  expect(r.b).toBe(3);\n});\n" > "$P/a.test.ts"
verdict 1 "ts constant table repeats a row"
has "the parameter table repeats a row" "$OUT" "ts constant table repeats a row: message"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst rows = [[1, 2], [3, 4]];\nit.each(rows)('a %%i', (a, b) => {\n  const r = f(a);\n  expect(r.a).toBe(b);\n  expect(r.b).toBe(3);\n});\n" > "$P/a.test.ts"
verdict 0 "ts constant table with distinct rows"
pids() { # pids <ids-a> <table-b>
  printf 'import pytest\nfrom f import f\n\n\n@pytest.mark.parametrize("x", [1, 2], ids=["%s", "p"])\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n\n\n@pytest.mark.parametrize("x", %s)\ndef test_b(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n' "$1" "$2" > "$P/test_a.py"
}
newp
pids q "[1, 2]"
verdict 1 "py same tables and bodies, ids differ in one"
pids q "[1, 3]"
verdict 0 "py different tables, ids differ"

# declared_tests looks at any depth.
newp
mkdir -p "$P/pkg/sub/deep"
printf '{"scripts":{"test":"vitest"}}\n' > "$P/pkg/sub/deep/package.json"
verdict 2 "test script three folders deep and no test files"
has "declares tests (pkg/sub/deep/package.json)" "$OUT" "deep test script: named"
printf '{"scripts":{"build":"tsc"}}\n' > "$P/pkg/sub/deep/package.json"
verdict 0 "deep package.json without a test script"
has "nothing to check" "$OUT" "deep package.json without a test script: nothing to check"

# Round 4, major 2: a table constant resolves in the scope of the each call.
tsrows() { # tsrows <file> <first rows> <second rows>
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\ndescribe('a', () => {\n  const T = %s;\n  it.each(T)('a %%i', (a, b) => {\n    expect(f(a).a).toBe(b);\n    expect(f(a).b).toBe(3);\n  });\n});\ndescribe('b', () => {\n  const T = %s;\n  it.each(T)('b %%i', (a, b) => {\n    expect(f(a).c).toBe(b);\n    expect(f(a).d).toBe(4);\n  });\n});\n" "$2" "$3" > "$1"
}
newp
tsrows "$P/a.test.ts" "[[1, 1], [1, 1]]" "[[1, 2], [3, 4]]"
verdict 1 "ts repeat in the first describe only"
has "a.test.ts:5: the parameter table repeats a row" "$OUT" "ts repeat in the first describe: flagged"
lacks "a.test.ts:12: the parameter table" "$OUT" "ts distinct table in the second describe: not flagged"
tsrows "$P/a.test.ts" "[[1, 2], [3, 4]]" "[[1, 1], [1, 1]]"
verdict 1 "ts repeat in the second describe only"
has "a.test.ts:12: the parameter table repeats a row" "$OUT" "ts repeat in the second describe: flagged"
tsrows "$P/a.test.ts" "[[1, 2], [3, 4]]" "[[5, 6], [7, 8]]"
verdict 0 "ts clean control: distinct tables in both describes"
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nfunction run(T) {\n  it.each(T)('a %%i', (a, b) => {\n    expect(f(a).a).toBe(b);\n    expect(f(a).b).toBe(3);\n  });\n}\nconst T = [[1, 1], [1, 1]];\nrun(T);\n" > "$P/a.test.ts"
verdict 0 "ts table that is a parameter is not resolved to an outer constant"

# Round 4, minor 4: as const, satisfies and parentheses around a table.
newp
for wrap in "[[1, 2], [1, 2]] as const" "[[1, 2], [1, 2]] satisfies number[][]" "([[1, 2], [1, 2]])"; do
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nit.each(%s)('a %%i', (a, b) => {\n  expect(f(a).a).toBe(b);\n  expect(f(a).b).toBe(3);\n});\n" "$wrap" > "$P/a.test.ts"
  verdict 1 "ts inline table repeats a row: $wrap"
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst T = %s;\nit.each(T)('a %%i', (a, b) => {\n  expect(f(a).a).toBe(b);\n  expect(f(a).b).toBe(3);\n});\n" "$wrap" > "$P/a.test.ts"
  verdict 1 "ts constant table repeats a row: $wrap"
done
printf "import { expect, it } from 'vitest';\nimport { f } from './f';\nconst T = [[1, 2], [3, 4]] as const;\nit.each(T)('a %%i', (a, b) => {\n  expect(f(a).a).toBe(b);\n  expect(f(a).b).toBe(3);\n});\n" > "$P/a.test.ts"
verdict 0 "ts clean control: as const table with distinct rows"

# Round 4, minor 5 and 6: Python constant tables and pytest.param ids.
pyrows() { # pyrows <rows text> — one parametrized test over a module constant
  printf 'import pytest\nfrom f import f\n\nROWS = %s\n\n\n@pytest.mark.parametrize("x", ROWS)\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n' "$1" > "$P/test_a.py"
}
newp
pyrows "[1, 1]"
verdict 1 "py constant table repeats a row"
has "test_a.py:8: the parameter table repeats a row" "$OUT" "py constant table repeats a row: names the case"
pyrows "(1, 1)"
verdict 1 "py constant tuple table repeats a row"
pyrows "[1, 2]"
verdict 0 "py clean control: constant table with distinct rows"
printf 'import pytest\nfrom f import f\n\nROWS = [1, 1]\nROWS = [1, 2]\n\n\n@pytest.mark.parametrize("x", ROWS)\ndef test_a(x):\n    assert f(x).a == 2\n' > "$P/test_a.py"
verdict 0 "py constant assigned twice is not row-checked"
pparam() { # pparam <id-a> <value-b> <id-b>
  printf 'import pytest\nfrom f import f\n\n\n@pytest.mark.parametrize("x", [pytest.param(1, id="%s"), pytest.param(2)])\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n\n\n@pytest.mark.parametrize("x", [pytest.param(%s, id="%s"), pytest.param(2)])\ndef test_b(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n' "$1" "$2" "$3" > "$P/test_a.py"
}
pparam a 1 b
verdict 1 "py pytest.param ids differ, tables the same"
pparam a 3 b
verdict 0 "py clean control: pytest.param values differ"

# Round 4, minor 7: a declaration with a call that no test names is context.
newp
ts_case "$P/a.test.ts" $'const _c = make(\'a\');\n' 2
ts_case "$P/b.test.ts" $'const _c = make(\'b\');\n' 2
verdict 0 "ts unreferenced declarations call with different arguments"
ts_case "$P/b.test.ts" $'const _c = make(\'a\');\n' 2
verdict 1 "ts unreferenced declarations call with the same arguments"
ts_case "$P/b.test.ts" $'const _c = \'b\';\n' 2
ts_case "$P/a.test.ts" $'const _c = \'a\';\n' 2
verdict 1 "ts clean control: unreferenced plain constants stay filtered"
for v in a b; do
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\ndescribe('d', () => {\n  const _c = make('%s');\n  it('x', () => {\n    const r = f(1);\n    expect(r.a).toBe(2);\n    expect(r.b).toBe(3);\n  });\n});\n" "$v" > "$P/$v.test.ts"
done
verdict 0 "ts unreferenced describe-level call with different arguments"
newp
py_case "$P/test_a.py" '_c = make("a")' 2
py_case "$P/test_b.py" '_c = make("b")' 2
verdict 0 "py unreferenced assignment calls with different arguments"
py_case "$P/test_b.py" '_c = make("a")' 2
verdict 1 "py unreferenced assignment calls with the same arguments"
py_case "$P/test_a.py" '_c = "a"' 2
py_case "$P/test_b.py" '_c = "b"' 2
verdict 1 "py clean control: unreferenced plain constants stay filtered"

# Round 5, item 2: a table is row-checked only when it is a const that the file never changes.
tsdecl() { # tsdecl <declaration and changes> — one it.each over T
  printf "import { expect, it } from 'vitest';\nimport { f } from './f';\n%s\nit.each(T)('a %%i', (a, b) => {\n  expect(f(a).a).toBe(b);\n  expect(f(a).b).toBe(3);\n});\n" "$1" > "$P/a.test.ts"
}
newp
tsdecl "let T = [[1, 1], [1, 1]]; T = [[1, 1], [2, 2]];"
verdict 0 "ts let table reassigned before use"
tsdecl "const T = [[1, 1], [1, 1]]; T.push([2, 2]);"
verdict 0 "ts const table changed by push"
tsdecl "const T = [[1, 1], [1, 1]]; T[1] = [2, 2];"
verdict 0 "ts const table changed by index assignment"
tsdecl "let T = [[1, 1], [1, 1]];"
verdict 1 "ts let table never written is row-checked"
tsdecl "var T = [[1, 1], [1, 1]];"
verdict 1 "ts var table never written is row-checked"
tsdecl "const T = [[1, 1], [1, 1]]; const n = T.length;"
verdict 1 "ts clean control: const table only read still repeats a row"
has "the parameter table repeats a row" "$OUT" "ts const table only read: flagged"

# Round 6, major 1: a table is resolved only when every reference is a plain read (the declaration, each(T), T.length).
for form in "Object.assign(T, [[1, 1], [2, 2]]);" "mut(T);" "const A = T; A.push([2, 2]);" "T['push']([2, 2]);" \
  "Array.prototype.push.call(T, [2, 2]);" "T[1][0] = 5;" "T[1].push(9);" "[T[0], T[1]] = [[1, 2], [3, 4]];" \
  "Object.defineProperty(T, 1, { value: [2, 2] });" "export { T };" "T.length = 1;" "const { 0: z } = T;"; do
  tsdecl "const T = [[1, 1], [1, 1]]; $form"
  verdict 0 "ts table with another reference is not resolved: $form"
done
tsdecl "let T = [[1, 1], [1, 1]]; Object.assign(T, [[1, 1], [2, 2]]);"
verdict 0 "ts let table with a call argument is not resolved"
tsdecl "const T = [[1, 1], [1, 1]]; function g() { const T = []; T.push(1); } function h(T) { T.push(2); } const o = { T: 1 }; const n = o.T;"
verdict 1 "ts shadowed names and property names do not switch the row check off"
tsdecl "const T = [[1, 2], [3, 4]]; function g() { const T = [[1, 1], [1, 1]]; return T.length; }"
verdict 0 "ts an unrelated shadowing table does not switch the row check on for the real one"
tsdecl "const T = [[1, 1], [1, 1]]; function g() { T.push([2, 2]); }"
verdict 0 "ts a write in another function counts"
tsdecl "const T = [[1, 1], [1, 1]]; const n = (T as const).length;"
verdict 1 "ts a wrapped plain read is still a plain read"
for form in "const n = T.map((r) => r[0]);" "let n = 0; for (const r of T) { n += r[0]; }" "const n = T.slice(1).length;"; do
  tsdecl "const T = [[1, 1], [1, 1]]; $form"
  verdict 1 "ts table with a read-only use keeps the row check: $form"
done
for form in "T.sort();" "T.reverse();" "T.splice(1, 1);" "for (const r of T) { T.push(r); }"; do
  tsdecl "const T = [[1, 1], [1, 1]]; $form"
  verdict 0 "ts clean control: a changing use still switches the row check off: $form"
done

# Round 6, major 1, Python: the same inverted rule for a module-level table.
pyref() { # pyref <extra text after the constant> — one parametrize over ROWS
  printf 'import pytest\nfrom f import f\n\nROWS = [1, 1]\n%s\n\n\n@pytest.mark.parametrize("x", ROWS)\ndef test_a(x):\n    r = f(x)\n    assert r.a == 2\n    assert r.b == 3\n' "$1" > "$P/test_a.py"
}
newp
pyref ""
verdict 1 "py table only read repeats a row"
pyref "ROWS.append(2)"
verdict 0 "py table changed by a method call is not resolved"
pyref "mut(ROWS)"
verdict 0 "py table passed to a call is not resolved"
pyref "ALIAS = ROWS"
verdict 0 "py table aliased is not resolved"
pyref "ROWS[1] = 2"
verdict 0 "py table changed by index assignment is not resolved"
pyref "def g():
    global ROWS
    ROWS = [1, 2]"
verdict 0 "py table written through global is not resolved"
pyref "def g(ROWS):
    ROWS.append(2)"
verdict 1 "py a parameter named like the table does not switch the row check off"
pyref "def g():
    ROWS = []
    ROWS.append(2)"
verdict 1 "py a local named like the table does not switch the row check off"
pyref "n = len(ROWS)"
verdict 1 "py table read by len keeps the row check"
pyref "for r in ROWS:
    n = r"
verdict 1 "py table read by a loop keeps the row check"
pyref "n = [r for r in ROWS]"
verdict 1 "py table read by a comprehension keeps the row check"
pyref "for r in ROWS:
    ROWS.append(r)"
verdict 0 "py clean control: a loop that also appends switches the row check off"

# Round 6, minor 2: test files inside a nested git repository are not checked, and the run says so.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/vendor/lib/b.test.ts" "" 2
ts_case "$P/vendor/lib/c.test.ts" "" 2
git init -q "$P/vendor/lib"
verdict 0 "nested git repository holds duplicates"
has "NOTE vendor/lib: nested git repository, 2 test files under it were not checked" "$OUT" "nested git repository: NOTE names the folder and the count"
ts_case "$P/vendor/lib/c.test.ts" "" 2
rm -rf "$P/vendor/lib/.git"
verdict 1 "clean control: without the nested repository the duplicates are found"
lacks "nested git repository" "$OUT" "no nested repository: no NOTE"
newp
ts_case "$P/vendor/lib/b.test.ts" "" 2
git init -q "$P/vendor/lib"
verdict 0 "every test file in a nested repository"
has "nested git repository, 1 test files under it" "$OUT" "every test file in a nested repository: NOTE, not an ignore-rule failure"

# Nested repositories are counted once each, the outermost only.
newp
ts_case "$P/vendor/lib/b.test.ts" "" 2
ts_case "$P/vendor/lib/inner/c.test.ts" "" 2
git init -q "$P/vendor/lib"
git init -q "$P/vendor/lib/inner"
verdict 0 "repository inside a nested repository"
has "NOTE vendor/lib: nested git repository, 2 test files under it were not checked" "$OUT" "nested in nested: counted once, under the outer one"
lacks "vendor/lib/inner:" "$OUT" "nested in nested: the inner repository has no NOTE of its own"

# A .git entry git cannot open stops the run; a plain folder is still read.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
printf 'garbage\n' > "$P/.git/HEAD"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "corrupt .git/HEAD: exit"
has "git cannot open it" "$OUT" "corrupt .git/HEAD: names the cause"
printf 'ref: refs/heads/main\n' > "$P/.git/HEAD"
verdict 1 "clean control: a repaired HEAD reads the files again"

# A corrupt index stops the run instead of reading nothing.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
git -C "$P" add -A
printf 'junk' > "$P/.git/index"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "corrupt .git/index: exit"
has "cannot list the files of the git work tree" "$OUT" "corrupt .git/index: names the cause"
rm -f "$P/.git/index"
verdict 1 "clean control: without the index the files are listed and the duplicates found"

# Round 6, minor 3: git failing for another reason than "not a git repository" stops the run.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
OUT=$(GIT_DIR="$T/no-such-git-dir" bash "$CHECK" "$P" 2>&1)
check 2 "$?" "broken GIT_DIR: exit"
has "git could not tell whether" "$OUT" "broken GIT_DIR: names the cause"
rm -rf "$P/.git"
verdict 1 "clean control: a plain folder without git is still read"

# Round 5, item 3: a project path that is a symlink is followed.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
ln -s "$P" "$T/linked-project"
OUT=$(bash "$CHECK" "$T/linked-project" 2>&1)
EC=$?
check 1 "$EC" "symlinked project path: duplicates found"
has "have the same body" "$OUT" "symlinked project path: reads the tests"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 1 "$?" "symlinked project path: real path gives the same answer"

# Round 5, item 4: test files that exist but are all ignored by git stop the run.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
printf '*.test.ts\n' > "$P/.git/info/exclude"
verdict 2 "every test file ignored by git"
has "2 test files were found but every one is ignored by git" "$OUT" "every test file ignored: names the cause and the count"
rm -f "$P/.git/info/exclude"
verdict 1 "clean control: nothing ignored, duplicates found"
ts_case "$P/c.test.ts" "" 5
printf 'a.test.ts\nb.test.ts\n' > "$P/.git/info/exclude"
verdict 0 "clean control: some test files ignored, one still read"

# Round 5, item 5: the Python version message, through an interpreter that reports an old version.
newp
py_case "$P/test_a.py" "" 2
mkdir -p "$T/oldpy"
cat > "$T/oldpy/python3" <<'STUB'
#!/bin/sh
if [ "$1" = -I ]; then shift; fi
exec "$TC_REAL_PY" -I -c 'import runpy, sys; sys.version_info = (3, 7, 0, "final", 0); sys.argv = sys.argv[1:]; runpy.run_path(sys.argv[0], run_name="__main__")' "$@"
STUB
chmod +x "$T/oldpy/python3"
OUT=$(TC_REAL_PY="$(command -v python3)" PATH="$T/oldpy:$PATH" bash "$CHECK" "$P" 2>&1)
check 2 "$?" "old python interpreter: exit"
has "is too old: this check needs python 3.8 or newer; install a newer Python 3 on the path" "$OUT" "old python interpreter: message says what to do"

# Review round: a PYTHONPATH module or sitecustomize must not change the result (clean control: same run without them).
newp
py_case "$P/test_a.py" "" 2
py_case "$P/test_b.py" "" 2
OUT=$(bash "$CHECK" "$P" 2>&1)
check 1 "$?" "python env control: duplicates found"
mkdir -p "$T/pp"
printf 'import sys\nsys.exit(0)\n' > "$T/pp/sitecustomize.py"
printf 'import sys\nsys.exit(0)\n' > "$T/pp/ast.py"
OUT=$(PYTHONPATH="$T/pp" bash "$CHECK" "$P" 2>&1)
check 1 "$?" "planted PYTHONPATH sitecustomize and ast module do not change the verdict"
printf 'import sys\nsys.exit(0)\n' > "$T/pp/startup.py"
OUT=$(PYTHONSTARTUP="$T/pp/startup.py" bash "$CHECK" "$P" 2>&1)
check 1 "$?" "planted PYTHONSTARTUP does not change the verdict"

# Review round: a failing git ls-files fails the gate, never an empty list.
newp
ts_case "$P/a.test.ts" "" 2
ts_case "$P/b.test.ts" "" 2
git -C "$P" add -A
OUT=$(bash "$CHECK" "$P" 2>&1)
check 1 "$?" "git ls-files control: duplicates found"
printf 'garbage' > "$P/.git/index"
OUT=$(bash "$CHECK" "$P" 2>&1)
check 2 "$?" "corrupted git index: the gate fails closed"

# Timing: CPU time (user + system), not wall time. 2000 cases over 40 files, then 5000 cases in one file per language.
cpu() { # cpu <dir> — prints "user sys", output of the check in $T/time.out
  local TIMEFORMAT='%U %S'
  { time bash "$CHECK" "$1" > "$T/time.out" 2>&1; } 2>&1
}
under() { # under <seconds> <"user sys">
  printf '%s\n' "$2" | awk -v max="$1" '{ print ($1 + $2 < max) ? "yes" : "no" }'
}
# Round 5, item 1 and round 6, minor 4: the git file list is intersected in one pass. Structural assertion: the number of
# external commands the check starts must not grow with the number of test files (shims count every start).
shim_count() { # shim_count <files> — prints the number of shimmed commands started on a project of that many test files
  local n=$1 tool real
  newp
  mkdir -p "$P/src" "$T/shims"
  rm -f "$T/shims/"* "$T/shim.count"
  : > "$T/shim.count"
  for tool in grep awk tr sort find readlink git cat head sed cut wc; do
    real=$(command -v "$tool") || continue
    printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$T/shim.count" "$real" > "$T/shims/$tool"
    chmod +x "$T/shims/$tool"
  done
  awk -v n="$n" 'BEGIN { for (i = 1; i <= n; i++) { out = sprintf("%s/src/t%d.test.ts", ARGV[1], i); printf "import { expect, it } from \"vitest\";\nit(\"c\", () => {\n  expect(f%d(1)).toBe(%d);\n});\n", i, i > out; close(out) } }' "$P"
  OUT=$(PATH="$T/shims:$PATH" bash "$CHECK" "$P" 2>&1)
  has "ok, $n test cases compared" "$OUT" "$n files: all compared"
  awk 'END { print NR }' "$T/shim.count"
}
SMALL=$(shim_count 50)
LARGE=$(shim_count 400)
check "$SMALL" "$LARGE" "external commands started: 50 files $SMALL, 400 files $LARGE (must not grow with the file count)"
case "$SMALL" in '' | 0) FAIL=$((FAIL + 1)); echo "FAIL: shims counted nothing" ;; *) PASS=$((PASS + 1)) ;; esac

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
check 1000 "$(grep -c 'it("case' "$P"/f*.test.ts | awk -F: '{ s += $2 } END { print s }')" "timing fixture: TS cases"
check 1000 "$(grep -c '^def test_' "$P"/pytests/*.py | awk -F: '{ s += $2 } END { print s }')" "timing fixture: py cases"
CPU=$(cpu "$P")
check 0 "$(grep -c FAIL "$T/time.out")" "timing fixture: clean"
has "ok, 2000 test cases compared" "$(cat "$T/time.out")" "timing fixture: 2000 cases compared"
check yes "$(under 5 "$CPU")" "2000 cases in 40 files take under 5 seconds of CPU time (user+sys: $CPU)"
echo "2000 cases, 40 files, CPU time (user sys): $CPU"
P=$(mktemp -d "$T/p.XXXXXX")
mkdir -p "$P/node_modules"
ln -s "$TSDIR" "$P/node_modules/typescript"
awk 'BEGIN {
  out = ARGV[1] "/big.test.ts"
  print "import { describe, expect, it } from \"vitest\";" > out
  print "describe(\"big\", () => {" > out
  for (i = 1; i <= 5000; i++) printf "  it(\"case %d\", () => {\n    const r = compute_%d(%d);\n    expect(r.total).toBe(%d);\n    expect(r.items.length).toBe(%d);\n  });\n", i, i, i, i + 1, i * 3 > out
  print "});" > out
  close(out)
  out = ARGV[1] "/test_big.py"
  for (i = 1; i <= 5000; i++) printf "def test_case_%d():\n    r = compute_%d(%d)\n    assert r.total == %d\n    assert len(r.items) == %d\n\n\n", i, i, i, i + 1, i * 3 > out
  close(out)
}' "$P"
mv "$P/test_big.py" "$T/test_big.py"
CPU=$(cpu "$P")
has "ok, 5000 test cases compared" "$(cat "$T/time.out")" "5000 TS cases in one file: all compared"
check yes "$(under 10 "$CPU")" "5000 TS cases in one file take under 10 seconds of CPU time (user+sys: $CPU)"
echo "5000 TS cases, one file, CPU time (user sys): $CPU"
rm "$P/big.test.ts"
mv "$T/test_big.py" "$P/test_big.py"
CPU=$(cpu "$P")
has "ok, 5000 test cases compared" "$(cat "$T/time.out")" "5000 py cases in one file: all compared"
check yes "$(under 10 "$CPU")" "5000 py cases in one file take under 10 seconds of CPU time (user+sys: $CPU)"
echo "5000 py cases, one file, CPU time (user sys): $CPU"

echo "seeded-duplicate-tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
