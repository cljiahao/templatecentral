#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted Python changes so it can't hand back broken code.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
meta=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    d=json.loads(sys.stdin.read() or '{}'); print(('true' if d.get('stop_hook_active') is True else 'false')+' '+str(d.get('agent_type') or ''))
except Exception: print('false ')" 2>/dev/null)
[ "${meta%% *}" = "true" ] && exit 0          # already re-running after a block — don't loop
case "${meta#* }" in Explore|Plan) exit 0 ;; esac   # read-only built-in agents never edit
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed=$( { git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '\.pyi?$' | head -1)
[ -n "$changed" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
