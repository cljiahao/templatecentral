#!/usr/bin/env bash
# Known-defect report: list the older templateCentral template patterns a project still carries. Read-only.
# Usage: defect-report.sh [project-dir]   (default: the current directory)
# Runs every check in defects/*.sh next to this script. There is no version filter: a harness refresh rewrites the recorded
# version, so a filter by version would report clean for source that was never touched. A check whose target file is absent
# counts as "not installed", never as clean.
# Output per match: file:line  <id>  <level>  matches an older template pattern: <description>. Fix: <fix>. Current template: <path>
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

# Print every regular file under the project with one of the given base names, pruning dependency and build folders.
# Files over 1 MB and symlinks are skipped, so nothing outside the project is read.
find_files() {
  local root=$1 name first=1 expr=()
  shift
  for name in "$@"; do
    if [ "$first" -eq 1 ]; then expr=(-name "$name"); first=0; else expr=("${expr[@]}" -o -name "$name"); fi
  done
  find "$root" \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build \
    -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o \
    -type f -size -"$((MAXBYTES + 1))"c \( "${expr[@]}" \) -print
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
for def in "$DEFECTS"/*.sh; do
  [ -f "$def" ] || die "no checks found in $DEFECTS"
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
  if [ -z "$found" ]; then
    ABSENT=$((ABSENT + 1))
    continue
  fi
  hits=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out=$(check "$f")
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
$found
EOF
  if [ "$hits" -gt 0 ]; then
    MATCHED=$((MATCHED + 1))
    if [ "$level" = high ]; then HIGH=1; fi
  fi
done

echo "$RUN checks run, $MATCHED matched, $ABSENT not installed. This is a list of known older template patterns, not an audit."
[ "$HIGH" -eq 0 ]
