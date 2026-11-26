#!/usr/bin/env bash
# scripts/gate-budget.test.sh — tests for the seeded gate-time budget (gate-budget.sh, its runner hook in ci-gates.sh, the ratchet kind and the session hook).
# Every number is fed into the record, and no test asserts on elapsed time. The few places that wait for a process (the signal probes, the closed-stdin probe) poll in 0.2 second steps with a fixed ceiling. Each guard probe runs on the real script (must pass) and on a copy with that guard removed (must fail).
# Usage: bash scripts/gate-budget.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared/template"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
check() { if [[ "$1" == "$2" ]]; then ok; else bad "$3: expected [$1], got [$2]"; fi; }
has() { if [[ "$2" == *"$1"* ]]; then ok; else bad "$3: [$1] not in [$2]"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/gbt.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

N=0
# newproj: a project folder P with the budget files and the runner.
newproj() {
  N=$((N + 1))
  P="$T/p$N"
  mkdir -p "$P/.claude" "$P/scripts"
  cp "$SH/.claude/gate-budget.sh" "$SH/.claude/gate-budget.conf" "$SH/.claude/gates.txt" "$SH/.claude/ci-gates.sh" "$P/.claude/"
  cp "$SH/.claude/hooks/session-context.sh" "$P/.claude/"
  cp "$REPO_ROOT/skills/scaffold/nestjs/template/.gitignore" "$P/.gitignore"
}
# rec <gate> <seconds> [exit]: one row of fixed seconds.
rec() { (cd "$P" && bash .claude/gate-budget.sh record "$1" 1000 $((1000 + $2)) "${3:-0}"); }
chk() { OUT=$(cd "$P" && bash .claude/gate-budget.sh check 2>&1); RC=$?; }
conf() { printf '%s\n' "$@" > "$P/.claude/gate-budget.conf"; }
rows() { cat "$P/.claude/gate-times.tsv" 2>/dev/null; }
TAB=$(printf '\t')
D='$'

# mutate <file-in-P> <sed-expression>: remove one guard from the copy under test.
mutate() { sed -i.bak "$2" "$P/$1" && rm -f "$P/$1.bak"; }

# --- probes: each takes a prepared project in P and returns 0 when the guard holds ---

probe_clean() { rec deps 100; rec ratchet 50; chk; [ "$RC" = 0 ] && [ -z "$OUT" ]; }
probe_over_total() { conf total_budget_seconds=100 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec deps 60; rec ratchet 60; chk; [ "$RC" = 0 ] && [[ "$OUT" == *"120s in total (budget 100s)"* ]]; }
probe_over_gate() { rec deps 200; chk; [ "$RC" = 0 ] && [[ "$OUT" == *"per-gate budget of 180s: deps 200s"* ]]; }
probe_regression() { for _ in 1 2 3 4; do rec deps 40; done; rec deps 60; chk; [[ "$OUT" == *"deps 60s vs median 40s"* ]]; }
probe_within_percent() { for _ in 1 2 3 4; do rec deps 40; done; rec deps 45; chk; [ -z "$OUT" ]; }
probe_failed_excluded() { for _ in 1 2 3; do rec deps 100; done; for _ in 1 2 3 4; do rec deps 1 1; done; rec deps 105; chk; [ -z "$OUT" ]; }
probe_failed_not_fast() { rec ratchet 400; rec ratchet 1 1; chk; [[ "$OUT" == *"ratchet 400s"* ]]; }
probe_no_data() { chk; [ "$RC" = 0 ] && [[ "$OUT" == *"no timing data"* ]] && [[ "$OUT" != *"within"* ]]; }
probe_deleted_record() { rec deps 10; rm -f "$P/.claude/gate-times.tsv"; chk; [[ "$OUT" == *"no timing data"* ]]; }
probe_bad_seconds() { printf 'deps\tabc\t0\t1\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"record line 1"* ]]; }
probe_negative() { printf 'deps\t-5\t0\t1\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ]; }
probe_huge() { printf 'deps\t99999999\t0\t1\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ]; }
probe_extra_field() { printf 'deps\t10\t0\t1\textra\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ]; }
probe_newline_name() { printf 'de\nps\t10\t0\t1\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ]; }
probe_record_tab_name() { (cd "$P" && bash .claude/gate-budget.sh record "de${TAB}ps" 1 2 0 2>/dev/null); local rc=$?; [ "$rc" = 2 ] && [ ! -e "$P/.claude/gate-times.tsv" ]; }
probe_unlisted() { (cd "$P" && bash .claude/gate-budget.sh record nosuchgate 1 2 0 2>/dev/null); local rc=$?; [ "$rc" = 2 ] && [ ! -e "$P/.claude/gate-times.tsv" ]; }
probe_clock_back() { rec deps -50 2>/dev/null; (cd "$P" && bash .claude/gate-budget.sh record deps 100 50 0); [ "$(awk -F'\t' 'END { print $2 }' "$P/.claude/gate-times.tsv")" = 0 ]; }
probe_keep_last() { conf total_budget_seconds=600 per_gate_budget_seconds=180 regression_percent=25 runs_kept=4; for i in 1 2 3 4 5 6; do rec deps "$i"; done; [ "$(rows | wc -l | tr -d ' ')" = 4 ] && [ "$(awk -F'\t' 'NR == 1 { print $2 }' "$P/.claude/gate-times.tsv")" = 3 ]; }
probe_atomic() { rec deps 1; rec deps 2; [ -z "$(find "$P/.claude" -name 'gate-times.*' ! -name 'gate-times.tsv')" ] && [ "$(rows | wc -l | tr -d ' ')" = 2 ]; }
probe_symlink_record() { printf 'deps\t5\t0\t1\n' > "$P/real.tsv"; ln -s ../real.tsv "$P/.claude/gate-times.tsv"; chk; local a=$RC; (cd "$P" && bash .claude/gate-budget.sh record deps 1 2 0 2>/dev/null); [ "$a" = 2 ] && [ "$(wc -l < "$P/real.tsv" | tr -d ' ')" = 1 ]; }
probe_dir_record() { mkdir "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 2 ]; }
probe_conf_text() { conf total_budget_seconds=abc per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"whole number"* ]]; }
probe_conf_negative() { conf total_budget_seconds=-5 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; chk; [ "$RC" = 2 ]; }
probe_conf_huge() { conf total_budget_seconds=999999999 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; chk; [ "$RC" = 2 ]; }
probe_conf_unknown() { conf total_budget_seconds=600 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20 extra=1; rec_ok; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"unknown key"* ]]; }
probe_conf_missing_key() { conf total_budget_seconds=600 per_gate_budget_seconds=180 regression_percent=25; rec_ok; chk; [ "$RC" = 2 ]; }
probe_conf_missing_file() { rm -f "$P/.claude/gate-budget.conf"; rec_ok; chk; [ "$RC" = 2 ]; }
probe_conf_duplicate() { conf total_budget_seconds=600 total_budget_seconds=900 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; chk; [ "$RC" = 2 ]; }
probe_once_per_session() { rec deps 700; local a b c; a=$(cd "$P" && echo '{"session_id":"s-1"}' | bash .claude/gate-budget.sh hook); b=$(cd "$P" && echo '{"session_id":"s-1"}' | bash .claude/gate-budget.sh hook); c=$(cd "$P" && echo '{"session_id":"s-2"}' | bash .claude/gate-budget.sh hook); [[ "$a" == *"over budget"* ]] && [ -z "$b" ] && [[ "$c" == *"over budget"* ]]; }
probe_hook_quiet() { rec deps 5; local a; a=$(cd "$P" && echo '{"session_id":"s-1"}' | bash .claude/gate-budget.sh hook); [ -z "$a" ] && [ -z "$(cd "$P" && echo '{}' | CLAUDE_PROJECT_DIR="$P" bash .claude/session-context.sh)" ]; }
probe_note_short() { rec deps 700; chk; [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -le 12 ] && [[ "$OUT" == *"not an allowed remedy"* ]] && [[ "$OUT" == *"dependency and build cache"* ]] && [[ "$OUT" == *"Only a human may raise a budget"* ]]; }
probe_session_hook() { rec deps 700; local a; a=$(cd "$P" && echo '{"session_id":"s-9"}' | CLAUDE_PROJECT_DIR="$P" bash .claude/session-context.sh); [[ "$a" == *"over budget"* ]]; }

# rec_ok: one valid row so a broken config is reached (and not "no data").
rec_ok() { printf 'deps\t5\t0\t1\n' > "$P/.claude/gate-times.tsv"; }

# Probe through the real runner: a failing gate keeps its status and output, and its row carries the exit status.
probe_runner_status() {
  rm -f "$P/scripts/test-budget.sh"
  local a_out a_rc b_out b_rc
  a_out=$(cd "$P" && env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); a_rc=$?
  b_out=$(cd "$P" && TC_GATE_TIMED=1 env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); b_rc=$?
  [ "$a_rc" = 1 ] && [ "$a_rc" = "$b_rc" ] && [ "$a_out" = "$b_out" ] && [[ "$a_out" == *"test-budget.sh is missing"* ]] && [ "$(awk -F'\t' '{ print $1 ":" $3 }' "$P/.claude/gate-times.tsv")" = "testbudget:1" ]
}
probe_runner_list() { local out; out=$(cd "$P" && bash .claude/ci-gates.sh list 2>&1); [[ "$out" == *"testbudget"* ]] && [ ! -e "$P/.claude/gate-times.tsv" ]; }

# Ratchet probes need a git project with the real ratchet and the budget files committed.
RG() { git -C "$P" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
ratchet_proj() {
  newproj
  cp "$SH/scripts/gate-ratchet.sh" "$P/scripts/"
  mkdir -p "$P/.claude/hooks"
  cp "$REPO_ROOT/skills/scaffold/shared/template-ts/.claude/hooks/protect-files.sh" "$P/.claude/hooks/"
  if [ -n "${NOCONF:-}" ]; then rm -f "$P/.claude/gate-budget.conf"; fi
  if [ -n "${PMUT:-}" ]; then sed -i.bak "$PMUT" "$P/.claude/hooks/protect-files.sh" && rm -f "$P/.claude/hooks/protect-files.sh.bak"; fi
  if [ -n "${RMUT:-}" ]; then sed -i.bak "$RMUT" "$P/scripts/gate-ratchet.sh" && rm -f "$P/scripts/gate-ratchet.sh.bak"; fi
  git -C "$P" init -q -b main
  RG add -A
  RG commit -q -m base
  RG checkout -q -b work
}
ratchet_run() { OUT=$(cd "$P" && bash scripts/gate-ratchet.sh main 2>&1); RC=$?; }
probe_ratchet_raise() { sed -i.bak 's/^total_budget_seconds=600/total_budget_seconds=900/' "$P/.claude/gate-budget.conf" && rm -f "$P/.claude/gate-budget.conf.bak"; RG commit -qam raise; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"total_budget_seconds was 600, now 900"* ]]; }
probe_ratchet_delete() { RG rm -q .claude/gate-budget.conf; RG commit -qm del; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"gate-budget.conf: file was present at the merge base, now removed"* ]]; }
probe_ratchet_lower() { sed -i.bak 's/^total_budget_seconds=600/total_budget_seconds=300/' "$P/.claude/gate-budget.conf" && rm -f "$P/.claude/gate-budget.conf.bak"; RG commit -qam lower; ratchet_run; [ "$RC" = 0 ]; }
probe_ratchet_gate_removed() { sed -i.bak '/^deps|/d' "$P/.claude/gates.txt" && rm -f "$P/.claude/gates.txt.bak"; RG commit -qam drop; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"gates.txt"* ]]; }
probe_ratchet_script() { printf '# x\n' >> "$P/.claude/gate-budget.sh"; RG commit -qam edit; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"gate-budget.sh"* ]]; }


