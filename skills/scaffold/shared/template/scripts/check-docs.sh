#!/usr/bin/env bash
# Docs check: check-docs.sh [markdown-file ...]. Offline; exits 1 with one `file:line: message` per finding (max 20).
# Checks README.md, AGENTS.md, docs/**/*.md and boundary READMEs: relative links and backticked repo paths must exist,
# and a README must not carry a `## Contents` heading or a list naming every child of its own folder.
# With arguments only those files are checked (pre-commit); without, the whole project (pre-push, CI).
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.." || exit 2

CAP=20
GENERATED='node_modules dist build .next coverage .venv venv __pycache__ .pytest_cache .ruff_cache .mypy_cache .pyright htmlcov .turbo .stryker-tmp .mutmut-cache .git'
SKIPPED_DIRS='.claude .github .azuredevops azure-pipelines .lefthook secrets .secrets'
EXTS='md|mdx|ts|tsx|js|jsx|mjs|cjs|py|json|yml|yaml|toml|sh|css|scss|sql|html|txt|env|example|ini|cfg|lock|svg|png|jpg|gif|ico|prisma'

findings=$(mktemp "${TMPDIR:-/tmp}/check-docs.XXXXXX") || exit 2
cands=$(mktemp "${TMPDIR:-/tmp}/check-docs-cands.XXXXXX") || { rm -f "$findings"; exit 2; }
trap 'rm -f "$findings" "$cands"' EXIT

in_git=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1

# True when any path segment is a generated folder, or git ignores the path.
is_generated() {
  local seg rest=$1
  while [ -n "$rest" ]; do
    seg=${rest%%/*}
    case " $GENERATED " in *" $seg "*) return 0 ;; esac
    case "$rest" in */*) rest=${rest#*/} ;; *) rest= ;; esac
  done
  [ "$in_git" -eq 1 ] && git check-ignore -q -- "$1" 2>/dev/null
}

# True when a project-relative path sits in a folder the harness owns or the build generates.
is_skipped_dir() {
  local seg rest=$1
  while [ -n "$rest" ]; do
    seg=${rest%%/*}
    case " $GENERATED $SKIPPED_DIRS " in *" $seg "*) return 0 ;; esac
    case "$rest" in */*) rest=${rest#*/} ;; *) rest= ;; esac
  done
  return 1
}

# True for a file this check reads: root README/AGENTS, docs/**/*.md, or a README.md below the root.
is_target() {
  case "$1" in
    README.md | AGENTS.md) return 0 ;;
    docs/*.md) ;;
    */README.md) ;;
    *) return 1 ;;
  esac
  is_skipped_dir "${1%/*}" && return 1
  return 0
}

# Lists every target file of the project, one per line.
list_all() {
  if [ "$in_git" -eq 1 ]; then
    git ls-files --cached --others --exclude-standard | LC_ALL=C sort -u
  else
    find . \( -name node_modules -o -name .git -o -name .venv -o -name dist -o -name build -o -name .next \) -prune -o -type f \( -name '*.md' \) -print | sed 's|^\./||' | LC_ALL=C sort
  fi
}

