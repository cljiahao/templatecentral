#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted TS changes so it can't hand back broken code.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
meta=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const d=JSON.parse(b||'{}');process.stdout.write((d.stop_hook_active===true?'true':'false')+' '+String(d.agent_type||''))}catch(e){process.stdout.write('false ')}})" 2>/dev/null)
[ "${meta%% *}" = "true" ] && exit 0          # already re-running after a block — don't loop
case "${meta#* }" in Explore|Plan) exit 0 ;; esac   # read-only built-in agents never edit
command -v pnpm >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed=$( { git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '\.(ts|tsx|mts|cts)$' | head -1)
[ -n "$changed" ] || exit 0
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
OUTPUT=$(pnpm exec tsc --noEmit --incremental 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
