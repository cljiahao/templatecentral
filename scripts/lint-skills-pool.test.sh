#!/usr/bin/env bash
# scripts/lint-skills-pool.test.sh — tests for the probe pool in scripts/lint-skills.test.sh.
# The pool code is cut out of that file (between its "probe pool" marker lines) and driven with probes
# written here. Each failing case has a clean control. Three guards are removed in turn (a result with
# no end marker, a job that exits non-zero, a probe that wrote no file); each removal must let the
# planted case through, so these tests would notice the guard going missing. An interrupt must stop
# the probes and remove the temp root. The assertions do not depend on timing or CPU count.
# Usage: bash scripts/lint-skills-pool.test.sh   (needs ps; run it outside a sandbox that hides processes)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/lint-skills.test.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/lint-pool-test.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
RUN=0
PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

awk '/^# ── probe pool ─/ { on = 1 } on { print } /^# ── end probe pool ─/ { exit }' "$SRC" > "$W/pool.sh"
check yes "$([[ "$(wc -l < "$W/pool.sh")" -gt 20 && -n "$(grep -F pool_collect "$W/pool.sh" || true)" ]] && echo yes || echo no)" "the pool code was found in $SRC"

cat > "$W/probes.sh" <<'PROBES'
p_ok() { emit PASS; }
p_wrong() { emit "FAIL: planted — expected [a], got [b]"; }
p_exit_early() { exit 0; }
p_empty() { : > "$T/r$NJOB"; }
p_truncated() { printf 'PASS\nPASS\n' > "$T/r$NJOB"; }
p_status() { emit PASS; exit 5; }
p_private() { if mkdir "$T/w$NJOB"; then emit PASS; else emit "FAIL: probe $NJOB shares its dir"; fi; }
p_waits_for_go() { local i; for (( i = 0; i < 2000; i++ )); do [[ -e "$T/go" ]] && break; sleep 0.05; done; emit "FAIL: first"; }
p_opens_go() { : > "$T/go"; emit "FAIL: last"; }
p_hang() { sleep 600 & echo "$!" > "$T/hang.pid"; wait; }
PROBES

# write_driver <jobs> <override file or -> <probe>... — a script that runs the probes through the pool; sets D to its dir.
write_driver() {
  local jobs=$1 over=$2 p
  shift 2
  D="$W/run$((++RUN))"
  mkdir -p "$D"
  {
    printf 'set -uo pipefail\nT=%q\nJOBS=%q\nPASS=0\nFAIL=0\nONLY=\n' "$D/t" "$jobs"
    cat <<'HEAD'
mkdir -p "$T"
HEAD
    printf 'source %q\nsource %q\n' "$W/pool.sh" "$W/probes.sh"
    [[ "$over" == - ]] || printf 'source %q\n' "$over"
    for p in "$@"; do printf 'pool_start %q %q\n' "$p" "$p"; done
    cat <<'TAIL'
pool_collect
echo "passed=$PASS failed=$FAIL"
[[ $FAIL -eq 0 ]]
TAIL
  } > "$D/driver.sh"
}

# drive <jobs> <override file or -> <probe>... — run the driver to the end; sets OUT and RC.
drive() {
  write_driver "$@"
  OUT=$(bash "$D/driver.sh" 2>&1); RC=$?
}

for jobs in 1 3; do
  drive "$jobs" - p_ok p_ok p_ok
  check 0 "$RC" "control, jobs=$jobs: three passing probes exit 0"
  check "passed=3 failed=0" "$OUT" "control, jobs=$jobs: nothing printed but the summary"

  drive "$jobs" - p_ok p_wrong p_ok
  check 1 "$RC" "jobs=$jobs: a planted wrong expectation exits non-zero"
  check yes "$([[ "$OUT" == *"FAIL: planted — expected [a], got [b]"* && "$OUT" == *"passed=2 failed=1" ]] && echo yes || echo no)" "jobs=$jobs: the planted failure is printed and counted"

  drive "$jobs" - p_ok p_exit_early p_ok
  check 1 "$RC" "jobs=$jobs: a probe that exits early without a result exits non-zero"
  check yes "$([[ "$OUT" == *"FAIL: p_exit_early — the probe wrote no result"* && "$OUT" == *"1 missing"* && "$OUT" == *"passed=2 failed=1" ]] && echo yes || echo no)" "jobs=$jobs: the early exit is named and counted as missing"

  drive "$jobs" - p_empty
  check 1 "$RC" "jobs=$jobs: an empty result file exits non-zero"
  drive "$jobs" - p_truncated
  check 1 "$RC" "jobs=$jobs: a result without its end marker exits non-zero"
  drive "$jobs" - p_status
  check 1 "$RC" "jobs=$jobs: a job that exits non-zero after a PASS result exits non-zero"
  drive "$jobs" - p_private p_private p_private p_private
  check 0 "$RC" "jobs=$jobs: every probe gets a work dir of its own"
done

drive 3 - p_waits_for_go p_ok p_opens_go
check yes "$([[ "$OUT" == *"FAIL: first"*"FAIL: last"* ]] && echo yes || echo no)" "failures print in probe order, not in finishing order"

cat > "$W/no-trailer-guard.sh" <<'M'
trailer_ok() { return 0; }
M
cat > "$W/no-status-guard.sh" <<'M'
status_ok() { return 0; }
M
cat > "$W/no-missing-guard.sh" <<'M'
missing_results_fail() { :; }
M
drive 3 "$W/no-trailer-guard.sh" p_truncated
check 0 "$RC" "guard removed (end marker): the truncated result passes, so the test above would catch the removal"
drive 3 "$W/no-status-guard.sh" p_status
check 0 "$RC" "guard removed (job status): the crashing job passes, so the test above would catch the removal"
drive 3 "$W/no-missing-guard.sh" p_exit_early
check 0 "$RC" "guard removed (missing result): the early exit passes, so the test above would catch the removal"

write_driver 2 - p_hang p_ok
bash "$D/driver.sh" > "$D/out" 2>&1 &
dpid=$!
for (( i = 0; i < 2000; i++ )); do [[ -s "$D/t/hang.pid" ]] && break; sleep 0.05; done
hpid=$(cat "$D/t/hang.pid" 2>/dev/null || true)
check yes "$([[ -n "$hpid" ]] && echo yes || echo no)" "interrupt: the hanging probe started"
kill -TERM "$dpid" 2>/dev/null || true
wait "$dpid"; drc=$?
check 143 "$drc" "interrupt: the driver exits 143 on TERM"
check no "$([[ -d "$D/t" ]] && echo yes || echo no)" "interrupt: the temp root is removed"
check no "$([[ -n "$hpid" ]] && kill -0 "$hpid" 2>/dev/null && echo yes || echo no)" "interrupt: the hanging probe is stopped"

echo "lint-skills-pool.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
