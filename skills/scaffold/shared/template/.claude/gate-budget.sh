#!/usr/bin/env bash
# Gate-time budget: gate-budget.sh <check|hook|record>. Local only: no account, key or service.
#   record <gate> <start-epoch> <end-epoch> <exit>  ci-gates.sh calls this after each gate; appends one row to .claude/gate-times.tsv.
#   check   prints nothing when within budget; prints a short note when over; prints "no data" when there is no record. Exit 0 unless the config, the gate list (.claude/gates.txt) or the record is broken (exit 2).
#   hook    SessionStart: reads the hook JSON on stdin, runs check, prints the over-budget note once per session id, prints nothing without data. A broken config, gate list or record prints its error line on stdout, once per session id too, so it stays visible. Always exit 0.
# Budgets live in .claude/gate-budget.conf (key=value, integers, allow-listed keys, no defaults in code). The gate ratchet fails a change that raises them or deletes the file; it is not an enforced kind, so a human-applied allow-gate-change label can waive a raise or a deletion by design.
# A gate's time is its latest passing run, else its latest run, so a gate that fails fast never looks fast. A failed run is left out of the regression median. A regression needs three earlier passing runs and at least 5 seconds of growth. The total adds each gate's time. Only gates listed in .claude/gates.txt count: a gate removed from the list drops out of the total and of the next write.
# In CI the record starts empty on every fresh checkout and holds only the gates that job ran, one row each: there the check covers the per-gate limit and the total of those gates only, and the regression check cannot fire. Local runs keep the history, so the regression check works there.
# Will not catch: hand edits of the git-ignored record (CI recomputes from its own run); slowness outside ci-gates.sh gates (tests, installs, deploys, queue and runner start); a gate run with TC_GATE_TIMED=1 exported (that turns recording off); a CI total that covers only one job's gates and has no history to compare; a machine slower than CI; a waived or raised budget approved by a human; two runs writing at once can lose a row (the write is atomic, never torn).
set -uo pipefail
export LC_ALL=C
# A closed stdin would hand the first pipe to `cat` as its own input and hang: give it /dev/null instead.
[ -p /dev/stdin ] || [ -f /dev/stdin ] || [ -c /dev/stdin ] || [ -S /dev/stdin ] || exec 0</dev/null
here=$(cd "$(dirname "$0")" && pwd) || exit 2
conf="$here/gate-budget.conf"
rec="$here/gate-times.tsv"
seen="$here/gate-budget.seen"
cmd=${1:-}
TMP=
GATES=
trap 'rm -f "${TMP:-}"' EXIT
trap 'rm -f "${TMP:-}"; exit 2' HUP INT TERM

fail() {
  printf 'gate-budget: %s\n' "$1" >&2
  exit 2
}

# True for 1 to 12 digits, no sign, no leading zero.
is_int() {
  case "$1" in '' | *[!0-9]* | 0?*) return 1 ;; esac
  [ "${#1}" -le 12 ]
}

# Sets TOTAL, PER, PCT and KEEP from the config; any missing, unknown, repeated or out-of-range line is an error.
load_conf() {
  local line key val n=0 got=" "
  if [ -L "$conf" ] || [ ! -f "$conf" ]; then fail "$conf is missing or not a regular file; restore it from version control"; fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in '' | '#'*) continue ;; esac
    case "$line" in *=*) ;; *) fail "$conf line $n is not key=value" ;; esac
    key=${line%%=*}
    val=${line#*=}
    is_int "$val" || fail "$conf line $n: $key needs a whole number, no sign, spaces or leading zero"
    [ "$val" -ge 1 ] || fail "$conf line $n: $key must be at least 1"
    case "$got" in *" $key "*) fail "$conf line $n: $key is set twice" ;; esac
    case "$key" in
      total_budget_seconds) [ "$val" -le 86400 ] || fail "$conf line $n: $key is above 86400"; TOTAL=$val ;;
      per_gate_budget_seconds) [ "$val" -le 86400 ] || fail "$conf line $n: $key is above 86400"; PER=$val ;;
      regression_percent) [ "$val" -le 1000 ] || fail "$conf line $n: $key is above 1000"; PCT=$val ;;
      runs_kept) if [ "$val" -lt 4 ] || [ "$val" -gt 200 ]; then fail "$conf line $n: $key must be 4 to 200"; fi; KEEP=$val ;;
      *) fail "$conf line $n: unknown key '$key'" ;;
    esac
    got="$got$key "
  done < "$conf"
  for key in total_budget_seconds per_gate_budget_seconds regression_percent runs_kept; do
    case "$got" in *" $key "*) ;; *) fail "$conf does not set $key" ;; esac
  done
}

