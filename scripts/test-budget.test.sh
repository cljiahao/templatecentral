#!/usr/bin/env bash
# scripts/test-budget.test.sh — tests for the seeded scripts/test-budget.sh.
# Usage: bash scripts/test-budget.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"
BUDGET="$SHARED/template/scripts/test-budget.sh"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/tb.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# put <dir> <path> <content> — writes one fixture file.
put() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
}

# run <dir> [args...] — sets OUT and EC.
run() {
  local d=$1
  shift
  OUT=$(bash "$BUDGET" "$@" "$d" 2>&1)
  EC=$?
}

# ts_project <dir> <src-lines> — a Vite-shaped project with that many source lines and no tests.
ts_project() {
  mkdir -p "$1/src"
  : > "$1/vite.config.ts"
  local i body=""
  for ((i = 1; i <= $2; i++)); do body+="export const v$i = $i;"$'\n'; done
  printf '%s' "$body" > "$1/src/lib.ts"
}

py_project() {
  mkdir -p "$1/src" "$1/test"
  printf 'fastapi\n' > "$1/requirements.txt"
  local i body=""
  for ((i = 1; i <= $2; i++)); do body+="v$i = $i"$'\n'; done
  printf '%s' "$body" > "$1/src/lib.py"
}

# clean projects pass with exactly one line
d=$T/ts-clean
ts_project "$d" 40
put "$d" src/lib.test.ts "import { it, expect } from 'vitest';
it('adds', () => {
  expect(1).toBe(1);
});"
run "$d"
check 0 "$EC" "ts_clean: exits 0"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "ts_clean: one line"
has "vite-react (.): src 40 LOC, test 4 LOC, ratio 10.00 per 100 (limit 35), 1 test files" "$OUT" "ts_clean: numbers"

d=$T/py-clean
py_project "$d" 40
put "$d" test/test_lib.py "from src.lib import v1


def test_one():
    assert v1 == 1"
run "$d"
check 0 "$EC" "py_clean: exits 0"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "py_clean: one line"
has "fastapi (.): src 40 LOC, test 3 LOC, ratio 7.50" "$OUT" "py_clean: numbers"

# ratio breach fails and names the numbers; the limit comes from one setting
d=$T/ts-ratio
ts_project "$d" 10
put "$d" src/big.test.ts "import { it, expect } from 'vitest';
it('a', () => { expect(1).toBe(1); });
it('b', () => { expect(2).toBe(2); });
it('c', () => { expect(3).toBe(3); });
it('d', () => { expect(4).toBe(4); });"
run "$d"
check 1 "$EC" "ratio_breach: exits 1"
has "test LOC 5 vs source LOC 10: 50.00 per 100 source LOC, limit 35 (TEST_BUDGET_MAX_RATIO)" "$OUT" "ratio_breach: names the numbers"
OUT=$(TEST_BUDGET_MAX_RATIO=50 bash "$BUDGET" "$d" 2>&1)
check 0 "$?" "ratio_limit: raised through the one setting passes at the boundary"
OUT=$(TEST_BUDGET_MAX_RATIO=abc bash "$BUDGET" "$d" 2>&1)
check 2 "$?" "ratio_limit: a non-number exits 2"
has "TEST_BUDGET_MAX_RATIO must be a number" "$OUT" "ratio_limit: names the setting"

# same default as the plugin gate
plugin_default=$(sed -n 's/^MO_MAX_TEST_RATIO=.*:-\([0-9]*\)}.*/\1/p' "$REPO_ROOT/scripts/measure-outcomes.sh")
seed_default=$(sed -n 's/^LIMIT=.*:-\([0-9]*\)}.*/\1/p' "$BUDGET")
check "$plugin_default" "$seed_default" "default_limit: equals MO_MAX_TEST_RATIO in measure-outcomes.sh"
check 35 "$seed_default" "default_limit: is 35"

# duplicate title in one file fails (TypeScript and pytest), the same title under two describes or classes does not
d=$T/ts-dup
ts_project "$d" 200
put "$d" src/dup.test.ts "describe('thing', () => {
  it('returns 404', () => {
    expect(1).toBe(1);
  });
  it('returns 404', () => {
    expect(2).toBe(2);
  });
});"
run "$d"
check 1 "$EC" "ts_dup_title: exits 1"
has "src/dup.test.ts:5: duplicate test title in one file: \"thing > returns 404\" (first at line 2)" "$OUT" "ts_dup_title: names file, line and title"

