#!/usr/bin/env bash
# SubagentStop — type-gate a subagent's uncommitted TS changes so it can't hand back broken code.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
meta=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const d=JSON.parse(b||'{}');process.stdout.write((d.stop_hook_active===true?'true':'false')+' '+String(d.agent_type||''))}catch(e){process.stdout.write('false ')}})" 2>/dev/null)
# Already re-running after a block: do not loop.
[ "${meta%% *}" = "true" ] && exit 0
# Read-only built-in agents never edit.
case "${meta#* }" in Explore|Plan) exit 0 ;; esac
command -v pnpm >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed=$( { git diff --name-only HEAD; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | grep -E '\.(ts|tsx|mts|cts)$' | head -1)
[ -n "$changed" ] || exit 0
pnpm exec tsc --version >/dev/null 2>&1 || exit 0
OUTPUT=$(pnpm exec tsc --noEmit --incremental 2>&1); EC=$?
# cap <chars>: lines cut to 200 chars; over budget keeps the first lines and the last ones (a runner's summary), with the dropped count between.
cap() { LC_ALL=C awk -v cap="$1" 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } { L[NR] = ucut($0, 200); T += length(L[NR]) + 1 } END { if (T <= cap) { for (i = 1; i <= NR; i++) print L[i]; exit } room = cap - 40; hb = int(room / 2); for (h = 0; h < NR && hl + length(L[h + 1]) + 1 <= hb; h++) hl += length(L[h + 1]) + 1; for (t = 0; NR - t > h && tl + length(L[NR - t]) + 1 <= room - hl; t++) tl += length(L[NR - t]) + 1; for (i = 1; i <= h; i++) print L[i]; printf "... %d more lines not shown\n", NR - h - t; for (i = NR - t + 1; i <= NR; i++) print L[i] }'; }
if [ "$EC" -ne 0 ]; then printf '%s\n' "$OUTPUT" | cap 1900 >&2; exit 2; fi
exit 0
