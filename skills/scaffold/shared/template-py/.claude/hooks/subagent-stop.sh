#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted Python changes so it can't hand back broken code.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
meta=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    d=json.loads(sys.stdin.read() or '{}'); print(('true' if d.get('stop_hook_active') is True else 'false')+' '+str(d.get('agent_type') or ''))
except Exception: print('false ')" 2>/dev/null)
# Already re-running after a block: do not loop.
[ "${meta%% *}" = "true" ] && exit 0
# Read-only built-in agents never edit.
case "${meta#* }" in Explore|Plan) exit 0 ;; esac
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed=$( { git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '\.pyi?$' | head -1)
[ -n "$changed" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
# cap <chars>: keep leading lines (each cut to 200 chars) within the budget, then count the dropped ones.
cap() { awk -v cap="$1" '{ l = substr($0, 1, 200); if (len + length(l) + 1 > cap) { drop++; next } print l; len += length(l) + 1 } END { if (drop) printf "... %d more lines not shown\n", drop }'; }
if [ "$EC" -ne 0 ]; then printf '%s\n' "$OUTPUT" | cap 1900 >&2; exit 2; fi
exit 0
