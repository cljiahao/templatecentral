#!/usr/bin/env bash
# scripts/changelog-lib.sh — shared fragment rules for the changelog check and assemble scripts.
# Sourced, never run. One allow-list: the exact file-name pattern, the exact category set and
# the content rules live here and nowhere else.

# Order is the section order of a release (Keep a Changelog, without Deprecated).
CL_CATEGORIES="added changed removed fixed security"
CL_DIR="changelog.d"
export CL_CATEGORIES CL_DIR

# Succeeds when the base name is a valid fragment name. The regex is anchored at both ends and
# bash matches the whole string, so a name with a newline anywhere fails.
# Prints the category on stdout.
cl_name_category() {
  local name=$1 re='^[a-z0-9][a-z0-9-]*\.(added|changed|removed|fixed|security)\.md$'
  [[ $name =~ $re ]] || return 1
  name=${name%.md}
  printf '%s\n' "${name##*.}"
}

# Succeeds when the file is a regular, non-symlink file whose non-blank lines all fit this
# grammar; otherwise prints "fragment line N breaks the rule ...: <line>" and fails. A line is
# valid only as one of:
#   bullet        "- " then text. The first non-blank line must be one.
#   nested bullet "  - " (two spaces) then text, after the first bullet.
#   continuation  two spaces then text, after the first bullet.
# Text starts with a letter, a digit, a backtick, "[", "(", a double or single quote, or "#" and
# a digit (a PR reference). It holds a letter or a digit, does not start with an ordered-list
# marker ("1." or "1)", which would open a nested list) or three backticks (a fence), and has no
# "<" before a letter or "/" outside a backtick span (raw HTML). Everything else is rejected, so
# no heading, quote, rule, setext underline, table or HTML block can pass. Blank lines are free.
cl_content_ok() {
  local LC_ALL=C
  local f=$1 line n=0 seen=0 rest t rule
  local re_blank='^[[:space:]]*$' re_first='^([A-Za-z0-9`[("'"'"']|#[0-9])'
  local bt re_ord='^[0-9]+[.)]([[:space:]]|$)' re_span
  bt=$(printf '\x60')
  re_span="^([^${bt}]*)${bt}[^${bt}]*${bt}(.*)\$"
  local re_alnum='[A-Za-z0-9]' re_html='<[A-Za-z/]'
  if [[ -L $f || ! -f $f ]]; then
    echo "fragment is not a regular file"; return 1
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    if [[ $line =~ $re_blank ]]; then continue; fi
    rule=""
    if [[ $line == '- '* ]]; then
      rest=${line#- }
    elif [[ $seen -eq 1 && $line == '  - '* ]]; then
      rest=${line#  - }
    elif [[ $seen -eq 1 && $line == '  '* && $line != '   '* ]]; then
      rest=${line#  }
    else
      rule="a line is '- text', or after the first bullet '  - text' or '  text' (two spaces)"
    fi
    if [[ -z $rule ]]; then
      seen=1
      t=$rest
      while [[ $t =~ $re_span ]]; do t=${BASH_REMATCH[1]}${BASH_REMATCH[2]}; done
      if [[ ! $rest =~ $re_first ]]; then
        rule="text starts with a letter, digit, backtick, [ ( \" ' or # and a digit"
      elif [[ $rest =~ $re_ord ]]; then
        rule="text may not start with a list marker such as 1."
      elif [[ $rest == '```'* ]]; then
        rule="text may not start with a code fence"
      elif [[ ! $rest =~ $re_alnum ]]; then
        rule="text holds a letter or a digit"
      elif [[ $t =~ $re_html ]]; then
        rule="no < before a letter or / outside backticks (raw HTML)"
      fi
    fi
    if [[ -n $rule ]]; then
      printf 'fragment line %d breaks the rule "%s": %s\n' "$n" "$rule" "${line//[[:cntrl:]]/?}"
      return 1
    fi
  done < "$f"
  if [[ $seen -eq 0 ]]; then echo "fragment has no bullet line"; return 1; fi
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
