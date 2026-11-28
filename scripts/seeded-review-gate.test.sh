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
  REC="$D/.claude/review/$(cd "$D" && git rev-parse HEAD).record"
  if [ -e "$REC" ]; then REC_N=1; else REC_N=0; fi
  check 0 "$REC_N" "refused pass wrote no record"
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

# ── wiring: a scaffolded project gets the gate, and the probes below must make verify-harness or the ratchet fail ──
SHARED="$REPO_ROOT/skills/scaffold/shared"
GUARDED_FILES=".claude/agents/code-reviewer.md .claude/review-checklist-stack.txt .claude/review-checklist.txt scripts/check-review-record.sh scripts/record-review.sh scripts/remove-harness.sh"
CLEAN=(env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u TC_REVIEW_BASE)
GIT=(git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)

# yn <command>: prints yes when the command succeeds and no when it fails.
yn() {
  if "$@"; then echo yes; else echo no; fi
}

# wf_status <stack> <shared-dir> <target>: prints ok when the copy works and refused when a part refuses.
wf_status() {
  if wf_scaffold "$@"; then echo ok; else echo refused; fi
}

# wf_scaffold <stack> <shared-dir> <target>: copies every part into <target>, commits it on main and branches to work; returns 1 when a part refuses.
wf_scaffold() {
  local st=$1 sh=$2 d=$3 part
  rm -rf "$d"
  mkdir -p "$d"
  for part in stack base agents settings late; do
    TC_STACK=$st TC_PART=$part bash "$sh/tc-copy.sh" "$d" > /dev/null 2>&1 || return 1
  done
  TC_STACK=$st TC_PART=ci TC_CI=github bash "$sh/tc-copy.sh" "$d" > /dev/null 2>&1 || return 1
  TC_STACK=$st TC_PART=manifest bash "$sh/tc-copy.sh" "$d" > /dev/null 2>&1 || return 1
  printf '# %s\n' "$st" > "$d/README.md"
  git -C "$d" init -q -b main
  git -C "$d" add -A
  "${GIT[@]}" -C "$d" commit -q -m scaffold || return 1
  git -C "$d" update-ref refs/remotes/origin/main main
  git -C "$d" checkout -q -b work
}

# wf_reset: puts $W back on the scaffold commit.
wf_reset() {
  git -C "$W" checkout -q -f work
  git -C "$W" reset -q --hard main
  git -C "$W" clean -fdq
}

# wf_commit <message>: commits every change in $W.
wf_commit() {
  git -C "$W" add -A
  "${GIT[@]}" -C "$W" commit -q --allow-empty -m "$1"
}

# wf_verify: runs verify-harness in $W; sets OUT and EC.
wf_verify() {
  OUT=$(cd "$W" && "${CLEAN[@]}" bash .claude/verify-harness.sh 2>&1)
  EC=$?
}

# wf_ratchet: runs the gate ratchet against main in $W; sets OUT and EC.
wf_ratchet() {
  OUT=$(cd "$W" && "${CLEAN[@]}" bash scripts/gate-ratchet.sh auto 2>&1)
  EC=$?
}

# wf_bless: re-hashes harness.json the way a human would, so only the structural checks can still fail.
wf_bless() {
  (cd "$W" && bash .claude/regen-harness.sh > /dev/null 2>&1)
}

