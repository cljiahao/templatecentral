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
seed_default=$(sed -n 's/^LIMIT=.*-\([0-9]*\)}.*/\1/p' "$BUDGET")
check "$plugin_default" "$seed_default" "default_limit: equals MO_MAX_TEST_RATIO in measure-outcomes.sh"
check 35 "$seed_default" "default_limit: is 35"

# a repeated title in one file is reported and never fails (TypeScript and pytest), as is the same title under two describes or classes
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
check 0 "$EC" "ts_dup_title: exits 0"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "ts_dup_title: one line"
has "1 same-title" "$OUT" "ts_dup_title: counted"
run "$d" -v
has "src/dup.test.ts:5: repeated test title in one file: \"thing > returns 404\" (first at line 2)" "$OUT" "ts_dup_title: -v names file, line and title"

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

d=$T/ts-loop
ts_project "$d" 200
put "$d" src/loop.test.ts "for (const v of [1, 2]) {
  it('handles value', () => { expect(v).toBeGreaterThan(0); });
}
it('handles value', () => { expect(3).toBe(3); });
describe('x', () => { it('a', () => { expect(1).toBe(1); }); });
describe('x', () => { it('a', () => { expect(2).toBe(2); }); });"
run "$d"
check 0 "$EC" "ts_loop_and_repeated_describe: exits 0 at a low ratio"
lacks "FAIL" "$OUT" "ts_loop_and_repeated_describe: no failure line"

d=$T/py-dup
py_project "$d" 200
put "$d" test/test_dup.py "def test_a():
    assert 1 == 1


def test_a():
    assert 2 == 2"
run "$d"
check 0 "$EC" "py_dup_title: exits 0"
run "$d" -v
has "test/test_dup.py:5: repeated test title in one file: \"test_a\"" "$OUT" "py_dup_title: -v names file and title"

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
check 0 "$EC" "spaces: repeated title does not fail"
run "$d" -v
has "src/my feature/some thing.test.ts:2: repeated test title" "$OUT" "spaces: names the spaced path"

# no file contents beyond test titles
d=$T/secret
ts_project "$d" 40
put "$d" src/s.test.ts "const TOP_SECRET = 'hunter2-value';
it('works', () => {
  expect(TOP_SECRET).toBe('hunter2-value');
});"
run "$d" -v
lacks "hunter2" "$OUT" "no_contents: neither line nor -v prints file content"

# failure output stays within 20 lines: twenty-five apps, each over the ratio
d=$T/many
mkdir -p "$d"
for i in $(seq 1 25); do
  ts_project "$d/app$i" 1
  put "$d" "app$i/src/f.test.ts" "it('x', () => { expect(1).toBe(1); });"
done
run "$d"
check 1 "$EC" "cap: exits 1"
check 1 "$([[ $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') -le 20 ]] && echo 1 || echo 0)" "cap: at most 20 lines"
has "... and " "$OUT" "cap: says how many more"

# -v output stays within 20 lines too
d=$T/many-dups
ts_project "$d" 2000
for i in $(seq 1 25); do
  put "$d" "src/f$i.test.ts" "it('x', () => { expect(1).toBe(1); });
it('x', () => { expect(1).toBe(1); });"
done
run "$d" -v
check 0 "$EC" "cap_verbose: exits 0"
check 1 "$([[ $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') -le 22 ]] && echo 1 || echo 0)" "cap_verbose: summary, 20 rows and a more-line"

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

# set but empty is an error like any other garbage; unset keeps the default
d=$T/ts-empty-limit
ts_project "$d" 40
OUT=$(TEST_BUDGET_MAX_RATIO="" bash "$BUDGET" "$d" 2>&1)
check 2 "$?" "empty_limit: exits 2"
has "TEST_BUDGET_MAX_RATIO must be a number" "$OUT" "empty_limit: names the setting"
OUT=$(env -u TEST_BUDGET_MAX_RATIO bash "$BUDGET" "$d" 2>&1)
check 0 "$?" "unset_limit: keeps the default"
has "(limit 35)" "$OUT" "unset_limit: default is 35"

# test-file lines over 300 bytes: counted in -v only, never fail
d=$T/ts-long
ts_project "$d" 200
long=$(printf 'x%.0s' $(seq 1 320))
put "$d" src/long.test.ts "it('long', () => { expect('$long').toBe('$long'); });"
run "$d"
check 0 "$EC" "long_lines: exits 0"
check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "long_lines: one line without -v"
run "$d" -v
has "1 test-file lines over 300 bytes (count only)" "$OUT" "long_lines: -v counts them"