# Emits `line<TAB>kind<TAB>target` for each link, backticked path and Contents heading outside code fences.
scan() {
  awk -v want_heading="$2" '
    function strip_spans(s,   out) {
      out = s
      gsub(/``[^`]*``/, "", out)
      return out
    }
    function emit(kind, t,   b) {
      printf "%d\t%s\t%s\n", NR, kind, t
      if (isitem && (kind == "link" || kind == "span")) {
        b = t
        sub(/#.*$/, "", b)
        sub(/\/$/, "", b)
        sub(/^.*\//, "", b)
        printf "%d\titemname\t%s\n", NR, b
      }
    }
    function scan_links(s,   p, j, c, depth, t) {
      while ((p = index(s, "](")) > 0) {
        s = substr(s, p + 2)
        if (substr(s, 1, 1) == "<") {
          j = index(s, ">")
          if (j == 0) continue
          t = substr(s, 2, j - 2)
        } else {
          depth = 0
          t = ""
          for (j = 1; j <= length(s); j++) {
            c = substr(s, j, 1)
            if (c == "(") depth++
            else if (c == ")") { if (depth == 0) break; depth-- }
            else if (c == " " || c == "\t") break
            t = t c
          }
        }
        emit("link", t)
      }
    }
    function scan_spans(s,   i, j, rest, t) {
      rest = strip_spans(s)
      while ((i = index(rest, "`")) > 0) {
        rest = substr(rest, i + 1)
        j = index(rest, "`")
        if (j == 0) break
        t = substr(rest, 1, j - 1)
        rest = substr(rest, j + 1)
        emit("span", t)
      }
    }
    BEGIN { fence = ""; comment = 0 }
    {
      line = $0
      if (fence == "") {
        if (match(line, /^[ \t]*(```+|~~~+)/)) {
          fence = substr(line, RSTART, RLENGTH)
          gsub(/^[ \t]+/, "", fence)
          fence = substr(fence, 1, 1)
          next
        }
      } else {
        t = line
        gsub(/^[ \t]+/, "", t)
        if (substr(t, 1, 3) == fence fence fence) fence = ""
        next
      }
      if (comment) {
        if (index(line, "-->")) { comment = 0; line = substr(line, index(line, "-->") + 3) } else next
      }
      while ((i = index(line, "<!--")) > 0) {
        j = index(substr(line, i), "-->")
        if (j > 0) line = substr(line, 1, i - 1) substr(line, i + j + 2)
        else { line = substr(line, 1, i - 1); comment = 1 }
      }
      if (want_heading == "1" && tolower(line) ~ /^#+[ \t]+contents[ \t]*$/) emit("heading", "")
      if (line ~ /^[ \t]*\[[^]]+\]:[ \t]*[^ \t]/) {
        t = line
        sub(/^[ \t]*\[[^]]+\]:[ \t]*/, "", t)
        sub(/[ \t].*$/, "", t)
        gsub(/^<|>$/, "", t)
        emit("link", t)
      }
      isitem = (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/)
      nospan = line
      gsub(/`[^`]*`/, "", nospan)
      scan_links(nospan)
      scan_spans(line)
    }
  ' "$1"
}

# Prints a finding as file:line: message.
report() { printf '%s:%s: %s\n' "$1" "$2" "$3" >> "$findings"; }

# True when the target exists relative to the file's folder (or the project root for a leading slash).
exists_as() {
  local file=$1 target=$2 dir
  dir=${file%/*}
  [ "$dir" = "$file" ] && dir=.
  case "$target" in
    /*) [ -e ".$target" ] && return 0 ;;
    *) [ -e "$dir/$target" ] && return 0 ;;
  esac
  return 1
}

# Checks one link target; skips web links, anchors and generated paths.
check_link() {
  local file=$1 ln=$2 t=$3
  t=${t%%#*}
  t=${t%%\?*}
  [ -n "$t" ] || return 0
  case "$t" in
    http://* | https://* | mailto:* | tel:* | //* | data:* | '#'*) return 0 ;;
  esac
  t=$(printf '%s' "$t" | sed 's/%20/ /g')
  exists_as "$file" "$t" && return 0
  case "$t" in /*) is_generated "${t#/}" && return 0 ;; *) is_generated "${file%/*}/$t" && return 0 ;; esac
  report "$file" "$ln" "broken link: $t"
}

# Checks one backticked span when it looks like a repo path (contains a slash, no spaces or placeholders).
check_span() {
  local file=$1 ln=$2 t=$3 base last
  case "$t" in
    */*) ;;
    *) return 0 ;;
  esac
  case "$t" in
    *[[:space:]]* | *'<'* | *'>'* | *'*'* | *'{'* | *'}'* | *'$'* | *'|'* | *';'* | *'&'* | *':'* | *'"'* | *"'"* | *'='* | *'?'* | *'!'* | *','* | *'~'* | /* | http* | '...'* | *'...') return 0 ;;
  esac
  base=${t%%#*}
  base=${base%/}
  [ -n "$base" ] || return 0
  last=${base##*/}
  if ! printf '%s' "$last" | grep -qE "\\.($EXTS)\$" && [ "${t%/}" = "$t" ] && [ ! -e "${base%%/*}" ]; then
    return 0
  fi
  [ -e "$base" ] && return 0
  exists_as "$file" "$base" && return 0
  is_generated "$base" && return 0
  report "$file" "$ln" "path does not exist: $t"
}

# Counts the folder children (files and subfolders, hidden ones excluded) a README list names; flags a full listing.
check_listing() {
  local file=$1 dir names all_files all_dirs n_files n_dirs
  dir=${file%/*}
  [ "$dir" = "$file" ] && dir=.
  names=$(mktemp "${TMPDIR:-/tmp}/check-docs-names.XXXXXX") || return 0
  while IFS=$'\t' read -r _ kind target; do
    [ "$kind" = itemname ] && printf '%s\n' "$target"
  done < "$cands" | LC_ALL=C sort -u > "$names"
  all_files=$(find "$dir" -maxdepth 1 -type f ! -name '.*' ! -name README.md -exec basename {} \; | LC_ALL=C sort)
  all_dirs=$(find "$dir" -maxdepth 1 -mindepth 1 -type d ! -name '.*' -exec basename {} \; | while IFS= read -r d; do is_generated "${dir#./}/$d" || printf '%s\n' "$d"; done | LC_ALL=C sort)
  n_files=0
  [ -n "$all_files" ] && n_files=$(printf '%s\n' "$all_files" | wc -l | tr -d ' ')
  n_dirs=0
  [ -n "$all_dirs" ] && n_dirs=$(printf '%s\n' "$all_dirs" | wc -l | tr -d ' ')
  if [ "$n_files" -ge 3 ] && [ -z "$(printf '%s\n' "$all_files" | LC_ALL=C comm -23 - "$names")" ]; then
    report "$file" 1 "README lists every file of its folder; describe the module, not its files"
  elif [ "$n_dirs" -ge 3 ] && [ -z "$(printf '%s\n' "$all_dirs" | LC_ALL=C comm -23 - "$names")" ]; then
    report "$file" 1 "README lists every subfolder of its folder; describe the module, not its layout"
  fi
  rm -f "$names"
  return 0
}

# Runs every check on one file.
check_file() {
  local file=$1 ln kind target is_readme=0
  case "$file" in README.md | */README.md) is_readme=1 ;; esac
  scan "$file" "$is_readme" > "$cands"
  while IFS=$'\t' read -r ln kind target; do
    case "$kind" in
      link) check_link "$file" "$ln" "$target" ;;
      span) check_span "$file" "$ln" "$target" ;;
      heading) report "$file" "$ln" "README has a Contents heading; a README must not list its folder" ;;
    esac
  done < "$cands"
  [ "$is_readme" -eq 1 ] && check_listing "$file"
  return 0
}

if [ "$#" -gt 0 ]; then
  files=$(printf '%s\n' "$@" | sed 's|^\./||')
else
  files=$(list_all)
fi

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  is_target "$f" || continue
  check_file "$f"
done <<EOF
$files
EOF

total=$(wc -l < "$findings" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  exit 0
fi
if [ "$total" -gt "$CAP" ]; then
  head -n $((CAP - 1)) "$findings"
  printf 'check-docs: %s more findings not shown\n' $((total - CAP + 1))
else
  cat "$findings"
fi
exit 1
