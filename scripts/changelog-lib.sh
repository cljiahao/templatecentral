#!/usr/bin/env bash
# scripts/changelog-lib.sh — shared fragment rules for changelog-check.sh and changelog-assemble.sh.
# Sourced, never run. One allow-list: the exact file-name pattern, the exact category set and
# the content rules live here and nowhere else.

CL_CATEGORIES="added changed fixed security"
CL_DIR="changelog.d"
export CL_CATEGORIES CL_DIR

# Succeeds when the base name is a valid fragment name. The regex is anchored at both ends and
# bash matches the whole string, so a name with a newline anywhere fails.
# Prints the category on stdout.
cl_name_category() {
  local name=$1 re='^[a-z0-9][a-z0-9-]*\.(added|changed|fixed|security)\.md$'
  [[ $name =~ $re ]] || return 1
  name=${name%.md}
  printf '%s\n' "${name##*.}"
}

# Succeeds when the file is a regular, non-symlink file whose first non-blank line is a bullet
# with text, and whose other non-blank lines are bullets or indented continuations. The text of
# each line (indent and bullet marker stripped, nested bullets included) may not start with a
# fence marker or a heading, and may not be a lone rule line (three or more - or = characters).
cl_content_ok() {
  local f=$1 line t first=1 seen=0
  local re_blank='^[[:space:]]*$' re_bullet='^[-*][[:space:]]+[^[:space:]]'
  local re_indent='^[[:space:]]'
  local re_marker='^[-*][[:space:]]+' re_rule='^(-{3,}|={3,})[[:space:]]*$'
  if [[ -L $f || ! -f $f ]]; then return 1; fi
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $re_blank ]]; then continue; fi
    if [[ $first -eq 1 ]]; then
      first=0
      if [[ ! $line =~ $re_bullet ]]; then return 1; fi
      seen=1
    fi
    if [[ ! $line =~ $re_bullet && ! $line =~ $re_indent ]]; then return 1; fi
    t=${line#"${line%%[![:space:]]*}"}
    if [[ $t =~ $re_marker ]]; then t=${t#"${BASH_REMATCH[0]}"}; fi
    case $t in
      '```'*|'~~~'*|'#'*) return 1 ;;
    esac
    if [[ $t =~ $re_rule ]]; then return 1; fi
  done < "$f"
  [[ $seen -eq 1 ]]
}

# Prints every entry under "## [Unreleased]" of the file: each line that is not blank and not a
# "---" rule, up to the next release heading. Exit status 3 when the file has no such heading.
cl_unreleased_entries() {
  awk '
    /^## \[Unreleased\]/ { u = 1; seen = 1; next }
    u && /^## \[/ { u = 0 }
    u && $0 !~ /^[[:space:]]*$/ && $0 !~ /^---[[:space:]]*$/ { print }
    END { exit seen ? 0 : 3 }
  ' "$1"
}

# Prints the file with the "## [Unreleased]" block reduced to the empty form: heading, blank
# line, "---", blank line. Everything else is copied unchanged.
cl_unreleased_emptied() {
  awk '
    /^## \[Unreleased\]/ { print; print ""; print "---"; print ""; u = 1; next }
    u && /^## \[/ { u = 0 }
    u { next }
    { print }
  ' "$1"
}
