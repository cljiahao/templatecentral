#!/usr/bin/env bash
# scripts/run-gates.sh — run the repo gates of validate-skills.yml that a change can affect.
# Usage: bash scripts/run-gates.sh --changed [<base-ref>]   gates for the paths changed since the merge base
#        bash scripts/run-gates.sh --all                    every gate
#        bash scripts/run-gates.sh --list [--changed [<base-ref>]]   print the gates, run nothing
#        bash scripts/run-gates.sh --check                  check the map against the workflow, run nothing
# Default base ref: origin/main. Exit: 0 all passed (or no changes), 1 a gate failed, 2 cannot run.
#
# LOCAL CONVENIENCE ONLY. CI runs the full set on every pull request and is the authority. A pass here
# is not a pass in CI, and this script never replaces or weakens a CI check.
#
# The gates are the `bash scripts/…` and `node adapters/…` commands in .github/workflows/validate-skills.yml
# (a base ref in `"origin/$BASE_REF"` is replaced by the base ref given here). The path-to-gate map is data,
# scripts/run-gates.map: tab-separated rows of <path glob> and <gate command>. The first row whose glob
# matches a path decides for that path (all rows with that exact glob apply); a gate command may start
# with VAR=value words; `@all` as the gate selects every gate; `@skip<TAB>command<TAB>reason` names a
# workflow command that is not a standalone gate. Fail safe toward more: a path that matches no row, a
# change to this script or the map, and any change under .github/ select every gate. The map is checked
# against the workflow on every run: a workflow command missing from the map, a map gate that is not in
# the workflow, and a script the map names that does not exist all stop the run with exit 2.
# An empty diff prints "no changes" and exits 0; no git diff, a bad base ref or an unreadable map exits 2.
# The paths checked = files committed since the merge base, staged, unstaged and untracked (not git-ignored),
# read NUL-separated, so a path with a space or newline maps correctly.
# RUN_GATES_WORKFLOW and RUN_GATES_MAP name other files (for the test of this script only).
# The script reads the repo, runs existing gates (stdin from /dev/null) and writes only under $TMPDIR (gate logs; kept on failure).
# Will not catch: what a gate reads that the map does not list (the map is a judgement, not a trace; a path
# the map misses must be unmapped to run everything); env set by a workflow step (`env:`) or `if:` guards
# (put an env in the map row); `run:` blocks that are not a `bash scripts/` or `node adapters/` command
# (inline shell, shellcheck, `bash -n`); a second command on one workflow line after the first; the
# fence-snapshot-change label (the frozen gates run unlabelled here); tools a gate needs and this machine
# lacks (that gate fails here and passes in CI).
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 2
WORKFLOW=${RUN_GATES_WORKFLOW:-$ROOT/.github/workflows/validate-skills.yml}
MAP=${RUN_GATES_MAP:-$ROOT/scripts/run-gates.map}
DEFAULT_BASE="origin/main"

WORK=""
KEEP=0
MAP_GLOB=()
MAP_GATE=()
MAP_REST=()
MAP_STRIP=()
GATES=()

# Print an error and stop with the cannot-run status.
die() { echo "run-gates: $*" >&2; exit 2; }

# Set STRIPPED to command $1 without its leading VAR=value words.
strip_env() {
  local c="$1" w
  while :; do
    w=${c%% *}
    case "$w" in
      [A-Za-z_]*=*) ;;
      *) break ;;
    esac
    case "$c" in
      *' '*) c=${c#* } ;;
      *) c=""; break ;;
    esac
  done
  STRIPPED=$c
}

