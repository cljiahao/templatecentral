#!/usr/bin/env bash
# Stop — run the test suite; exit 2 (stderr to Claude) forces a fix before the turn ends.
# stop_hook_active guard: prevents re-entry when Claude re-runs after a Stop exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print('true' if json.loads(sys.stdin.read() or '{}').get('stop_hook_active') is True else 'false')
except Exception: print('false')" 2>/dev/null)
[ "$active" = "true" ] && exit 0
# Nothing uncommitted (no tracked diff vs HEAD, no new untracked files) → nothing new to test this turn.
if git rev-parse --verify -q HEAD >/dev/null 2>&1 && git diff --quiet HEAD -- . 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
  exit 0
fi
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(python -m pytest test/ -q 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
