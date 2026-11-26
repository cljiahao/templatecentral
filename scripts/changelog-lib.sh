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
  local -x LC_ALL=C
  local name=$1 re='^[a-z0-9][a-z0-9-]*\.(added|changed|removed|fixed|security)\.md$'
  [[ $name =~ $re ]] || return 1
  name=${name%.md}
  printf '%s\n' "${name##*.}"
}

# Succeeds when the file is a regular, non-symlink file that fits the grammar below; otherwise
# prints "fragment [line N] breaks the rule ...: <line>" and fails. check and assemble both call
# it on every fragment and emit the file as it is, so the validated bytes are the emitted bytes.
# Every byte-level command here runs with LC_ALL=C exported, so the verdict is the same in every
# locale and for a caller that only sources this file. A tool that fails stops the check.
# 1. Bytes first, on the whole file: no control byte except LF (CR, TAB, NUL, ESC, DEL all fail,
#    counted with tr, never with read), and the last byte is LF. An empty file has no bullet
#    line. So Markdown and bash see the same lines: only LF ends one.
# 2. Valid UTF-8 only, as an allow-list of byte sequences (no overlong form, surrogate, lone
#    continuation byte or byte C0, C1, F5 to FF), and none of the invisible or reordering code
#    points: C1 controls, soft hyphen, U+061C, U+180E, U+200B-U+200F, U+2028-U+202E,
#    U+2060-U+206F, U+FEFF, U+FFF9-U+FFFB and the tag characters U+E0000-U+E007F.
# 3. Lines: no blank line. The first line is "- text"; after it "- text", "  - text" (nested)
#    or "  text" (exactly two spaces). Text starts with a letter, digit, backtick, "[", "(", a
#    double or single quote, or "#" and a digit (a PR reference), holds a letter or digit, and
#    does not start with an ordered-list marker ("1." or "1)").
# 4. Backticks: a line has an even number of them, never two in a row, never one after a
#    backslash. Then spans pair first with second, third with fourth, on the line alone, which
#    is what Markdown does, so "inside a span" means the same to the script and to Markdown.
# 5. Outside spans: no "<" before a letter, "/", "!" or "?" (HTML tag, comment, CDATA, PI,
#    declaration, autolink: the only constructs that could swallow a backtick), no "](", "]["
#    or "] [" (a link destination or label), no "]:" (a link reference definition, wherever its
#    label starts), and the "[" and "]" balance within the line, a backslash before a bracket
#    changing nothing, so no label can run over a line break or hide behind an escape.
# No heading, quote, fence, rule, setext underline, table, list-marker line or HTML block passes.
cl_content_ok() {
  local -x LC_ALL=C
  local f=$1 line n=0 seen=0 rest t rule bad out rc i nbt balanced
  local re_first='^([A-Za-z0-9`[("'"'"']|#[0-9])'
  local bt bs re_ord='^[0-9]+[.)]([[:space:]]|$)' parts
  local re_alnum='[A-Za-z0-9]' re_html='<[A-Za-z/!?]' re_link='\]([(]|[[:space:]]*\[)'
  local c=$'[\x80-\xbf]' re_utf8 re_ban
  re_utf8=$'^([ -~]|[\xc2-\xdf]'$c$'|\xe0[\xa0-\xbf]'$c$'|[\xe1-\xec\xee\xef]'$c$c
  re_utf8+=$'|\xed[\x80-\x9f]'$c$'|\xf0[\x90-\xbf]'$c$c$'|[\xf1-\xf3]'$c$c$c
  re_utf8+=$'|\xf4[\x80-\x8f]'$c$c$')*$'
  re_ban=$'\xc2[\x80-\x9f]|\xc2\xad|\xd8\x9c|\xe1\xa0\x8e|\xe2\x80[\x8b-\x8f]|\xe2\x80[\xa8-\xae]'
  re_ban+=$'|\xe2\x81[\xa0-\xaf]|\xef\xbb\xbf|\xef\xbf[\xb9-\xbb]|\xf3\xa0[\x80-\x81]'$c
  local awk_bal='BEGIN { s = ENVIRON["S"]; d = 0; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "[") d++
      else if (c == "]") { d--; if (d < 0) exit 1 }
    }
    exit (d != 0) }'
  bt=$(printf '\x60'); bs=$(printf '\x5c')
  if [[ -L $f || ! -f $f ]]; then
    echo "fragment is not a regular file"; return 1
  fi
  bad=$(tr -d '\n\040-\176\200-\377' < "$f" | wc -c) \
    || { echo "fragment cannot be read"; return 1; }
  if [[ ${bad//[[:space:]]/} != 0 ]]; then
    echo "fragment breaks the rule \"no control byte except LF (no CR, TAB or NUL)\""; return 1
  fi
  if [[ ! -s $f ]]; then echo "fragment has no bullet line"; return 1; fi
  bad=$(tail -c 1 "$f" | wc -l) || { echo "fragment cannot be read"; return 1; }
  if [[ ${bad//[[:space:]]/} != 1 ]]; then
    echo "fragment breaks the rule \"the last line ends with a newline\""; return 1
  fi
  out=$(grep -a -n -v -E -e "$re_utf8" "$f"); rc=$?
  case $rc in
    0) echo "fragment line ${out%%:*} breaks the rule \"valid UTF-8 only\""; return 1 ;;
    1) ;;
    *) echo "fragment cannot be checked: grep failed"; return 1 ;;
  esac
  out=$(grep -a -n -E -e "$re_ban" "$f"); rc=$?
  case $rc in
    0) echo "fragment line ${out%%:*} breaks the rule \"no invisible or reordering character\""
       return 1 ;;
    1) ;;
    *) echo "fragment cannot be checked: grep failed"; return 1 ;;
  esac
  while IFS= read -r line; do
    n=$((n + 1))
    rule=""
    if [[ $line == '- '* ]]; then
      rest=${line#- }
    elif [[ $seen -eq 1 && $line == '  - '* ]]; then
      rest=${line#  - }
    elif [[ $seen -eq 1 && $line == '  '* ]]; then
      rest=${line#  }
    else
      rule="a line is '- text', or after the first bullet '  - text' or '  text'; no blank line"
    fi
    if [[ -z $rule ]]; then
      seen=1
      IFS=$bt read -r -a parts <<< "${rest}x"
      nbt=$(( ${#parts[@]} - 1 ))
      parts[nbt]=${parts[$nbt]%x}
      if [[ ! $rest =~ $re_first ]]; then
        rule="text starts with a letter, digit, backtick, [ ( \" ' or # and a digit"
      elif [[ $rest =~ $re_ord ]]; then
        rule="text may not start with a list marker such as 1."
      elif [[ $rest == *"$bt$bt"* ]]; then
        rule="no two backticks in a row"
      elif [[ $rest == *"$bs$bt"* ]]; then
        rule="no backslash before a backtick"
      elif [[ $(( nbt % 2 )) -ne 0 ]]; then
        rule="an even number of backticks on a line"
      elif [[ ! $rest =~ $re_alnum ]]; then
        rule="text holds a letter or a digit"
      else
        t=""; i=0
        while [[ $i -le $nbt ]]; do t=$t${parts[$i]}; i=$((i + 2)); done
        balanced=0
        if [[ $t == *'['* || $t == *']'* ]]; then
          S=$t awk "$awk_bal" < /dev/null || balanced=1
        fi
        if [[ $t =~ $re_html ]]; then
          rule="no < before a letter, / ! or ? outside backticks (raw HTML)"
        elif [[ $t == *']:'* ]]; then
          rule="no ]: outside backticks (link reference definition)"
        elif [[ $balanced -ne 0 ]]; then
          rule="[ and ] outside backticks balance on the line (a label cannot run on or hide)"
        elif [[ $t =~ $re_link ]]; then
          rule="no ]( ][ or ] [ outside backticks (link destination or label)"
        fi
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