# --- fix round 1 probes ---
hookrun() { (cd "$P" && printf '%s' "$1" | bash .claude/gate-budget.sh hook 2>&1); }
probe_unlisted_row() { printf 'zzz\t590\t0\t1\ndeps\t20\t0\t2\n' > "$P/.claude/gate-times.tsv"; chk; [ "$RC" = 0 ] && [ -z "$OUT" ]; }
probe_unlisted_dropped() { printf 'zzz\t5\t0\t1\n' > "$P/.claude/gate-times.tsv"; rec deps 3; [ "$(awk -F'\t' '$1 == "zzz"' "$P/.claude/gate-times.tsv" | wc -l | tr -d ' ')" = 0 ] && [ "$(rows | wc -l | tr -d ' ')" = 1 ]; }
probe_gates_missing() { rec deps 5; rm -f "$P/.claude/gates.txt"; chk; local a=$RC; (cd "$P" && bash .claude/gate-budget.sh record deps 1 2 0 2>/dev/null); local b=$?; [ "$a" = 2 ] && [ "$b" = 2 ] && [[ "$OUT" == *"gates.txt"* ]]; }
probe_session_long() { rec deps 700; local id; id=$(printf "a%.0s" $(seq 1 101)); hookrun "{\"session_id\":\"$id\"}" >/dev/null; [ ! -e "$P/.claude/gate-budget.seen" ]; }
probe_session_first() { rec deps 700; hookrun '{"note":"x \"session_id\":\"bad\"","session_id":"real"}' >/dev/null; [ "$(cat "$P/.claude/gate-budget.seen")" = "over:real" ]; }
probe_session_multiline() { rec deps 700; hookrun $'{\n"session_id"\n:"m1",\n"session_id":"m2"}' >/dev/null; [ "$(cat "$P/.claude/gate-budget.seen" 2>/dev/null)" = "over:m1" ]; }
probe_hook_error_throttled() { conf total_budget_seconds=abc per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; local a b c; a=$(hookrun '{"session_id":"e-1"}'); local ra=$?; b=$(hookrun '{"session_id":"e-1"}'); c=$(hookrun '{"session_id":"e-2"}'); [ "$ra" = 0 ] && [[ "$a" == *"whole number"* ]] && [ -z "$b" ] && [[ "$c" == *"whole number"* ]]; }
probe_hook_broken_exit() { conf total_budget_seconds=abc per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; (cd "$P" && echo '{}' | bash .claude/gate-budget.sh hook >/dev/null 2>&1); local a=$?; (cd "$P" && echo '{}' | CLAUDE_PROJECT_DIR="$P" bash .claude/session-context.sh >/dev/null 2>&1); local b=$?; [ "$a" = 0 ] && [ "$b" = 0 ]; }
probe_seen_dir() { rec deps 700; mkdir "$P/.claude/gate-budget.seen"; local a; a=$(hookrun '{"session_id":"d-1"}'); [[ "$a" == *"directory or symlink"* ]] && [[ "$a" == *"over budget"* ]] && [ -z "$(find "$P/.claude/gate-budget.seen" -type f)" ]; }
# A closed stdin must neither hang nor fail: the hook runs in the background and is killed after about 3 seconds if it is still there.
probe_closed_stdin() {
  rec deps 700
  local pid i=0 out="$P/hook.out"
  (cd "$P" && bash .claude/gate-budget.sh hook <&- > "$out" 2>&1) & pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 15 ]; do sleep 0.2; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 1; fi
  wait "$pid"; local rc=$?
  [ "$rc" = 0 ] && grep -q "over budget" "$out"
}
probe_conf_symlink() { printf '%s\n' total_budget_seconds=600 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20 > "$P/real.conf"; rm -f "$P/.claude/gate-budget.conf"; ln -s ../real.conf "$P/.claude/gate-budget.conf"; rec_ok; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"not a regular file"* ]]; }
probe_conf_zero() { conf total_budget_seconds=0600 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; rec_ok; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"whole number"* ]]; }
probe_conf_crlf() { printf 'total_budget_seconds=600\r\nper_gate_budget_seconds=180\r\nregression_percent=25\r\nruns_kept=20\r\n' > "$P/.claude/gate-budget.conf"; rec_ok; chk; [ "$RC" = 2 ] && [[ "$OUT" == *"whole number"* ]]; }
# A missing or failing gate-budget.sh costs the gate nothing but prints exactly one line.
probe_runner_missing_budget() {
  printf 'exit 0\n' > "$P/scripts/test-budget.sh"; rm -f "$P/.claude/gate-budget.sh"
  local a_out a_rc b_out b_rc
  a_out=$(cd "$P" && TC_GATE_TIMED=1 env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); a_rc=$?
  b_out=$(cd "$P" && env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); b_rc=$?
  [ "$a_rc" = 0 ] && [ "$b_rc" = 0 ] && [ -z "$a_out" ] && [[ "$b_out" == *"gate-budget.sh is missing"* ]] && [ "$(printf '%s\n' "$b_out" | wc -l | tr -d ' ')" = 1 ]
}
probe_runner_record_fails() {
  printf 'exit 0\n' > "$P/scripts/test-budget.sh"; printf 'exit 3\n' > "$P/.claude/gate-budget.sh"
  local out rc
  out=$(cd "$P" && env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"recording the timing of testbudget failed (status 3)"* ]] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]
}
# The runner passes any exit status, stdout and stderr through unchanged; the gate body is made to end with the script's own status.
probe_runner_codes() {
  sed -i.bak 's/^    bash scripts\/test-budget.sh || fail .*$/    bash scripts\/test-budget.sh; exit $?/' "$P/.claude/ci-gates.sh" && rm -f "$P/.claude/ci-gates.sh.bak"
  local c a_out a_rc b_out b_rc
  for c in 0 3 255; do
    printf 'echo out; echo err >&2; exit %s\n' "$c" > "$P/scripts/test-budget.sh"
    a_out=$(cd "$P" && env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); a_rc=$?
    b_out=$(cd "$P" && TC_GATE_TIMED=1 env -u GITHUB_ACTIONS -u TF_BUILD bash .claude/ci-gates.sh testbudget 2>&1); b_rc=$?
    if [ "$a_rc" = "$c" ] && [ "$b_rc" = "$c" ] && [ "$a_out" = "$b_out" ] && [ "$(awk -F'\t' 'END { print $3 }' "$P/.claude/gate-times.tsv")" = "$c" ]; then :; else return 1; fi
  done
}
# --- signal probes -------------------------------------------------------------------------------
# note <text>: why a probe failed, shown only on the real script (a removed guard is expected to fail).
note() { if [ -z "${MUTATING:-}" ]; then echo "  note: $*"; fi; }
# The launcher starts the runner in its own session with default signals (a background job of a script would ignore INT), reports the process id and the raw end status ("exit N" or "signal N").
write_launcher() {
  cat > "$T/launch.pl" <<'LEOF'
use POSIX qw(setsid);
my $dir = shift @ARGV;
my $in;
my $w;
if ($ENV{LSTDIN}) { pipe($in, $w) or die "pipe"; }
my $pid = fork();
die "fork" unless defined $pid;
if (!$pid) {
  setsid();
  $SIG{INT} = $SIG{TERM} = $SIG{HUP} = 'DEFAULT';
  if ($in) { open(STDIN, '<&', $in) or die; } else { open(STDIN, '<', '/dev/null') or die; }
  open(STDOUT, '>', "$dir/run.out") or die;
  open(STDERR, '>&', \*STDOUT) or die;
  chdir $dir;
  exec @ARGV or die "exec";
}
open(my $f, '>', "$dir/wpid") or die; print $f "$pid\n"; close $f;
waitpid($pid, 0);
my $st = $?;
my $r = ($st & 127) ? "signal " . ($st & 127) : "exit " . ($st >> 8);
open($f, '>', "$dir/status.tmp") or die; print $f "$r\n"; close $f;
rename "$dir/status.tmp", "$dir/status";
LEOF
}
# await <file>: wait up to 15 seconds for a file to appear.
await() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 75 ]; do sleep 0.2; i=$((i + 1)); done; [ -e "$1" ]; }
# alive <pidfile>: sets ALIVE to 0 or 1; returns 1 (and says why) when the pid file does not hold a number, so liveness is unknown.
alive() {
  local pid
  pid=$(cat "$1" 2>/dev/null)
  case "$pid" in '' | *[!0-9]*) note "cannot tell whether the process in $1 is alive: no pid recorded"; return 1 ;; esac
  if kill -0 "$pid" 2>/dev/null; then ALIVE=1; else ALIVE=0; fi
}
# fixture <A|C>: a gate script that records its pid and a background grandchild, then waits. C handles INT, TERM and HUP by stopping the grandchild and exiting 7.
fixture() {
  {
    cat <<'FEOF'
echo $$ > "$PIDS/gate"
sleep 300 </dev/null >/dev/null 2>&1 &
gc=$!
echo "$gc" > "$PIDS/gc"
FEOF
    if [ "$1" = C ]; then
      cat <<'FEOF'
trap 'kill "$gc" 2>/dev/null; exit 7' INT TERM HUP
FEOF
    fi
    cat <<'FEOF'
echo up > "$PIDS/ready"
wait
FEOF
  } > "$P/scripts/test-budget.sh"
}
# sigrun <timed|plain> <A|C> <INT|TERM|HUP> <wrapper|group>: runs the gate, sends the signal, waits for the end. Sets SR_STATUS, SR_ROWS, SR_GATE, SR_GC (1 when still alive); returns 1 when the run cannot be judged.
sigrun() {
  local mode=$1 sig=$3 tgt=$4 wp
  rm -rf "$P/pids" "$P/status" "$P/wpid" "$P/run.out" "$P/.claude/gate-times.tsv"; mkdir "$P/pids"
  fixture "$2"
  sed -i.bak 's/^    bash scripts\/test-budget.sh || fail .*$/    bash scripts\/test-budget.sh; exit $?/' "$P/.claude/ci-gates.sh" && rm -f "$P/.claude/ci-gates.sh.bak"
  if [ "$mode" = plain ]; then
    env -u GITHUB_ACTIONS -u TF_BUILD -u LSTDIN TC_GATE_TIMED=1 PIDS="$P/pids" perl "$T/launch.pl" "$P" bash .claude/ci-gates.sh testbudget >/dev/null 2>&1 </dev/null &
  else
    env -u GITHUB_ACTIONS -u TF_BUILD -u TC_GATE_TIMED -u LSTDIN PIDS="$P/pids" perl "$T/launch.pl" "$P" bash .claude/ci-gates.sh testbudget >/dev/null 2>&1 </dev/null &
  fi
  if ! await "$P/pids/ready"; then note "the gate never reported ready"; return 1; fi
  wp=$(cat "$P/wpid" 2>/dev/null)
  case "$wp" in '' | *[!0-9]*) note "no process id for the runner"; return 1 ;; esac
  if [ "$tgt" = group ]; then kill -s "$sig" -- "-$wp"; else kill -s "$sig" "$wp"; fi
  if ! await "$P/status"; then note "the runner did not end after $sig to the $tgt"; kill -9 -- "-$wp" 2>/dev/null; return 1; fi
  sleep 0.6
  SR_STATUS=$(cat "$P/status")
  SR_ROWS=0
  if [ -f "$P/.claude/gate-times.tsv" ]; then SR_ROWS=$(wc -l < "$P/.claude/gate-times.tsv" | tr -d ' '); fi
  alive "$P/pids/gate" || return 1; SR_GATE=$ALIVE
  alive "$P/pids/gc" || return 1; SR_GC=$ALIVE
  # Cleanup only, after every observation is taken.
  kill -9 "$(cat "$P/pids/gate")" "$(cat "$P/pids/gc")" 2>/dev/null
  return 0
}
# sigcase <A|C> <sig> <target>: a timed run ends like an untimed one, leaves no gate process behind, and records exactly one row.
sigcase() {
  local fix=$1 sig=$2 tgt=$3 st gate gc rows exit_col want_gc=0
  if [ "$fix" = A ] && [ "$sig" = INT ]; then want_gc=1; fi
  sigrun timed "$fix" "$sig" "$tgt" || return 1
  st=$SR_STATUS; gate=$SR_GATE; gc=$SR_GC; rows=$SR_ROWS
  exit_col=$(awk -F'\t' 'END { print $3 }' "$P/.claude/gate-times.tsv" 2>/dev/null)
  if [ "$rows" != 1 ]; then note "$fix $sig $tgt: $rows rows recorded, wanted 1"; return 1; fi
  if [ "$gate" != 0 ]; then note "$fix $sig $tgt: the gate is still alive"; return 1; fi
  # A background job of a script ignores INT, so fixture A keeps its grandchild after INT in an untimed run too.
  if [ "$gc" != "$want_gc" ]; then note "$fix $sig $tgt: grandchild alive=$gc, wanted $want_gc"; return 1; fi
  if [ "$exit_col" = 0 ]; then note "$fix $sig $tgt: a signalled gate recorded exit 0"; return 1; fi
  # An untimed bash holds INT sent to it alone until the gate ends, so that one case has nothing to compare with.
  if [ "$sig" = INT ] && [ "$tgt" = wrapper ]; then return 0; fi
  sigrun plain "$fix" "$sig" "$tgt" || return 1
  if [ "$SR_STATUS" != "$st" ]; then note "$fix $sig $tgt: untimed ended with [$SR_STATUS], timed with [$st]"; return 1; fi
  if [ "$SR_ROWS" != 0 ]; then note "$fix $sig $tgt: an untimed run recorded a row"; return 1; fi
  return 0
}
probe_sig_matrix() {
  write_launcher
  local f s t
  for f in A C; do for s in INT TERM HUP; do for t in wrapper group; do
    sigcase "$f" "$s" "$t" || return 1
  done; done; done
}
probe_sig_term_wrapper() { write_launcher; sigcase A TERM wrapper; }
probe_sig_int_group() { write_launcher; sigcase C INT group; }
probe_sig_term_handler() { write_launcher; sigcase C TERM group; }
probe_sig_hup_wrapper() { write_launcher; sigcase C HUP wrapper; }
# The hook exits 0 even when a signal ends it.
probe_hook_signal_exit() {
  write_launcher
  rm -rf "$P/status" "$P/wpid"
  # A copy of the script that writes a marker once its traps are set, so the signal never lands early.
  rm -f "$P/ready"
  awk '/^  input=/ { print "  echo up > ready" } { print }' "$P/.claude/gate-budget.sh" > "$P/.claude/gate-budget-ready.sh"
  if ! grep -q 'echo up > ready' "$P/.claude/gate-budget-ready.sh"; then note "could not add the ready marker"; return 1; fi
  LSTDIN=1 perl "$T/launch.pl" "$P" bash .claude/gate-budget-ready.sh hook >/dev/null 2>&1 </dev/null &
  await "$P/wpid" || return 1
  if ! await "$P/ready"; then note "the hook never reported ready"; kill -9 -- "-$(cat "$P/wpid")" 2>/dev/null; return 1; fi
  kill -s TERM -- "-$(cat "$P/wpid")"
  await "$P/status" || { kill -9 -- "-$(cat "$P/wpid")" 2>/dev/null; return 1; }
  [ "$(cat "$P/status")" = "exit 0" ]
}
probe_ignore_patterns() {
  git -C "$P" init -q -b main
  local f
  for f in .claude/gate-times.tsv .claude/gate-budget.seen .claude/gate-times.aB3xYz .claude/gate-budget.aB3xYz; do git -C "$P" check-ignore -q "$f" || return 1; done
  for f in .claude/gate-budget.conf .claude/gate-budget.sh .claude/gates.txt; do if git -C "$P" check-ignore -q "$f"; then return 1; fi; done
}
probe_ignore_all_stacks() {
  newproj
  local st
  for st in nestjs nextjs fastapi vite-react; do
    cp "$REPO_ROOT/skills/scaffold/$st/template/.gitignore" "$P/.gitignore"
    probe_ignore_patterns || { bad "stack $st: .gitignore patterns"; return 0; }
  done
}
probe_ratchet_raise_per() { sed -i.bak 's/^per_gate_budget_seconds=180/per_gate_budget_seconds=900/' "$P/.claude/gate-budget.conf" && rm -f "$P/.claude/gate-budget.conf.bak"; RG commit -qam raise; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"per_gate_budget_seconds was 180, now 900"* ]]; }
probe_ratchet_raise_pct() { sed -i.bak 's/^regression_percent=25/regression_percent=90/' "$P/.claude/gate-budget.conf" && rm -f "$P/.claude/gate-budget.conf.bak"; RG commit -qam raise; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"regression_percent was 25, now 90"* ]]; }
probe_ratchet_new_high() { conf total_budget_seconds=86400 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; RG add -A; RG commit -qm new; ratchet_run; [ "$RC" = 1 ] && [[ "$OUT" == *"total_budget_seconds"* ]] && [[ "$OUT" == *"was 600 (seeded default)"* ]]; }
probe_ratchet_new_default() { conf total_budget_seconds=600 per_gate_budget_seconds=180 regression_percent=25 runs_kept=20; RG add -A; RG commit -qm new; ratchet_run; [ "$RC" = 0 ]; }
probe_protect_conf() {
  command -v node >/dev/null 2>&1 || return 0
  local a b
  a=$(cd "$P" && printf '{"tool_input":{"file_path":"%s/.claude/gate-budget.conf"}}' "$P" | CLAUDE_PROJECT_DIR="$P" bash .claude/hooks/protect-files.sh 2>&1)
  b=$(cd "$P" && printf '{"tool_input":{"file_path":"%s/.claude/gate-times.tsv"}}' "$P" | CLAUDE_PROJECT_DIR="$P" bash .claude/hooks/protect-files.sh 2>&1)
  local k
  k=$(cd "$P" && bash scripts/gate-ratchet.sh --list-guarded HEAD)
  [[ "$a" == *'"permissionDecision":"ask"'* ]] && [[ "$a" == *"gate-budget.conf"* ]] && [ -z "$b" ] && [[ "$k" == *$'gatetime\t.claude/gate-budget.conf\t0'* ]]
}
ratchet_proj_nc() { NOCONF=1; ratchet_proj; NOCONF=; }
# An unreadable record is an error, never an empty history that the next record overwrites.
probe_unreadable_record() {
  if [ "$(id -u)" = 0 ]; then return 0; fi
  rec deps 5; rec deps 6
  local before out rc
  before=$(cat "$P/.claude/gate-times.tsv")
  chmod 000 "$P/.claude/gate-times.tsv"
  out=$(cd "$P" && bash .claude/gate-budget.sh record deps 1 9 0 2>&1); rc=$?
  chmod 600 "$P/.claude/gate-times.tsv"
  local cout crc
  chmod 000 "$P/.claude/gate-times.tsv"
  cout=$(cd "$P" && bash .claude/gate-budget.sh check 2>&1); crc=$?
  chmod 600 "$P/.claude/gate-times.tsv"
  [ "$rc" = 2 ] && [[ "$out" == *"cannot read"* ]] && [ "$(cat "$P/.claude/gate-times.tsv")" = "$before" ] && [ "$crc" = 2 ] && [[ "$cout" == *"cannot read"* ]]
}
# One name rule: record takes 40 characters and refuses 41 with a clear error, and check never meets a name record wrote.
probe_name_len() {
  local n40 n41 o41 r41 r40
  n40=$(printf 'a%.0s' $(seq 1 40)); n41="${n40}a"
  printf '%s|x|y\n%s|x|y\n' "$n40" "$n41" >> "$P/.claude/gates.txt"
  o41=$(cd "$P" && bash .claude/gate-budget.sh record "$n41" 1 2 0 2>&1); r41=$?
  (cd "$P" && bash .claude/gate-budget.sh record "$n40" 1 2 0 >/dev/null 2>&1); r40=$?
  chk
  [ "$r41" = 2 ] && [[ "$o41" == *"at most 40 characters"* ]] && [ "$r40" = 0 ] && [ "$RC" = 0 ] && [ "$(rows | wc -l | tr -d ' ')" = 1 ]
}
probe_hook_script_missing() {
  rm -f "$P/.claude/gate-budget.sh"
  local out rc
  out=$(cd "$P" && echo '{}' | CLAUDE_PROJECT_DIR="$P" bash .claude/session-context.sh 2>&1); rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"gate-budget.sh is missing"* ]] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]
}
probe_hook_script_crash() {
  printf 'echo boom >&2\nexit 9\n' > "$P/.claude/gate-budget.sh"
  local out rc
  out=$(cd "$P" && echo '{}' | CLAUDE_PROJECT_DIR="$P" bash .claude/session-context.sh 2>&1); rc=$?
  [ "$rc" = 0 ] && [[ "$out" == *"exited with status 9"* ]] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]
}
probe_protect_script() {
  command -v node >/dev/null 2>&1 || return 0
  local a k
  # The hook alone, in a folder without the ratchet, so its own list is what answers.
  mkdir -p "$P/pf/.claude/hooks"; cp "$P/.claude/hooks/protect-files.sh" "$P/pf/.claude/hooks/"
  a=$(cd "$P/pf" && printf '{"tool_input":{"file_path":"%s/pf/.claude/gate-budget.sh"}}' "$P" | CLAUDE_PROJECT_DIR="$P/pf" bash .claude/hooks/protect-files.sh 2>&1)
  k=$(cd "$P" && bash scripts/gate-ratchet.sh --list-guarded HEAD)
  [[ "$a" == *'"permissionDecision":"ask"'* ]] && [[ "$a" == *"gate-budget.sh"* ]] && [[ "$k" == *$'guard\t.claude/gate-budget.sh\t1'* ]]
}

