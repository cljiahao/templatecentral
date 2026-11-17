#!/usr/bin/env bash
# Stop — typecheck + run only the tests related to changed files; exit 2 (stderr to Claude) forces a fix.
# The full suite runs in pre-push and CI. stop_hook_active guard prevents re-entry after an exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Working-tree code files (tracked diff plus untracked) present on disk.
files=$( { git diff --name-only --relative --diff-filter=d HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
set --
any=""; cfg=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "${f##*/}" in
    vitest.config.*|package.json|tsconfig*.json|pnpm-lock.yaml) any=1; cfg=1; continue ;;
  esac
  case "$f" in *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs) any=1; set -- "$@" "$f" ;; esac
done <<EOF2
$files
EOF2
[ -n "$any" ] || exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
pnpm exec tsc --version >/dev/null 2>&1 || { echo "tsc unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm exec tsc --noEmit --incremental 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
pnpm exec vitest --version >/dev/null 2>&1 || { echo "vitest unavailable — skipping Stop gate" >&2; exit 0; }
# Config or lockfile changes can break every test: run the full suite, not just related files.
if [ -n "$cfg" ]; then
  OUTPUT=$(pnpm exec vitest --run --passWithNoTests 2>&1); EC=$?
else
  OUTPUT=$(pnpm exec vitest related --run --passWithNoTests "$@" 2>&1); EC=$?
fi
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
