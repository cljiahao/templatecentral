#!/usr/bin/env bash
# Known-defect report: list the older templateCentral template patterns a project still carries. Read-only.
# Usage: defect-report.sh [project-dir]   (default: the current directory)
# Runs every check in defects/*.sh next to this script. There is no version filter: a harness refresh rewrites the recorded
# version, so a filter by version would report clean for source that was never touched. A check whose target file is absent
# counts as "not installed", never as clean.
# Output per match: file:line  <id>  <level>  matches an older template pattern: <description>. Fix: <fix>. Current template: <path>
# A check function prints one file:line per match and exits 0; any other exit status from it is an error and ends the run with exit 2.
# Exit 0 when nothing matched or only "check" level matched, 1 when a "high" level check matched, 2 when it cannot run.
# Never writes inside the project, never edits source. No login, key, token or network.
# Needs bash 3.2+, find, grep, awk.
set -u

NL='
'
MAXBYTES=1048576
die() { echo "defect-report: $1" >&2; exit 2; }

# True when FILE contains the literal PATTERN.
has() { grep -qF -- "$2" "$1"; }

# True when FILE does not contain the literal PATTERN; an unreadable file counts as containing it.
lacks() {
  grep -qF -- "$2" "$1"
  [ $? -eq 1 ]
}

# Print FILE:LINE for the first line of FILE that contains the literal PATTERN.
at() {
  local n
  n=$(grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1)
  echo "$1:${n:-1}"
}

# Print FILE with comments blanked and line numbers kept. Strings stay. .py uses # and triple quotes; everything else uses // and /* */.
strip_comments() {
  local mode=slash
  case "$1" in *.py) mode='hash' ;; esac
  awk -v mode="$mode" '
    BEGIN { st = 0; q = ""; tq = "" }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); d = substr(line, i, 2); t = substr(line, i, 3)
        if (st == 1) {
          if (mode == "slash" && d == "*/") { st = 0; i += 2 }
          else if (mode == "hash" && t == tq) { st = 0; i += 3 }
          else i++
          continue
        }
        if (q != "") {
          out = out c
          if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
          if (c == q) q = ""
          i++
          continue
        }
        if (mode == "slash") {
          if (d == "//") break
          if (d == "/*") { st = 1; out = out " "; i += 2; continue }
          if (c == "\"" || c == "\047" || c == "`") { q = c; out = out c; i++; continue }
        } else {
          if (c == "#") break
          if (t == "\"\"\"" || t == "\047\047\047") { st = 1; tq = t; out = out " "; i += 3; continue }
          if (c == "\"" || c == "\047") { q = c; out = out c; i++; continue }
        }
        out = out c
        i++
      }
      if (q == "\"" || q == "\047") q = ""
      print out
    }' "$1"
}

# Print the number of the first line of TEXT that contains the literal PATTERN, or 1.
line_of() {
  local n
  n=$(printf '%s\n' "$1" | awk -v p="$2" 'index($0, p) { print NR; exit }')
  echo "${n:-1}"
}

# Print every regular file under the project with one of the given base names, pruning dependency and build folders below the root only.
# Files over 1 MB and symlinks are skipped, so nothing outside the project is read.
find_files() {
  local root=$1 name first=1 expr=()
  shift
  for name in "$@"; do
    if [ "$first" -eq 1 ]; then expr=(-name "$name"); first=0; else expr=("${expr[@]}" -o -name "$name"); fi
  done
  find "$root" -mindepth 1 \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build \
    -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o \
    -type f -size -"$((MAXBYTES + 1))"c \( "${expr[@]}" \) -print
}

# Print the files with one of the given base names that the scan skips: symlinks, files over 1 MB, and names with a newline.
find_skipped() {
  local root=$1 name first=1 expr=()
  shift
  for name in "$@"; do
    if [ "$first" -eq 1 ]; then expr=(-name "$name"); first=0; else expr=("${expr[@]}" -o -name "$name"); fi
  done
  find "$root" -mindepth 1 \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build \
    -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o \
    \( -type l -o \( -type f -size +"$MAXBYTES"c \) \) \( "${expr[@]}" \) -print
}

