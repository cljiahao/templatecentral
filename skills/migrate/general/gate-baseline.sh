#!/usr/bin/env bash
# Gate baseline: let a gate fail only on NEW findings. Findings that existed at adoption are recorded once in .claude/gate-baseline.txt and may only shrink.
# Usage: gate-baseline.sh [-C <project-dir>] [-f <baseline-file>] <command> ...
#   record <gate> <adapter> [--rc N]   stdin = the gate's output. Writes the gate's findings into the file. A gate that already has entries must match them exactly (use prune to shrink).
#   check  <gate> <adapter> [--rc N] [--strict-stale]   stdin = the gate's output. Exit 1 on a finding that is not in the file, on output it cannot parse, or on a tool that failed without findings. Prints REMOVABLE for entries that match nothing now.
#   prune  <gate> <adapter> [--rc N]   stdin = the gate's output. Removes entries that match nothing and lowers counts; never adds.
#   validate                           Format only: exit 1 when the file is missing, unsorted, duplicated, has a carriage return or is unparsable. It does not compare with an earlier version; growth does that.
#   growth <base-ref> [<head-ref>]     Exit 1 when the file at head (default HEAD) has an entry or count that the file at <base-ref> lacks; prints WEAKENED/UNREADABLE lines in the format gate-ratchet.sh uses.
#   run <record|dry|check|prune>       Runs the project's lint, type check and seeded check scripts itself and applies the command to each (gates: lint types workflows dockerfile).
# Adapters (what each gate prints today): colon = "path:line[:col]: message" (eslint -f unix, ruff --output-format concise, check-workflows.sh, check-dockerfile.sh);
#   tsc = "path(line,col): error TSnnnn: message" (tsc --pretty false); pyright = "  path:line:col - error: message (rule)".
# --rc N is the tool's exit code (default 1). Output is parsed whatever the code: a finding not in the file or a line it cannot read fails even at rc 0. Colour codes and carriage returns are stripped first.
# File format: line 1 is "# templatecentral gate baseline v1"; then one line per entry: gate TAB file TAB count TAB fingerprint, sorted bytewise by gate, file, fingerprint.
# The fingerprint is the message with spaces collapsed, never the line number, so moved code matches and a second copy (count + 1) is new. A renamed file is new.
# Exit 0 ok, 1 a finding or growth, 2 a usage error or an unusable file. Nothing is read from .env files; no network. Needs bash 3.2+, POSIX awk, sort; git for growth.
set -u

TAB=$(printf '\t')
NL='
'
HEADER='# templatecentral gate baseline v1'
die() { echo "gate-baseline: $1" >&2; exit 2; }

ROOT=.
BFILE=
while [ $# -gt 0 ]; do
  case "$1" in
    -C) shift; [ $# -gt 0 ] || die "-C needs a directory"; ROOT=$1 ;;
    -f) shift; [ $# -gt 0 ] || die "-f needs a path"; BFILE=$1 ;;
    *) break ;;
  esac
  shift