# Sets GATES to the space-padded names listed in gates.txt; a missing or unreadable gate list is an error.
load_gates() {
  local line list=" " gl="$here/gates.txt"
  if [ ! -f "$gl" ] || [ ! -r "$gl" ]; then fail "$gl is missing or unreadable; restore it from version control"; fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    list="$list${line%%|*} "
  done < "$gl"
  GATES=$list
}

# Exit 3 with the first bad line when a record row is not: gate name, seconds, exit status, epoch, separated by single tabs.
validate_record() {
  awk -F'\t' '
    function bad(why) { printf "gate-budget: record line %d: %s; delete .claude/gate-times.tsv to start over\n", NR, why > "/dev/stderr"; exit 3 }
    function num(v, max) { return v ~ /^(0|[1-9][0-9]*)$/ && length(v) <= 12 && v + 0 <= max }
    NF != 4 { bad("expected 4 tab-separated fields") }
    $1 !~ /^[a-z][a-z0-9-]*$/ || length($1) > 40 { bad("bad gate name") }
    !num($2, 604800) { bad("seconds must be a whole number up to 604800") }
    !num($3, 255) { bad("exit status must be a whole number up to 255") }
    !num($4, 999999999999) { bad("epoch must be a whole number") }
  ' "$rec"
}

# Prints the over-budget lines (nothing when within budget) for the record.
report() {
  awk -F'\t' -v total_b="$TOTAL" -v per_b="$PER" -v pct="$PCT" -v listed="$GATES" '
    index(listed, " " $1 " ") == 0 { next }
    { if (!($1 in n)) order[++g] = $1; n[$1]++; sec[$1, n[$1]] = $2 + 0; ex[$1, n[$1]] = $3 + 0 }
    END {
      for (i = 1; i <= g; i++) {
        name = order[i]; last = n[name]; li = 0
        for (j = last; j >= 1; j--) if (ex[name, j] == 0) { li = j; break }
        cur[name] = li ? sec[name, li] : sec[name, last]
        total += cur[name]
        if (li > 1) {
          c = 0
          for (j = 1; j < li; j++) if (ex[name, j] == 0) a[++c] = sec[name, j] + 0
          if (c >= 3) {
            for (x = 2; x <= c; x++) { v = a[x]; y = x - 1; while (y >= 1 && a[y] > v) { a[y + 1] = a[y]; y-- } a[y + 1] = v }
            med[name] = a[int((c + 1) / 2)]
            if (cur[name] * 100 > med[name] * (100 + pct) && cur[name] - med[name] >= 5) reg[name] = 1
          }
          split("", a)
        }
      }
      for (i = 1; i <= g; i++) rank[i] = order[i]
      for (i = 1; i < g; i++) { m = i; for (j = i + 1; j <= g; j++) if (cur[rank[j]] > cur[rank[m]] || (cur[rank[j]] == cur[rank[m]] && rank[j] < rank[m])) m = j; t = rank[i]; rank[i] = rank[m]; rank[m] = t }
      over = (total > total_b)
      for (i = 1; i <= g; i++) { if (cur[rank[i]] > per_b) { over = 1; ps = ps (ps == "" ? "" : ", ") rank[i] " " cur[rank[i]] "s" } if (reg[rank[i]]) { over = 1; rs = rs (rs == "" ? "" : ", ") rank[i] " " cur[rank[i]] "s vs median " med[rank[i]] "s" } }
      if (!over) exit
      printf "gate-time: over budget. Gates take %ds in total (budget %ds).\n", total, total_b
      s = ""; for (i = 1; i <= g && i <= 3; i++) s = s (s == "" ? "" : ", ") rank[i] " " cur[rank[i]] "s"
      printf "Slowest: %s.\n", s
      if (ps != "") printf "Over the per-gate budget of %ds: %s.\n", per_b, ps
      if (rs != "") printf "Slower than the median of earlier runs by more than %d%%: %s.\n", pct, rs
    }
  ' "$rec"
}

remedies() {
  cat <<'NOTE'
Revise the project to make its gates faster. Allowed remedies:
- dependency and build cache
- run independent gates in parallel
- run only affected tests locally while CI runs all
- smaller Docker build context and better layer order
- faster test setup
Removing, skipping or weakening a check is not an allowed remedy. Only a human may raise a budget in .claude/gate-budget.conf.
NOTE
}

