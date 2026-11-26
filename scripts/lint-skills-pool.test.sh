#!/usr/bin/env bash
# scripts/lint-skills-pool.test.sh — tests for the probe pool and the LINT_TEST_JOBS check in scripts/lint-skills.test.sh.
# The pool code is cut out of that file (between its "probe pool" marker lines) and driven with probes
# written here. The JOBS check is run on the top of that file, cut at the temp dir line.
# Each failing case has a clean control. Guards are removed in turn: the result end marker, the job
# status check, the missing-result check, the JOBS check, the order of mktemp before it, the process-group
# cleanup (replaced by a ps-based one), the keep-the-dir rule, the serial point. Each removal must let the
# planted case through, so these tests would notice the guard going missing.
# Cleanup is tested with ps on PATH, with ps absent and with a ps that always fails.
# Nothing here reads a clock: probes and the driver meet through FIFOs (a read waits for the other side),
# and a driver that dies early is reported by an "exited" line. A driver that does not exit is found by a
# bounded count of one-second read retries (NEXT_TRIES); then its process group is killed and the case fails
# with its own message ("hung"), so a broken pool cannot hang the test. The wait is a failure bound, never
# an assertion about how long a pass takes.
# A probe reads /dev/null as stdin: the driver's stdin holds a line, and a probe that reads it must see EOF.
# The one strict-serial property (JOBS=1 finishes the last probe before the parent-side code) is tested
# in two halves: the pool's own run (p_ok, the result file is there at the serial point) and a mutant run
# with the serial point removed (a probe that the parent code releases, so the file is not there). A probe
# that ran for a fixed time would be a wall-time assertion, so the guard's absence is shown by the mutant.
# Usage: bash scripts/lint-skills-pool.test.sh   (run it outside a sandbox that hides or blocks mktemp)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/lint-skills.test.sh"
BASH_BIN=$(command -v bash)
W=$(mktemp -d "${TMPDIR:-/tmp}/lint-pool-test.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
RUN=0
PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# yn <command...> — yes when the command succeeds, else no.
yn() { if "$@"; then echo yes; else echo no; fi; }
# has <text> <needle> — yes when text contains needle.
has() { case $1 in *"$2"*) echo yes ;; *) echo no ;; esac; }
# ordered <text> <first> <second> — yes when first appears before second.
ordered() { case $1 in *"$2"*"$3"*) echo yes ;; *) echo no ;; esac; }
# alive <pid> — yes when the process exists.
alive() { if [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; then echo yes; else echo no; fi; }
# isdir <path> — yes when the directory exists.
isdir() { if [[ -d "$1" ]]; then echo yes; else echo no; fi; }

awk '/^# ── probe pool ─/ { on = 1 } on { print } /^# ── end probe pool ─/ { exit }' "$SRC" > "$W/pool.sh"
check yes "$(yn grep -qF pool_collect "$W/pool.sh")" "the pool code (pool_collect) was found in $SRC"
check yes "$(yn grep -qF pool_stop_group "$W/pool.sh")" "the pool code (pool_stop_group) was found in $SRC"

cat > "$W/probes.sh" <<'PROBES'
p_ok() { emit PASS; }
p_wrong() { emit "FAIL: planted — expected [a], got [b]"; }
p_exit_early() { exit 0; }
p_empty() { : > "$T/r$NJOB"; }
p_truncated() { printf 'PASS\nPASS\n' > "$T/r$NJOB"; }
p_status() { emit PASS; exit 5; }
p_private() { if mkdir "$T/w$NJOB"; then emit PASS; else emit "FAIL: probe $NJOB shares its dir"; fi; }
p_waits_for_go() { local x; read -r x <&7; emit "FAIL: first"; }
p_opens_go() { echo go >&7; emit "FAIL: last"; }
p_gated() { local x; read -r x <&7; emit PASS; }
p_stdin() { local x; if read -r x; then emit "FAIL: probe $NJOB read stdin: $x"; else emit PASS; fi; }
p_hang() { sleep 600 & echo "$!" > "$T/hang.pid"; echo started > "$NOTE"; wait; }
PROBES

# write_driver <jobs> <override file or -> <probe>... — a script that runs the probes through the pool; sets D to its dir.
# $EXTRA (text) runs after the probes are started and before they are collected.
EXTRA=
write_driver() {
  local jobs=$1 over=$2 p
  shift 2
  D="$W/run$((++RUN))"
  mkdir -p "$D"
  printf 'data from the driver stdin\n' > "$D/in"
  {
    printf 'echo $$ > %q\nset -uo pipefail\nset -m\nT=%q\nJOBS=%q\nNOTE=%q\nPASS=0\nFAIL=0\nONLY=\n' "$D/dpid" "$D/t" "$jobs" "$D/note"
    cat <<'HEAD'
mkdir -p "$T"
mkfifo "$T/gate"
exec 7<>"$T/gate"
HEAD
    printf 'source %q\nsource %q\n' "$W/pool.sh" "$W/probes.sh"
    if [[ "$over" != - ]]; then printf 'source %q\n' "$over"; fi
    for p in "$@"; do printf 'pool_start %q %q\n' "$p" "$p"; done
    printf '%s\n' "$EXTRA"
    cat <<'TAIL'
pool_collect
echo "passed=$PASS failed=$FAIL"
[[ $FAIL -eq 0 ]]
TAIL
  } > "$D/driver.sh"
}

# The driver runs in the background in a process group of its own and tells this script through the note
# FIFO (fd 3) when it exits; the probes' own lines on that FIFO ("started") come through the same way.
NEXT_TRIES=120
# next_line — read one line of the note FIFO into LINE; false after NEXT_TRIES one-second read timeouts.
next_line() {
  local i
  LINE=
  for ((i = 0; i < NEXT_TRIES; i++)); do
    if read -r -t 1 LINE <&3; then return 0; fi
  done
  return 1
}

# start_driver <path dir or -> — start the driver written by write_driver, with the path dir as PATH when given.
start_driver() {
  local pdir=$1
  mkfifo "$D/note"
  exec 3<>"$D/note"
  LINE=
  (
    set -m
    if [[ "$pdir" == - ]]; then "$BASH_BIN" "$D/driver.sh" > "$D/out" 2>&1 < "$D/in" & else PATH="$pdir" "$BASH_BIN" "$D/driver.sh" > "$D/out" 2>&1 < "$D/in" & fi
    echo "$!" > "$D/spid"
    wait $!
    echo "exited $?" > "$D/note"
  ) 2>/dev/null &
}

# await_exit — wait for the driver's "exited" line. Sets DRC (its exit status, or hung), HUNG (yes or no)
# and OUT. A driver that is still running after the retry bound has its process group killed.
await_exit() {
  local spid
  DRC=
  HUNG=no
  while :; do
    case $LINE in exited*) DRC=${LINE#exited }; break ;; esac
    next_line || break
  done
  if [[ -z "$DRC" ]]; then
    HUNG=yes
    DRC=hung
    spid=$(cat "$D/spid" 2>/dev/null || true)
    if [[ -n "$spid" ]]; then kill -KILL -- "-$spid" 2>/dev/null || true; fi
    next_line || true
  fi
  exec 3<&-
  OUT=$(cat "$D/out")
}

# drive <jobs> <override file or -> <probe>... — run the driver to the end; sets OUT and RC.
drive() {
  write_driver "$@"
  start_driver -
  await_exit
  RC=$DRC
  check no "$HUNG" "the driver exits within the retry bound (hung: its group was killed)"
}

for jobs in 1 3; do
  drive "$jobs" - p_ok p_ok p_ok
  check 0 "$RC" "control, jobs=$jobs: three passing probes exit 0"
  check "passed=3 failed=0" "$OUT" "control, jobs=$jobs: nothing printed but the summary"

  drive "$jobs" - p_ok p_wrong p_ok
  check 1 "$RC" "jobs=$jobs: a planted wrong expectation exits non-zero"
  check yes "$(has "$OUT" "FAIL: planted — expected [a], got [b]")" "jobs=$jobs: the planted failure is printed"
  check yes "$(has "$OUT" "passed=2 failed=1")" "jobs=$jobs: the planted failure is counted"

  drive "$jobs" - p_ok p_exit_early p_ok
  check 1 "$RC" "jobs=$jobs: a probe that exits early without a result exits non-zero"
  check yes "$(has "$OUT" "FAIL: p_exit_early — the probe wrote no result")" "jobs=$jobs: the early exit is named"
  check yes "$(has "$OUT" "1 missing")" "jobs=$jobs: the early exit is counted as missing"
  check yes "$(has "$OUT" "passed=2 failed=1")" "jobs=$jobs: the early exit costs one failure"

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
check yes "$(ordered "$OUT" "FAIL: first" "FAIL: last")" "failures print in probe order, not in finishing order (the first probe cannot finish before the last)"

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

# Probe stdin. The driver's stdin holds a line (written by write_driver); a probe must see EOF.
for jobs in 1 3; do
  drive "$jobs" - p_stdin p_stdin
  check 0 "$RC" "control, jobs=$jobs: a probe that reads stdin gets EOF, not the driver's stdin"
done
awk '/^pool_start\(\)/ { on = 1 } on { print } on && /^}/ { exit }' "$W/pool.sh" | sed 's|) </dev/null &|) \&|' > "$W/no-devnull.sh"
check yes "$(yn grep -qF '( "$@" ) &' "$W/no-devnull.sh")" "the stdin mutant starts the probe without </dev/null"
drive 3 "$W/no-devnull.sh" p_stdin
check 1 "$RC" "guard removed (</dev/null): the probe reads the driver's stdin and fails, so the control above would catch the removal"
check yes "$(has "$OUT" "read stdin: data from the driver stdin")" "guard removed (</dev/null): the failure names the stdin line the probe read"

# Serial point. Control: one job, the result file is there when the serial point returns.
EXTRA=$(cat <<'X'
pool_serial_point
if [[ -e "$T/r1" ]]; then echo "at-serial-point r1=yes"; else echo "at-serial-point r1=no"; fi
echo go >&7
X
)
drive 1 - p_ok
check yes "$(has "$OUT" "at-serial-point r1=yes")" "jobs=1: the last probe has finished at the serial point"
# More than one job: the serial point does not wait, so the parent-side code overlaps a probe it releases.
drive 3 - p_gated
check yes "$(has "$OUT" "at-serial-point r1=no")" "jobs=3: parent-side code overlaps a running probe"
check 0 "$RC" "jobs=3: the released probe passes"
# Guard removed: the serial point does nothing, one job, a probe the parent releases.
echo 'pool_serial_point() { :; }' > "$W/no-serial-point.sh"
drive 1 "$W/no-serial-point.sh" p_gated
check yes "$(has "$OUT" "at-serial-point r1=no")" "guard removed (serial point): the parent-side code runs before the last probe finished, which the jobs=1 control above would catch"
EXTRA=

# Interrupt cleanup. interrupt_run <path dir or -> <override file or -> <probe>... starts the driver,
# waits (on the FIFO) until the hanging probe says it started, sends TERM and waits for the driver's
# "exited" line. Sets D, HPID, DRC (driver exit status), HUNG and OUT.
interrupt_run() {
  local pdir=$1 over=$2 dpid
  shift 2
  write_driver 2 "$over" "$@"
  start_driver "$pdir"
  HPID=
  if next_line && [[ "$LINE" == started ]]; then
    HPID=$(cat "$D/t/hang.pid")
    dpid=$(cat "$D/dpid")
    kill -TERM "$dpid" 2>/dev/null || true
  fi
  await_exit
}

# tool_dir <dir> <ps behavior: none|fail> — a PATH dir with the tools the pool needs, and a ps or none.
tool_dir() {
  local d=$1 t p
  mkdir -p "$d"
  for t in sleep sed tail mv rm mkdir mkfifo cat awk wc head grep dirname env date mktemp find tr; do
    p=$(command -v "$t") && ln -s "$p" "$d/$t"
  done
  if [[ "$2" == fail ]]; then
    printf '#!/bin/sh\nexit 1\n' > "$d/ps"
    chmod +x "$d/ps"
  fi
}
tool_dir "$W/nops" none
tool_dir "$W/badps" fail
check no "$(yn test -e "$W/nops/ps")" "the ps-less PATH has no ps"

cleanup_cases() { # cleanup_cases <label> <path dir or ->
  interrupt_run "$2" - p_hang p_ok
  check yes "$(yn test -n "$HPID")" "$1: the hanging probe started"
  check no "$HUNG" "$1: the driver exits after TERM within the retry bound (hung: its group was killed)"
  check 143 "$DRC" "$1: the driver exits 143 on TERM"
  check no "$(isdir "$D/t")" "$1: the temp root is removed"
  check no "$(has "$OUT" WARNING)" "$1: no warning is printed"
  check no "$(alive "$HPID")" "$1: the hanging probe and its group are stopped"
  kill -KILL "$HPID" 2>/dev/null || true
}
cleanup_cases "interrupt with ps" -
cleanup_cases "interrupt without ps on PATH" "$W/nops"
cleanup_cases "interrupt with a failing ps" "$W/badps"

# Guard removed: a ps-based cleanup under a failing ps leaves the probe's child alive.
cat > "$W/ps-cleanup.sh" <<'M'
pool_cleanup() {
  local k
  trap '' INT TERM
  for k in $(ps -A -o pid=,ppid= 2>/dev/null | awk -v me="$$" '$2 == me { print $1 }'); do kill -KILL "$k" 2>/dev/null || true; done
  rm -rf "$T"
}
M
interrupt_run "$W/badps" "$W/ps-cleanup.sh" p_hang p_ok
check yes "$(alive "$HPID")" "guard removed (process groups, ps-based cleanup under a failing ps): the child survives, which the control above would catch"
kill -KILL "$HPID" 2>/dev/null || true

# A driver that does not exit after TERM: the retry bound ends the wait and the driver's group is killed.
cat > "$W/hang-cleanup.sh" <<'M'
pool_cleanup() { trap '' INT TERM; while :; do sleep 1; done; }
M
NEXT_TRIES=3
interrupt_run - "$W/hang-cleanup.sh" p_hang p_ok
NEXT_TRIES=120
check yes "$HUNG" "planted hung driver: reported as hung when the retry bound is reached"
check hung "$DRC" "planted hung driver: the status is hung"
check no "$(alive "$(cat "$D/dpid")")" "planted hung driver: its process group was killed"
kill -KILL "$HPID" 2>/dev/null || true

# A group that cannot be confirmed gone: warn and keep the temp root.
cat > "$W/unconfirmed.sh" <<'M'
CLEAN_TRIES=2
kill() { case "$*" in "-0 --"*) return 0 ;; esac; builtin kill "$@"; }
M
interrupt_run - "$W/unconfirmed.sh" p_hang p_ok
check 143 "$DRC" "unconfirmed death: the driver still exits 143"
check yes "$(has "$OUT" "could not be confirmed stopped")" "unconfirmed death: a warning is printed"
check yes "$(isdir "$D/t")" "unconfirmed death: the temp root is kept"
kill -KILL "$HPID" 2>/dev/null || true
rm -rf "$D/t"