# rguard <probe> <sed> <name>: like guard, but the ratchet is mutated before the base commit so the edit is not itself flagged.
rguard() {
  local setup=${4:-ratchet_proj}
  RMUT=""
  run_probe "$setup" "$1" || bad "$3: probe fails on the real ratchet"
  RMUT=$2
  "$setup"
  MUTATING=1
  if "$1"; then bad "$3: probe still passes with the guard removed"; else ok; fi
  MUTATING=
  RMUT=""
}
# pguard <probe> <sed> <name>: like rguard, but the protect-files hook is the mutated file.
pguard() {
  run_probe ratchet_proj "$1" || bad "$3: probe fails on the real hook"
  PMUT=$2
  ratchet_proj
  MUTATING=1
  if "$1"; then bad "$3: probe still passes with the guard removed"; else ok; fi
  MUTATING=
  PMUT=""
}
# run_probe <setup> <probe>: setup is newproj or ratchet_proj.
run_probe() { "$1"; "$2"; }
# guard <setup> <probe> <file> <sed> <name>: the probe passes on the real file and fails with the guard removed.
guard() {
  run_probe "$1" "$2" || bad "$5: probe fails on the real script"
  "$1"
  local before
  before=$(cat "$P/$3")
  mutate "$3" "$4"
  if [ "$(cat "$P/$3")" = "$before" ]; then bad "$5: the mutation changed nothing"; return; fi
  MUTATING=1
  if "$2"; then bad "$5: probe still passes with the guard removed"; else ok; fi
  MUTATING=
}
plain() { if run_probe "$1" "$2"; then ok; else bad "$2"; fi; }

