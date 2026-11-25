#!/usr/bin/env bash
# scripts/check-tests-wired.test.sh — tests for scripts/check-tests-wired.sh on scratch trees.
# Each failing case has a clean control; the last case runs the check on this repo.
# Usage: bash scripts/check-tests-wired.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-tests-wired.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tests-wired.XXXXXX") || exit 1
trap 'rm -rf "${T:?}"' EXIT
PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# tree <name> — a scratch scripts dir with a.test.sh and b.test.sh and an empty workflow dir.
tree() {
  rm -rf "${T:?}/$1"; mkdir -p "$T/$1/scripts" "$T/$1/wf"
  : > "$T/$1/scripts/a.test.sh"; : > "$T/$1/scripts/b.test.sh"
}
# run <name> — the check's exit code and output on that tree.
run() { OUT=$(bash "$CHECK" "$T/$1/scripts" "$T/$1/wf" 2>&1); RC=$?; }

tree wired
printf 'jobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/wired/wf/ci.yml"
run wired
check 0 "$RC" "control: both tests wired passes"
check yes "$([[ "$OUT" == OK:* ]] && echo yes || echo no)" "control: prints OK"

tree split
printf 'steps:\n  - run: bash scripts/a.test.sh\n' > "$T/split/wf/one.yml"
printf 'steps:\n  - run: bash scripts/b.test.sh\n' > "$T/split/wf/two.yaml"
run split
check 0 "$RC" "control: tests spread over two workflow files, .yml and .yaml, pass"

tree miss
printf 'steps:\n  - run: bash scripts/a.test.sh\n' > "$T/miss/wf/ci.yml"
run miss
check 1 "$RC" "planted miss: b.test.sh not run fails"
check yes "$([[ "$OUT" == *"scripts/b.test.sh is not run"* && "$OUT" != *"scripts/a.test.sh is not run"* ]] && echo yes || echo no)" "planted miss: names only the missing test"

tree comment
printf 'steps:\n  - run: bash scripts/a.test.sh\n    # bash scripts/b.test.sh\n' > "$T/comment/wf/ci.yml"
run comment
check 1 "$RC" "a commented-out run does not count"

tree prefix
printf 'steps:\n  - run: bash scripts/a.test.sh\n  - run: bash scripts/b.test.sh.bak\n' > "$T/prefix/wf/ci.yml"
run prefix
check 1 "$RC" "a longer file name does not count for b.test.sh"

tree dot
printf 'steps:\n  - run: bash scripts/a.test.sh\n  - run: bash scripts/bxtest.sh\n' > "$T/dot/wf/ci.yml"
run dot
check 1 "$RC" "the dot in the name is literal"

tree nowf
run nowf
check 1 "$RC" "no workflow file fails"

rm -rf "${T:?}/notests"; mkdir -p "$T/notests/scripts" "$T/notests/wf"
printf 'steps:\n  - run: bash scripts/a.test.sh\n' > "$T/notests/wf/ci.yml"
run notests
check 1 "$RC" "no test file fails"

OUT=$(bash "$CHECK" 2>&1); RC=$?
check 0 "$RC" "this repo: every scripts/*.test.sh is run by a workflow step ($OUT)"

echo "check-tests-wired.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
