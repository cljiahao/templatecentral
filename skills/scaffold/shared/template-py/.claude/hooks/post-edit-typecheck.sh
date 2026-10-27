#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on Python edits only. Feedback-only (never blocks).
# Errors reach Claude via hookSpecificOutput.additionalContext — plain stdout from a
# PostToolUse hook goes to the debug log only. Always exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    ti=json.load(sys.stdin).get('tool_input') or {}
    print(ti.get('file_path') or ti.get('path') or '')
except Exception:
    print('')" 2>/dev/null)
case "$file" in *.py|*.pyi) ;; *) exit 0 ;; esac
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pyright --version >/dev/null 2>&1 || exit 0
out=$(python -m pyright src/ 2>&1) && exit 0
errs=$(printf '%s\n' "$out" | grep -E ' - error' | head -20)
[ -n "$errs" ] || errs=$(printf '%s\n' "$out" | tail -20)
[ -n "$errs" ] || exit 0
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":("pyright reports type errors after this edit — fix them before moving on:\n"+sys.argv[1])[:9000]}}))' "$errs" 2>/dev/null
exit 0
