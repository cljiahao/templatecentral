#!/usr/bin/env bash
# Gate baseline: let a gate fail only on NEW findings. Findings that existed at adoption are recorded once in .claude/gate-baseline.txt and may only shrink.
# Scope is closed: four gates only, lint (eslint or ruff), types (tsc or pyright), check-workflows.sh and check-dockerfile.sh (with its hadolint output).
# Usage: gate-baseline.sh [-C <project-dir>] [-f <baseline-file>] <command> ...
#   record <gate> <adapter> [--tool NAME] [--rc N]   stdin = the gate's output. Writes the gate's findings and one gate line (the tool that ran) into the file, even with zero findings. A recorded gate must match exactly (use prune to shrink).
#   check  <gate> <adapter> [--tool NAME] [--rc N] [--strict-stale]   stdin = the gate's output. Exit 1 on a finding that is not in the file, on a different tool than the recorded one, on output it cannot parse, or on a tool that failed without findings. Prints REMOVABLE for entries that match nothing now.
#   prune  <gate> <adapter> [--tool NAME] [--rc N]   stdin = the gate's output. Removes entries that match nothing and lowers counts; never adds.
#   validate                           Format only: exit 1 when the file is missing, an older version, unsorted, duplicated, has a carriage return or is unparsable. It does not compare with an earlier version; growth does that.
#   growth <base-ref> [<head-ref>]     Exit 1 when the file at head (default HEAD) has an entry or count that the file at <base-ref> lacks, or lacks or changes a gate line the base has; prints WEAKENED/UNREADABLE lines in the format gate-ratchet.sh uses.
#   run <record|dry|check|prune>       Runs the project's lint, type check and seeded check scripts itself and applies the command to each (gates: lint types workflows dockerfile).
#     run check and run prune fail when a recorded gate does not apply now or runs with another tool than the recorded one.
# Adapters (what each gate prints today): colon = "path:line[:col]: message" (eslint -f unix, ruff --output-format concise, check-workflows.sh, check-dockerfile.sh) and the hadolint form "path:line CODE level: message";
#   tsc = "path(line,col): error TSnnnn: message" (tsc --pretty false); pyright = "  path:line:col - error: message (rule)".
# --rc N is the tool's exit code (default 1). A line is a finding first; only a line that is not a finding and matches one known full-line summary is a summary.
# At rc 0 a line that is neither is tool noise and is ignored; at a non-zero rc it fails. A script gate (workflows, dockerfile) needs a finding or a summary line even at rc 0.
# run reads stdout only; stderr counts only when the tool exits non-zero and stdout has no finding line. record replaces a v1 file with a NOTE. Colour, cursor and hyperlink escape sequences and carriage returns are stripped first.
# File format (version 2): line 1 is "# templatecentral gate baseline v2"; then one gate line per recorded gate, "# gate" TAB gate TAB tool, sorted by gate; then one line per entry: gate TAB file TAB count TAB fingerprint, sorted bytewise by gate, file, fingerprint.
# The fingerprint is the message with spaces collapsed, never the line number, so moved code matches and a second copy (count + 1) is new. A renamed file is new. validate, check, prune and growth fail on a version 1 file; record replaces it.
# Exit 0 ok, 1 a finding or growth, 2 a usage error or an unusable file. Nothing is read from .env files; no network. Needs bash 3.2+, POSIX awk, sort; git for growth.
set -u

TAB=$(printf '\t')
CR=$(printf '\r')
NL='
'
HEADER='# templatecentral gate baseline v2'
HEADER_V1='# templatecentral gate baseline v1'
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