done
[ $# -gt 0 ] || die "usage: gate-baseline.sh [-C dir] [-f file] <record|check|prune|validate|growth|run> ..."
CMD=$1
shift
ROOT_LOGICAL=$ROOT
if ! ROOT=$(cd -P -- "$ROOT" 2>/dev/null && pwd -P); then die "cannot enter $ROOT_LOGICAL"; fi
BREL=${BFILE:-.claude/gate-baseline.txt}
case "$BREL" in /*) BPATH=$BREL ;; *) BPATH=$ROOT/$BREL ;; esac
case "$BREL$ROOT" in *"$NL"*|*"$TAB"*) die "a path contains a newline or tab" ;; esac

W=$(mktemp -d "${TMPDIR:-/tmp}/gatebl.XXXXXX") || die "cannot create a temp dir"
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

valid_gate() { case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac; return 0; }
valid_adapter() { case "$1" in colon|tsc|pyright) return 0 ;; esac; return 1; }

# norm <adapter>: stdin to "file TAB fingerprint TAB original line"; a line it cannot read becomes "! TAB TAB line".
norm() {
  GB_ROOTS="$ROOT$NL$ROOT_LOGICAL" awk -v ad="$1" '
    function collapse(s) { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    function relpath(p,   i, r) {
      for (i = 1; i <= nr; i++) { r = R[i] "/"; if (R[i] != "" && index(p, r) == 1) { p = substr(p, length(r) + 1); break } }
      while (index(p, "./") == 1) p = substr(p, 3)
      return p
    }
    function flush() {
      if (have) { printf "%s\t%s\t%s\n", collapse(relpath(pf)), collapse(pm), po }
      have = 0
    }
    BEGIN { nr = split(ENVIRON["GB_ROOTS"], R, "\n"); esc = sprintf("%c", 27) }
    {
      line = $0; gsub(esc "\\[[0-9;]*[A-Za-z]", "", line); sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^[0-9]+ (problems?|errors?)/ || line ~ /^Found [0-9]+ errors?/ || line ~ /^\[\*\] / || line ~ /^All checks passed/ || line ~ /^check-[a-z]+: (ok|no Dockerfile found)/ || line ~ /^WARNING check-[a-z]+: /) { flush(); next }
      if (ad == "tsc") {
        if (line !~ /^[[:space:]]/ && match(line, /\([0-9]+,[0-9]+\): /)) { flush(); pf = substr(line, 1, RSTART - 1); pm = substr(line, RSTART + RLENGTH); po = line; have = 1; next }
        if (line ~ /^[[:space:]]/ && have) { pm = pm " " line; po = po " " collapse(line); next }
      } else if (ad == "pyright") {
        if (match(line, /:[0-9]+:[0-9]+ - [a-z]+: /)) {
          flush(); pf = substr(line, 1, RSTART - 1); sub(/^[[:space:]]+/, "", pf)
          pm = substr(line, RSTART + index(substr(line, RSTART), " - ") + 2); po = line; have = 1; next
        }
        if (line ~ /^[[:space:]]/ && have) { pm = pm " " line; po = po " " collapse(line); next }
        if (line ~ /^([\/]|[A-Za-z]:[\\\/])/ || line ~ /^[0-9]+ errors?,/) { flush(); next }
      } else {
        if (match(line, /:[0-9]+(:[0-9]+)?: /)) { flush(); pf = substr(line, 1, RSTART - 1); pm = substr(line, RSTART + RLENGTH); po = line; have = 1; next }
      }
      flush()
      printf "!\t\t%s\n", line
    }
    END { flush() }'
}

# validate_file <path> <label>: prints each problem, returns 1 when there is any.
validate_file() {
  local f=$1 label=$2 bad=0 out
  if [ -L "$f" ]; then echo "gate-baseline: $label is a symlink" >&2; return 1; fi
  if [ ! -f "$f" ]; then echo "gate-baseline: $label is missing" >&2; return 1; fi
  if [ "$(head -n 1 "$f")" != "$HEADER" ]; then echo "gate-baseline: $label does not start with the line: $HEADER" >&2; return 1; fi
  if [ -n "$(tail -c 1 "$f")" ]; then echo "gate-baseline: $label does not end in a newline" >&2; bad=1; fi
  out=$(tail -n +2 "$f" | awk -F'\t' -v cr="$(printf '\r')" '
    index($0, cr) { printf "line %d: carriage return\n", NR + 1; next }
    NF != 4 { printf "line %d: expected 4 tab-separated fields\n", NR + 1; next }
    $1 !~ /^[a-z0-9-]+$/ { printf "line %d: bad gate name\n", NR + 1 }
    $2 == "" || $4 == "" { printf "line %d: empty file or fingerprint\n", NR + 1 }
    $3 !~ /^[1-9][0-9]*$/ { printf "line %d: count is not a positive integer\n", NR + 1 }')
  if [ -n "$out" ]; then printf 'gate-baseline: %s: %s\n' "$label" "$out" >&2; bad=1; fi
  if [ "$bad" -eq 0 ] && ! tail -n +2 "$f" | LC_ALL=C sort -c -u -t "$TAB" -k1,1 -k2,2 -k4 2>/dev/null; then
    echo "gate-baseline: $label is not sorted, or has two entries for one gate, file and fingerprint" >&2; bad=1
  fi
  return "$bad"
}

# counts <normalized-file>: "file TAB fingerprint TAB count", sorted.
counts() {
  awk -F'\t' '$1 != "!" { c[$1 "\t" $2]++ } END { for (k in c) print k "\t" c[k] }' "$1" | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2
}
# gate_entries <gate>: that gate's entries as "file TAB fingerprint TAB count", sorted.
gate_entries() {
  tail -n +2 "$BPATH" | awk -F'\t' -v g="$1" '$1 == g { print $2 "\t" $4 "\t" $3 }' | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2
}
# write_baseline <body-file>: header plus the sorted body replaces the file.
write_baseline() {
  local tmp d
  d=$(dirname -- "$BPATH")
  [ ! -L "$BPATH" ] || die "$BREL is a symlink; refusing to write it"
  mkdir -p -- "$d" || die "cannot create $d"
  tmp=$(mktemp "$d/.gate-baseline.XXXXXX") || die "cannot write in $d"
  if ! { { printf '%s\n' "$HEADER"; LC_ALL=C sort -t "$TAB" -k1,1 -k2,2 -k4 "$1"; } >"$tmp" && mv -f -- "$tmp" "$BPATH"; }; then rm -f -- "$tmp"; die "cannot write $BREL"; fi
}

RC=1
STRICT=0
GATE=
ADAPTER=
# take_gate_args <args...>: gate, adapter and options of record, check and prune.
take_gate_args() {
  [ $# -ge 2 ] || die "usage: gate-baseline.sh $CMD <gate> <adapter> [--rc N]"
  GATE=$1; ADAPTER=$2; shift 2
  valid_gate "$GATE" || die "bad gate name '$GATE'"
  valid_adapter "$ADAPTER" || die "unknown adapter '$ADAPTER' (colon, tsc, pyright)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --rc) shift; [ $# -gt 0 ] || die "--rc needs a number"; RC=$1; case "$RC" in ''|*[!0-9]*) die "--rc needs a number" ;; esac ;;
      --strict-stale) STRICT=1 ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
}
# load_findings: stdin through the adapter into $W/norm.tsv and $W/cur.tsv, whatever the tool's exit code.
load_findings() {
  norm "$ADAPTER" >"$W/norm.tsv"
  counts "$W/norm.tsv" >"$W/cur.tsv"
  NUNP=$(awk -F'\t' '$1 == "!" { n++ } END { print n + 0 }' "$W/norm.tsv")
}

cmd_validate() {
  validate_file "$BPATH" "$BREL" || exit 1
  echo "gate-baseline: $BREL ok ($(tail -n +2 "$BPATH" | wc -l | tr -d ' ') entries)"
}

cmd_record() {
  take_gate_args "$@"
  load_findings
  if [ "$NUNP" -gt 0 ]; then
    echo "gate-baseline: $GATE: output the adapter cannot read, so nothing is recorded:" >&2
    awk -F'\t' '$1 == "!" { print "  " $3 }' "$W/norm.tsv" | head -n 10 >&2
    exit 1
  fi
  if [ -e "$BPATH" ] || [ -L "$BPATH" ]; then validate_file "$BPATH" "$BREL" || exit 2; fi
  : >"$W/body"
  if [ -f "$BPATH" ]; then tail -n +2 "$BPATH" | awk -F'\t' -v g="$GATE" '$1 != g' >"$W/body"; fi
  gate_entries "$GATE" >"$W/old.tsv" 2>/dev/null || : >"$W/old.tsv"
  if [ -s "$W/old.tsv" ]; then
    if cmp -s "$W/old.tsv" "$W/cur.tsv"; then echo "gate-baseline: $GATE unchanged ($(wc -l <"$W/cur.tsv" | tr -d ' ') entries)"; exit 0; fi
    echo "gate-baseline: $GATE is already baselined and the findings differ; the file may only shrink. Fix new findings, or run prune to drop fixed ones." >&2
    exit 1
  fi
  awk -F'\t' -v g="$GATE" '{ printf "%s\t%s\t%s\t%s\n", g, $1, $3, $2 }' "$W/cur.tsv" >>"$W/body"
  write_baseline "$W/body"
  echo "gate-baseline: $GATE recorded $(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$W/cur.tsv") finding(s) in $(wc -l <"$W/cur.tsv" | tr -d ' ') entr(ies)"
}

cmd_check() {
  take_gate_args "$@"
  validate_file "$BPATH" "$BREL" || exit 2
  load_findings
  gate_entries "$GATE" >"$W/old.tsv"
  if [ "$NUNP" -gt 0 ]; then
    echo "gate-baseline: $GATE printed output that cannot be baselined (not a finding line):" >&2
    awk -F'\t' '$1 == "!" { print "  " $3 }' "$W/norm.tsv" | head -n 10 >&2
    exit 1
  fi
  if [ "$RC" -ne 0 ] && [ ! -s "$W/norm.tsv" ]; then
    echo "gate-baseline: $GATE exited $RC with no finding it can read; a failed tool is not a clean run." >&2
    exit 1
  fi
  awk -F'\t' -v g="$GATE" -v sum="$W/sum" '
    FILENAME == base { b[$1 "\t" $2] = $3; next }
    FILENAME == cur { c[$1 "\t" $2] = $3; next }
    { k = $1 "\t" $2; o[k] = o[k] "\n    " $3 }
    END {
      for (k in c) if (c[k] > b[k] + 0) { split(k, a, "\t"); printf "NEW %s: %s: %s (found %d, baseline %d)%s\n", g, a[1], a[2], c[k], b[k] + 0, o[k]; nn++ }
      for (k in b) if (b[k] > c[k] + 0) { split(k, a, "\t"); printf "REMOVABLE %s: %s: %s (baseline %d, found %d)\n", g, a[1], a[2], b[k], c[k] + 0; nr++ }
      print nn + 0, nr + 0 > sum
    }' base="$W/old.tsv" cur="$W/cur.tsv" "$W/old.tsv" "$W/cur.tsv" "$W/norm.tsv" >"$W/report" 2>&1
  read -r NNEW NREM <"$W/sum"
  grep -v '^REMOVABLE' "$W/report" | sed 's/^/gate-baseline: /' >&2
  grep '^REMOVABLE' "$W/report" | LC_ALL=C sort | sed 's/^/gate-baseline: /'
  if [ "$NNEW" -gt 0 ]; then
    echo "gate-baseline: $GATE has $NNEW new finding(s) beyond $BREL. Fix them; the baseline may not grow." >&2
    exit 1
  fi
  if [ "$NREM" -gt 0 ]; then
    echo "gate-baseline: $GATE has $NREM removable entr(ies); run prune to drop them."
    [ "$STRICT" -eq 0 ] || exit 1
  fi
  echo "gate-baseline: $GATE ok (no new finding)"
}

cmd_prune() {
  take_gate_args "$@"
  validate_file "$BPATH" "$BREL" || exit 2
  load_findings
  [ "$NUNP" -eq 0 ] || die "$GATE printed output the adapter cannot read; not pruning on a failed run"
  if [ "$RC" -ne 0 ] && [ ! -s "$W/norm.tsv" ]; then die "$GATE exited $RC with no finding it can read; not pruning on a failed run"; fi
  gate_entries "$GATE" >"$W/old.tsv"
  tail -n +2 "$BPATH" | awk -F'\t' -v g="$GATE" '$1 != g' >"$W/body"
  awk -F'\t' -v g="$GATE" -v sum="$W/sum" '
    FILENAME == cur { c[$1 "\t" $2] = $3; next }
    { k = $1 "\t" $2; n = ($3 < c[k] + 0) ? $3 : c[k] + 0
      if (n > 0) printf "%s\t%s\t%d\t%s\n", g, $1, n, $2
      if (n == 0) gone++
      if (n > 0 && n < $3) lowered++ }
    END { print gone + 0, lowered + 0 > sum }' cur="$W/cur.tsv" "$W/cur.tsv" "$W/old.tsv" >>"$W/body"
  write_baseline "$W/body"
  read -r NGONE NLOW <"$W/sum"
  echo "gate-baseline: $GATE pruned: $NGONE entr(ies) removed, $NLOW lowered"
}

cmd_growth() {
  [ $# -ge 1 ] || die "usage: gate-baseline.sh growth <base-ref> [<head-ref>]"
  local base=$1 head=${2:-HEAD}
  command -v git >/dev/null 2>&1 || die "git not found"
  git -C "$ROOT" rev-parse --verify -q "$base^{commit}" >/dev/null || die "$base is not a commit"
  git -C "$ROOT" rev-parse --verify -q "$head^{commit}" >/dev/null || die "$head is not a commit"
  case "$BREL" in /*) die "growth needs a baseline path relative to the project directory, not $BREL" ;; esac
  if ! git -C "$ROOT" show "$head:./$BREL" >"$W/head.txt" 2>/dev/null; then echo "gate-baseline: $BREL does not exist at $head; nothing grew (the gates fail closed without it)"; exit 0; fi
  if ! validate_file "$W/head.txt" "$BREL at $head" 2>"$W/err"; then
    printf 'UNREADABLE %s: %s\n' "$BREL" "$(tr '\n' ' ' <"$W/err")"
    exit 2
  fi
  if git -C "$ROOT" show "$base:./$BREL" >"$W/base.txt" 2>/dev/null; then
    if ! validate_file "$W/base.txt" "$BREL at $base" 2>"$W/err"; then printf 'UNREADABLE %s: %s\n' "$BREL" "$(tr '\n' ' ' <"$W/err")"; exit 2; fi
    INTRO=0
  else
    printf '%s\n' "$HEADER" >"$W/base.txt"; INTRO=1
  fi
  awk -F'\t' -v p="$BREL" -v intro="$INTRO" '
    FILENAME == base { if (FNR > 1) b[$1 "\t" $2 "\t" $4] = $3; next }
    FNR > 1 { k = $1 "\t" $2 "\t" $4
      if ($3 + 0 > b[k] + 0) { printf "WEAKENED %s: the baseline grew: %s %s %s (%d -> %d)\n", p, $1, $2, $4, b[k] + 0, $3; n++ } }
    END { if (n + 0 == 0) exit 0; if (intro) printf "WEAKENED %s: the baseline file is new in this change, so every entry counts as growth\n", p; exit 1 }' base="$W/base.txt" "$W/base.txt" "$W/head.txt" || exit 1
  echo "gate-baseline: the baseline did not grow"
}

# --- run: the project's own gates ---
GATES="lint types workflows dockerfile"
SKIP=
SKIPKIND=
RCV=0
gate_node_ok() {
  command -v pnpm >/dev/null 2>&1 || { SKIP="pnpm not found"; SKIPKIND=cannot; return 1; }
  [ -d "$ROOT/node_modules" ] || { SKIP="dependencies not installed (no node_modules)"; SKIPKIND=cannot; return 1; }
  return 0
}
py_bin() {
  if [ -x "$ROOT/.venv/bin/$1" ]; then echo "$ROOT/.venv/bin/$1"; else command -v "$1" 2>/dev/null || true; fi
}
# gate_run <gate>: runs the gate's tool in the project, output in $W/out.txt, exit code in RCV, adapter in ADAPTER. Returns 1 with SKIP set when the gate does not apply.
gate_run() {
  local g=$1 bin f found
  SKIP=
  SKIPKIND=na
  case "$g" in
    lint)
      if ls "$ROOT"/eslint.config.* >/dev/null 2>&1; then
        gate_node_ok || return 1
        ADAPTER="colon"; (cd "$ROOT" && pnpm exec eslint . -f unix) >"$W/out.txt" 2>&1; RCV=$?
      elif bin=$(py_bin ruff) && [ -n "$bin" ]; then
        ADAPTER="colon"; (cd "$ROOT" && "$bin" check --no-cache --output-format concise .) >"$W/out.txt" 2>&1; RCV=$?
      else SKIP="no eslint.config.* and no ruff"; return 1; fi ;;
    types)
      if [ -f "$ROOT/tsconfig.json" ]; then
        gate_node_ok || return 1
        ADAPTER="tsc"; (cd "$ROOT" && pnpm exec tsc --noEmit --incremental false --pretty false) >"$W/out.txt" 2>&1; RCV=$?
      elif { [ -f "$ROOT/pyrightconfig.json" ] || grep -q 'tool.pyright' "$ROOT/pyproject.toml" 2>/dev/null; } && bin=$(py_bin pyright) && [ -n "$bin" ]; then
        ADAPTER="pyright"; (cd "$ROOT" && "$bin") >"$W/out.txt" 2>&1; RCV=$?
      else SKIP="no tsconfig.json and no configured pyright"; return 1; fi ;;
    workflows|dockerfile)
      [ -f "$ROOT/scripts/check-$g.sh" ] || { SKIP="scripts/check-$g.sh is missing"; return 1; }
      found=0
      if [ "$g" = workflows ]; then
        for f in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml "$ROOT"/.github/actions/*/action.yml "$ROOT"/.github/actions/*/action.yaml "$ROOT"/azure-pipelines.yml "$ROOT"/azure-pipelines/*.yml; do
          if [ -f "$f" ]; then found=1; break; fi
        done
        [ "$found" -eq 1 ] || { SKIP="no workflow or pipeline file"; return 1; }
      elif [ -z "$(find "$ROOT" \( -name node_modules -o -name .git -o -name .venv \) -prune -o -type f \( -name Dockerfile -o -name 'Dockerfile.*' \) -print -quit)" ]; then
        SKIP="no Dockerfile"; return 1
      fi
      ADAPTER="colon"; (cd "$ROOT" && bash "scripts/check-$g.sh") >"$W/out.txt" 2>&1; RCV=$? ;;
  esac
  return 0
}
# gate_has_entries <gate>: the baseline file has at least one entry for the gate.
gate_has_entries() { [ -f "$BPATH" ] && tail -n +2 "$BPATH" | awk -F'\t' -v g="$1" '$1 == g { f = 1 } END { exit !f }'; }

cmd_run() {
  [ $# -eq 1 ] || die "usage: gate-baseline.sh run <record|dry|check|prune>"
  local mode=$1 g worst=0 sub
  case "$mode" in record|dry|check|prune) ;; *) die "unknown run mode '$mode'" ;; esac
  if [ "$mode" = check ] || [ "$mode" = prune ]; then validate_file "$BPATH" "$BREL" || exit 2; fi
  for g in $GATES; do
    if [ "$mode" = prune ] && ! gate_has_entries "$g"; then echo "gate-baseline: $g has no baseline entries; nothing to prune"; continue; fi
    if ! gate_run "$g"; then
      if { [ "$mode" = check ] || [ "$mode" = prune ]; } && { [ "$SKIPKIND" = cannot ] || gate_has_entries "$g"; }; then
        echo "gate-baseline: $g cannot run here ($SKIP)" >&2; worst=1
      else echo "gate-baseline: $g does not apply or was not run ($SKIP)"; fi
      continue
    fi
    if [ "$mode" = dry ]; then
      RC=$RCV; load_findings <"$W/out.txt"
      if [ "$NUNP" -gt 0 ]; then echo "gate-baseline: $g would NOT be recorded: its output has $NUNP line(s) the adapter cannot read"; continue; fi
      echo "gate-baseline: $g would record $(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$W/cur.tsv") finding(s) in $(wc -l <"$W/cur.tsv" | tr -d ' ') entr(ies)"
      continue
    fi
    sub=$mode
    if bash "$0" -C "$ROOT" -f "$BREL" "$sub" "$g" "$ADAPTER" --rc "$RCV" <"$W/out.txt"; then :; else
      worst=1
    fi
  done
  exit "$worst"
}

case "$CMD" in
  validate) cmd_validate ;;
  record) cmd_record "$@" ;;
  check) cmd_check "$@" ;;
  prune) cmd_prune "$@" ;;
  growth) cmd_growth "$@" ;;
  run) cmd_run "$@" ;;
  *) die "unknown command '$CMD'" ;;
esac
