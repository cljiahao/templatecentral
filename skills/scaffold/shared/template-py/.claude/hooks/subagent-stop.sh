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
# cap <chars>: lines cut to 200 chars; over budget keeps the first lines and the last ones (a runner's summary), with the dropped count between.
cap() { awk -v cap="$1" '{ L[NR] = substr($0, 1, 200); T += length(L[NR]) + 1 } END { if (T <= cap) { for (i = 1; i <= NR; i++) print L[i]; exit } room = cap - 40; hb = int(room / 2); for (h = 0; h < NR && hl + length(L[h + 1]) + 1 <= hb; h++) hl += length(L[h + 1]) + 1; for (t = 0; NR - t > h && tl + length(L[NR - t]) + 1 <= room - hl; t++) tl += length(L[NR - t]) + 1; for (i = 1; i <= h; i++) print L[i]; printf "... %d more lines not shown\n", NR - h - t; for (i = NR - t + 1; i <= NR; i++) print L[i] }'; }
if [ "$EC" -ne 0 ]; then printf '%s\n' "$OUTPUT" | cap 1900 >&2; exit 2; fi
exit 0
