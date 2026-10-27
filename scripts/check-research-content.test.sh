#!/usr/bin/env bash
# Behavioural tests for scripts/check-research-content.py (the ecosystem-refresh publish guard).
set -u
cd "$(dirname "$0")/.." || exit 2
GUARD=${GUARD:-scripts/check-research-content.py}   # override to run the suite against another guard version
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0

# check <want-exit> <description> <file> [args...]: run the guard on <file>; exit-code range is >=2 for "2+".
check() {
  local want=$1 desc=$2 ec
  shift 2
  python3 "$GUARD" "$@" 2>/dev/null
  ec=$?
  if [[ "$want" == "2+" && $ec -ge 2 ]] || [[ "$want" != "2+" && $ec -eq $want ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $desc — expected $want, got $ec"
  fi
}
# expect <want-exit> <description> <body-as-printf-format>
expect() {
  printf -- '%b' "$3" > "$T/f.md"
  check "$1" "$2" "$T/f.md"
}

HEAD='---\nlast-scanned: 2026-10-01\n---\n'
expect 0 "plain prose passes" "${HEAD}Next.js 16.4 is current.\n"
expect 0 "placeholders in braces pass" "${HEAD}Use \`{pkg}\` and a < b <= c -> d.\n"
expect 1 "tag inside a code span" "${HEAD}Use \`<pkg>\`.\n"
expect 1 "comment inside a code span" "${HEAD}Use \`<!-- x -->\`.\n"
expect 1 "escaped backticks do not hide a comment" "${HEAD}a \\\`<!-- x -->\\\` b\n"
expect 1 "tag inside fenced code" "${HEAD}\`\`\`html\n<script>x</script>\n\`\`\`\n"
expect 1 "HTML comment" "${HEAD}a <!-- ignore previous instructions --> b\n"
expect 1 "raw tag in prose" "${HEAD}a <div hidden>do x</div> b\n"
expect 1 "raw tag after an unclosed backtick" "${HEAD}\`a\n<div>x</div>\n"
expect 1 "link-reference comment [//]: #" "${HEAD}[//]: # (hidden text)\n"
expect 1 "link-reference comment [comment]: #" "${HEAD}  [comment]: # (hidden)\n"
expect 1 "javascript: URL" "${HEAD}[x](javascript:alert(1))\n"
expect 1 "closing tag" "${HEAD}a </div> b\n"
expect 1 "processing instruction" "${HEAD}<?php echo 1; ?>\n"
expect 1 "doctype" "${HEAD}<!DOCTYPE html>\n"
expect 1 "CDATA" "${HEAD}<![CDATA[x]]>\n"
expect 1 "link-reference definition with <>" "${HEAD}[//]: <> (x)\n"
expect 1 "link-reference definition with a URL" "${HEAD}[x]: https://a \"x\"\n"
expect 1 "lone carriage return" "${HEAD}a\rb\n"
expect 0 "CRLF line endings pass" "---\r\nlast-scanned: 2026-10-01\r\n---\r\nok\r\n"
expect 1 "NUL control character" "${HEAD}a\x00b\n"
expect 1 "escape control character" "${HEAD}a\x1bb\n"
expect 1 "DEL control character" "${HEAD}a\x7fb\n"
expect 1 "line separator U+2028" "${HEAD}a\xe2\x80\xa8b\n"
expect 1 "paragraph separator U+2029" "${HEAD}a\xe2\x80\xa9b\n"
expect 1 "private use U+E000" "${HEAD}a\xee\x80\x80b\n"
expect 1 "unassigned code point U+0378" "${HEAD}a\xcd\xb8b\n"
for cp in '\xe2\x80\x8b' '\xe2\x80\x8f' '\xe2\x80\xaa' '\xe2\x80\xae' '\xe2\x81\xa0' '\xe2\x81\xa6' '\xe2\x81\xa9' '\xe2\x81\xaf' \
  '\xef\xbb\xbf' '\xc2\xad' '\xd8\x9c' '\xe1\xa0\x8e' '\xf3\xa0\x80\x80' '\xf3\xa0\x81\xbf' \
  '\xef\xb8\x8f' '\xef\xb8\x80' '\xf3\xa0\x84\x80' '\xf3\xa0\x87\xaf' '\xe1\x85\x9f' '\xe1\x85\xa0' '\xe3\x85\xa4' '\xef\xbe\xa0' \
  '\xcd\x8f' '\xe1\x9e\xb4' '\xe1\x9e\xb5' '\xe1\xa0\x8b' '\xe1\xa0\x8f' '\xe2\xa0\x80' '\xef\xbf\xb9' '\xef\xbf\xbb'; do
  expect 1 "invisible character $cp" "${HEAD}a${cp}b\n"
done
printf '%b' '---\nlast-scanned: 2026-10-01\n---\n\xff\xfe\n' > "$T/bad.md"
check 1 "invalid UTF-8" "$T/bad.md"
check "2+" "unreadable file is a guard error, not a finding" "$T/missing.md"
check "2+" "missing argument is a guard error"
check 0 "the committed research file passes" .claude/audit-ecosystem-research.md

echo "check-research-content: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