d=$T/ts-nested
ts_project "$d" 200
put "$d" src/nest.test.ts "describe('a', () => {
  it('returns 404', () => {
    expect(1).toBe(1);
  });
});
describe('b', () => {
  it('returns 404', () => {
    expect(2).toBe(2);
  });
});"
run "$d"
check 0 "$EC" "ts_same_title_under_two_describes: passes"

d=$T/py-dup
py_project "$d" 200
put "$d" test/test_dup.py "def test_a():
    assert 1 == 1


def test_a():
    assert 2 == 2"
run "$d"
check 1 "$EC" "py_dup_title: exits 1"
has "test/test_dup.py:5: duplicate test title in one file: \"test_a\"" "$OUT" "py_dup_title: names file and title"

d=$T/py-classes
py_project "$d" 200
put "$d" test/test_cls.py "class TestA:
    def test_x(self):
        assert 1 == 1


class TestB:
    def test_x(self):
        assert 2 == 2"
run "$d"
check 0 "$EC" "py_same_name_in_two_classes: passes"

# cross-file same title is reported and passes
d=$T/ts-cross
ts_project "$d" 200
put "$d" src/a.test.ts "it('renders', () => {
  expect(1).toBe(1);
});"
put "$d" src/b.test.ts "it('renders', () => {
  expect(2).toBe(2);
});"
run "$d"
check 0 "$EC" "cross_file_title: passes"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "cross_file_title: one line without -v"
has "1 same-title" "$OUT" "cross_file_title: counted"
run "$d" -v
has "same title in 2 files: \"renders\": src/a.test.ts, src/b.test.ts" "$OUT" "cross_file_title: -v names the files"

# near-identical assertion sets
d=$T/ts-sim
ts_project "$d" 300
body="expect(a).toBe(1);
  expect(b).toBe(2);
  expect(c).toBe(3);
  expect(d).toBe(4);"
put "$d" src/x.test.ts "it('x1', () => {
  $body
});"
put "$d" src/y.test.ts "it('y1', () => {
  $body
});"
run "$d" -v
check 0 "$EC" "similar_assertions: passes"
has "1 similar-assertion" "$OUT" "similar_assertions: counted"
has "src/x.test.ts, src/y.test.ts" "$OUT" "similar_assertions: names the files"

# unit and e2e naming the same route
d=$T/ts-route
ts_project "$d" 300
put "$d" src/users.test.ts "it('lists', async () => {
  expect(await get('/api/users')).toBe(1);
});"
put "$d" e2e/flow.spec.ts "it('flows', async () => {
  expect(await get('/api/users')).toBe(2);
});"
run "$d" -v
check 0 "$EC" "unit_e2e_route: passes"
has "1 unit-e2e" "$OUT" "unit_e2e_route: counted"
has "unit and e2e name the same route /api/users: src/users.test.ts, e2e/flow.spec.ts" "$OUT" "unit_e2e_route: names both files"

d=$T/py-fn
py_project "$d" 300
put "$d" test/test_unit.py "from src.lib import compute


def test_u():
    assert compute(1) == 1"
put "$d" test/e2e/test_flow.py "from src.lib import compute


def test_f():
    assert compute(2) == 2"
run "$d" -v
has "unit and e2e name the same function compute: test/test_unit.py, test/e2e/test_flow.py" "$OUT" "unit_e2e_function: reported"

# empty project and project without tests
d=$T/empty
mkdir -p "$d"
run "$d"
check 0 "$EC" "empty: exits 0"
check "test-budget: ok, no source or test files" "$OUT" "empty: says so in one line"

d=$T/no-tests
ts_project "$d" 20
run "$d"
check 0 "$EC" "no_tests: exits 0"
has "src 20 LOC, test 0 LOC, ratio 0.00 per 100 (limit 35), 0 test files" "$OUT" "no_tests: zero test files"

d=$T/only-tests
mkdir -p "$d"
put "$d" a.test.ts "it('a', () => { expect(1).toBe(1); });"
run "$d"
check 0 "$EC" "only_tests: no source, no ratio, exits 0"
has "ratio n/a" "$OUT" "only_tests: ratio is n/a"

# paths with spaces, in the project path and inside it
d="$T/my project"
ts_project "$d" 40
put "$d" "src/my feature/some thing.test.ts" "it('adds', () => { expect(1).toBe(1); });
it('adds', () => { expect(1).toBe(1); });"
run "$d"
check 1 "$EC" "spaces: duplicate title found"
has "src/my feature/some thing.test.ts:2: duplicate test title" "$OUT" "spaces: names the spaced path"

