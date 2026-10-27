#!/usr/bin/env bash
# PostToolUse(Edit|Write) — fast type feedback on TS edits only. Feedback-only (never blocks).
# Errors reach Claude via hookSpecificOutput.additionalContext — plain stdout from a
# PostToolUse hook goes to the debug log only. Always exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
file=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const ti=(JSON.parse(b||'{}').tool_input)||{};process.stdout.write(ti.file_path||ti.path||'')}catch(e){process.stdout.write('')}})" 2>/dev/null)
case "$file" in *.ts|*.tsx|*.mts|*.cts) ;; *) exit 0 ;; esac
command -v pnpm >/dev/null 2>&1 || exit 0
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
out=$(pnpm exec tsc --noEmit --incremental 2>&1) && exit 0
errs=$(printf '%s\n' "$out" | grep -E 'error TS[0-9]+' | head -20)
[ -n "$errs" ] || errs=$(printf '%s\n' "$out" | tail -20)
[ -n "$errs" ] || exit 0
node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("tsc --noEmit reports type errors after this edit — fix them before moving on:\n"+process.argv[1]).slice(0,9000)}}))' "$errs" 2>/dev/null
exit 0