src=${BASH_SOURCE[0]:-$0}
if ! HERE=$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd -P); then die "cannot locate the script directory"; fi
DEFECTS=$HERE/defects
[ -d "$DEFECTS" ] || die "no defects directory at $DEFECTS"

ARG=
for a in "$@"; do
  case "$a" in
    -*) die "unknown option $a (usage: defect-report.sh [project-dir])" ;;
    *) [ -z "$ARG" ] || die "one project directory only"; ARG=$a ;;
  esac
done
ARG=${ARG:-.}
[ -d "$ARG" ] || die "not a directory: $ARG"
if ! P=$(cd -P -- "$ARG" 2>/dev/null && pwd -P); then die "cannot enter $ARG"; fi
case "$P$HERE" in *"$NL"*) die "a path contains a newline" ;; esac

RUN=0
MATCHED=0
ABSENT=0
HIGH=0
SKIPPED=
for def in "$DEFECTS"/*.sh; do
  [ -f "$def" ] || die "no checks found in $DEFECTS"
  # A check file that exits while it loads never reaches the marker, so it is refused.
  # shellcheck source=/dev/null
  loaded=$( . "$def" >/dev/null 2>&1 </dev/null; echo loaded )
  [ "$loaded" = loaded ] || die "check file $def exits or fails while loading"
  id='' level='' names='' template='' desc='' fix=''
  unset -f check
  # shellcheck source=/dev/null
  . "$def" || die "cannot read $def"
  if [ -z "$id" ] || [ -z "$names" ] || [ -z "$template" ] || [ -z "$desc" ] || [ -z "$fix" ]; then die "incomplete check file $def"; fi
  case "$level" in high|check) ;; *) die "bad level '$level' in $def" ;; esac
  command -v check >/dev/null 2>&1 || die "no check function in $def"
  RUN=$((RUN + 1))
  read -r -a namearr <<< "$names"
  if ! found=$(find_files "$P" "${namearr[@]}"); then die "find failed in $P"; fi
  if ! skipped=$(find_skipped "$P" "${namearr[@]}"); then die "find failed in $P"; fi
  list=
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      [ -r "$f" ] || die "cannot read $f (check $id)"
      list="$list$f$NL"
    else
      skipped="$skipped$NL$f"
    fi
  done <<EOF
$found
EOF
  nskip=$(printf '%s\n' "$skipped" | grep -c . || true)
  if [ "$nskip" -gt 0 ]; then SKIPPED="$SKIPPED$skipped$NL"; fi
  if [ -z "$list" ]; then
    [ "$nskip" -eq 0 ] || die "check $id: every candidate file was skipped (symlink, over 1 MB, or a newline in the path), so nothing was scanned"
    ABSENT=$((ABSENT + 1))
    continue
  fi
  hits=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out=$(check "$f")
    rc=$?
    [ "$rc" -eq 0 ] || die "check $id failed on $f (exit status $rc)"
    [ -n "$out" ] || continue
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      hits=$((hits + 1))
      printf '%s  %s  %s  matches an older template pattern: %s. Fix: %s. Current template: %s\n' \
        "${m#"$P"/}" "$id" "$level" "$desc" "$fix" "$template"
    done <<EOF
$out
EOF
  done <<EOF
$list
EOF
  if [ "$hits" -gt 0 ]; then
    MATCHED=$((MATCHED + 1))
    if [ "$level" = high ]; then HIGH=1; fi
  fi
done

NSKIP=$(printf '%s' "$SKIPPED" | grep . | LC_ALL=C sort -u | grep -c . || true)
if [ "$NSKIP" -gt 0 ]; then
  echo "defect-report: $NSKIP candidate file(s) were not scanned (symlink, over 1 MB, or a newline in the path)" >&2
fi
echo "$RUN checks run, $MATCHED matched, $ABSENT not installed. This is a list of known older template patterns, not an audit."
[ "$HIGH" -eq 0 ]