# Print the gate commands of the workflow, one per line, unique, in file order.
read_gates() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(-[[:space:]]+)?name:/ { next }
    {
      line = $0
      while (match(line, /(bash scripts\/|node adapters\/)/)) {
        start = RSTART
        before = (start == 1) ? " " : substr(line, start - 1, 1)
        cmd = substr(line, start)
        line = substr(line, start + 1)
        if (before !~ /[ \t(:]/) continue
        if (match(cmd, / \||;|\)|>|&&/)) cmd = substr(cmd, 1, RSTART - 1)
        sub(/[ \t]+$/, "", cmd)
        sub(/"origin\/\$BASE_REF"/, "{BASE}", cmd)
        if (cmd ~ /[$"'"'"'`\\*?\[]/) {
          print "run-gates: cannot read workflow command: " cmd > "/dev/stderr"
          bad = 1
          continue
        }
        if (!(cmd in seen)) { seen[cmd] = 1; print cmd }
      }
    }
    END { exit bad }
  ' "$WORKFLOW"
}

# Read the workflow gates into GATES.
load_gates() {
  [ -r "$WORKFLOW" ] || die "cannot read $WORKFLOW"
  local out g
  out=$(read_gates) || die "the workflow has a command this script cannot read"
  GATES=()
  while IFS= read -r g; do
    [ -n "$g" ] && GATES+=("$g")
  done <<<"$out"
  [ "${#GATES[@]}" -gt 0 ] || die "no gate commands found in the workflow"
}

# Read the map rows into MAP_GLOB, MAP_GATE, MAP_REST and MAP_STRIP (the gate without its env words).
load_map() {
  [ -r "$MAP" ] || die "cannot read the map $MAP"
  local glob gate rest
  MAP_GLOB=()
  MAP_GATE=()
  MAP_REST=()
  MAP_STRIP=()
  while IFS=$'\t' read -r glob gate rest || [ -n "$glob" ]; do
    case "$glob" in
      '' | '#'*) continue ;;
    esac
    [ -n "$gate" ] || die "map row without a gate: $glob"
    if [ "$glob" != "@skip" ] && [ -n "$rest" ]; then die "map row has more than two fields: $glob"; fi
    MAP_GLOB+=("$glob")
    MAP_GATE+=("$gate")
    MAP_REST+=("$rest")
    strip_env "$gate"
    MAP_STRIP+=("$STRIPPED")
  done <"$MAP"
  [ "${#MAP_GLOB[@]}" -gt 0 ] || die "the map has no rows"
}

# Succeed when $1 is a line of the newline-separated list $2.
in_list() {
  local item
  while IFS= read -r item; do
    [ "$item" = "$1" ] && return 0
  done <<<"$2"
  return 1
}

# Stop when the map and the workflow disagree.
check_map() {
  local bad=0 i g s script gates_text map_text skip_text
  gates_text=$(printf '%s\n' "${GATES[@]}")
  map_text=""
  skip_text=""
  i=0
  while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
    g=${MAP_GATE[$i]}
    if [ "${MAP_GLOB[$i]}" = "@skip" ]; then
      skip_text="$skip_text$g"$'\n'
    elif [ "$g" != "@all" ]; then
      s=${MAP_STRIP[$i]}
      map_text="$map_text$s"$'\n'
      script=${s#* }
      script=${script%% *}
      [ -f "$ROOT/$script" ] || { echo "run-gates: the map names a script that does not exist: $script" >&2; bad=1; }
      in_list "$s" "$gates_text" || { echo "run-gates: the map has a gate that is not in the workflow: $s" >&2; bad=1; }
    fi
    case "${MAP_GLOB[$i]}" in
      *'*'* | *'?'* | *'['* | @skip | @*) ;;
      *) [ -e "$ROOT/${MAP_GLOB[$i]}" ] || { echo "run-gates: the map has a path that does not exist: ${MAP_GLOB[$i]}" >&2; bad=1; } ;;
    esac
    i=$((i + 1))
  done
  for g in "${GATES[@]}"; do
    if in_list "$g" "$map_text"; then continue; fi
    if in_list "$g" "$skip_text"; then continue; fi
    echo "run-gates: a workflow command is missing from the map: $g" >&2
    bad=1
  done
  [ "$bad" -eq 0 ] || die "map and workflow disagree (edit scripts/run-gates.map)"
}

# Set FIRST to the glob of the first map row that matches path $1; fail when none does.
# The empty quotes after $g keep shellcheck quiet and the glob live.
first_glob() {
  local i g
  FIRST=""
  i=0
  while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
    g=${MAP_GLOB[$i]}
    if [ "$g" != "@skip" ]; then
      if [[ $1 == $g"" ]]; then FIRST=$g; return 0; fi
    fi
    i=$((i + 1))
  done
  return 1
}

# Write the changed paths (NUL-separated) to $2, using merge base of $1 and HEAD.
collect_changes() {
  local base="$1" out="$2" mb top
  case "$base" in
    -*) die "bad base ref: $base" ;;
  esac
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "no git repository at $ROOT"
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || die "cannot read the git top level"
  [ "$(cd "$top" && pwd -P)" = "$ROOT" ] || die "$ROOT is not the top level of its git repository"
  git -C "$ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "bad base ref: $base (run: git fetch origin main)"
  mb=$(git -C "$ROOT" merge-base "$base" HEAD 2>/dev/null) || die "no merge base between $base and HEAD"
  git -C "$ROOT" diff -z --no-renames --name-only "$mb" -- >"$out.tracked" || die "git diff failed"
  git -C "$ROOT" ls-files -z --others --exclude-standard >"$out.untracked" || die "git ls-files failed"
  cat "$out.tracked" "$out.untracked" >"$out"
}

# Select gates for the NUL-separated paths in file $1: sets SELECT_ALL (0/1), SELECTED (lines) and REASON.
select_gates() {
  local p i g
  SELECT_ALL=0
  SELECTED=""
  REASON=""
  while IFS= read -r -d '' p; do
    case "$p" in
      scripts/run-gates.sh | scripts/run-gates.map | .github/*)
        SELECT_ALL=1; REASON="$p changed"; continue ;;
    esac
    if ! first_glob "$p"; then
      SELECT_ALL=1; REASON="no map row matches $p"; continue
    fi
    i=0
    while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
      if [ "${MAP_GLOB[$i]}" = "$FIRST" ]; then
        g=${MAP_GATE[$i]}
        if [ "$g" = "@all" ]; then
          SELECT_ALL=1; REASON="$p maps to all gates"
        else
          SELECTED="$SELECTED${MAP_STRIP[$i]}"$'\n'
        fi
      fi
      i=$((i + 1))
    done
  done <"$1"
}

# Print the full map command (with its env words) for workflow gate $1; fail when the map has none.
map_command() {
  local i
  i=0
  while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
    if [ "${MAP_GLOB[$i]}" != "@skip" ] && [ "${MAP_GATE[$i]}" != "@all" ]; then
      if [ "${MAP_STRIP[$i]}" = "$1" ]; then printf '%s\n' "${MAP_GATE[$i]}"; return 0; fi
    fi
    i=$((i + 1))
  done
  return 1
}

# Set CPU_NOW to the children's CPU seconds (user + system) so far. `times` must run in this shell, not
# in a $(...) subshell, which has no children of its own.
child_cpu() {
  times >"$WORK/times"
  CPU_NOW=$(awk 'NR == 2 { for (i = 1; i <= 2; i++) { split($i, a, "m"); sub(/s/, "", a[2]); t += a[1] * 60 + a[2] } printf "%.3f", t }' "$WORK/times")
}

# Run gate command $1 (stripped form), with base ref $2; return its exit status.
run_gate() {
  local full words w i start end cpu status
  full=$(map_command "$1") || die "no map command for gate: $1"
  read -r -a words <<<"$full"
  i=0
  while [ "$i" -lt "${#words[@]}" ]; do
    w=${words[$i]}
    words[i]=${w//\{BASE\}/$2}
    i=$((i + 1))
  done
  child_cpu
  start=$CPU_NOW
  (cd "$ROOT" && env "${words[@]}") </dev/null >"$WORK/gate.log" 2>&1
  status=$?
  child_cpu
  end=$CPU_NOW
  cpu=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }')
  if [ "$status" -eq 0 ]; then
    printf 'PASS  %-60s %ss cpu\n' "$1" "$cpu"
  else
    printf 'FAIL  %-60s %ss cpu (exit %s)\n' "$1" "$cpu" "$status"
    FAILED="$FAILED  $1"$'\n'
    cp "$WORK/gate.log" "$WORK/fail-$FAILN.log"
    echo "      log: $WORK/fail-$FAILN.log"
    tail -n 15 "$WORK/gate.log" | sed 's/^/      | /'
    FAILN=$((FAILN + 1))
    KEEP=1
  fi
  return "$status"
}

MODE=""
LIST=0
CHANGED=0
BASE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE=all ;;
    --check) MODE=check ;;
    --list) LIST=1 ;;
    --changed)
      CHANGED=1
      if [ $# -gt 1 ]; then
        case "$2" in
          --*) ;;
          *) BASE="$2"; shift ;;
        esac
      fi
      ;;
    *) die "unknown argument: $1 (see the header of scripts/run-gates.sh)" ;;
  esac
  shift
done
[ -n "$BASE" ] || BASE="$DEFAULT_BASE"
if [ "$CHANGED" -eq 1 ] && [ "$MODE" = "all" ]; then die "--changed and --all exclude each other"; fi
if [ "$CHANGED" -eq 1 ] && [ "$MODE" = "check" ]; then die "--check takes no other mode"; fi
if [ "$CHANGED" -eq 1 ]; then MODE=changed; fi
if [ -z "$MODE" ] && [ "$LIST" -eq 1 ]; then MODE=all; fi
[ -n "$MODE" ] || die "give --changed [<base-ref>], --all, --list or --check"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || die "cannot create a scratch dir under TMPDIR"
# Remove the scratch dir unless a gate failed.
trap 'if [ "$KEEP" -eq 0 ]; then rm -rf "$WORK"; fi' EXIT

load_gates
load_map
check_map
if [ "$MODE" = "check" ]; then echo "run-gates: map matches the workflow (${#GATES[@]} commands)"; exit 0; fi

PLAN=""
if [ "$MODE" = "changed" ]; then
  collect_changes "$BASE" "$WORK/changes"
  if [ ! -s "$WORK/changes" ]; then echo "no changes"; exit 0; fi
  select_gates "$WORK/changes"
  if [ "$SELECT_ALL" -eq 1 ]; then echo "run-gates: all gates selected: $REASON" >&2; fi
else
  SELECT_ALL=1
fi
for g in "${GATES[@]}"; do
  if [ "$SELECT_ALL" -eq 0 ] && ! in_list "$g" "$SELECTED"; then continue; fi
  map_command "$g" >/dev/null || continue
  PLAN="$PLAN$g"$'\n'
done
[ -n "$PLAN" ] || die "no gate selected (internal error: this must not happen on a non-empty diff)"

if [ "$LIST" -eq 1 ]; then printf '%s' "$PLAN"; exit 0; fi

FAILED=""
FAILN=0
TOTAL=0
while IFS= read -r g; do
  [ -n "$g" ] || continue
  TOTAL=$((TOTAL + 1))
  run_gate "$g" "$BASE"
done <<<"$PLAN"

echo "summary: $TOTAL gates run, $((TOTAL - FAILN)) passed, $FAILN failed (local run; CI runs the full set)"
if [ "$FAILN" -gt 0 ]; then
  printf 'failed:\n%s' "$FAILED"
  exit 1
fi
exit 0
