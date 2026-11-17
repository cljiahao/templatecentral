#!/usr/bin/env bash
# Stop — typecheck + run only the tests related to changed files; exit 2 (stderr to Claude) forces a fix.
# The full suite runs in pre-push and CI. stop_hook_active guard prevents re-entry after an exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Working-tree changes: tracked diff (deletions included) plus untracked files; quotePath off keeps non-ASCII names intact.
files=$( { git -c core.quotePath=false diff --name-only --relative HEAD; git -c core.quotePath=false ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
set --
any=""; cfg=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "${f##*/}" in
    vitest.config.*|vite.config.*|vitest.workspace.*|vitest.setup.*|package.json|tsconfig*.json|pnpm-lock.yaml|pnpm-workspace.yaml|.npmrc) any=1; cfg=1; continue ;;
  esac
  case "$f" in
    test/setup.*|*/test/setup.*) any=1; cfg=1; continue ;;
  esac
  case "$f" in
    *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs)
      any=1
      # A deleted code file has nothing to relate to: run everything.
      if [ -f "$f" ]; then set -- "$@" "$f"; else cfg=1; fi ;;
  esac
done <<EOF2
$files
EOF2
[ -n "$any" ] || exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
pnpm exec tsc --version >/dev/null 2>&1 || { echo "tsc unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm exec tsc --noEmit --incremental 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
pnpm exec vitest --version >/dev/null 2>&1 || { echo "vitest unavailable — skipping Stop gate" >&2; exit 0; }
# Config, setup, lockfile or deleted-file changes can break every test: run the full suite.
# A related run that finds no test for the changed files also falls back to the full suite.
if [ -z "$cfg" ]; then
  OUTPUT=$(pnpm exec vitest related --run "$@" 2>&1); EC=$?
  if [ "$EC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi "no test files found"; then cfg=1; fi
fi
if [ -n "$cfg" ]; then
  OUTPUT=$(pnpm exec vitest --run --passWithNoTests 2>&1); EC=$?
fi
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