for ST in nextjs nestjs vite-react fastapi; do
  W="$T/wf-$ST"
  if ! wf_scaffold "$ST" "$SHARED" "$W"; then check ok scaffold-failed "wiring[$ST]: scaffold copies every part"; continue; fi
  for f in $GUARDED_FILES; do check yes "$(yn test -s "$W/$f")" "wiring[$ST]: scaffold seeds $f"; done
  check yes "$(yn grep -q 'review-record' "$W/lefthook.yml")" "wiring[$ST]: lefthook carries the review gate"
  check 1 "$(sed -n '/^pre-push:/,$p' "$W/lefthook.yml" | grep -c 'run: bash scripts/check-review-record.sh')" "wiring[$ST]: the review gate runs in pre-push"
  check yes "$(yn grep -q '^review|scripts/check-review-record.sh|-$' "$W/.claude/gates.txt")" "wiring[$ST]: gates.txt row is pre-push only"
  check no "$(yn grep -q 'check-review-record' "$W/.github/workflows/ci.yml")" "wiring[$ST]: CI has no always-skipping review step"
  check yes "$(yn git -C "$W" check-ignore -q .claude/review/abc.record)" "wiring[$ST]: .gitignore covers .claude/review/"
  guarded=$(cd "$W" && bash scripts/gate-ratchet.sh --list-guarded HEAD 2>&1)
  for f in $GUARDED_FILES; do
    check yes "$(printf '%s\n' "$guarded" | awk -F'\t' -v p="$f" '$2 == p && $3 == 1 { h = 1 } END { print h ? "yes" : "no" }')" "wiring[$ST]: $f is guarded and enforced"
  done
  for f in $GUARDED_FILES; do check 1 "$(grep -c "\"path\": \"$f\"" "$W/.claude/harness.json")" "wiring[$ST]: harness.json lists $f"; done

  # clean control
  wf_verify; check 0 "$EC" "wiring[$ST]: control, verify-harness passes ($OUT)"
  wf_ratchet; check 0 "$EC" "wiring[$ST]: control, ratchet passes ($OUT)"

  # (a) gate script removed, then emptied; the second case is blessed so only the structural check is left
  wf_reset; git -C "$W" rm -q scripts/check-review-record.sh; wf_commit "remove gate"
  wf_verify; check 1 "$EC" "wiring[$ST]: (a) removed gate script fails verify-harness"
  has "check-review-record.sh" "$OUT" "wiring[$ST]: (a) the message names the script"
  wf_bless; wf_verify; check 1 "$EC" "wiring[$ST]: (a) removed gate script still fails after re-hashing"
  wf_reset; : > "$W/scripts/check-review-record.sh"; wf_commit "empty gate"
  wf_verify; check 1 "$EC" "wiring[$ST]: (a) emptied gate script fails verify-harness"
  wf_bless; wf_verify; check 1 "$EC" "wiring[$ST]: (a) emptied gate script still fails after re-hashing"
  has "REVIEW GATE FILE MISSING" "$OUT" "wiring[$ST]: (a) the empty file is named"
  wf_reset; printf '\n  \n' > "$W/scripts/check-review-record.sh"; wf_commit "blank gate"
  wf_bless; wf_verify; check 1 "$EC" "wiring[$ST]: (a) whitespace-only gate script fails after re-hashing"
  has "REVIEW GATE FILE MISSING" "$OUT" "wiring[$ST]: (a) the whitespace-only file is named"
  wf_reset; wf_bless; wf_verify; check 0 "$EC" "wiring[$ST]: (a) control, an untouched gate script passes after re-hashing"

  # (b) lefthook pre-push line removed
  wf_reset
  awk '/^    review-record:/ { skip = 1; next } skip && /^    [a-z]/ { skip = 0 } skip && /^[a-z]/ { skip = 0 } !skip' "$W/lefthook.yml" > "$W/lefthook.new" && mv "$W/lefthook.new" "$W/lefthook.yml"
  check no "$(yn grep -q 'check-review-record' "$W/lefthook.yml")" "wiring[$ST]: (b) the probe removed the lefthook line"
  wf_commit "drop review hook"
  wf_verify; check 1 "$EC" "wiring[$ST]: (b) removed lefthook line fails verify-harness"
  wf_bless; wf_verify; check 1 "$EC" "wiring[$ST]: (b) removed lefthook line still fails after re-hashing"
  has "GATE MISSING: review" "$OUT" "wiring[$ST]: (b) the review gate is named"

  # (c) checklist edited in the change under review
  wf_reset; printf 'nothing to see\n' > "$W/.claude/review-checklist.txt"; wf_commit "weaken checklist"
  wf_verify; check 1 "$EC" "wiring[$ST]: (c) edited checklist fails verify-harness"
  wf_ratchet; check 1 "$EC" "wiring[$ST]: (c) edited checklist fails the ratchet"
  has ".claude/review-checklist.txt" "$OUT" "wiring[$ST]: (c) the ratchet names the checklist"
  wf_bless; wf_verify; check 0 "$EC" "wiring[$ST]: (c) a re-hashed checklist passes verify-harness, the ratchet is the catch"
  wf_ratchet; check 1 "$EC" "wiring[$ST]: (c) re-hashed checklist still fails the ratchet"
  wf_reset; printf 'x\n' >> "$W/.claude/agents/code-reviewer.md"; wf_commit "edit reviewer"
  wf_ratchet; check 1 "$EC" "wiring[$ST]: (c) edited reviewer agent fails the ratchet"
  wf_reset; printf 'x\n' >> "$W/scripts/record-review.sh"; wf_commit "edit recorder"
  wf_ratchet; check 1 "$EC" "wiring[$ST]: (c) edited record-review.sh fails the ratchet"

  # (e) the review row deleted from gates.txt: the hash check catches it until a human re-hashes; verify-harness.sh does not yet fail on the missing row after that
  wf_reset; grep -v '^review|' "$W/.claude/gates.txt" > "$W/.claude/gates.new" && mv "$W/.claude/gates.new" "$W/.claude/gates.txt"
  check 0 "$(grep -c '^review|' "$W/.claude/gates.txt")" "wiring[$ST]: (e) the probe removed the review row"
  wf_commit "drop review row"
  wf_verify; check 1 "$EC" "wiring[$ST]: (e) a deleted review row fails verify-harness"
  has ".claude/gates.txt" "$OUT" "wiring[$ST]: (e) the failure names gates.txt"
  wf_reset; wf_bless; wf_verify; check 0 "$EC" "wiring[$ST]: (e) control, the untouched row passes after re-hashing"
