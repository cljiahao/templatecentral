#!/usr/bin/env bash
# Stop — typecheck + tests; exit 2 (stderr to Claude) forces a fix. stop_hook_active guard prevents re-entry after an exit-2 block.
# Code files in the diff run `vitest related` (it follows the module graph); any other file in the diff (config, setup,
# lockfile, data, snapshot, deletion, rename) or more than 50 changed files runs `pnpm test`.
# Inert (nothing runs): root *.md, root LICENSE*/CHANGELOG*, and .md or images under the top-level docs/ directory.
# Fails closed: a missing tool or a run past STOP_GATE_LIMIT seconds (default 270, under the 300 s hook timeout) exits 2 with a message.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Paths in the diff: deletions and renames as separate paths, untracked included; without a HEAD commit, everything tracked or untracked.
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  files=$( { git -c core.quotePath=false diff --name-only --no-renames HEAD; git -c core.quotePath=false ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
else
  files=$(git -c core.quotePath=false ls-files --cached --others --exclude-standard 2>/dev/null | sort -u)
fi
[ -n "$files" ] || exit 0
# Files named in a vitest config's setupFiles are setup code: changing one can change every test.
setup_files=$(cat vitest.config.* vite.config.* vitest.workspace.* 2>/dev/null | grep -A4 'setupFiles' | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"" | sed 's|^\./||')
set --
n=0; any=""; cfg=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  case "$f" in
    */*) case "$f" in docs/*.md|docs/*.png|docs/*.jpg|docs/*.jpeg|docs/*.gif|docs/*.ico) continue ;; esac ;;
    *) case "$f" in *.md|LICENSE*|CHANGELOG*) continue ;; esac ;;
  esac
  any=1
  case "$f" in
    *.ts|*.tsx|*.mts|*.cts|*.js|*.jsx|*.mjs|*.cjs) ;;
    *) cfg=1; continue ;;
  esac
  case "${f##*/}" in
    vitest.*|vite.config.*) cfg=1; continue ;;
  esac
  case "$f" in
    test/setup.*|*/test/setup.*) cfg=1; continue ;;
    # Any root-level *.config.* file (next, playwright, eslint, postcss, ...) can change how every test builds or runs.
    */*) ;;
    *.config.*) cfg=1; continue ;;
  esac
  if [ -n "$setup_files" ] && printf '%s\n' "$setup_files" | grep -qxF "$f"; then cfg=1; continue; fi
  # A deleted code file has nothing to relate to: run everything.
  if [ -f "$f" ]; then set -- "$@" "$f"; else cfg=1; fi
done <<EOF2
$files
EOF2
[ "$n" -gt 50 ] && { any=1; cfg=1; }
[ -n "$any" ] || exit 0
LIMIT=${STOP_GATE_LIMIT:-270}
DEADLINE=$(( $(date +%s) + LIMIT ))
OUT=$(mktemp "${TMPDIR:-/tmp}/stopgate.XXXXXX") || { echo "Stop gate: cannot create a temporary file" >&2; exit 2; }
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
# fail <label>: report a failed or timed-out step and block.
fail() {
  if [ "$EC" -eq 124 ]; then echo "Stop gate timed out after ${LIMIT}s while running $1; run it manually (pre-push and CI still gate this change)." >&2
  else echo "$OUTPUT" | tail -20 >&2; fi
  exit 2
}
command -v pnpm >/dev/null 2>&1 || { echo "Stop gate cannot run: pnpm is unavailable; install it (corepack enable)." >&2; exit 2; }
pnpm exec tsc --version >/dev/null 2>&1 || { echo "Stop gate cannot run: tsc is unavailable (pnpm exec tsc); run pnpm install." >&2; exit 2; }
run pnpm exec tsc --noEmit --incremental
[ "$EC" -eq 0 ] || fail tsc
if [ -z "$cfg" ]; then
  pnpm exec vitest --version >/dev/null 2>&1 || { echo "Stop gate cannot run: vitest is unavailable (pnpm exec vitest); run pnpm install." >&2; exit 2; }
  run pnpm exec vitest related --run "$@"
  # A related run that selects no test never passes silently: fall back to the full suite.
  if [ "$EC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi "no test files found"; then cfg=1; fi
fi
[ -z "$cfg" ] || run pnpm test
[ "$EC" -eq 0 ] || fail tests
exit 0