# norm <adapter>: stdin to "file TAB fingerprint TAB original line"; a line it cannot read becomes "! TAB TAB line", a summary line "= TAB TAB line".
# A line is tried as a finding first; it is a summary only when it is not a finding and matches one full-line pattern.
norm() {
  LC_ALL=C GB_ROOTS="$ROOT$NL$ROOT_LOGICAL" awk -v ad="$1" '
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
    function is_summary(l) {
      if (l ~ /^[0-9]+ problems?$/) return 1
      if (l ~ /^Found [0-9]+ errors?\.?$/ || l ~ /^Found [0-9]+ errors? in .+$/) return 1
      if (l ~ /^\[\*\] [0-9]+ fixable with the `--fix` option\.$/) return 1
      if (l ~ /^All checks passed!?$/) return 1
      if (l ~ /^check-(workflows|dockerfile): ok \([0-9]+ files?\)$/) return 1
      if (l ~ /^check-dockerfile: no Dockerfile found, nothing to check$/) return 1
      if (l ~ /^WARNING check-dockerfile: .+$/) return 1
      if (l ~ /^check-dockerfile: hadolint reported findings for .+ \(above\)\. Fix them\. .+$/) return 1
      if (ad == "pyright" && (l ~ /^[0-9]+ errors?, [0-9]+ warnings?, [0-9]+ informations?[ ]*$/ || l ~ /^([\/]|[A-Za-z]:[\\\/]).*$/)) return 1
      return 0
    }
    BEGIN { nr = split(ENVIRON["GB_ROOTS"], R, "\n"); esc = sprintf("%c", 27); bel = sprintf("%c", 7) }
    {
      line = $0
      gsub(esc "\\\\", bel, line)
      gsub(esc "\\][^" bel "]*" bel, "", line)
      gsub(esc "\\[[0-?]*[ -/]*[@-~]", "", line)
      sub(/\r$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      found = 0
      if (ad == "tsc") {
        if (line !~ /^[[:space:]]/ && match(line, /\([0-9]+,[0-9]+\): /)) { nf = substr(line, 1, RSTART - 1); nm = substr(line, RSTART + RLENGTH); found = 1 }
      } else if (ad == "pyright") {
        if (match(line, /:[0-9]+:[0-9]+ - [a-z]+: /)) {
          nf = substr(line, 1, RSTART - 1); sub(/^[[:space:]]+/, "", nf)
          nm = substr(line, RSTART + index(substr(line, RSTART), " - ") + 2); found = 1
        }
      } else {
        if (match(line, /:[0-9]+ [A-Z]+[0-9]+ (error|warning|info|style): /)) {
          nf = substr(line, 1, RSTART - 1); nm = substr(line, RSTART + 1); sub(/^[0-9]+ /, "", nm); found = 1
        } else if (match(line, /:[0-9]+(:[0-9]+)?: /)) { nf = substr(line, 1, RSTART - 1); nm = substr(line, RSTART + RLENGTH); found = 1 }
      }
      if (found) { flush(); pf = nf; pm = nm; po = line; have = 1; next }
      if (is_summary(line)) { flush(); printf "=\t\t%s\n", line; next }
      if (ad != "colon" && line ~ /^[[:space:]]/ && have) { pm = pm " " line; po = po " " collapse(line); next }
      flush()
      printf "!\t\t%s\n", line
    }
    END { flush() }'
}

# file_gl <file>: the gate lines of a baseline file as "gate TAB tool". file_entries <file>: its entry lines.
file_gl() { tail -n +2 "$1" 2>/dev/null | awk -F'\t' '$1 == "# gate" { print $2 "\t" $3 }'; }
file_entries() { tail -n +2 "$1" 2>/dev/null | awk -F'\t' '$1 != "# gate"'; }

# validate_file <path> <label>: prints each problem, returns 1 when there is any.
validate_file() {
  local f=$1 label=$2 bad=0 out first
  if [ -L "$f" ]; then echo "gate-baseline: $label is a symlink" >&2; return 1; fi
  if [ ! -f "$f" ]; then echo "gate-baseline: $label is missing" >&2; return 1; fi
  first=$(head -n 1 "$f")
  if [ "$first" = "$HEADER_V1" ]; then echo "gate-baseline: $label is an older format (v1). Record it again: run harness-refresh.sh --apply --gate-baseline on the project." >&2; return 1; fi
  if [ "$first" != "$HEADER" ]; then echo "gate-baseline: $label does not start with the line: $HEADER" >&2; return 1; fi
  if [ -n "$(tail -c 1 "$f")" ]; then echo "gate-baseline: $label does not end in a newline" >&2; bad=1; fi
  out=$(tail -n +2 "$f" | LC_ALL=C awk -F'\t' -v cr="$CR" '
    index($0, cr) { printf "line %d: carriage return\n", NR + 1; next }
    $1 == "# gate" {
      if (NF != 3 || $2 !~ /^[a-z0-9-]+$/ || $3 !~ /^[a-z0-9-]+$/) { printf "line %d: bad gate line\n", NR + 1; next }
      if (entries) printf "line %d: gate line after entries\n", NR + 1
      if (prev != "" && $2 <= prev) printf "line %d: gate lines are not sorted or one gate has two\n", NR + 1
      prev = $2; G[$2] = 1; next
    }
    {
      entries = 1
      if (NF != 4) { printf "line %d: expected 4 tab-separated fields\n", NR + 1; next }
      if ($1 !~ /^[a-z0-9-]+$/) printf "line %d: bad gate name\n", NR + 1
      else if (!($1 in G)) printf "line %d: gate %s has entries but no gate line\n", NR + 1, $1
      if ($2 == "" || $4 == "") printf "line %d: empty file or fingerprint\n", NR + 1
      if ($3 !~ /^[1-9][0-9]*$/) printf "line %d: count is not a positive integer\n", NR + 1
    }')
  if [ -n "$out" ]; then printf 'gate-baseline: %s: %s\n' "$label" "$out" >&2; bad=1; fi
  if [ "$bad" -eq 0 ] && ! file_entries "$f" | LC_ALL=C sort -c -u -t "$TAB" -k1,1 -k2,2 -k4 2>/dev/null; then
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
  file_entries "$BPATH" | awk -F'\t' -v g="$1" '$1 == g { print $2 "\t" $4 "\t" $3 }' | LC_ALL=C sort -t "$TAB" -k1,1 -k2,2
}
# gate_tool <gate>: the tool recorded for the gate, empty when the gate is not recorded.
gate_tool() { file_gl "$BPATH" | awk -F'\t' -v g="$1" '$1 == g { print $2 }'; }
# write_baseline <gate-lines-file> <body-file>: header, sorted gate lines and sorted entries replace the file.
write_baseline() {
  local tmp d
  d=$(dirname -- "$BPATH")
  [ ! -L "$BPATH" ] || die "$BREL is a symlink; refusing to write it"
  mkdir -p -- "$d" || die "cannot create $d"
  tmp=$(mktemp "$d/.gate-baseline.XXXXXX") || die "cannot write in $d"
  if ! { {
    printf '%s\n' "$HEADER"
    LC_ALL=C sort -t "$TAB" -k1,1 "$1" | awk -F'\t' '{ printf "# gate\t%s\t%s\n", $1, $2 }'
    LC_ALL=C sort -t "$TAB" -k1,1 -k2,2 -k4 "$2"
  } >"$tmp" && mv -f -- "$tmp" "$BPATH"; }; then rm -f -- "$tmp"; die "cannot write $BREL"; fi
}

RC=1
STRICT=0
NOSIG=0
GATE=
ADAPTER=
TOOL=
# take_gate_args <args...>: gate, adapter and options of record, check and prune.
take_gate_args() {
  [ $# -ge 2 ] || die "usage: gate-baseline.sh $CMD <gate> <adapter> [--tool NAME] [--rc N]"
  GATE=$1; ADAPTER=$2; shift 2
  TOOL=$ADAPTER
  valid_gate "$GATE" || die "bad gate name '$GATE'"
  valid_adapter "$ADAPTER" || die "unknown adapter '$ADAPTER' (colon, tsc, pyright)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --rc) shift; [ $# -gt 0 ] || die "--rc needs a number"; RC=$1; case "$RC" in ''|*[!0-9]*) die "--rc needs a number" ;; esac ;;
      --tool) shift; [ $# -gt 0 ] || die "--tool needs a name"; TOOL=$1; valid_gate "$TOOL" || die "bad tool name '$TOOL'" ;;
      --strict-stale) STRICT=1 ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
}
# load_findings: stdin through the adapter into $W/norm.tsv and $W/cur.tsv. At rc 0 a line that is not a finding is tool noise and is dropped.
# A script gate (tool "script") always prints a finding or a summary line, so none of either means the script did not run: NOSIG is 1.
load_findings() {
  local nsum nfind
  norm "$ADAPTER" >"$W/norm.raw"
  nsum=$(awk -F'\t' '$1 == "=" { n++ } END { print n + 0 }' "$W/norm.raw")
  if [ "$RC" -eq 0 ]; then awk -F'\t' '$1 != "!" && $1 != "="' "$W/norm.raw" >"$W/norm.tsv"; else awk -F'\t' '$1 != "="' "$W/norm.raw" >"$W/norm.tsv"; fi
  counts "$W/norm.tsv" >"$W/cur.tsv"
  NUNP=$(awk -F'\t' '$1 == "!" { n++ } END { print n + 0 }' "$W/norm.tsv")
  nfind=$(awk -F'\t' '$1 != "!" { n++ } END { print n + 0 }' "$W/norm.tsv")
  NOSIG=0
  if [ "$TOOL" = script ] && [ $((nfind + nsum)) -eq 0 ]; then NOSIG=1; fi
}
# require_same_tool: exit 1 when the gate was recorded with another tool than the one that ran now.
require_same_tool() {
  local rtool
  rtool=$(gate_tool "$GATE")
  if [ -n "$rtool" ] && [ "$rtool" != "$TOOL" ]; then
    echo "gate-baseline: $GATE was recorded with the tool '$rtool' but ran with '$TOOL'. A change may have switched the gate off; restore the tool, or record the gate again by hand." >&2
    exit 1
  fi
}

cmd_validate() {
  validate_file "$BPATH" "$BREL" || exit 1
  echo "gate-baseline: $BREL ok ($(file_entries "$BPATH" | wc -l | tr -d ' ') entries, $(file_gl "$BPATH" | wc -l | tr -d ' ') gates)"
}

cmd_record() {
  take_gate_args "$@"
  load_findings
  if [ "$NUNP" -gt 0 ]; then
    echo "gate-baseline: $GATE: output the adapter cannot read, so nothing is recorded:" >&2
    awk -F'\t' '$1 == "!" { print "  " $3 }' "$W/norm.tsv" | head -n 10 >&2
    exit 1
  fi
  if [ "$NOSIG" -eq 1 ]; then echo "gate-baseline: $GATE: a script gate printed no finding and no summary line, so it did not run; nothing is recorded." >&2; exit 1; fi
  if [ "$RC" -ne 0 ] && [ ! -s "$W/norm.tsv" ]; then
    echo "gate-baseline: $GATE exited $RC with no finding it can read; a failed tool is not a clean run, so nothing is recorded." >&2
    exit 1
  fi
  local otool='' haveold=0
  if [ -f "$BPATH" ] && [ ! -L "$BPATH" ] && [ "$(head -n 1 "$BPATH")" = "$HEADER_V1" ]; then
    echo "gate-baseline: NOTE: $BREL is an older v1 file; it is replaced by a v2 file, and each gate is recorded again by its own run." >&2
  elif [ -e "$BPATH" ] || [ -L "$BPATH" ]; then
    validate_file "$BPATH" "$BREL" || exit 2
    haveold=1
  fi
  : >"$W/body"; : >"$W/gl"
  if [ "$haveold" -eq 1 ]; then
    file_entries "$BPATH" | awk -F'\t' -v g="$GATE" '$1 != g' >"$W/body"
    file_gl "$BPATH" | awk -F'\t' -v g="$GATE" '$1 != g' >"$W/gl"
    otool=$(gate_tool "$GATE")
  fi
  if [ -n "$otool" ]; then
    if [ "$otool" != "$TOOL" ]; then
      echo "gate-baseline: $GATE is already baselined with the tool '$otool', not '$TOOL'; the file may only shrink." >&2
      exit 1
    fi
    gate_entries "$GATE" >"$W/old.tsv"
    if cmp -s "$W/old.tsv" "$W/cur.tsv"; then echo "gate-baseline: $GATE unchanged ($(wc -l <"$W/cur.tsv" | tr -d ' ') entries)"; exit 0; fi
    echo "gate-baseline: $GATE is already baselined and the findings differ; the file may only shrink. Fix new findings, or run prune to drop fixed ones." >&2
    exit 1
  fi
  printf '%s\t%s\n' "$GATE" "$TOOL" >>"$W/gl"
  awk -F'\t' -v g="$GATE" '{ printf "%s\t%s\t%s\t%s\n", g, $1, $3, $2 }' "$W/cur.tsv" >>"$W/body"
  write_baseline "$W/gl" "$W/body"
  echo "gate-baseline: $GATE recorded $(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$W/cur.tsv") finding(s) in $(wc -l <"$W/cur.tsv" | tr -d ' ') entr(ies)"
}

cmd_check() {
  take_gate_args "$@"
  validate_file "$BPATH" "$BREL" || exit 2
  require_same_tool
  load_findings
  gate_entries "$GATE" >"$W/old.tsv"
  if [ "$NUNP" -gt 0 ]; then
    echo "gate-baseline: $GATE printed output that cannot be baselined (not a finding line):" >&2
    awk -F'\t' '$1 == "!" { print "  " $3 }' "$W/norm.tsv" | head -n 10 >&2
    exit 1
  fi
  if [ "$NOSIG" -eq 1 ]; then
    echo "gate-baseline: $GATE: a script gate printed no finding and no summary line; the script did not run." >&2
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
  [ -n "$(gate_tool "$GATE")" ] || die "$GATE is not recorded in $BREL; nothing to prune"
  require_same_tool
  load_findings
  [ "$NUNP" -eq 0 ] || die "$GATE printed output the adapter cannot read; not pruning on a failed run"
  [ "$NOSIG" -eq 0 ] || die "$GATE: a script gate printed no finding and no summary line; the script did not run; not pruning"
  if [ "$RC" -ne 0 ] && [ ! -s "$W/norm.tsv" ]; then die "$GATE exited $RC with no finding it can read; not pruning on a failed run"; fi
  gate_entries "$GATE" >"$W/old.tsv"
  file_entries "$BPATH" | awk -F'\t' -v g="$GATE" '$1 != g' >"$W/body"
  file_gl "$BPATH" >"$W/gl"
  awk -F'\t' -v g="$GATE" -v sum="$W/sum" '
    FILENAME == cur { c[$1 "\t" $2] = $3; next }
    { k = $1 "\t" $2; n = ($3 < c[k] + 0) ? $3 : c[k] + 0
      if (n > 0) printf "%s\t%s\t%d\t%s\n", g, $1, n, $2
      if (n == 0) gone++
      if (n > 0 && n < $3) lowered++ }
    END { print gone + 0, lowered + 0 > sum }' cur="$W/cur.tsv" "$W/cur.tsv" "$W/old.tsv" >>"$W/body"
  write_baseline "$W/gl" "$W/body"
  read -r NGONE NLOW <"$W/sum"
  echo "gate-baseline: $GATE pruned: $NGONE entr(ies) removed, $NLOW lowered"
}

cmd_growth() {
  [ $# -ge 1 ] || die "usage: gate-baseline.sh growth <base-ref> [<head-ref>]"
  local base=$1 head=${2:-HEAD} top
  command -v git >/dev/null 2>&1 || die "git not found"
  case "$BREL" in
    /*) die "growth needs a baseline path relative to the project directory, not $BREL" ;;
    ..|../*|*/..|*/../*) die "growth needs a baseline path inside the project directory, not $BREL" ;;
  esac
  git -C "$ROOT" rev-parse --verify -q "$base^{commit}" >/dev/null || die "$base is not a commit"
  git -C "$ROOT" rev-parse --verify -q "$head^{commit}" >/dev/null || die "$head is not a commit"
  if ! git -C "$ROOT" show "$head:./$BREL" >"$W/head.txt" 2>/dev/null; then
    if ! git -C "$ROOT" show "$base:./$BREL" >/dev/null 2>&1 && [ ! -e "$BPATH" ]; then
      top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || top=
      if [ -n "$top" ] && [ -f "$top/.claude/gate-baseline.txt" ] && [ "$top/.claude/gate-baseline.txt" != "$BPATH" ]; then
        die "$BREL is missing here, but $top/.claude/gate-baseline.txt exists: the project directory is probably wrong"
      fi
    fi
    echo "gate-baseline: $BREL does not exist at $head; nothing grew (the gates fail closed without it)"; exit 0
  fi
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
    FILENAME == base { if (FNR > 1) { if ($1 == "# gate") bg[$2] = $3; else b[$1 "\t" $2 "\t" $4] = $3 } next }
    FNR > 1 {
      if ($1 == "# gate") { hg[$2] = $3; next }
      k = $1 "\t" $2 "\t" $4
      if ($3 + 0 > b[k] + 0) { printf "WEAKENED %s: the baseline grew: %s %s %s (%d -> %d)\n", p, $1, $2, $4, b[k] + 0, $3; n++ }
    }
    END {
      for (g in bg) {
        if (!(g in hg)) { printf "WEAKENED %s: the gate line for %s (tool %s) was removed\n", p, g, bg[g]; n++ }
        else if (hg[g] != bg[g]) { printf "WEAKENED %s: the tool of gate %s changed: %s -> %s\n", p, g, bg[g], hg[g]; n++ }
      }
      if (n + 0 == 0) exit 0
      if (intro) printf "WEAKENED %s: the baseline file is new in this change, so every entry counts as growth\n", p
      exit 1
    }' base="$W/base.txt" "$W/base.txt" "$W/head.txt" || exit 1
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
# gate_run <gate>: runs the gate's tool in the project, output in $W/out.txt, exit code in RCV, adapter in ADAPTER, tool name in TOOL.
# Returns 1 with SKIP set when it cannot run: SKIPKIND is na when the gate does not apply to the project (decided from the files on disk), cannot when the project has it but the tool is unavailable.
gate_run() {
  local g=$1 bin f found
  SKIP=
  SKIPKIND=na
  : >"$W/err.txt"
  case "$g" in
    lint)
      if ls "$ROOT"/eslint.config.* >/dev/null 2>&1; then
        gate_node_ok || return 1
        ADAPTER="colon"; TOOL=eslint; (cd "$ROOT" && pnpm exec eslint . -f unix) >"$W/out.txt" 2>"$W/err.txt"; RCV=$?
      elif bin=$(py_bin ruff) && [ -n "$bin" ]; then
        ADAPTER="colon"; TOOL=ruff; (cd "$ROOT" && "$bin" check --no-cache --output-format concise .) >"$W/out.txt" 2>"$W/err.txt"; RCV=$?
      else SKIP="no eslint.config.* and no ruff"; return 1; fi ;;
    types)
      if [ -f "$ROOT/tsconfig.json" ]; then
        gate_node_ok || return 1
        ADAPTER="tsc"; TOOL=tsc; (cd "$ROOT" && pnpm exec tsc --noEmit --incremental false --pretty false) >"$W/out.txt" 2>"$W/err.txt"; RCV=$?
      elif [ -f "$ROOT/pyrightconfig.json" ] || grep -q 'tool.pyright' "$ROOT/pyproject.toml" 2>/dev/null; then
        bin=$(py_bin pyright)
        [ -n "$bin" ] || { SKIP="pyright is configured but not installed"; SKIPKIND=cannot; return 1; }
        ADAPTER="pyright"; TOOL=pyright; (cd "$ROOT" && "$bin") >"$W/out.txt" 2>"$W/err.txt"; RCV=$?
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
      ADAPTER="colon"; TOOL=script; (cd "$ROOT" && bash "scripts/check-$g.sh") >"$W/out.txt" 2>&1; RCV=$? ;;
  esac
  return 0
}
# gate_recorded <gate>: the baseline file has a gate line for the gate.
gate_recorded() { [ -f "$BPATH" ] && [ -n "$(gate_tool "$1")" ]; }

# merge_stderr: when the tool exited non-zero and its stdout holds no finding line, its stderr is the evidence and is appended to the output. Otherwise stderr is dropped.
merge_stderr() {
  [ "$RCV" -ne 0 ] || return 0
  [ -s "$W/err.txt" ] || return 0
  if [ "$(norm "$ADAPTER" <"$W/out.txt" | awk -F'\t' '$1 != "!" && $1 != "=" { n++ } END { print n + 0 }')" -eq 0 ]; then cat "$W/err.txt" >>"$W/out.txt"; fi
}

cmd_run() {
  [ $# -eq 1 ] || die "usage: gate-baseline.sh run <record|dry|check|prune>"
  local mode=$1 g worst=0 rec
  case "$mode" in record|dry|check|prune) ;; *) die "unknown run mode '$mode'" ;; esac
  if [ "$mode" = check ] || [ "$mode" = prune ]; then validate_file "$BPATH" "$BREL" || exit 2; fi
  for g in $GATES; do
    rec=0
    if gate_recorded "$g"; then rec=1; fi
    if [ "$mode" = prune ] && [ "$rec" -eq 0 ]; then echo "gate-baseline: $g is not recorded; nothing to prune"; continue; fi
    if ! gate_run "$g"; then
      if { [ "$mode" = check ] || [ "$mode" = prune ]; } && { [ "$SKIPKIND" = cannot ] || [ "$rec" -eq 1 ]; }; then
        echo "gate-baseline: $g cannot run here ($SKIP)" >&2; worst=1
      else echo "gate-baseline: $g does not apply or was not run ($SKIP)"; fi
      continue
    fi
    merge_stderr
    if [ "$mode" = dry ]; then
      RC=$RCV; load_findings <"$W/out.txt"
      if [ "$NUNP" -gt 0 ]; then echo "gate-baseline: $g would NOT be recorded: its output has $NUNP line(s) the adapter cannot read"; continue; fi
      if [ "$NOSIG" -eq 1 ]; then echo "gate-baseline: $g would NOT be recorded: the script printed no finding and no summary line"; continue; fi
      if [ "$RC" -ne 0 ] && [ ! -s "$W/norm.tsv" ]; then echo "gate-baseline: $g would NOT be recorded: it exited $RC with no finding it can read"; continue; fi
      echo "gate-baseline: $g would record $(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$W/cur.tsv") finding(s) in $(wc -l <"$W/cur.tsv" | tr -d ' ') entr(ies)"
      continue
    fi
    if bash "$0" -C "$ROOT" -f "$BREL" "$mode" "$g" "$ADAPTER" --tool "$TOOL" --rc "$RCV" <"$W/out.txt"; then :; else
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
