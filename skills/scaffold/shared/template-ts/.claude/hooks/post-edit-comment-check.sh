#!/usr/bin/env bash
# PostToolUse(Edit|Write) — flags change-narration, multi-line comments, parenthetical asides and ADR restatements.
# Feedback-only (never blocks). Patterns come from .claude/comment-hygiene-patterns.txt.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

patterns=".claude/comment-hygiene-patterns.txt"
[ -f "$patterns" ] || exit 0

flush_block() {
  [ "$block_len" -gt 1 ] && [ "$block_lic" -eq 0 ] && flagged="$flagged
  - comment block of $block_len lines: keep one short line above the code, or none"
  block_len=0
  block_lic=0
}

flagged=""
block_len=0
block_lic=0
prev_lineno=0
plain_re='^[[:space:]]*//([^/]|$)'
directive_re='^(eslint-|@ts-|prettier-|istanbul |c8 |v8 |NOSONAR)'
while IFS= read -r cline; do
  lineno="${cline%%:*}"
  content="${cline#*:}"
  if [ "$prev_lineno" -ne 0 ] && [ "$lineno" -ne $((prev_lineno + 1)) ]; then
    flush_block
  fi
  stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|//|\*|/\*\*?)[[:space:]]?@@')
  if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$patterns"; then
    flagged="$flagged
  - narration: $stripped"
  fi
  if printf '%s' "$content" | grep -qE "$plain_re" && ! printf '%s' "$stripped" | grep -qE "$directive_re"; then
    [ "$block_len" -eq 0 ] && [ "$lineno" -le 2 ] && block_lic=1
    printf '%s' "$stripped" | grep -qE 'Copyright|SPDX|[Ll]icen[cs]e' && block_lic=1
    block_len=$((block_len + 1))
    if printf '%s' "$stripped" | grep -qE '\([^()]*[[:space:]][^()]*\)'; then
      flagged="$flagged
  - parenthetical aside: $stripped"
    fi
    rest=$(printf '%s' "$stripped" | sed -E 's/[Aa][Dd][Rr][- ]?[0-9]+//g; s/[[:punct:][:space:]]+//g')
    if printf '%s' "$stripped" | grep -qE '[Aa][Dd][Rr][- ]?[0-9]+' && [ -n "$rest" ]; then
      flagged="$flagged
  - ADR restated: cite the id only (ADR-NNNN): $stripped"
    fi
  else
    flush_block
  fi
  prev_lineno="$lineno"
done < <(grep -nE '^[[:space:]]*(#|//|\*|/\*\*?)' "$file")
flush_block

if [ -n "$flagged" ]; then
  msg="⚠ comment hygiene:$flagged"
  node -e "process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:'PostToolUse',additionalContext:process.argv[1]}}))" "$msg"
fi
exit 0