# an unreadable file fails closed: exit 2, one line naming it, even when the rest is within budget
d=$T/ts-unreadable
ts_project "$d" 40
put "$d" src/ok.test.ts "it('ok', () => { expect(1).toBe(1); });"
put "$d" src/locked.test.ts "it('locked', () => { expect(1).toBe(1); });"
chmod 000 "$d/src/locked.test.ts"
if [[ ! -r "$d/src/locked.test.ts" ]]; then
  OUT=$(bash "$BUDGET" "$d" 2>&1)
  check 2 "$?" "unreadable: exits 2"
  check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "unreadable: one line"
  has "cannot read src/locked.test.ts" "$OUT" "unreadable: names the file"
fi
chmod 644 "$d/src/locked.test.ts"

# agreement with the plugin gate: same source and test lines per stack template
mo=$(MO_REPO_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/measure-outcomes.sh" 2>&1)
for stack in nextjs nestjs vite-react fastapi; do
  want=$(printf '%s\n' "$mo" | awk -v s="$stack" '$0 == "== " s " ==" { f = 1; next } f && /source files/ { gsub(/,/, ""); print "src " $6 " test " $12 " files " $9; exit }')
  out=$(bash "$BUDGET" "$REPO_ROOT/skills/scaffold/$stack/template" 2>&1)
  got=$(printf '%s\n' "$out" | sed -n 's/.*: src \([0-9]*\) LOC, test \([0-9]*\) LOC.*, \([0-9]*\) test files.*/src \1 test \2 files \3/p')
  check "$want" "$got" "plugin_agreement[$stack]: measure-outcomes and test-budget count the same lines"
done

# the same counts as the plugin gate on tricky trees: a file name with a newline, a symlink to a file and one to a folder
fix_tree() { # fix_tree <dir>
  mkdir -p "$1/src/sub"
  : > "$1/vite.config.ts"
  printf 'export const a = 1;\nexport const b = 2;\nexport const c = 3;\n' > "$1/src/real.ts"
  printf 'export const a = 1;\nexport const b = 2;\nexport const c = 3;\nexport const d = 4;\nexport const e = 5;\nexport const f = 6;\n' > "$1/src/new"$'\n'"line.ts"
  ln -s real.ts "$1/src/link.ts"
  ln -s sub "$1/src/dirlink"
  printf "it('a', () => { expect(1).toBe(1); });\n" > "$1/src/a.test.ts"
}
for mode in walk git; do
  d=$T/tricky-$mode
  fix_tree "$d"
  if [[ $mode == git ]]; then
    (cd "$d" && git init -q . && git add -A > /dev/null 2>&1)
  fi
  mo=$(bash "$REPO_ROOT/scripts/measure-outcomes.sh" "$d" 2>&1)
  want=$(printf '%s\n' "$mo" | awk '/source files/ { gsub(/,/, ""); print "src " $6 " test " $12 " files " $9; exit }')
  got=$(bash "$BUDGET" "$d" 2>&1 | sed -n 's/.*: src \([0-9]*\) LOC, test \([0-9]*\) LOC.*, \([0-9]*\) test files.*/src \1 test \2 files \3/p')
  check "$want" "$got" "tricky_tree[$mode]: counts match the plugin gate ($want)"
done
check "$(bash "$BUDGET" "$T/tricky-walk" | sed 's/^[^:]*: //')" "$(bash "$BUDGET" "$T/tricky-git" | sed 's/^[^:]*: //')" "tricky_tree: walk and git modes agree"

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
  printf '# %s\n\nA scaffolded project.\n' "$stack" > "$d/README.md"
  check 1 "$([[ -f $d/docs/adr/0001-test-each-behaviour-once.md && -x $d/scripts/test-budget.sh && -f $d/.claude/skills/test-consolidate/SKILL.md ]] && echo 1 || echo 0)" "scaffold[$stack]: ADR, script and skill seeded"
  OUT=$(cd "$d" && bash scripts/test-budget.sh 2>&1)
  check 0 "$?" "scaffold[$stack]: budget exits 0 ($OUT)"
  check 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "scaffold[$stack]: one line"
  OUT=$(cd "$d" && bash scripts/check-docs.sh 2>&1)
  check 0 "$?" "scaffold[$stack]: check-docs exits 0 ($OUT)"
done

echo "test-budget.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
