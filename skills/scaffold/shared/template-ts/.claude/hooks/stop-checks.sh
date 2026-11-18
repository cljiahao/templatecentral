#!/usr/bin/env bash
# Stop — typecheck + tests; exit 2 (stderr to Claude) forces a fix. stop_hook_active guard prevents re-entry after an exit-2 block.
# Code files in the diff run `vitest related` (it follows the module graph); any other file in the diff (config, setup,
# lockfile, data, snapshot, deletion, rename) or more than 50 changed files runs `pnpm test`.
# Only changes inside the project directory count, even when it is a subdirectory of the repository.
# Inert (nothing runs): root *.md, root LICENSE*/CHANGELOG*, and .md, .png, .jpg, .jpeg, .gif or .ico files under the top-level docs/ directory.
# Fails closed: a missing tool or a run past STOP_GATE_LIMIT seconds (default 270, under the 300 s hook timeout) exits 2 with a message.
# Change detection never fails open: a missing project dir, a missing git, a broken repository or an unreadable index exits 2, not 0.
# Only positive evidence (no .git entry here or in any parent, git itself working) lets the hook exit 0 as "not a repository".
# A GIT_DIR, GIT_WORK_TREE or GIT_INDEX_FILE inherited from the hook environment must not redirect change detection.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
gate_git_fail() { echo "Stop gate: cannot read changed files ($1); repair the repository or run the checks manually." >&2; exit 2; }
PROJ="${CLAUDE_PROJECT_DIR:-.}"
input=$(cat)
active=$(printf '%s' "$input" | node -e "let b='';process.stdin.on('data',c=>b+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(b||'{}').stop_hook_active===true?'true':'false')}catch(e){process.stdout.write('false')}})" 2>/dev/null)
[ "$active" = "true" ] && exit 0
if ! cd "$PROJ" 2>/dev/null; then
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && gate_git_fail "cannot enter project directory $PROJ"
  exit 0
fi
command -v git >/dev/null 2>&1 || gate_git_fail "git is not on PATH"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  d=$PWD
  while :; do
    [ -e "$d/.git" ] && gate_git_fail "git rev-parse failed inside a repository"
    [ "$d" = / ] && break
    d=${d%/*}; [ -n "$d" ] || d=/
  done
  exit 0
fi
# Paths in the diff, relative to the project dir and limited to it (--relative; ls-files is cwd-scoped): deletions and renames as separate paths, untracked included; without a HEAD commit, everything tracked or untracked.
git rev-parse --verify -q HEAD >/dev/null 2>&1; head_rc=$?
if [ "$head_rc" -eq 0 ]; then
  diff_out=$(git -c core.quotePath=false diff --relative --name-only --no-renames HEAD 2>/dev/null) || gate_git_fail "git diff failed"
  new_out=$(git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null) || gate_git_fail "git ls-files failed"
  files=$(printf '%s\n%s\n' "$diff_out" "$new_out" | sort -u)
elif [ "$head_rc" -eq 1 ]; then
  all_out=$(git -c core.quotePath=false ls-files --cached --others --exclude-standard 2>/dev/null) || gate_git_fail "git ls-files failed"
  files=$(printf '%s\n' "$all_out" | sort -u)
else
  gate_git_fail "git rev-parse HEAD failed"
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
  # "./" keeps a name that starts with "-" from being read as an option.
  if [ -f "$f" ]; then set -- "$@" "./$f"; else cfg=1; fi
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
# probe <label> <message> <cmd...>: version probe under the shared deadline; a timeout reports like any step, a failure prints the message.
probe() {
  local label=$1 msg=$2
  shift 2
  run "$@"
  [ "$EC" -eq 124 ] && fail "$label"
  [ "$EC" -eq 0 ] || { echo "$msg" >&2; exit 2; }
}
command -v pnpm >/dev/null 2>&1 || { echo "Stop gate cannot run: pnpm is unavailable; install it (corepack enable)." >&2; exit 2; }
probe "tsc --version" "Stop gate cannot run: tsc is unavailable (pnpm exec tsc); run pnpm install." pnpm exec tsc --version
run pnpm exec tsc --noEmit --incremental
[ "$EC" -eq 0 ] || fail tsc
if [ -z "$cfg" ]; then
  probe "vitest --version" "Stop gate cannot run: vitest is unavailable (pnpm exec vitest); run pnpm install." pnpm exec vitest --version
  run pnpm exec vitest related --run "$@"
  # A related run that selects no test never passes silently: fall back to the full suite.
  if [ "$EC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi "no test files found"; then cfg=1; fi
fi
[ -z "$cfg" ] || run pnpm test
[ "$EC" -eq 0 ] || fail tests
exit 0
