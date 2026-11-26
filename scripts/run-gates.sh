#!/usr/bin/env bash
# scripts/run-gates.sh — run the repo gates of the pull-request workflows that a change can affect.
# Usage: bash scripts/run-gates.sh --changed [<base-ref>]   gates for the paths changed since the merge base
#        bash scripts/run-gates.sh --all                    every gate
#        bash scripts/run-gates.sh --list [--changed [<base-ref>]]   print the gates, run nothing
#        bash scripts/run-gates.sh --check                  check the map against the workflows and the gate sources, run nothing
# Default base ref: origin/main. Exit: 0 all passed (or no changes), 1 a gate failed, 2 cannot run.
#
# LOCAL CONVENIENCE ONLY. CI runs the full set on every pull request and is the authority. A pass here
# is not a pass in CI, and this script never replaces or weakens a CI check.
#
# Design rule: --changed must never select fewer gates than CI would fail on. When unsure, it selects all.
#
# The gates are the `bash scripts/…` and `node adapters/…` commands on the run lines of every workflow in
# .github/workflows that triggers on pull_request (a base ref written `"origin/$BASE_REF"` is replaced by
# the base ref given here). The path-to-gate map is data, scripts/run-gates.map: tab-separated rows of
# <path glob> and <gate command>. The first row whose glob matches a path decides for that path (all rows
# with that exact glob apply); a gate command may start with VAR=value words; `@all` as the gate selects
# every gate; `@skip<TAB>command<TAB>reason` names a workflow command that is not a standalone gate.
# Fail safe toward more: a path that matches no row, a change to this script or the map, and any change
# under .github/ select every gate.
#
# Allow-list parser. On a run line, `scripts/` and `adapters/` are accepted only as `bash scripts/…` and
# `node adapters/…` (one space) or inside an @skip command. Any other use (`python3 scripts/x.py`,
# `sh scripts/x.sh`, `bash ./scripts/x.sh`, two spaces, `&&bash scripts/x.sh`), a `cd`, `pushd` or
# `working-directory:` into scripts or adapters, and a command with a quote, `$`, backtick, glob, backslash
# or `<` stop the run with exit 2, naming file and line. A second command on one line is read as its own
# gate. An @skip row that no run line contains also stops the run. Every map check, and the audit below,
# exits 2 with its reason on stderr before any gate runs.
#
# Audit (--check only; the test of this script runs it on every pull request). The map names, for each
# path row, the gates that path feeds. For every gate the audit looks in the gate script's own text for
# each path the map lists (a literal path, a glob's literal prefix, or a script's name). A gate that
# names a mapped path but is not selected by that path's row fails the check: add the gate to the row,
# give the row `@all`, or, when the name is a fixture or a comment and not a read, record that with
# `@noread<TAB>gate<TAB>map globs` (space-separated, or `*` for every path; a comment above gives the reason). A @noread
# row that no longer matches fails too. A gate that runs another script is covered by that script's own
# rows (a script-to-script edge is a map row, not an audit finding).
#
# Run state. Each gate runs with stdin from /dev/null and a time limit: RUN_GATES_TIMEOUT seconds,
# default 3600. A gate over the limit, or killed by a signal, is reported FAIL; the gate's whole process
# group is stopped. A gate that passes but prints SKIP: or SKIPPED: lines (a tool this machine lacks, or
# CI=true unset) is reported PASS-WITH-SKIPS: it passed here, and CI runs what it skipped. A SIGINT,
# SIGTERM or SIGHUP stops the running gate and removes the scratch dir. Every GIT_* repository variable
# is unset at the start, so a gate and the diff read this repo, never the caller's.
#
# An empty diff prints "no changes" and exits 0; no git diff, a bad base ref, no common ancestor or an
# unreadable map exits 2. The paths checked = files committed since the merge base, staged, unstaged and
# untracked (not git-ignored; this script's own scratch dir is left out), read NUL-separated, so a path
# with a space or newline maps correctly.
# RUN_GATES_WORKFLOWS (a directory of workflows, scanned instead of .github/workflows) and RUN_GATES_MAP
# (another map file) are for the test of this script only.
# The script reads the repo, runs existing gates and writes only under $TMPDIR (gate logs; kept on failure).
# The audit reads only a gate script's own text, not the scripts it calls: test-template-copy.sh runs
# build-agents-dist.sh, which copies CHANGELOG.md, and the audit does not see that. A @noread row can
# hide a later real read of the same path. A gate grandchild that moves to its own process group survives
# the group kill. Local `uses: ./` steps (composite actions, reusable workflows) stop the run unless an
# @skip row names them. A rename whose old or new path matches a map row is named on stderr.
# Will not catch: what a gate reads that its own script text does not name (a path built in a variable, a glob loop,
# data read through a tool; the map and the audit are a judgement, not a trace; list a path the audit
# misses as unmapped, which selects all); env set by a workflow step (`env:`) or `if:` guards (put an env
# in the map row); `run:` blocks and steps that are not a `bash scripts/` or `node adapters/` command
# (inline shell, shellcheck, `bash -n`, the dist-build output check: CI only); workflows that do not
# trigger on pull_request, and what a reusable or composite workflow runs (a local `uses: ./` is refused, not read); a `cd` through a variable; the
# fence-snapshot-change label (the frozen gates run unlabelled here); tools a gate needs and this machine
# lacks (that gate fails here and passes in CI, or reports skips here and runs in CI).
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
unset GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX GIT_QUARANTINE_PATH

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 2
MAP=${RUN_GATES_MAP:-$ROOT/scripts/run-gates.map}
DEFAULT_BASE="origin/main"
LIMIT=${RUN_GATES_TIMEOUT:-3600}

