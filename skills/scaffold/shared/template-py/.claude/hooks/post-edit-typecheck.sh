#!/usr/bin/env bash
# PostToolUse(Edit|Write): fast type feedback, never blocks; errors reach Claude via additionalContext.
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
# Own deadline (TYPECHECK_LIMIT seconds, default 45, under the 60 s settings timeout); a timeout is reported, never blocking.
LIMIT=${TYPECHECK_LIMIT:-45}
DEADLINE=$(( $(date +%s) + LIMIT ))
OUT=$(mktemp "${TMPDIR:-/tmp}/typecheck.XXXXXX") || exit 0
CHILD=; WATCH=; p=
trap 'for p in $CHILD $WATCH; do kill -KILL -- "-$p" 2>/dev/null; done; rm -f "$OUT" "$OUT.timeout"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
# run <cmd...>: stdin closed, own process group, killed when the shared deadline passes. Sets EC (124 = timeout) and OUTPUT.
run() {
  local left=$(( DEADLINE - $(date +%s) ))
  rm -f "$OUT.timeout"
  if [ "$left" -le 0 ]; then EC=124; OUTPUT=""; return 0; fi
  set -m
  { "$@" </dev/null >"$OUT" 2>&1 & CHILD=$!; } 2>/dev/null
  { ( sleep "$left"; : >"$OUT.timeout"; kill -TERM -- "-$CHILD"; sleep 2; kill -KILL -- "-$CHILD" ) >/dev/null 2>&1 & WATCH=$!; } 2>/dev/null
  set +m
  { wait "$CHILD"; EC=$?; } 2>/dev/null
  kill -KILL -- "-$WATCH" 2>/dev/null; wait "$WATCH" 2>/dev/null
  kill -KILL -- "-$CHILD" 2>/dev/null
  CHILD=; WATCH=
  if [ -f "$OUT.timeout" ]; then EC=124; fi
  OUTPUT=$(cat "$OUT" 2>/dev/null)
  return 0
}
# timed_out: tell the agent the typecheck produced no result, then exit without blocking.
timed_out() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"pyright timed out after "+sys.argv[1]+"s: no type result for this edit; run it manually."}}))' "$LIMIT" 2>/dev/null
  exit 0
}
run python -m pyright --version
[ "$EC" -eq 124 ] && timed_out
[ "$EC" -eq 0 ] || exit 0
run python -m pyright src/
[ "$EC" -eq 124 ] && timed_out
[ "$EC" -eq 0 ] && exit 0
out=$OUTPUT
# cap <bytes>: keep leading lines (each cut to 200 bytes on a UTF-8 boundary) within the budget, then count the dropped ones.
cap() { LC_ALL=C awk -v cap="$1" 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } { l = ucut($0, 200); if (len + length(l) + 1 > cap) { drop++; next } print l; len += length(l) + 1 } END { if (drop) printf "... %d more lines not shown\n", drop }'; }
errs=$(printf '%s\n' "$out" | grep -E ' - error' | cap 1700)
[ -n "$errs" ] || errs=$(printf '%s\n' "$out" | cap 1700)
[ -n "$errs" ] || exit 0
python3 -c 'import json,sys,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":("pyright reports type errors after this edit — fix them before moving on:\n"+os.fsencode(sys.argv[1]).decode("utf-8","replace"))[:2000]}}))' "$errs" 2>/dev/null
exit 0