for p in probe_clean probe_over_total probe_over_gate probe_regression probe_within_percent probe_failed_excluded probe_failed_not_fast probe_no_data probe_deleted_record \
  probe_bad_seconds probe_negative probe_huge probe_extra_field probe_newline_name probe_record_tab_name probe_unlisted probe_clock_back probe_keep_last probe_atomic \
  probe_symlink_record probe_dir_record probe_conf_text probe_conf_negative probe_conf_huge probe_conf_unknown probe_conf_missing_key probe_conf_missing_file probe_conf_duplicate \
  probe_once_per_session probe_hook_quiet probe_note_short probe_session_hook probe_runner_status probe_runner_list \
  probe_unlisted_row probe_unlisted_dropped probe_gates_missing probe_session_first probe_session_long probe_session_multiline probe_hook_error_throttled probe_hook_broken_exit probe_seen_dir \
  probe_closed_stdin probe_conf_symlink probe_conf_zero probe_conf_crlf probe_runner_missing_budget probe_runner_record_fails probe_runner_codes probe_sig_matrix probe_unreadable_record probe_name_len probe_hook_script_missing probe_hook_script_crash probe_hook_signal_exit probe_ignore_patterns; do
  plain newproj "$p"
done
for p in probe_ratchet_raise probe_ratchet_delete probe_ratchet_lower probe_ratchet_gate_removed probe_ratchet_script probe_ratchet_raise_per probe_ratchet_raise_pct probe_protect_conf probe_protect_script; do
  plain ratchet_proj "$p"