# Prints the note for the record, or the "no data" line when there is none.
run_check() {
  local out
  load_conf
  load_gates
  if [ -L "$rec" ] || [ -d "$rec" ]; then fail "$rec is a symlink or a directory; remove it"; fi
  if [ ! -e "$rec" ] || [ ! -s "$rec" ]; then
    echo "gate-time: no timing data yet (run gates with .claude/ci-gates.sh); the budget was not checked."
    return 0
  fi
  [ -f "$rec" ] || fail "$rec is not a regular file; remove it"
  validate_record || exit 2
  out=$(report) || fail "cannot compute the gate times"
  if [ -z "$out" ]; then return 0; fi
  printf '%s\n' "$out"
  remedies
}

do_record() {
  local gate=${2:-} t0=${3:-} t1=${4:-} code=${5:-} secs
  case "$gate" in '' | [!a-z]* | *[!a-z0-9-]*) fail "bad gate name" ;; esac
  load_gates
  case "$GATES" in *" $gate "*) ;; *) fail "'$gate' is not a listed gate" ;; esac
  is_int "$t0" || fail "start is not a whole number"
  is_int "$t1" || fail "end is not a whole number"
  is_int "$code" || fail "exit status is not a whole number"
  [ "$code" -le 255 ] || fail "exit status is above 255"
  secs=$((t1 - t0))
  [ "$secs" -ge 0 ] || secs=0
  [ "$secs" -le 604800 ] || secs=604800
  load_conf
  if [ -L "$rec" ] || [ -d "$rec" ]; then fail "$rec is a symlink or a directory"; fi
  TMP=$(mktemp "$here/gate-times.XXXXXX") || fail "cannot create a temporary file"
  {
    if [ -f "$rec" ]; then cat "$rec"; fi
    printf '%s\t%s\t%s\t%s\n' "$gate" "$secs" "$code" "$t1"
  } | awk -F'\t' -v g="$gate" -v keep="$KEEP" -v listed="$GATES" '
    index(listed, " " $1 " ") == 0 { next }
    { n++; line[n] = $0; if ($1 == g) { c++; idx[c] = n } }
    END { drop = c - keep; for (i = 1; i <= drop; i++) skip[idx[i]] = 1; for (i = 1; i <= n; i++) if (!(i in skip)) print line[i] }
  ' > "$TMP" || fail "cannot write the record"
  mv -f "$TMP" "$rec" || fail "cannot replace the record"
  TMP=
}

# Session id from the hook JSON: the first "session_id" key at a JSON key position (after { or ,), on one line, whitelisted to letters, digits, dash and underscore (1 to 100); empty when absent or odd.
session_id() {
  local v
  v=$(printf '%s' "$1" | tr '\n\r' '  ' | awk '{
    if (match($0, /[{,][ \t]*"session_id"[ \t]*:[ \t]*"[^"]*"/)) {
      v = substr($0, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*"/, "", v); sub(/"$/, "", v)
      if (v ~ /^[A-Za-z0-9_-]+$/ && length(v) <= 100) print v
    }
  }')
  printf '%s' "$v"
}

# Prints $2 once per session id and kind $1 (over or err); a marker that is a directory or symlink is itself reported, every time.
hook_print() {
  local kind=$1 sid=$2 out=$3
  if [ -d "$seen" ] || [ -L "$seen" ]; then
    printf 'gate-budget: %s is a directory or symlink; remove it so the note shows once per session\n' "$seen"
  elif [ -n "$sid" ]; then
    if [ -f "$seen" ] && [ "$(cat "$seen" 2>/dev/null)" = "$kind:$sid" ]; then exit 0; fi
    if TMP=$(mktemp "$here/gate-budget.XXXXXX" 2>/dev/null); then
      printf '%s\n' "$kind:$sid" > "$TMP"
      mv -f "$TMP" "$seen" || rm -f "$TMP"
      TMP=
    fi
  fi
  printf '%s\n' "$out"
}

do_hook() {
  local input sid out
  input=$(cat)
  sid=$(session_id "$input")
  out=$(run_check 2>&1)
  case "$out" in
    "" | "gate-time: no timing data"*) ;;
    "gate-time: over budget"*) hook_print over "$sid" "$out" ;;
    *) hook_print err "$sid" "$out" ;;
  esac
  exit 0
}

case "$cmd" in
  record) do_record "$@" ;;
  check) run_check ;;
  hook) do_hook ;;
  *) echo "usage: gate-budget.sh <check|hook|record>" >&2; exit 2 ;;
esac
