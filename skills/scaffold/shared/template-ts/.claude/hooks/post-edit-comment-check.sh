#!/usr/bin/env bash
# PostToolUse(Edit|Write) — flags change-narration comments and oversized comment blocks.
# Feedback-only (never blocks). Patterns come from .claude/comment-hygiene-patterns.txt.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

patterns=".claude/comment-hygiene-patterns.txt"
[ -f "$patterns" ] || exit 0

flagged=""
block_len=0
prev_lineno=0
while IFS= read -r cline; do
  lineno="${cline%%:*}"
  content="${cline#*:}"
  if [ "$prev_lineno" -ne 0 ] && [ "$lineno" -ne $((prev_lineno + 1)) ]; then
    [ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines)"
    block_len=0
  fi
  stripped=$(printf '%s' "$content" | sed -E 's@^[[:space:]]*(#|//|\*|/\*\*?)[[:space:]]?@@')
  if [ -n "$stripped" ] && printf '%s' "$stripped" | grep -qEf "$patterns"; then
    flagged="$flagged
  - narration: $stripped"
  fi
  if printf '%s' "$content" | grep -qE '^[[:space:]]*//'; then
    block_len=$((block_len + 1))
  else
    [ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines)"
    block_len=0
  fi
  prev_lineno="$lineno"
done < <(grep -nE '^[[:space:]]*(#|//|\*|/\*\*?)' "$file")
[ "$block_len" -gt 5 ] && flagged="$flagged
  - oversized comment block ($block_len lines, end of file)"

if [ -n "$flagged" ]; then
  msg="⚠ comment hygiene:$flagged"
  node -e "process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:'PostToolUse',additionalContext:process.argv[1]}}))" "$msg"
fi
exit 0
