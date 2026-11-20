#!/usr/bin/env bash
# Known-defect report: list the older templateCentral template patterns a project still carries. Read-only.
# Usage: defect-report.sh [project-dir]   (default: the current directory)
# Runs every check in defects/*.sh next to this script. There is no version filter: a harness refresh rewrites the recorded
# version, so a filter by version would report clean for source that was never touched. A check finds its files by content:
# names are file-name globs (for example *.ts) and content is the literal text a candidate must contain, so a renamed file or
# function is still found. Test files, *.d.ts and files in test, tests, __tests__ or __mocks__ folders are not candidates.
# A check with no matching file counts as "no matching file found", never as clean.
# A candidate that is skipped (symlink, over 1 MB, newline in the path) is counted on stderr. When a skipped file over 1 MB holds the
# check's content text and nothing else was scanned, the run exits 2, because that file may be the match.
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

# Print FILE with comments blanked and line numbers kept. Strings stay, triple-quoted ones too. .py uses #; everything else uses // and /* */.
# Limits: nested template literals, regex literals and Python docstrings count as strings, so text in them is not blanked.
strip_comments() {
  local mode=slash
  case "$1" in *.py) mode='hash' ;; esac
  LC_ALL=C awk -v mode="$mode" '
    BEGIN { st = 0; q = "" }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); d = substr(line, i, 2); t = substr(line, i, 3)
        if (st == 1) {
          if (d == "*/") { st = 0; i += 2 } else i++
          continue
        }
        if (q != "") {
          if (length(q) == 3 && t == q) { out = out t; q = ""; i += 3; continue }
          out = out c
          if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
          if (length(q) == 1 && c == q) q = ""
          i++
          continue
        }
        if (mode == "slash") {
          if (d == "//") break
          if (d == "/*") { st = 1; out = out " "; i += 2; continue }
          if (c == "\"" || c == "\047" || c == "`") { q = c; out = out c; i++; continue }
        } else {
          if (c == "#") break
          if (t == "\"\"\"" || t == "\047\047\047") { q = t; out = out t; i += 3; continue }
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

# True when the path (relative to the project root) is a test, mock or type-declaration file, which no check scans.
is_test_file() {
  case "${1#"$P"/}" in
    *.test.*|*.spec.*|*.d.ts|test_*.py|*_test.py|*/test_*.py|conftest.py|*/conftest.py) return 0 ;;
    test/*|tests/*|__tests__/*|__mocks__/*|*/test/*|*/tests/*|*/__tests__/*|*/__mocks__/*) return 0 ;;
  esac
  return 1
}

# True when the project source declares a unique index ("unique: true", also quoted); used by the checks that matter only then.
UNIQ_RE='(^|[^A-Za-z0-9_])["'"'"']?unique["'"'"']?[[:space:]]*:[[:space:]]*true'
has_unique_index() {
  local f rc
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_test_file "$f" && continue
    grep -qE -- "$UNIQ_RE" "$f"
    rc=$?
    [ "$rc" -ne 2 ] || die "cannot read $f"
    [ "$rc" -eq 0 ] || continue
    if strip_comments "$f" | grep -qE -- "$UNIQ_RE"; then return 0; fi
  done <<EOF
$(find_files "$P" '*.ts' '*.js' '*.mjs' '*.cjs')
EOF
  return 1
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

# Print each symlink below the root that points at a directory outside the project. It is not followed, so what is behind it is not scanned.
find_dirlinks() {
  local root=$1 l real
  find "$root" -mindepth 1 \( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build \
    -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o -type l -print | while IFS= read -r l; do
    [ -d "$l" ] || continue
    real=$(cd -P -- "$l" 2>/dev/null && pwd -P) || continue
    case "$real/" in "$root"/*) continue ;; esac
    echo "$l"
  done
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
if ! DIRLINKS=$(find_dirlinks "$P"); then die "find failed in $P"; fi
SKIPPED=$DIRLINKS$NL
for def in "$DEFECTS"/*.sh; do
  [ -f "$def" ] || die "no checks found in $DEFECTS"
  # A check file that exits while it loads never reaches the marker, so it is refused.
  # shellcheck source=/dev/null
  loaded=$( . "$def" >/dev/null 2>&1 </dev/null; echo loaded )
  [ "$loaded" = loaded ] || die "check file $def exits or fails while loading"
  id='' level='' names='' content='' template='' desc='' fix=''
  unset -f check
  # shellcheck source=/dev/null
  . "$def" || die "cannot read $def"
  if [ -z "$id" ] || [ -z "$names" ] || [ -z "$template" ] || [ -z "$desc" ] || [ -z "$fix" ]; then die "incomplete check file $def"; fi
  case "$level" in high|check) ;; *) die "bad level '$level' in $def" ;; esac
  command -v check >/dev/null 2>&1 || die "no check function in $def"
  RUN=$((RUN + 1))
  read -r -a namearr <<< "$names"
  contentargs=()
  for w in $content; do contentargs=("${contentargs[@]+"${contentargs[@]}"}" -e "$w"); done
  if ! found=$(find_files "$P" "${namearr[@]}"); then die "find failed in $P"; fi
  if ! skipped=$(find_skipped "$P" "${namearr[@]}"); then die "find failed in $P"; fi
  list=
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      [ -r "$f" ] || die "cannot read $f (check $id)"
      if is_test_file "$f"; then continue; fi
      if [ -n "$content" ]; then
        grep -qF "${contentargs[@]}" -- "$f"
        rc=$?
        [ "$rc" -ne 2 ] || die "cannot read $f (check $id)"
        [ "$rc" -eq 0 ] || continue
      fi
      list="$list$f$NL"
    else
      skipped="$skipped$NL$f"
    fi
  done <<EOF
$found
EOF
  nskip=$(printf '%s\n' "$skipped" | grep -c . || true)
  if [ "$nskip" -gt 0 ]; then SKIPPED="$SKIPPED$skipped$NL"; fi
  bigmatch=0
  if [ "$nskip" -gt 0 ] && [ -n "$content" ]; then
    while IFS= read -r s; do
      if [ -f "$s" ] && [ ! -L "$s" ] && grep -qF "${contentargs[@]}" -- "$s"; then bigmatch=1; fi
    done <<EOF
$skipped
EOF
  fi
  if [ -z "$list" ]; then
    [ "$nskip" -eq 0 ] || { [ -n "$content" ] && [ "$bigmatch" -eq 0 ]; } || die "check $id: every candidate file was skipped (symlink, over 1 MB, or a newline in the path), so nothing was scanned"
    [ -z "$DIRLINKS" ] || die "check $id: a symlinked directory below the project is not followed, so its file may be behind it ($(printf '%s' "$DIRLINKS" | head -n 1))"
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
echo "$RUN checks run, $MATCHED matched, $ABSENT with no matching file found. This is a list of known older template patterns, not an audit."
[ "$HIGH" -eq 0 ]