done
for p in probe_ratchet_new_high probe_ratchet_new_default; do
  plain ratchet_proj_nc "$p"
done
probe_ignore_all_stacks

# Guard removal: one real guard each, probe must fail without it.
guard newproj probe_failed_excluded .claude/gate-budget.sh 's/if (ex\[name, j\] == 0) a\[++c\]/a[++c]/' "failed run left out of the median"
guard newproj probe_failed_not_fast .claude/gate-budget.sh 's/cur\[name\] = li ? sec\[name, li\] : sec\[name, last\]/cur[name] = sec[name, last]/' "latest passing run counts, not a fast failure"
guard newproj probe_clock_back .claude/gate-budget.sh '/\[ "[$]secs" -ge 0 \] || secs=0/d' "clock going backwards clamps to 0"
guard newproj probe_extra_field .claude/gate-budget.sh '/NF != 4/d' "record rows need exactly four fields"
guard newproj probe_huge .claude/gate-budget.sh 's/!num([$]2, 604800)/0/' "huge seconds rejected"
guard newproj probe_conf_unknown .claude/gate-budget.sh 's/^      \*) fail "[$]conf line [$]n: unknown key.*$/      *) ;;/' "unknown config key rejected"
guard newproj probe_symlink_record .claude/gate-budget.sh '/is a symlink or a directory; remove it/d' "symlinked record rejected"
guard newproj probe_once_per_session .claude/gate-budget.sh '/\[ "[$](cat "[$]seen" 2>\/dev\/null)" = "[$]kind:[$]sid" \]/d' "note once per session"
guard newproj probe_unlisted .claude/gate-budget.sh '/is not a listed gate/d' "only listed gates recorded"
guard newproj probe_runner_status .claude/ci-gates.sh 's/^  exit "[$]rc"$/  exit 0/' "recording keeps the gate exit status"
rguard probe_ratchet_raise 's/emit("max", "gatetime:" k, v)/emit("skip", k, v)/' "raised budget caught"
rguard probe_ratchet_raise_per 's/k == "per_gate_budget_seconds" || //' "raised per-gate budget caught"
rguard probe_ratchet_raise_pct 's/ || k == "regression_percent") emit/) emit/' "raised regression percent caught"
rguard probe_ratchet_delete 's/if \[ "[$]have_head" -eq 0 \]; then/if false; then/' "deleted budget config caught by the removed-file path"
rguard probe_ratchet_new_high "s/gatetime) seeded=1; printf .* > \"[\$]wd/gatetime) printf \"\" > \"${D}wd/" "new config held to the seeded defaults" ratchet_proj_nc
rguard probe_protect_conf '/gate-budget.conf | \*\/.claude\/gate-budget.conf) KIND=gatetime/d' "protect-files asks about the budget config"
guard newproj probe_unlisted_row .claude/gate-budget.sh '/index(listed, " " [$]1 " ") == 0 { next }/{N;/in n/s/^.*\n//;}' "check counts listed gates only"
guard newproj probe_unlisted_dropped .claude/gate-budget.sh '/index(listed, " " [$]1 " ") == 0 { next }/{N;/line\[n\]/s/^.*\n//;}' "record drops unlisted rows"
guard newproj probe_gates_missing .claude/gate-budget.sh '/is missing or unreadable; restore it from version control/d' "missing gate list fails closed"
guard newproj probe_session_long .claude/gate-budget.sh 's/ \&\& length(v) <= 100//' "session id length capped"
guard newproj probe_hook_broken_exit .claude/gate-budget.sh 's/^  exit 0$/  exit 2/' "hook always exits 0"
guard newproj probe_session_multiline .claude/gate-budget.sh "s/tr '[^']*' '[^']*' | //" "session id reads one line"
guard newproj probe_hook_error_throttled .claude/gate-budget.sh "s/hook_print err \"[\$]sid\" \"[\$]out\" ;;/echo \"${D}out\" ;;/" "broken-config error shown once per session"
guard newproj probe_seen_dir .claude/gate-budget.sh 's/if \[ -d "[$]seen" \] || \[ -L "[$]seen" \]; then/if false; then/' "marker directory reported"
guard newproj probe_closed_stdin .claude/gate-budget.sh '/-p \/dev\/stdin/d' "closed stdin does not hang the hook"
guard newproj probe_conf_symlink .claude/gate-budget.sh 's/if \[ -L "[$]conf" \] || /if /' "symlinked config rejected"
guard newproj probe_conf_zero .claude/gate-budget.sh 's/ | 0?\*)/)/' "leading zero rejected"
guard newproj probe_conf_crlf .claude/gate-budget.sh 's/ | \*\[!0-9\]\*//' "non-digit config value rejected"
guard newproj probe_runner_missing_budget .claude/ci-gates.sh '/the timing of [$]gate was not recorded/d' "a missing budget script is reported once"
guard newproj probe_runner_record_fails .claude/ci-gates.sh '/recording the timing of [$]gate failed/d' "a failing record is reported once"
guard newproj probe_sig_int_group .claude/ci-gates.sh 's/^  set -m$/  :/' "the gate gets its own group with default INT"
guard newproj probe_sig_term_wrapper .claude/ci-gates.sh "/^  trap 'forward TERM' TERM\$/d" "TERM to the runner reaches the gate"
guard newproj probe_sig_term_wrapper .claude/ci-gates.sh 's/kill -s "[$]1" -- "-[$]child" 2>\/dev\/null || //' "the signal goes to the whole group"
guard newproj probe_sig_term_handler .claude/ci-gates.sh 's/^    kill -s "[$]got" "[$][$]"$/    :/' "the runner ends by the signal like an untimed run"
guard newproj probe_sig_int_group .claude/ci-gates.sh "/^  trap 'forward INT' INT\$/d" "INT to the runner and its group is forwarded"
guard newproj probe_sig_hup_wrapper .claude/ci-gates.sh "/^  trap 'forward HUP' HUP\$/d" "HUP to the runner reaches the gate"
guard newproj probe_hook_signal_exit .claude/gate-budget.sh 's/^  SIGEXIT=0$/  SIGEXIT=2/' "a signal ends the hook with status 0"
guard newproj probe_name_len .claude/gate-budget.sh 's/^  \[ "[$]{#1}" -le "[$]NAME_MAX" \]$/  true/' "record refuses names longer than check accepts"
guard newproj probe_hook_script_missing .claude/session-context.sh '/gate-budget.sh is missing; the gate-time note is off/d' "the session hook says when the script is missing"
guard newproj probe_hook_script_crash .claude/session-context.sh '/the gate-time hook exited with status/d' "the session hook says when the script crashes"
if [ "$(id -u)" != 0 ]; then
  guard newproj probe_unreadable_record .claude/gate-budget.sh 's/ || fail "cannot read [$]rec; the history is kept, fix its permissions"//' "an unreadable record is not read as empty"
  guard newproj probe_unreadable_record .claude/gate-budget.sh '/^  \[ -r "[$]rec" \] || fail "cannot read/d' "check names an unreadable record"
fi
pguard probe_protect_script 's/\.claude\/gate-budget\.sh|\*\/\.claude\/gate-budget\.sh|//' "protect-files asks about the budget script"
guard newproj probe_ignore_patterns .gitignore '/gate-budget\.??????/d' "temp files git-ignored"

echo "gate-budget.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
