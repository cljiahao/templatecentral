#!/usr/bin/env bash
# scripts/changelog-lib.sh — shared fragment rules for changelog-check.sh and changelog-assemble.sh.
# Sourced, never run. One allow-list: the exact file-name pattern, the exact category set and
# the content rules live here and nowhere else.

CL_CATEGORIES="added changed fixed security"
CL_DIR="changelog.d"
export CL_CATEGORIES CL_DIR

# Succeeds when the base name is a valid fragment name. Prints the category on stdout.
cl_name_category() {
  local name=$1 re='^[a-z0-9][a-z0-9-]*\.(added|changed|fixed|security)\.md$'
  case $name in
    *$'\n'*) return 1 ;;
  esac
  [[ $name =~ $re ]] || return 1
  name=${name%.md}
  printf '%s\n' "${name##*.}"
}

# Succeeds when the file is a regular, non-symlink file whose first non-blank line is a bullet
# with text, and whose other non-blank lines are bullets or indented continuations that do not
# start with a fence marker or a heading.
cl_content_ok() {
  local f=$1 line t first=1 seen=0
  local re_blank='^[[:space:]]*$' re_bullet='^[-*][[:space:]]+[^[:space:]]' re_indent='^[[:space:]]'
  if [[ -L $f || ! -f $f ]]; then return 1; fi
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $re_blank ]]; then continue; fi
    if [[ $first -eq 1 ]]; then
      first=0
      if [[ ! $line =~ $re_bullet ]]; then return 1; fi
      seen=1
    elif [[ $line =~ $re_bullet ]]; then
      :
    elif [[ $line =~ $re_indent ]]; then
      t=${line#"${line%%[![:space:]]*}"}
      case $t in
        '```'*|'~~~'*|'#'*) return 1 ;;
      esac
    else
      return 1
    fi
  done < "$f"
  [[ $seen -eq 1 ]]
}