# no file contents beyond test titles
d=$T/secret
ts_project "$d" 40
put "$d" src/s.test.ts "const TOP_SECRET = 'hunter2-value';
it('works', () => {
  expect(TOP_SECRET).toBe('hunter2-value');
});"
run "$d" -v
lacks "hunter2" "$OUT" "no_contents: neither line nor -v prints file content"

# failure output stays within 20 lines
d=$T/many
ts_project "$d" 2000
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
  put "$d" "src/f$i.test.ts" "it('x', () => { expect(1).toBe(1); });
it('x', () => { expect(1).toBe(1); });"
done
run "$d"
check 1 "$EC" "cap: exits 1"
check 1 "$([[ $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') -le 20 ]] && echo 1 || echo 0)" "cap: at most 20 lines"
has "... and " "$OUT" "cap: says how many more"

# monorepo: each folder is its own app and counted in its own language
d=$T/mono
mkdir -p "$d"
ts_project "$d/web" 30
py_project "$d/api" 30
put "$d/web" src/w.test.ts "it('w', () => { expect(1).toBe(1); });"
put "$d/api" test/test_a.py "def test_a():
    assert 1 == 1"
run "$d"
check 0 "$EC" "mono: exits 0"
has "vite-react (web): src 30 LOC, test 1 LOC" "$OUT" "mono: web app"
has "fastapi (api): src 30 LOC, test 2 LOC" "$OUT" "mono: api app"

# comments, blank lines, block comments and docstrings are not lines
d=$T/comments
ts_project "$d" 10
put "$d" src/c.test.ts "// a comment

/* block
   comment */
it('c', () => { expect(1).toBe(1); });"
run "$d"
has "test 1 LOC" "$OUT" "comments: only code lines count"

# unknown option and missing folder
OUT=$(bash "$BUDGET" --nope 2>&1)
check 2 "$?" "unknown_option: exits 2"
OUT=$(bash "$BUDGET" "$T/does-not-exist" 2>&1)
check 2 "$?" "missing_folder: exits 2"

# read-only: no file in the project changes
d=$T/readonly
ts_project "$d" 40
put "$d" src/r.test.ts "it('r', () => { expect(1).toBe(1); });"
before=$(cd "$d" && find . -type f -exec shasum {} + | sort | shasum)
run "$d" -v
after=$(cd "$d" && find . -type f -exec shasum {} + | sort | shasum)
check "$before" "$after" "read_only: project files unchanged"

# agreement with the plugin gate: same source and test lines per stack template
mo=$(MO_REPO_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/measure-outcomes.sh" 2>&1)
for stack in nextjs nestjs vite-react fastapi; do
  want=$(printf '%s\n' "$mo" | awk -v s="$stack" '$0 == "== " s " ==" { f = 1; next } f && /source files/ { gsub(/,/, ""); print "src " $6 " test " $12 " files " $9; exit }')
  out=$(bash "$BUDGET" "$REPO_ROOT/skills/scaffold/$stack/template" 2>&1)
  got=$(printf '%s\n' "$out" | sed -n 's/.*: src \([0-9]*\) LOC, test \([0-9]*\) LOC.*, \([0-9]*\) test files.*/src \1 test \2 files \3/p')
  check "$want" "$got" "plugin_agreement[$stack]: measure-outcomes and test-budget count the same lines"
done

# a fresh scaffold of each stack: budget passes and the docs check passes with the ADR
scaffold() { # scaffold <stack> <dir>
  mkdir -p "$2"
  local part
  for part in stack base agents settings late; do
    TC_STACK=$1 TC_PART=$part bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
  done
  TC_STACK=$1 TC_PART=ci TC_CI=github bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
  TC_STACK=$1 TC_PART=tail bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
  TC_STACK=$1 TC_PART=manifest bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
}
for stack in nextjs nestjs vite-react fastapi; do
  d=$T/scaffold-$stack
  scaffold "$stack" "$d"
  check 1 "$([[ -f $d/docs/adr/0001-test-each-behaviour-once.md && -x $d/scripts/test-budget.sh && -f $d/.claude/skills/test-consolidate/SKILL.md ]] && echo 1 || echo 0)" "scaffold[$stack]: ADR, script and skill seeded"
  OUT=$(cd "$d" && bash scripts/test-budget.sh 2>&1)
  check 0 "$?" "scaffold[$stack]: budget exits 0 ($OUT)"
  check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "scaffold[$stack]: one line"
  OUT=$(cd "$d" && bash scripts/check-docs.sh 2>&1)
  check 0 "$?" "scaffold[$stack]: check-docs exits 0 ($OUT)"
done

echo "test-budget.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