done

# (d) each new manifest row dropped in turn: the copy refuses every stack it feeds; a row only one stack uses leaves the other stack copying
for ROW in template/.claude/agents/code-reviewer.md template/.claude/review-checklist.txt template/scripts/check-review-record.sh template/scripts/record-review.sh template/scripts/remove-harness.sh template-ts/.claude/review-checklist-stack.txt template-py/.claude/review-checklist-stack.txt; do
  ALT="$T/alt-$(basename "$ROW")"
  rm -rf "$ALT"
  mkdir -p "$ALT/skills"
  cp -Rp "$REPO_ROOT/skills/scaffold" "$ALT/skills/scaffold"
  cp -Rp "$REPO_ROOT/.claude-plugin" "$ALT/.claude-plugin"
  grep -vF "$ROW " "$SHARED/template.manifest" > "$ALT/skills/scaffold/shared/template.manifest"
  check 1 "$(grep -cF "$ROW " "$SHARED/template.manifest")" "wiring: manifest row $ROW exists"
  case "$ROW" in
    template-ts/*) BADS="nextjs nestjs vite-react"; OK=fastapi ;;
    template-py/*) BADS="fastapi"; OK=nextjs ;;
    *) BADS="nextjs nestjs vite-react fastapi"; OK="" ;;
  esac
  for BAD in $BADS; do
    check refused "$(wf_status "$BAD" "$ALT/skills/scaffold/shared" "$T/alt-bad")" "wiring: (d) missing row $ROW makes the $BAD copy refuse"
  done
  if [ -n "$OK" ]; then
    check ok "$(wf_status "$OK" "$ALT/skills/scaffold/shared" "$T/alt-ok")" "wiring: (d) control, the $OK copy is not affected by $ROW"
  fi
done
check ok "$(wf_status nextjs "$SHARED" "$T/alt-full")" "wiring: (d) control, the unmodified manifest copies"

echo "seeded-review-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
