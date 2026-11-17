#!/usr/bin/env bash
# Advisory comment-hygiene scan (PostToolUse, never blocks); `--scan FILE` prints findings and exits 1.
AWK_TAG=py
read -r -d '' AWK <<'AWKEOF' || true
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function note(n, m) { if (emit == "find") printf "%d\t%s\n", n, m }
function txt(n, t) { if (emit == "text") printf "%d\t%s\n", n, t }
function isdir(t) {
  if (lang == "ts") return t ~ /^(eslint-|@ts-|prettier-|istanbul |c8 |v8 |NOSONAR|@vitest-environment|@jest-environment)/
  return t ~ /^(noqa|type:|pyright:|pragma|ruff:|fmt:|pylint:|isort:|mypy:|NOSONAR|-\*-)/
}
function islic(t) { return t ~ /^(Copyright|\(c\)|SPDX-License-Identifier|Licensed under|The MIT License|Permission is hereby|Apache License)/ }
function chk(n, t,   x) {
  txt(n, t)
  if (t ~ /(^|[ \t])\([^()]+\)/) note(n, "parenthetical aside: " t)
  if (t ~ /[Aa][Dd][Rr][- ]?[0-9]+/) {
    x = t; gsub(/[Aa][Dd][Rr][- ]?[0-9]+/, "", x); gsub(/[^A-Za-z0-9]/, "", x)
    if (x != "") note(n, "ADR restated: cite the id only (ADR-NNNN): " t)
  }
}
function endrun() {
  if (run_len > 1 && !run_lic) note(run_start, "comment block of " run_len " lines: keep one short line above the code, or none")
  run_len = 0; run_lic = 0
}
function fullline(n, t) {
  fl = 1
  if (isdir(t)) { fl = 0; return }
  if (run_len == 0) { run_start = n; run_lic = (islic(t) && n <= 3) }
  run_len++; chk(n, t)
}
function trailing(n, code, t) {
  if (isdir(t)) return
  if (code ~ /@[0-9a-f]+[ \t]*$/ && t ~ /^v[0-9]/) return
  note(n, "trailing comment: move it above the code or delete it")
  chk(n, t)
}
function blkline(n, t) {
  t = trim(t)
  if (t == "") return
  if (isdir(t)) return
  blk_len++
  if (blk_len == 1) blk_lic = (islic(t) && n <= 3)
  chk(n, t)
}
function blkend() {
  if (blk_len > 1 && !blk_lic) note(blk_start, "block/JSDoc comment of " blk_len " lines: one summary line on a public API, or none")
  in_blk = 0; blk_len = 0
}
function clean(s) { sub(/^[ \t]*\*+[ \t]?/, "", s); return trim(s) }
function scan_ts(line, n,   i, L, c, d, q, has, prev, text, rest, e, j, cls, cj) {
  L = length(line); i = 1; q = ""; has = in_tpl; prev = ""
  while (i <= L) {
    c = substr(line, i, 1); d = substr(line, i + 1, 1)
    if (in_tpl) { if (c == "\\") { i += 2; continue } if (c == "`") in_tpl = 0; i++; continue }
    if (q != "") { if (c == "\\") { i += 2; continue } if (c == q) q = ""; i++; continue }
    if (c == " " || c == "\t") { i++; continue }
    if (c == "/" && d == "/" && prev != ":") {
      text = substr(line, i + 2)
      if (substr(text, 1, 1) == "/") return
      text = trim(text)
      if (has) trailing(n, substr(line, 1, i - 1), text); else fullline(n, text)
      return
    }
    if (c == "/" && d == "*") {
      endrun()
      rest = substr(line, i + 2); e = index(rest, "*/")
      if (e > 0) {
        text = clean(substr(rest, 1, e - 1))
        if (has && substr(line, 1, i - 1) ~ /^[ \t]*\{[ \t]*$/) fullline(n, text)
        else if (has) trailing(n, substr(line, 1, i - 1), text)
        else { blk_len = 0; blk_start = n; blk_lic = 0; blkline(n, text); blkend() }
        i += 3 + e; has = 1; prev = "/"; continue
      }
      in_blk = 1; blk_len = 0; blk_start = n; blk_lic = 0
      blkline(n, clean(rest)); return
    }
    if (c == SQ || c == "\"") { q = c; has = 1; i++; continue }
    if (c == "`") { in_tpl = 1; has = 1; i++; continue }
    if (c == "/" && (prev == "" || index("(,=:[!&|?{};", prev) > 0)) {
      j = i + 1; cls = 0
      while (j <= L) {
        cj = substr(line, j, 1)
        if (cj == "\\") { j += 2; continue }
        if (cj == "[") cls = 1; else if (cj == "]") cls = 0; else if (cj == "/" && !cls) break
        j++
      }
      i = j + 1; has = 1; prev = "/"; continue
    }
    has = 1; prev = c; i++
  }
}
function scan_py(line, n,   i, L, c, d, q, has, text, rest, e, doc, t, delim) {
  L = length(line); i = 1; q = ""; has = 0
  while (i <= L) {
    c = substr(line, i, 1); d = substr(line, i + 1, 1)
    if (q != "") { if (c == "\\") { i += 2; continue } if (c == q) q = ""; i++; continue }
    if (c == " " || c == "\t") { i++; continue }
    if (c == "#") {
      text = trim(substr(line, i + 1))
      if (has) trailing(n, substr(line, 1, i - 1), text); else fullline(n, text)
      return
    }
    if ((c == "\"" || c == SQ) && d == c && substr(line, i + 2, 1) == c) {
      delim = c c c; rest = substr(line, i + 3); doc = !has; e = index(rest, delim)
      if (e > 0) {
        t = trim(substr(rest, 1, e - 1))
        if (doc && t != "") chk(n, t)
        i += 5 + e; has = 1; continue
      }
      in_str3 = delim; str3_doc = doc; doc_start = n; doc_len = 0
      t = trim(rest)
      if (doc && t != "") { doc_len++; chk(n, t) }
      return
    }
    if (c == "\"" || c == SQ) { q = c; has = 1; i++; continue }
    has = 1; i++
  }
}
BEGIN { SQ = sprintf("%c", 39) }
{
  n = NR; line = $0; sub(/\r$/, "", line); fl = 0
  if (n == 1 && line ~ /^#!/) next
  if (lang == "ts" && in_blk) {
    e = index(line, "*/")
    blkline(n, clean(e > 0 ? substr(line, 1, e - 1) : line))
    if (e > 0) blkend()
    next
  }
  if (lang == "py" && in_str3 != "") {
    e = index(line, in_str3)
    t = trim(e > 0 ? substr(line, 1, e - 1) : line)
    if (str3_doc && t != "") { doc_len++; chk(n, t) }
    if (e > 0) {
      if (str3_doc && doc_len > 1) note(doc_start, "docstring of " doc_len " lines: one summary line on a public API, or none")
      in_str3 = ""
    }
    next
  }
  if (lang == "ts") scan_ts(line, n); else scan_py(line, n)
  if (!fl) endrun()
}
END { endrun() }
AWKEOF

scan() {
  awk -v lang="$AWK_TAG" -v emit=find "$AWK" "$1"
  texts=$(awk -v lang="$AWK_TAG" -v emit=text "$AWK" "$1")
  [ -n "$texts" ] || return 0
  printf '%s\n' "$texts" | cut -f2- | grep -nEf "$patterns" | while IFS= read -r m; do
    body=${m#*:}
    case "$body" in UTF-*|SHA-*|AES-*|RSA-*|ISO-*|RFC-*|TLS-*|SSL-*|HTTP-*|DES-*|MD-*|HMAC-*|CRC-*|ECDSA-*|PBKDF-*|BASE-*) continue ;; esac
    ln=$(printf '%s\n' "$texts" | sed -n "${m%%:*}p" | cut -f1)
    printf '%s\tnarration or reference: %s\n' "$ln" "$body"
  done
}

patterns="${COMMENT_HYGIENE_PATTERNS:-.claude/comment-hygiene-patterns.txt}"
if [ "${1:-}" = "--scan" ]; then
  [ -f "${2:-}" ] && [ -f "$patterns" ] || exit 0
  found=$(scan "$2" | sort -s -t "$(printf '\t')" -k1,1n)
  [ -n "$found" ] || exit 0
  printf '%s\n' "$found" | awk -F'\t' -v f="$2" '{ printf "%s:%s: %s\n", f, $1, $2 }'
  exit 1
fi

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
[ -f "$patterns" ] || exit 0

found=$(scan "$file" | sort -s -t "$(printf '\t')" -k1,1n)
if [ -n "$found" ]; then
  msg="⚠ comment hygiene (see standards/code-standards/comments.md):
$(printf '%s\n' "$found" | awk -F'\t' '{ printf "  - line %s: %s\n", $1, $2 }')"
  python3 -c "import json,sys; print(json.dumps({'hookSpecificOutput':{'hookEventName':'PostToolUse','additionalContext':sys.argv[1]}}))" "$msg"
fi
exit 0
