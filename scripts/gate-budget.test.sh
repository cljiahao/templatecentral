#!/usr/bin/env bash
# scripts/gate-budget.test.sh — tests for the seeded gate-time budget (gate-budget.sh, its runner hook in ci-gates.sh, the ratchet kind and the session hook).
# Every number is fed into the record; no test sleeps or reads a clock. Each guard probe runs on the real script (must pass) and on a copy with that guard removed (must fail).
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
}
# rec <gate> <seconds> [exit]: one row of fixed seconds.
rec() { (cd "$P" && bash .claude/gate-budget.sh record "$1" 1000 $((1000 + $2)) "${3:-0}"); }
chk() { OUT=$(cd "$P" && bash .claude/gate-budget.sh check 2>&1); RC=$?; }
conf() { printf '%s\n' "$@" > "$P/.claude/gate-budget.conf"; }
rows() { cat "$P/.claude/gate-times.tsv" 2>/dev/null; }
TAB=$(printf '\t')

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

# rguard <probe> <sed> <name>: like guard, but the ratchet is mutated before the base commit so the edit is not itself flagged.
rguard() {
  RMUT=""
  run_probe ratchet_proj "$1" || bad "$3: probe fails on the real ratchet"
  RMUT=$2
  ratchet_proj
  if "$1"; then bad "$3: probe still passes with the guard removed"; else ok; fi
  RMUT=""
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
  if "$2"; then bad "$5: probe still passes with the guard removed"; else ok; fi
}
plain() { if run_probe "$1" "$2"; then ok; else bad "$2"; fi; }

for p in probe_clean probe_over_total probe_over_gate probe_regression probe_within_percent probe_failed_excluded probe_failed_not_fast probe_no_data probe_deleted_record \
  probe_bad_seconds probe_negative probe_huge probe_extra_field probe_newline_name probe_record_tab_name probe_unlisted probe_clock_back probe_keep_last probe_atomic \
  probe_symlink_record probe_dir_record probe_conf_text probe_conf_negative probe_conf_huge probe_conf_unknown probe_conf_missing_key probe_conf_missing_file probe_conf_duplicate \
  probe_once_per_session probe_hook_quiet probe_note_short probe_session_hook probe_runner_status probe_runner_list; do
  plain newproj "$p"
done
for p in probe_ratchet_raise probe_ratchet_delete probe_ratchet_lower probe_ratchet_gate_removed probe_ratchet_script; do
  plain ratchet_proj "$p"
done

# Guard removal: one real guard each, probe must fail without it.
guard newproj probe_failed_excluded .claude/gate-budget.sh 's/if (ex\[name, j\] == 0) a\[++c\]/a[++c]/' "failed run left out of the median"
guard newproj probe_failed_not_fast .claude/gate-budget.sh 's/cur\[name\] = li ? sec\[name, li\] : sec\[name, last\]/cur[name] = sec[name, last]/' "latest passing run counts, not a fast failure"
guard newproj probe_clock_back .claude/gate-budget.sh '/\[ "[$]secs" -ge 0 \] || secs=0/d' "clock going backwards clamps to 0"
guard newproj probe_extra_field .claude/gate-budget.sh '/NF != 4/d' "record rows need exactly four fields"
guard newproj probe_huge .claude/gate-budget.sh 's/!num([$]2, 604800)/0/' "huge seconds rejected"
guard newproj probe_conf_unknown .claude/gate-budget.sh 's/^      \*) fail "[$]conf line [$]n: unknown key.*$/      *) ;;/' "unknown config key rejected"
guard newproj probe_symlink_record .claude/gate-budget.sh '/is a symlink or a directory; remove it/d' "symlinked record rejected"
guard newproj probe_once_per_session .claude/gate-budget.sh '/\[ "[$](cat "[$]seen" 2>\/dev\/null)" = "[$]sid" \]/d' "note once per session"
guard newproj probe_unlisted .claude/gate-budget.sh '/is not a listed gate/d' "only listed gates recorded"
guard newproj probe_runner_status .claude/ci-gates.sh 's/^  exit "[$]rc"$/  exit 0/' "recording keeps the gate exit status"
rguard probe_ratchet_raise 's/emit("max", "gatetime:" k, v)/emit("skip", k, v)/' "raised budget caught"

echo "gate-budget.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
