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

# fixture <name> [noignore]: a git repo with main (also origin/main) and a feature branch one commit ahead; sets D.
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
    if [ "${2:-}" = noignore ]; then echo "node_modules/" > .gitignore; else echo ".claude/review/" > .gitignore; fi
    echo base > a.txt
    git add -A
    git commit -q -m base
    git update-ref refs/remotes/origin/main main
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
    OUT=$(cd "$D" && env "${ENVARGS[@]}" "${EXTRA[@]}" bash "scripts/$s" "$@" 2>&1 < "$IN")
  else
    OUT=$(cd "$D" && env "${ENVARGS[@]}" "${EXTRA[@]}" bash "scripts/$s" "$@" 2>&1 < /dev/null)
  fi
  EC=$?
}

# reply <file> <lines...>: writes a reviewer reply.
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

# local_has <needle> <description>: asserts message text on the last OUT, local mode only.
local_has() {
  if [ "$MODE" = local ]; then has "$1" "$OUT" "$2"; fi
}

# prep: runs --prepare in $D.
prep() {
  run record-review.sh --prepare
}

# record_pass: prepares, then records a pass reply with no findings.
record_pass() {
  prep
  reply "$T/pass.txt" "FINDINGS: none" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
}

# manual_record <sha> <base> <hash> <verdict>: writes a record by hand.
manual_record() {
  mkdir -p "$D/.claude/review"
  mbv=$(git -C "$D" merge-base "$2" HEAD 2> /dev/null) || mbv=$(printf '%040d' 0)
  printf 'sha=%s\nbase=%s\ndiff_hash=%s\nmerge_base=%s\nverdict=%s\n' "$1" "$2" "$3" "$mbv" "$4" > "$D/.claude/review/$1.record"
}

zeros=$(printf '%064d' 0)