WORK=""
KEEP=0
GATE_PID=""
WD_PID=""
MAP_GLOB=()
MAP_GATE=()
MAP_REST=()
MAP_STRIP=()
MAP_LINE=()
GATES=()
WF_FILES=()
USED_SKIPS=""
NOREAD=""
USED_NOREAD=""

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

# Succeed when $1 is a line of the newline-separated list $2.
in_list() {
  local item
  while IFS= read -r item; do
    [ "$item" = "$1" ] && return 0
  done <<<"$2"
  return 1
}

# Print the records of one workflow file $1 (shown as $2): `G<TAB>command` per gate, `S<TAB>command` per
# @skip command found, `E<TAB>message` per line this parser refuses. The skip commands are in $WORK/skips.
read_gates() {
  awk -v file="$2" -v skipfile="$WORK/skips" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function ind(s,   t) { t = s; sub(/[^ ].*$/, "", t); return length(t) }
    function err(ln, msg, text) { print "E\t" file ":" ln ": " msg ": " text }
    function bad_chars(cmd,   i) {
      for (i = 1; i <= length(cmd); i++) if (index(special, substr(cmd, i, 1))) return 1
      return 0
    }
    function check_line(text, ln,   k, s, rest, off, p, nc, w, a, c, b, word, lead, cmd, covered, j, pos, ok, q) {
      split("", cs); split("", ce); nc = 0
      for (k = 1; k <= nskip; k++) {
        s = skips[k]; rest = text; off = 0
        while ((p = index(rest, s)) > 0) {
          nc++; cs[nc] = off + p; ce[nc] = off + p + length(s) - 1; used[s] = 1
          off += p + length(s) - 1; rest = substr(rest, p + length(s))
        }
      }
      for (w = 1; w <= 2; w++) {
        word = (w == 1) ? "scripts/" : "adapters/"
        lead = (w == 1) ? "bash " : "node "
        pos = 1
        while ((p = index(substr(text, pos), word)) > 0) {
          a = pos + p - 1
          pos = a + 1
          c = (a > 1) ? substr(text, a - 1, 1) : " "
          if (c ~ /[A-Za-z0-9_-]/) continue
          covered = 0
          for (j = 1; j <= nc; j++) if (a >= cs[j] && a <= ce[j]) covered = 1
          if (covered) continue
          ok = 0
          if (a > 5 && substr(text, a - 5, 5) == lead) {
            b = (a > 6) ? substr(text, a - 6, 1) : " "
            if (a == 6 || b ~ /[ \t(:]/) ok = 1
          }
          if (!ok) {
            err(ln, "scripts/ or adapters/ used in a form this runner does not read (only `bash scripts/…` and `node adapters/…` with one space are; add an @skip row to scripts/run-gates.map if it is meant)", text)
            continue
          }
          cmd = substr(text, a - 5)
          if (match(cmd, /[|;)>&]/)) cmd = substr(cmd, 1, RSTART - 1)
          cmd = trim(cmd)
          q = "\"origin/$BASE_REF\""
          while ((j = index(cmd, q)) > 0) cmd = substr(cmd, 1, j - 1) "{BASE}" substr(cmd, j + length(q))
          if (bad_chars(cmd)) { err(ln, "cannot read workflow command", cmd); continue }
          if (!(cmd in seen)) { seen[cmd] = 1; print "G\t" cmd }
        }
      }
      if (match(text, /(^|[ \t;&|(])(cd|pushd)[ \t]+[^;&|]*(scripts|adapters)/)) err(ln, "a cd into scripts or adapters (this runner cannot follow it)", text)
    }
    BEGIN {
      special = "$\"`\\*?[<" sprintf("%c", 39)
      while ((getline sk < skipfile) > 0) if (sk != "") skips[++nskip] = sk
      close(skipfile)
    }
    {
      raw = $0
      if (inblock) {
        if (raw ~ /^[ \t]*$/) next
        if (ind(raw) > keyind) { if (raw !~ /^[ \t]*#/) check_line(trim(raw), FNR); next }
        inblock = 0
      }
      if (cont) {
        if (raw ~ /^[ \t]*$/) next
        if (ind(raw) > keyind) { if (raw !~ /^[ \t]*#/) check_line(trim(raw), FNR); next }
        cont = 0
      }
      if (raw ~ /^[ \t]*#/) next
      if (match(raw, /^[ \t]*(-[ \t]+)*uses:[ \t]*[\047"]?\.\//)) {
        val = trim(substr(raw, RSTART + RLENGTH - 2)); sub(/[ \t]+#.*$/, "", val); gsub(/[\047"]/, "", val)
        ok = 0
        for (k = 1; k <= nskip; k++) if (index(val, skips[k]) > 0) { ok = 1; used[skips[k]] = 1 }
        if (!ok) err(FNR, "a local uses: (composite action or reusable workflow) this runner cannot read; add an @skip row naming it to scripts/run-gates.map", val)
        next
      }
      if (raw ~ /^[ \t]*(-[ \t]+)?working-directory:/) {
        if (raw ~ /(scripts|adapters)/) err(FNR, "working-directory in scripts or adapters (this runner cannot follow it)", trim(raw))
        next
      }
      if (match(raw, /^[ \t]*(-[ \t]+)*run:([ \t]|$)/)) {
        keyind = index(raw, "run:") - 1
        rest = trim(substr(raw, RSTART + RLENGTH))
        if (rest ~ /^[|>][+-]?[0-9]*([ \t]+#.*)?$/) { inblock = 1; next }
        if (rest != "") { check_line(rest, FNR); cont = 1 }
      }
    }
    END { for (s in used) print "S\t" s }
  ' "$1"
}

# Succeed when workflow file $1 mentions pull_request anywhere outside a comment. The whole file is read, so
# a workflow with `jobs:` before `on:` is seen; a mention elsewhere (an `if:` guard) only adds a workflow.
triggers_on_pr() {
  awk '/^[[:space:]]*#/ { next } /pull_request/ { f = 1 } END { exit !f }' "$1"
}

# Read the gates of every pull_request workflow into GATES, the @skip commands that were found into USED_SKIPS.
load_gates() {
  local f out kind val bad=0 g wfdir
  WF_FILES=()
  wfdir=${RUN_GATES_WORKFLOWS:-$ROOT/.github/workflows}
  for f in "$wfdir"/*.yml "$wfdir"/*.yaml; do
    [ -f "$f" ] || continue
    if triggers_on_pr "$f"; then WF_FILES+=("$f"); fi
  done
  [ "${#WF_FILES[@]}" -gt 0 ] || die "no workflow that triggers on pull_request in $wfdir"
  GATES=()
  USED_SKIPS=""
  for f in "${WF_FILES[@]}"; do
    [ -r "$f" ] || die "cannot read $f"
    out=$(read_gates "$f" "${f#"$ROOT"/}") || die "cannot read $f"
    while IFS=$'\t' read -r kind val; do
      case "$kind" in
        G) if ! in_list "$val" "$(printf '%s\n' "${GATES[@]:-}")"; then GATES+=("$val"); fi ;;
        S) USED_SKIPS="$USED_SKIPS$val"$'\n' ;;
        E) echo "run-gates: $val" >&2; bad=1 ;;
      esac
    done <<<"$out"
  done
  [ "$bad" -eq 0 ] || die "a workflow run line this script cannot read safely (see above; fix the line or add an @skip row to scripts/run-gates.map)"
  g=0
  for f in "${GATES[@]:-}"; do
    [ -n "$f" ] && g=$((g + 1))
  done
  [ "$g" -gt 0 ] || die "no gate commands found in the pull_request workflows"
}

# Read the map rows into MAP_GLOB, MAP_GATE, MAP_REST, MAP_STRIP (the gate without its env words) and MAP_LINE.
# Write the @skip commands to $WORK/skips for the workflow parser.
load_map() {
  [ -r "$MAP" ] || die "cannot read the map $MAP"
  local glob gate rest ln=0 w
  NOREAD=""
  USED_NOREAD=""
  MAP_GLOB=()
  MAP_GATE=()
  MAP_REST=()
  MAP_STRIP=()
  MAP_LINE=()
  : >"$WORK/skips"
  while IFS=$'\t' read -r glob gate rest || [ -n "$glob" ]; do
    ln=$((ln + 1))
    case "$glob" in
      '' | '#'*) continue ;;
    esac
    [ -n "$gate" ] || die "map row without a gate (line $ln): $glob"
    if [ "$glob" = "@noread" ]; then
      [ -n "$rest" ] || die "@noread row needs <gate><TAB><map globs> (line $ln)"
      strip_env "$gate"
      set -f
      for w in $rest; do NOREAD="$NOREAD$STRIPPED"$'\t'"$w"$'\n'; done
      set +f
      continue
    fi
    if [ "$glob" != "@skip" ] && [ -n "$rest" ]; then die "map row has more than two fields (line $ln): $glob"; fi
    MAP_GLOB+=("$glob")
    MAP_GATE+=("$gate")
    MAP_REST+=("$rest")
    MAP_LINE+=("$ln")
    strip_env "$gate"
    MAP_STRIP+=("$STRIPPED")
    if [ "$glob" = "@skip" ]; then printf '%s\n' "$gate" >>"$WORK/skips"; fi
  done <"$MAP"
  [ "${#MAP_GLOB[@]}" -gt 0 ] || die "the map has no rows"
}

# Stop when the map and the workflows disagree.
check_map() {
  local bad=0 i g s script gates_text map_text skip_text where fix
  gates_text=$(printf '%s\n' "${GATES[@]}")
  map_text=""
  skip_text=""
  fix="edit or remove that row in scripts/run-gates.map (a script that was renamed or deleted needs its rows renamed or removed)"
  i=0
  while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
    g=${MAP_GATE[$i]}
    where="map row at line ${MAP_LINE[$i]} (${MAP_GLOB[$i]} -> $g)"
    if [ "${MAP_GLOB[$i]}" = "@skip" ]; then
      skip_text="$skip_text$g"$'\n'
      in_list "$g" "$USED_SKIPS" || { echo "run-gates: $where: no workflow run line contains this @skip command; $fix" >&2; bad=1; }
    elif [ "$g" != "@all" ]; then
      s=${MAP_STRIP[$i]}
      map_text="$map_text$s"$'\n'
      script=${s#* }
      script=${script%% *}
      [ -f "$ROOT/$script" ] || { echo "run-gates: $where: the map names a script that does not exist: $script; $fix" >&2; bad=1; }
      in_list "$s" "$gates_text" || { echo "run-gates: $where: the map has a gate that is not in the workflow: $s; $fix" >&2; bad=1; }
    fi
    case "${MAP_GLOB[$i]}" in
      *'*'* | *'?'* | *'['* | @skip | @*) ;;
      *) [ -e "$ROOT/${MAP_GLOB[$i]}" ] || { echo "run-gates: $where: the map has a path that does not exist: ${MAP_GLOB[$i]}; $fix" >&2; bad=1; } ;;
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

# Select the gates for path $1: set SELECT_ALL, add to SELECTED (lines) and set REASON.
select_path() {
  local p="$1" i g
  case "$p" in
    scripts/run-gates.sh | scripts/run-gates.map | .github/*)
      SELECT_ALL=1; REASON="$p changed"; return 0 ;;
  esac
  if ! first_glob "$p"; then
    SELECT_ALL=1; REASON="no map row matches $p"; return 0
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
}

# Select gates for the NUL-separated paths in file $1: sets SELECT_ALL (0/1), SELECTED (lines) and REASON.
select_gates() {
  local p
  SELECT_ALL=0
  SELECTED=""
  REASON=""
  while IFS= read -r -d '' p; do
    select_path "$p"
  done <"$1"
}

# Fail when a gate script names a path the map lists but the map row does not select that gate, unless a
# @noread row records that the name is not a read. Fail on a @noread row that no longer matches anything.
audit_map() {
  local i g lit pat rep s seen bad=0 gate script found pp pr glob
  : >"$WORK/pats"
  i=0
  while [ "$i" -lt "${#MAP_GLOB[@]}" ]; do
    glob=${MAP_GLOB[$i]}
    i=$((i + 1))
    case "$glob" in
      @*) continue ;;
      *'['*) continue ;;
    esac
    lit=${glob%%[*?]*}
    pat=${lit%/}
    [ "${#pat}" -ge 3 ] || continue
    rep=${glob//\*/x}
    rep=${rep//\?/x}
    printf '%s\t%s\n' "$pat" "$rep" >>"$WORK/pats"
    case "$pat" in
      scripts/*) s=${pat#scripts/}; [ "${#s}" -ge 3 ] && printf '%s\t%s\n' "$s" "$rep" >>"$WORK/pats" ;;
    esac
  done
  for gate in "${GATES[@]}"; do
    strip_env "$gate"
    script=${STRIPPED#* }
    script=${script%% *}
    [ -f "$ROOT/$script" ] || continue
    found=$(awk -F '\t' '
      NR == FNR { n++; p[n] = $1; r[n] = $2; next }
      { for (i = 1; i <= n; i++) if (!f[i] && index($0, p[i])) f[i] = 1 }
      END { for (i = 1; i <= n; i++) if (f[i]) print p[i] "\t" r[i] }
    ' "$WORK/pats" "$ROOT/$script")
    seen=""
    while IFS=$'\t' read -r pp pr; do
      [ -n "$pp" ] || continue
      SELECT_ALL=0; SELECTED=""; REASON=""
      select_path "$pr"
      [ "$SELECT_ALL" -eq 1 ] && continue
      if in_list "$STRIPPED" "$SELECTED"; then continue; fi
      first_glob "$pr" || true
      if in_list "$STRIPPED"$'\t'"$FIRST" "$NOREAD"; then USED_NOREAD="$USED_NOREAD$STRIPPED"$'\t'"$FIRST"$'\n'; continue; fi
      if in_list "$STRIPPED"$'\t*' "$NOREAD"; then USED_NOREAD="$USED_NOREAD$STRIPPED"$'\t*\n'; continue; fi
      if in_list "$pr" "$seen"; then continue; fi
      seen="$seen$pr"$'\n'
      echo "run-gates: audit: gate [$STRIPPED] names \"$pp\" in its scripts, but the map row for \"$FIRST\" does not select it (add the gate to that row or make the row @all)" >&2
      bad=1
    done <<<"$found"
  done
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    in_list "$s" "$USED_NOREAD" || { echo "run-gates: audit: @noread row is stale (the gate no longer names that path, or the row selects it): ${s//$'\t'/ -> }; remove it from scripts/run-gates.map" >&2; bad=1; }
  done <<<"$NOREAD"
  [ "$bad" -eq 0 ] || die "the audit found a gate the map does not select for a path it names (edit scripts/run-gates.map)"
}

# Write the changed paths (NUL-separated) to $2, using merge base of $1 and HEAD.
collect_changes() {
  local base="$1" out="$2" mb top rel
  case "$base" in
    -*) die "bad base ref: $base" ;;
  esac
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "no git repository at $ROOT"
  top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || die "cannot read the git top level"
  [ "$(cd "$top" && pwd -P)" = "$ROOT" ] || die "$ROOT is not the top level of its git repository"
  git -C "$ROOT" rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "bad base ref: $base (run: git fetch origin main)"
  mb=$(git -C "$ROOT" merge-base "$base" HEAD 2>/dev/null) || die "no merge base between $base and HEAD"
  git -C "$ROOT" diff -z --no-renames --name-only "$mb" -- >"$out.tracked" || die "git diff failed"
  git -C "$ROOT" diff -z -M --name-status "$mb" -- >"$out.renames" || die "git diff failed"
  case "$WORK" in
    "$ROOT"/*)
      rel=${WORK#"$ROOT"/}
      git -C "$ROOT" ls-files -z --others --exclude-standard -- . ":(exclude)$rel" >"$out.untracked" || die "git ls-files failed" ;;
    *)
      git -C "$ROOT" ls-files -z --others --exclude-standard >"$out.untracked" || die "git ls-files failed" ;;
  esac
  cat "$out.tracked" "$out.untracked" >"$out"
}

# Name each rename in file $1 (git diff -z --name-status -M) where the old or the new path matches a map row.
# Both paths are in the changed set already (the diff that selects gates runs with --no-renames); this line
# only tells the reader which pairs were one move.
note_renames() {
  local st a b
  while IFS= read -r -d '' st; do
    case "$st" in
      R* | C*)
        IFS= read -r -d '' a || break
        IFS= read -r -d '' b || break
        if first_glob "$a" || first_glob "$b"; then echo "run-gates: renamed: $a -> $b (the map rows of both paths apply)" >&2; fi ;;
      *) IFS= read -r -d '' a || break ;;
    esac
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
  local full words w i start end cpu status n
  full=$(map_command "$1") || die "no map command for gate: $1"
  read -r -a words <<<"$full"
  i=0
  while [ "$i" -lt "${#words[@]}" ]; do
    w=${words[$i]}
    words[i]=${w//\{BASE\}/$2}
    i=$((i + 1))
  done
  rm -f "$WORK/timeout"
  child_cpu
  start=$CPU_NOW
  set -m
  (cd "$ROOT" && exec env "${words[@]}") </dev/null >"$WORK/gate.log" 2>&1 &
  GATE_PID=$!
  (sleep "$LIMIT"; : >"$WORK/timeout"; kill -TERM -- "-$GATE_PID" 2>/dev/null; sleep 5; kill -KILL -- "-$GATE_PID" 2>/dev/null) </dev/null >/dev/null 2>&1 &
  WD_PID=$!
  set +m
  { wait "$GATE_PID"; } 2>/dev/null
  status=$?
  kill -KILL -- "-$WD_PID" 2>/dev/null
  { wait "$WD_PID"; } 2>/dev/null
  if [ -e "$WORK/timeout" ]; then kill -KILL -- "-$GATE_PID" 2>/dev/null; fi
  GATE_PID=""
  WD_PID=""
  child_cpu
  end=$CPU_NOW
  cpu=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }')
  if [ -e "$WORK/timeout" ]; then
    printf 'FAIL  %-60s %ss cpu (timed out after %ss; the gate was stopped)\n' "$1" "$cpu" "$LIMIT"
    [ "$status" -ne 0 ] || status=1
  elif [ "$status" -ne 0 ]; then
    if [ "$status" -gt 128 ]; then
      printf 'FAIL  %-60s %ss cpu (exit %s, killed by signal %s)\n' "$1" "$cpu" "$status" "$((status - 128))"
    else
      printf 'FAIL  %-60s %ss cpu (exit %s)\n' "$1" "$cpu" "$status"
    fi
  else
    n=$(grep -c -E '^[[:space:]]*SKIP(PED)?:' "$WORK/gate.log") || true
    if [ "${n:-0}" -gt 0 ]; then
      printf 'PASS-WITH-SKIPS  %-60s %ss cpu (%s skip lines: CI runs what was skipped here)\n' "$1" "$cpu" "$n"
      grep -E '^[[:space:]]*SKIP(PED)?:' "$WORK/gate.log" | head -n 5 | sed 's/^/      | /'
      SKIPPED="$SKIPPED  $1"$'\n'
      SKIPN=$((SKIPN + 1))
    else
      printf 'PASS  %-60s %ss cpu\n' "$1" "$cpu"
    fi
    return 0
  fi
  FAILED="$FAILED  $1"$'\n'
  cp "$WORK/gate.log" "$WORK/fail-$FAILN.log"
  echo "      log: $WORK/fail-$FAILN.log"
  tail -n 15 "$WORK/gate.log" | sed 's/^/      | /'
  FAILN=$((FAILN + 1))
  KEEP=1
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
case "$LIMIT" in
  '' | *[!0-9]* | 0) die "RUN_GATES_TIMEOUT must be a whole number of seconds above 0, not: $LIMIT" ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/run-gates.XXXXXX") || die "cannot create a scratch dir under TMPDIR"
WORK=$(cd "$WORK" && pwd -P) || die "cannot enter the scratch dir"
exec 4>&2 # the signal handlers report here; the wait on a gate runs with stderr silenced
# Remove the scratch dir unless a gate failed.
trap 'if [ "$KEEP" -eq 0 ]; then rm -rf "$WORK"; fi' EXIT
# A SIGINT, SIGTERM or SIGHUP kills the running gate's group and the watchdog's, then exits 128 + the signal.
trap 'trap - INT TERM HUP; kill -KILL -- "-$GATE_PID" 2>/dev/null; kill -KILL -- "-$WD_PID" 2>/dev/null; echo "run-gates: interrupted by INT; the running gate was stopped" >&4; exit 130' INT
trap 'trap - INT TERM HUP; kill -KILL -- "-$GATE_PID" 2>/dev/null; kill -KILL -- "-$WD_PID" 2>/dev/null; echo "run-gates: interrupted by TERM; the running gate was stopped" >&4; exit 143' TERM
trap 'trap - INT TERM HUP; kill -KILL -- "-$GATE_PID" 2>/dev/null; kill -KILL -- "-$WD_PID" 2>/dev/null; echo "run-gates: interrupted by HUP; the running gate was stopped" >&4; exit 129' HUP

load_map
load_gates
check_map
if [ "$MODE" = "check" ]; then
  audit_map
  echo "run-gates: map matches the workflows and the gate sources (${#GATES[@]} commands)"
  exit 0
fi

PLAN=""
if [ "$MODE" = "changed" ]; then
  collect_changes "$BASE" "$WORK/changes"
  if [ ! -s "$WORK/changes" ]; then echo "no changes"; exit 0; fi
  select_gates "$WORK/changes"
  note_renames "$WORK/changes.renames"
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

if [ "$LIST" -eq 1 ]; then printf '%s' "${PLAN//\{BASE\}/$BASE}"; exit 0; fi

FAILED=""
FAILN=0
SKIPPED=""
SKIPN=0
TOTAL=0
while IFS= read -r g; do
  [ -n "$g" ] || continue
  TOTAL=$((TOTAL + 1))
  run_gate "$g" "$BASE"
done <<<"$PLAN"

summary="summary: $TOTAL gates run, $((TOTAL - FAILN)) passed, $FAILN failed"
if [ "$SKIPN" -gt 0 ]; then summary="$summary, $SKIPN passed with skips"; fi
echo "$summary (local run; CI runs the full set)"
if [ "$SKIPN" -gt 0 ]; then printf 'passed with skips (CI runs what they skipped):\n%s' "$SKIPPED"; fi
if [ "$FAILN" -gt 0 ]; then
  printf 'failed:\n%s' "$FAILED"
  exit 1
fi
exit 0
