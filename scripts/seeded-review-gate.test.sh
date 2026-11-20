#!/usr/bin/env bash
# scripts/seeded-review-gate.test.sh — tests for the seeded check-review-record.sh and record-review.sh in real git fixtures.
# Usage: bash scripts/seeded-review-gate.test.sh
# Runs once as a local run (CI markers cleared) and once with CI=true GITHUB_ACTIONS=true, where the gate skips.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SC="$REPO_ROOT/skills/scaffold/shared/template/scripts"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/review-gate.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# fixture <name> [ignore]: a git repo with main and a feature branch one commit ahead; sets D.
fixture() {
  D="$T/$1"
  rm -rf "$D"
  mkdir -p "$D/scripts"
  cp "$SC/check-review-record.sh" "$SC/record-review.sh" "$D/scripts/"
  (
    cd "$D" || exit 2
    git init -q
    git checkout -q -b main
    git config user.email t@example.com
    git config user.name t
    git config commit.gpgsign false
    if [ "${2:-ignore}" = ignore ]; then echo ".claude/review/" > .gitignore; else echo "node_modules/" > .gitignore; fi
    echo base > a.txt
    git add -A
    git commit -q -m base
    git checkout -q -b feature
    echo change > b.txt
    git add -A
    git commit -q -m change
  ) || exit 2
}

# run <script> [args]: runs a seeded script in $D under the current mode; sets OUT and EC. Stdin comes from $IN when set.
run() {
  local s=$1
  shift
  if [ -n "${IN:-}" ]; then
    OUT=$(cd "$D" && env "${ENVARGS[@]}" bash "scripts/$s" "$@" 2>&1 < "$IN")
  else
    OUT=$(cd "$D" && env "${ENVARGS[@]}" bash "scripts/$s" "$@" 2>&1 < /dev/null)
  fi
  EC=$?
}

# reply <file> <body...>: writes a reviewer reply.
reply() {
  local f=$1
  shift
  printf '%s\n' "$@" > "$f"
}

# gate_fail <description>: expects the gate to fail locally and to skip in CI.
gate_fail() {
  run check-review-record.sh
  if [ "$MODE" = local ]; then
    check 1 "$EC" "$1 fails ($OUT)"
  else
    check 0 "$EC" "$1 skips in CI"
    has "SKIP in CI" "$OUT" "$1 says it skipped"
  fi
}

suite() {
  fixture nofile
  gate_fail "no record"
  [ "$MODE" = local ] && has "no review record for commit" "$OUT" "no-record message"
  [ "$MODE" = local ] && has "code-reviewer agent" "$OUT" "no-record message tells how to fix"

  fixture good
  run record-review.sh --prepare
  check 0 "$EC" "prepare succeeds ($OUT)"
  has "current.diff" "$OUT" "prepare names the diff file"
  has "+change" "$(cat "$D/.claude/review/current.diff")" "prepared diff holds the change"
  reply "$T/pass.txt" "a.txt:1 | nit | naming: x | y" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  check 0 "$EC" "record of a pass verdict succeeds ($OUT)"
  has "verdict pass" "$OUT" "record message names the verdict"
  run check-review-record.sh
  check 0 "$EC" "valid pass record passes (control) ($OUT)"
  if [ "$MODE" = local ]; then has "ok, commit" "$OUT" "pass message"; fi

  (cd "$D" && echo more > c.txt && git add -A && git commit -q -m more)
  gate_fail "record for another commit"
  (cd "$D" && git reset -q --hard HEAD~1)

  fixture stale
  run record-review.sh < /dev/null
  reply "$T/pass.txt" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  sha=$(cd "$D" && git rev-parse HEAD)
  sed 's/^diff_hash=.*/diff_hash=0000000000000000000000000000000000000000000000000000000000000000/' "$D/.claude/review/$sha.record" > "$T/r" && cp "$T/r" "$D/.claude/review/$sha.record"
  gate_fail "record with another diff hash"
  [ "$MODE" = local ] && has "stale" "$OUT" "stale message"

  fixture failv
  reply "$T/fail.txt" "b.txt:1 | major | errors: swallowed | rethrow" "VERDICT: fail"
  run record-review.sh "$T/fail.txt"
  check 0 "$EC" "record of a fail verdict is written ($OUT)"
  gate_fail "fail verdict"
  [ "$MODE" = local ] && has "verdict is fail" "$OUT" "fail verdict message"

  fixture bad
  reply "$T/pass.txt" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  sha=$(cd "$D" && git rev-parse HEAD)
  printf 'sha=%s\nbase=main\nverdict=pass\nsurprise=1\n' "$sha" > "$D/.claude/review/$sha.record"
  gate_fail "malformed record"
  [ "$MODE" = local ] && has "malformed" "$OUT" "malformed message"
  printf 'sha=%s\nbase=--evil\ndiff_hash=%s\nverdict=pass\n' "$sha" "$(printf '%064d' 0)" > "$D/.claude/review/$sha.record"
  gate_fail "record with an option-like base"
  printf 'sha=%s\nbase=main\ndiff_hash=short\nverdict=pass\n' "$sha" > "$D/.claude/review/$sha.record"
  gate_fail "record with a short hash"
  printf 'sha=%s\nbase=main\ndiff_hash=%s\nverdict=maybe\n' "$sha" "$(printf '%064d' 0)" > "$D/.claude/review/$sha.record"
  gate_fail "record with an unknown verdict"

  fixture blocking
  reply "$T/block.txt" "b.txt:1 | blocker | injection: raw query | use parameters" "VERDICT: pass"
  run record-review.sh "$T/block.txt"
  check 1 "$EC" "pass verdict with a blocker finding is refused"
  has "refused" "$OUT" "refusal message"
  has "1 blocker or major" "$OUT" "refusal counts findings"
  check 0 "$([ -e "$D/.claude/review/$(cd "$D" && git rev-parse HEAD).record" ] && echo 1 || echo 0)" "refused pass wrote no record"
  reply "$T/major.txt" "b.txt:2 | major | logic: edge | fix" "VERDICT: pass"
  run record-review.sh "$T/major.txt"
  check 1 "$EC" "pass verdict with a major finding is refused"

  fixture noverdict
  reply "$T/nov.txt" "b.txt:1 | nit | naming: x | y"
  run record-review.sh "$T/nov.txt"
  check 1 "$EC" "reply without a verdict line is refused"
  has "VERDICT" "$OUT" "missing-verdict message"

  fixture stdin
  reply "$T/pass.txt" "VERDICT: pass"
  IN="$T/pass.txt" run record-review.sh
  check 0 "$EC" "record reads the reply from stdin ($OUT)"
  IN=""

  fixture noignore noignore
  reply "$T/pass.txt" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  check 1 "$EC" "record refuses when .claude/review/ is not gitignored"
  has ".claude/review/" "$OUT" "gitignore message names the line"
}

for MODE in local ci; do
  if [ "$MODE" = local ]; then
    ENVARGS=(-u CI -u GITHUB_ACTIONS -u TF_BUILD)
  else
    ENVARGS=(CI=true GITHUB_ACTIONS=true)
  fi
  IN=""
  suite
done

echo "seeded-review-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
