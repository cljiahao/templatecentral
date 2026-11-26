#!/usr/bin/env bash
# scripts/workflow-job-ids.test.sh — tests for scripts/workflow-job-ids.sh on scratch workflows.
# One planted job id of each form the old reader missed (uppercase, underscore, trailing comment) next to
# a plain id as the clean control, the unreadable-line failure, the missing-jobs failure and the scope of
# the reader (deeper lines, comments and later top-level keys are not job ids). The last case runs the
# reader on this repo's validate-skills.yml and compares it with the `needs` list of all-checks.
# Usage: bash scripts/workflow-job-ids.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READER="$ROOT/scripts/workflow-job-ids.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/job-ids.XXXXXX") || exit 1
trap 'rm -rf "${T:?}"' EXIT
PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# has <text> <substring> — yes when the text holds the substring.
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# ids <name> — the workflow on stdin is read; sets OUT (ids, one per line, on one line joined by spaces) and RC.
ids() {
  cat > "$T/$1.yml"
  OUT=$(bash "$READER" "$T/$1.yml" 2>"$T/$1.err"); RC=$?
  OUT=$(printf '%s' "$OUT" | tr '\n' ' ')
  ERR=$(cat "$T/$1.err")
}

ids plain <<'YML'
name: x
on: push
jobs:
  build:
    runs-on: x
  test-all:
    runs-on: x
YML
check 0 "$RC" "control: plain ids exit 0"
check "build test-all" "$OUT" "control: plain ids are listed in file order"

ids upper <<'YML'
jobs:
  build:
    runs-on: x
  Deploy:
    runs-on: x
YML
check "build Deploy" "$OUT" "an id with an uppercase letter is listed"

ids underscore <<'YML'
jobs:
  build:
    runs-on: x
  run_tests:
    runs-on: x
YML
check "build run_tests" "$OUT" "an id with an underscore is listed"

ids comment <<'YML'
jobs:
  build:
    runs-on: x
  lint:   # the fast one
    runs-on: x
YML
check "build lint" "$OUT" "an id with a trailing comment is listed"

ids all_forms <<'YML'
jobs:
  Aa_b-9: # c
    runs-on: x
YML
check "Aa_b-9" "$OUT" "an id with every allowed character and a comment is listed"

old=$(awk '/^jobs:/ { on = 1; next } on && /^  [a-z0-9-]+:[[:space:]]*$/ { sub(/:.*/, "", $1); print $1 }' "$T/all_forms.yml")
check "" "$old" "the old reader lists none of the forms (so the cases above would catch a return to it)"

ids scope <<'YML'
# header comment
jobs:
  # a comment at job indent
  one:
    steps:
      - run: echo
    env:
      NOT_A_JOB: x
  two:
    runs-on: x
permissions:
  contents: read
  also_not_a_job:
    x: y
YML
check 0 "$RC" "scope: exit 0"
check "one two" "$OUT" "scope: deeper keys, comments and keys after jobs are not job ids"

ids quoted <<'YML'
jobs:
  build:
    runs-on: x
  "quoted":
    runs-on: x
YML
check 1 "$RC" "a quoted job key fails as unreadable"
check yes "$(has "$ERR" 'unreadable line under jobs:   "quoted":')" "the unreadable line is named"

ids flow <<'YML'
jobs:
  build: {runs-on: x}
YML
check 1 "$RC" "a flow-mapping job fails as unreadable"

ids nojobs <<'YML'
on: push
YML
check 1 "$RC" "no jobs key fails"
check yes "$(has "$ERR" "no jobs: key")" "no jobs key: says why"
ids emptyjobs <<'YML'
jobs:
  # nothing
on: push
YML
check 1 "$RC" "a jobs key without a job id fails"
check yes "$(has "$ERR" "no job id found")" "no job id: says why"

bash "$READER" > /dev/null 2>&1; check 2 "$?" "no argument exits 2"
bash "$READER" "$T/missing.yml" > /dev/null 2>&1; check 2 "$?" "a missing file exits 2"

repo_ids=$(bash "$READER" "$ROOT/.github/workflows/validate-skills.yml" | grep -vx all-checks | sort | tr '\n' ' ')
needs=$(awk '/^  all-checks:/ { a = 1 } a && /^    needs:/ { n = 1; next } n && /^      - / { sub(/^      - /, ""); print; next } n { exit }' "$ROOT/.github/workflows/validate-skills.yml" | sort | tr '\n' ' ')
check "$needs" "$repo_ids" "this repo: the job ids of validate-skills.yml equal the needs of all-checks"
check yes "$(has "$repo_ids" "validate")" "this repo: the reader found jobs"

echo "workflow-job-ids.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