cat > "$W/rm-anyway.sh" <<'M'
CLEAN_TRIES=2
kill() { case "$*" in "-0 --"*) return 0 ;; esac; builtin kill "$@"; }
pool_cleanup() { trap '' INT TERM; rm -rf "$T"; }
M
interrupt_run - "$W/rm-anyway.sh" p_hang p_ok
check no "$(isdir "$D/t")" "guard removed (keep the dir): the temp root goes although a group is alive, which the unconfirmed-death test above would catch"
kill -KILL "$HPID" 2>/dev/null || true

# LINT_TEST_JOBS. The top of the script is cut at the temp dir line and followed by a line that prints accepted.
awk '{ print } /^T=\$\(mktemp/ { exit }' "$SRC" > "$W/head.sh"
echo 'echo accepted' >> "$W/head.sh"
check yes "$(yn grep -q '^T=[$](mktemp' "$W/head.sh")" "the top of the script was cut at the temp dir line"

# run_head <script> <env assignment or -u NAME>... — run it with TMPDIR in an empty dir; sets OUT, RC, LEFT (entries left in it).
run_head() {
  local script=$1
  shift
  rm -rf "$W/tmpd"
  mkdir -p "$W/tmpd"
  OUT=$(env "$@" TMPDIR="$W/tmpd" "$BASH_BIN" "$script" 2>&1); RC=$?
  LEFT=$(find "$W/tmpd" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
}

for v in 0 -1 abc 007 2.5 " 3" "" 99999999999999999999 257 1000; do
  run_head "$W/head.sh" "LINT_TEST_JOBS=$v"
  check 2 "$RC" "LINT_TEST_JOBS=[$v] exits 2"
  check yes "$(has "$OUT" "LINT_TEST_JOBS must be a whole number from 1 to 256")" "LINT_TEST_JOBS=[$v] names the range"
  check no "$(has "$OUT" accepted)" "LINT_TEST_JOBS=[$v] stops before the script goes on"
  check 0 "$LEFT" "LINT_TEST_JOBS=[$v] leaves no temp dir"
done
for v in 1 256 17; do
  run_head "$W/head.sh" "LINT_TEST_JOBS=$v"
  check 0 "$RC" "control: LINT_TEST_JOBS=$v is accepted"
  check yes "$(has "$OUT" accepted)" "control: LINT_TEST_JOBS=$v goes on"
  check 1 "$LEFT" "control: LINT_TEST_JOBS=$v makes its temp dir after the check"
done
run_head "$W/head.sh" -u LINT_TEST_JOBS
check 0 "$RC" "control: LINT_TEST_JOBS unset is accepted (the CPU count is used)"

# Guard removed: no JOBS check.
awk '/^if ! \[\[ "\$JOBS" =~/ { print "if false; then"; next } { print }' "$W/head.sh" > "$W/head-no-check.sh"
check yes "$(has "$(cat "$W/head-no-check.sh")" 'if false; then')" "the mutant without the JOBS check was built"
run_head "$W/head-no-check.sh" LINT_TEST_JOBS=0
check 0 "$RC" "guard removed (JOBS check): 0 is accepted, which the exit 2 test above would catch"
run_head "$W/head-no-check.sh" LINT_TEST_JOBS=99999999999999999999
check 0 "$RC" "guard removed (JOBS check): a 20-digit value is accepted, which the exit 2 test above would catch"

# Guard removed: the temp dir is made before the check.
{ grep '^T=[$](mktemp' "$W/head.sh"; grep -v '^T=[$](mktemp' "$W/head.sh"; } > "$W/head-mktemp-first.sh"
run_head "$W/head-mktemp-first.sh" LINT_TEST_JOBS=abc
check 1 "$LEFT" "guard removed (check before mktemp): a rejected value leaves a temp dir, which the no-temp-dir test above would catch"

echo "lint-skills-pool.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
