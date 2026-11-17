#!/usr/bin/env bash
# Stop — typecheck + tests; exit 2 (stderr to Claude) forces a fix. stop_hook_active guard prevents re-entry after an exit-2 block.
# Code files in the diff run `vitest related` (it follows the module graph); any other file in the diff (config, setup,
# lockfile, data, snapshot, deletion, rename) or more than 50 changed files runs `pnpm test`. Only docs and images are inert.
# Timeout: see docs/harness.md.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Working-tree changes: tracked diff (deletions and renames as separate paths) plus untracked; quotePath off keeps non-ASCII names intact.
files=$( { git -c core.quotePath=false diff --name-only --no-renames HEAD; git -c core.quotePath=false ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
[ -n "$files" ] || exit 0
set --
n=0; any=""; cfg=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  case "$f" in
    *.md|docs/*|*/docs/*|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|LICENSE|*/LICENSE|CHANGELOG*|*/CHANGELOG*) continue ;;
  esac
  any=1
  case "$f" in
    *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs) ;;
    *) cfg=1; continue ;;
  esac
  case "${f##*/}" in
    vitest.config.*|vite.config.*|vitest.workspace.*|vitest.setup.*) cfg=1; continue ;;
  esac
  case "$f" in
    test/setup.*|*/test/setup.*) cfg=1; continue ;;
  esac
  # A deleted code file has nothing to relate to: run everything.
  if [ -f "$f" ]; then set -- "$@" "$f"; else cfg=1; fi
done <<EOF2
$files
EOF2
[ "$n" -gt 50 ] && { any=1; cfg=1; }
[ -n "$any" ] || exit 0
command -v pnpm >/dev/null 2>&1 || { echo "pnpm unavailable — skipping Stop gate" >&2; exit 0; }
pnpm exec tsc --version >/dev/null 2>&1 || { echo "tsc unavailable — skipping Stop gate" >&2; exit 0; }
OUTPUT=$(pnpm exec tsc --noEmit --incremental 2>&1); EC=$?
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
if [ -z "$cfg" ]; then
  pnpm exec vitest --version >/dev/null 2>&1 || { echo "vitest unavailable — skipping Stop gate" >&2; exit 0; }
  OUTPUT=$(pnpm exec vitest related --run "$@" 2>&1); EC=$?
  # A related run that selects no test never passes silently: fall back to the full suite.
  if [ "$EC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi "no test files found"; then cfg=1; fi
fi
if [ -n "$cfg" ]; then
  OUTPUT=$(pnpm test 2>&1); EC=$?
fi
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