suite() {
  fixture nofile
  gate_fail "no record"
  local_has "no review record for commit" "no-record message"
  local_has "code-reviewer agent" "no-record message tells how to fix"
  local_has "verbatim" "fix message says to save the reply verbatim"

  fixture good
  prep
  check 0 "$EC" "prepare succeeds ($OUT)"
  has "current.diff" "$OUT" "prepare names the diff file"
  has "+change" "$(cat "$D/.claude/review/current.diff")" "prepared diff holds the change"
  reply "$T/pass.txt" "a.txt:1 | nit | naming: x | y" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  check 0 "$EC" "record of a pass verdict succeeds ($OUT)"
  has "verdict pass" "$OUT" "record message names the verdict"
  run check-review-record.sh
  check 0 "$EC" "valid pass record passes (control) ($OUT)"
  local_has "ok, commit" "pass message"

  (cd "$D" && echo more > c.txt && git add -A && git commit -q -m more)
  gate_fail "record for another commit"

  fixture content
  (cd "$D" && echo second > c.txt && git add -A && git commit -q -m second)
  record_pass
  second_hash=$(sed -n 's/^diff_hash=//p' "$D/.claude/review/$(cd "$D" && git rev-parse HEAD).record")
  (cd "$D" && git reset -q --hard HEAD~1 && echo different > b.txt && git add -A && git commit -q -m different)
  manual_record "$(cd "$D" && git rev-parse HEAD)" origin/main "$second_hash" pass
  gate_fail "record whose hash belongs to other content"
  local_has "stale" "stale message for changed content"

  fixture stalehash
  record_pass
  sha=$(cd "$D" && git rev-parse HEAD)
  manual_record "$sha" origin/main "$zeros" pass
  gate_fail "record with another diff hash"
  local_has "stale" "stale message"

  fixture failv
  prep
  reply "$T/fail.txt" "b.txt:1 | major | errors: swallowed | rethrow" "VERDICT: fail"
  run record-review.sh "$T/fail.txt"
  check 0 "$EC" "record of a fail verdict is written ($OUT)"
  gate_fail "fail verdict"
  local_has "verdict is fail" "fail verdict message"

  fixture bad
  record_pass
  sha=$(cd "$D" && git rev-parse HEAD)
  rec="$D/.claude/review/$sha.record"
  mbv=$(git -C "$D" merge-base origin/main HEAD)
  printf 'sha=%s\nbase=origin/main\nverdict=pass\nsurprise=1\n' "$sha" > "$rec"
  printf 'merge_base=%s\n' "$mbv" >> "$rec"
  gate_fail "malformed record"
  local_has "malformed" "malformed message"
  printf 'sha=%s\nbase=--evil\ndiff_hash=%s\nverdict=pass\n' "$sha" "$zeros" > "$rec"
  gate_fail "record with an option-like base"
  printf 'sha=%s\nbase=origin/main\ndiff_hash=short\nverdict=pass\n' "$sha" > "$rec"
  printf 'merge_base=%s\n' "$mbv" >> "$rec"
  gate_fail "record with a short hash"
  printf 'sha=%s\nbase=origin/main\ndiff_hash=%s\nverdict=maybe\n' "$sha" "$zeros" > "$rec"
  printf 'merge_base=%s\n' "$mbv" >> "$rec"
  gate_fail "record with an unknown verdict"
  printf 'sha=%s\r\nbase=origin/main\r\ndiff_hash=%s\r\nverdict=pass\r\n' "$sha" "$zeros" > "$rec"
  printf 'merge_base=%s\n' "$mbv" >> "$rec"
  gate_fail "CRLF record"
  local_has "carriage return" "CRLF message"
  printf 'sha=%s\nbase=origin/main\ndiff_hash=%s\nverdict=fail\nverdict=pass\n' "$sha" "$zeros" > "$rec"
  printf 'merge_base=%s\n' "$mbv" >> "$rec"
  gate_fail "record with a duplicate key"
  local_has "duplicate verdict" "duplicate-key message"

  fixture orphan
  (cd "$D" && git checkout -q --orphan solo && git commit -q -m solo)
  manual_record "$(cd "$D" && git rev-parse HEAD)" origin/main "$zeros" pass
  gate_fail "orphan branch with no merge base"
  local_has "no merge base" "no-merge-base message"
  reply "$T/pass.txt" "FINDINGS: none" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  check 1 "$EC" "record-review refuses with no merge base"
  has "no merge base" "$OUT" "record-review names the missing merge base"

  fixture dirty
  record_pass
  run check-review-record.sh
  check 0 "$EC" "clean tree passes (control) ($OUT)"
  echo more >> "$D/b.txt"
  gate_fail "dirty tree"
  local_has "commit the changes, then review again" "dirty-tree message"
  (cd "$D" && git checkout -q -- b.txt && echo new > untracked.txt)
  gate_fail "untracked file"
  rm -f "$D/untracked.txt"
  echo more >> "$D/b.txt"
  prep
  check 1 "$EC" "prepare refuses a dirty tree"
  has "commit the changes, then review again" "$OUT" "prepare dirty-tree message"

  fixture empty
  (cd "$D" && git checkout -q main && git checkout -q -b same)
  prep
  check 1 "$EC" "empty diff is refused by prepare"
  has "nothing to review" "$OUT" "empty-diff message"
  manual_record "$(cd "$D" && git rev-parse HEAD)" origin/main "$zeros" pass
  gate_fail "record for a branch with no commits beyond base"
  local_has "nothing to review" "gate empty-diff message"

  fixture headbase
  EXTRA=(TC_REVIEW_BASE=HEAD)
  prep
  check 1 "$EC" "base equal to HEAD is refused"
  has "HEAD itself" "$OUT" "base-is-HEAD message"
  EXTRA=(TC_NOOP=1)

  fixture detached
  (cd "$D" && git checkout -q --detach)
  record_pass
  check 0 "$EC" "detached HEAD records ($OUT)"
  run check-review-record.sh
  check 0 "$EC" "detached HEAD passes (control) ($OUT)"

  fixture badbase
  EXTRA=(TC_REVIEW_BASE=nope/branch)
  prep
  check 1 "$EC" "unknown TC_REVIEW_BASE is refused"
  has "does not exist" "$OUT" "unknown-base message"
  EXTRA=(TC_REVIEW_BASE=--evil)
  prep
  check 1 "$EC" "option-like TC_REVIEW_BASE is refused"
  has "not a plain branch name" "$OUT" "option-like base message"
  EXTRA=(TC_NOOP=1)

  fixture nobase
  (cd "$D" && git update-ref -d refs/remotes/origin/main && git config branch.feature.remote . && git config branch.feature.merge refs/heads/feature)
  prep
  check 1 "$EC" "the upstream is not used as a base"
  has "no base ref found" "$OUT" "no-base message"
  EXTRA=(TC_NOOP=1)

  fixture originbase
  prep
  has "base origin/main" "$OUT" "default base is origin/main"

  fixture config
  run check-review-record.sh --emit
  h1=$(printf '%s\n' "$OUT" | sed -n 3p)
  (cd "$D" && git config core.abbrev 4 && git config diff.noprefix true && git config diff.mnemonicPrefix true && git config diff.algorithm patience && git config color.ui always && git config diff.context 9)
  run check-review-record.sh --emit
  h2=$(printf '%s\n' "$OUT" | sed -n 3p)
  check "$h1" "$h2" "diff hash ignores user git config"
  check 64 "${#h1}" "diff hash is 64 hex characters"

  fixture ci1
  OUT=$(cd "$D" && env -u GITHUB_ACTIONS -u TF_BUILD CI=1 bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 1 "$EC" "a bare CI=1 does not skip the gate ($OUT)"
  OUT=$(cd "$D" && env -u GITHUB_ACTIONS -u TF_BUILD CI=true bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 1 "$EC" "a bare CI=true does not skip the gate"
  OUT=$(cd "$D" && env TF_BUILD=True bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 0 "$EC" "TF_BUILD skips the gate"
  has "SKIP in CI" "$OUT" "TF_BUILD skip message"

  fixture blocking
  prep
  reply "$T/block.txt" "b.txt:1 | blocker | injection: raw query | use parameters" "VERDICT: pass"
  run record-review.sh "$T/block.txt"
  check 1 "$EC" "pass verdict with a blocker finding is refused"
  has "refused" "$OUT" "refusal message"
  has "1 blocker or major" "$OUT" "refusal counts findings"
  check 0 "$([ -e "$D/.claude/review/$(cd "$D" && git rev-parse HEAD).record" ] && echo 1 || echo 0)" "refused pass wrote no record"
  reply "$T/x.txt" "b.txt:2 | major | logic: edge | fix" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "pass verdict with a major finding is refused"
  reply "$T/x.txt" "- \`dir with space/f.ts:3-9\` | Blocker | injection: x | y" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "bulleted finding with a spaced path and a range is refused"
  has "refused" "$OUT" "bulleted refusal message"
  reply "$T/x.txt" "src/app.ts | MAJOR | logic: x | y" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "finding with no line number and upper case is refused"
  reply "$T/x.txt" "> a.ts:1 |blocker| x | y" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "finding with tight pipes is refused"

  fixture verdicts
  prep
  reply "$T/x.txt" "b.txt:1 | nit | naming: x | y"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "reply without a verdict line is refused"
  has "VERDICT" "$OUT" "missing-verdict message"
  reply "$T/x.txt" "VERDICT: pass" "FINDINGS: none"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "verdict that is not the last line is refused"
  reply "$T/x.txt" "FINDINGS: none" "VERDICT: fail" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "two verdict lines are refused"
  reply "$T/x.txt" "b.txt:1 | nit | naming: x | y" "VERDICT: pass"
  printf 'FINDINGS: none\r\nVERDICT: pass\r\n' > "$T/crlf.txt"
  run record-review.sh "$T/crlf.txt"
  check 0 "$EC" "a CRLF reply is accepted (control) ($OUT)"
  rm -f "$D/.claude/review/"*.record
  reply "$T/x.txt" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "pass with no finding lines and no FINDINGS: none is refused"
  has "FINDINGS: none" "$OUT" "explicit-none message"
  reply "$T/x.txt" "b.txt:1 | nit | naming: x | y" "FINDINGS: none" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "FINDINGS: none beside a finding line is refused"
  reply "$T/x.txt" "VERDICT: fail"
  run record-review.sh "$T/x.txt"
  check 0 "$EC" "a fail verdict needs no FINDINGS line ($OUT)"

  fixture stalediff
  record_pass
  check 0 "$EC" "record with a fresh current.diff succeeds (control) ($OUT)"
  (cd "$D" && echo more > c.txt && git add -A && git commit -q -m more)
  reply "$T/x.txt" "FINDINGS: none" "VERDICT: pass"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "record with a stale current.diff is refused"
  has "current.diff is stale: run" "$OUT" "stale current.diff message"
  rm -f "$D/.claude/review/current.diff"
  run record-review.sh "$T/x.txt"
  check 1 "$EC" "record without current.diff is refused"
  has "run 'bash scripts/record-review.sh --prepare'" "$OUT" "missing current.diff message"

  fixture stdin
  prep
  reply "$T/pass.txt" "FINDINGS: none" "VERDICT: pass"
  IN="$T/pass.txt" run record-review.sh
  check 0 "$EC" "record reads the reply from stdin ($OUT)"
  IN=""

  fixture nearer
  (cd "$D" && echo two > c.txt && git add -A && git commit -q -m two && git branch near HEAD~1)
  EXTRA=(TC_REVIEW_BASE=near)
  record_pass
  check 0 "$EC" "record against a nearer branch is written ($OUT)"
  EXTRA=(TC_NOOP=1)
  gate_fail "record made against a nearer base than the gate wants"
  local_has "base 'near' but the base now is 'origin/main'" "base-mismatch message names both"
  EXTRA=(TC_REVIEW_BASE=near)
  run check-review-record.sh
  check 0 "$EC" "same base passes (control) ($OUT)"
  EXTRA=(TC_NOOP=1)

  fixture movedbase
  (cd "$D" && echo two > c.txt && git add -A && git commit -q -m two)
  record_pass
  (cd "$D" && git update-ref refs/remotes/origin/main HEAD~1)
  gate_fail "base ref moved to a different merge base"
  local_has "stale" "moved-base message"

  fixture ghfalse
  OUT=$(cd "$D" && env -u TF_BUILD GITHUB_ACTIONS=false bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 1 "$EC" "GITHUB_ACTIONS=false does not skip ($OUT)"
  OUT=$(cd "$D" && env -u TF_BUILD GITHUB_ACTIONS=true bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 0 "$EC" "GITHUB_ACTIONS=true skips (control)"
  OUT=$(cd "$D" && env -u GITHUB_ACTIONS TF_BUILD=1 bash scripts/check-review-record.sh 2>&1 < /dev/null)
  EC=$?
  check 1 "$EC" "TF_BUILD=1 does not skip"

  fixture nohash
  mkdir -p "$T/nohash-bin"
  for t in git bash sed cut cat rm mktemp dirname tr cmp grep head wc env awk sort; do
    printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "$t")" > "$T/nohash-bin/$t"
    chmod +x "$T/nohash-bin/$t"
  done
  OUT=$(cd "$D" && env "${ENVARGS[@]}" PATH="$T/nohash-bin" bash scripts/check-review-record.sh --emit 2>&1 < /dev/null)
  EC=$?
  check 2 "$EC" "--emit with no hash tool exits 2 ($OUT)"
  has "need shasum or sha256sum" "$OUT" "no-hash-tool message"
  OUT=$(cd "$D" && env "${ENVARGS[@]}" PATH="$T/nohash-bin" bash scripts/record-review.sh --prepare 2>&1 < /dev/null)
  EC=$?
  check 2 "$EC" "record-review with no hash tool exits 2"
  check 0 "$(find "$D/.claude/review" -name "*.record" 2> /dev/null | wc -l | tr -d ' ')" "no record written without a hash tool"

  fixture noignore noignore
  reply "$T/pass.txt" "FINDINGS: none" "VERDICT: pass"
  run record-review.sh "$T/pass.txt"
  check 1 "$EC" "record refuses when .claude/review/ is not gitignored"
  has ".claude/review/" "$OUT" "gitignore message names the line"
}

for MODE in local ci; do
  if [ "$MODE" = local ]; then
    ENVARGS=(-u CI -u GITHUB_ACTIONS -u TF_BUILD -u TC_REVIEW_BASE)
  else
    ENVARGS=(-u TC_REVIEW_BASE CI=true GITHUB_ACTIONS=true)
  fi
  IN=""
  EXTRA=(TC_NOOP=1)
  suite
done

echo "seeded-review-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
