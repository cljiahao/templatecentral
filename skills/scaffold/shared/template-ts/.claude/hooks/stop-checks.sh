#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
# Nothing uncommitted (no tracked diff vs HEAD, no new untracked files) → nothing new to test this turn.
if git rev-parse --verify -q HEAD >/dev/null 2>&1 && git diff --quiet HEAD -- . 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
  exit 0
fi
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm test 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
