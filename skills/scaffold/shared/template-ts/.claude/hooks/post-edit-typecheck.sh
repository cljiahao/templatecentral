#!/usr/bin/env bash
# PostToolUse(Edit|Write): fast type feedback, never blocks; errors reach Claude via additionalContext.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx|*.mts|*.cts) ;; *) exit 0 ;; esac
command -v pnpm >/dev/null 2>&1 || exit 0
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
  node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"tsc --noEmit timed out after "+process.argv[1]+"s: no type result for this edit; run it manually."}}))' "$LIMIT" 2>/dev/null
  exit 0
}
run pnpm exec tsc --version
[ "$EC" -eq 124 ] && timed_out
[ "$EC" -eq 0 ] || exit 0
run pnpm exec tsc --noEmit --incremental
[ "$EC" -eq 124 ] && timed_out
[ "$EC" -eq 0 ] && exit 0
out=$OUTPUT
# cap <bytes>: keep leading lines (each cut to 200 bytes on a UTF-8 boundary) within the budget, then count the dropped ones.
cap() { LC_ALL=C awk -v cap="$1" 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } { l = ucut($0, 200); if (len + length(l) + 1 > cap) { drop++; next } print l; len += length(l) + 1 } END { if (drop) printf "... %d more lines not shown\n", drop }'; }
errs=$(printf '%s\n' "$out" | grep -E 'error TS[0-9]+' | cap 1700)
[ -n "$errs" ] || errs=$(printf '%s\n' "$out" | cap 1700)
[ -n "$errs" ] || exit 0
node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:Array.from("tsc --noEmit reports type errors after this edit — fix them before moving on:\n"+process.argv[1]).slice(0,2000).join("")}}))' "$errs" 2>/dev/null
exit 0
