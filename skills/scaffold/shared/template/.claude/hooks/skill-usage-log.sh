#!/usr/bin/env bash
# PostToolUse(Skill) — silent skill-usage logger. Records which skills are invoked so the
# /skill-audit skill can later surface workflows worth capturing as a committed project skill.
# Silent + non-blocking: always exits 0, never interrupts. Log is per-developer (gitignored).
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
# Real JSON parse (a regex misreads values containing `}`): node on TS stacks, python3 on FastAPI.
if command -v node >/dev/null 2>&1; then
  name=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{const s=((JSON.parse(b||'{}')||{}).tool_input||{}).skill;if(typeof s==='string')process.stdout.write(s)}catch(e){}})" 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  name=$(printf '%s' "$input" | python3 -c "import json,sys
try:
    s=(json.load(sys.stdin).get('tool_input') or {}).get('skill')
except Exception:
    s=None
sys.stdout.write(s if isinstance(s, str) else '')" 2>/dev/null)
else
  exit 0
fi
name=$(printf '%s' "$name" | head -1 | tr -d '\t\r')
[ -z "$name" ] && exit 0
[ -d .claude ] || exit 0
printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" >> .claude/skill-usage.log 2>/dev/null
exit 0
