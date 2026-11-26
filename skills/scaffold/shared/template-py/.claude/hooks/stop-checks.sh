#!/usr/bin/env bash
# Stop — typecheck + tests; exit 2 (stderr to Claude) forces a fix. stop_hook_active guard prevents re-entry after an exit-2 block.
# Selection is sound or it is the full suite: when every changed file is a test file, run just those files;
# any other changed file (source, config, fixture, data, deletion, rename) or more than 50 changed files runs all tests.
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
active=$(printf '%s' "$input" | python3 -I -c "import json,sys
try: print('true' if json.loads(sys.stdin.read() or '{}').get('stop_hook_active') is True else 'false')
except Exception: print('false')" 2>/dev/null)
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
# Paths relative to the project dir, untracked included; without a HEAD commit, every file.
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
n=0; src_changed=""; full=""; tests=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  case "$f" in
    */*) case "$f" in docs/*.md|docs/*.png|docs/*.jpg|docs/*.jpeg|docs/*.gif|docs/*.ico) continue ;; esac ;;
    *) case "$f" in *.md|LICENSE*|CHANGELOG*) continue ;; esac ;;
  esac
  case "$f" in
    test/*|tests/*)
      case "${f##*/}" in
        # A deleted test-pattern file may be a helper other tests import: run everything.
        test_*.py|*_test.py) if [ -f "$f" ]; then tests="$tests
./$f"; else full=1; fi; continue ;;
      esac ;;
  esac
  src_changed=1; full=1
done <<EOF2
$files
EOF2
[ "$n" -gt 50 ] && { src_changed=1; full=1; }
[ -n "$tests$full" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
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
# cap <chars>: lines cut to 200 chars; over budget keeps the first lines and the last ones (a runner's summary), with the dropped count between.
cap() { LC_ALL=C awk -v cap="$1" 'function ucut(s, n) { if (length(s) <= n) return s; s = substr(s, 1, n); sub(/[\300-\337]$/, "", s); sub(/[\340-\357][\200-\277]?$/, "", s); sub(/[\360-\367]([\200-\277]([\200-\277])?)?$/, "", s); return s } { L[NR] = ucut($0, 200); T += length(L[NR]) + 1 } END { if (T <= cap) { for (i = 1; i <= NR; i++) print L[i]; exit } room = cap - 40; hb = int(room / 2); for (h = 0; h < NR && hl + length(L[h + 1]) + 1 <= hb; h++) hl += length(L[h + 1]) + 1; for (t = 0; NR - t > h && tl + length(L[NR - t]) + 1 <= room - hl; t++) tl += length(L[NR - t]) + 1; for (i = 1; i <= h; i++) print L[i]; printf "... %d more lines not shown\n", NR - h - t; for (i = NR - t + 1; i <= NR; i++) print L[i] }'; }
# fail <label>: report a failed or timed-out step and block.
fail() {
  if [ "$EC" -eq 124 ]; then echo "Stop gate timed out after ${LIMIT}s while running $1; run it manually (pre-push and CI still gate this change)." >&2
  else printf '%s\n' "$OUTPUT" | cap 1900 >&2; fi
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
probe "pytest --version" "Stop gate cannot run: pytest is unavailable (python -m pytest); install the dev dependencies." python -m pytest --version
if [ -n "$src_changed" ]; then
  probe "pyright --version" "Stop gate cannot run: pyright is unavailable (python -m pyright); install the dev dependencies." python -I -m pyright --version
  run python -I -m pyright src/
  [ "$EC" -eq 0 ] || fail pyright
fi
if [ -n "$full" ]; then
  tdirs=""
  [ -d test ] && tdirs="test"
  [ -d tests ] && tdirs="$tdirs tests"
  # shellcheck disable=SC2086
  run python -m pytest -q $tdirs
  # With no test/ or tests/ directory pytest uses the configured testpaths; collecting nothing there is a failure, not a pass.
  if [ "$EC" -eq 5 ]; then echo "Stop gate: pytest collected no tests (no test/ or tests/ directory and no testpaths); add tests or configure testpaths." >&2; exit 2; fi
else
  set --
  while IFS= read -r t; do [ -n "$t" ] && set -- "$@" "$t"; done <<EOF2
$(printf '%s\n' "$tests" | sort -u)
EOF2
  run python -m pytest -q "$@"
  # 5 = nothing collected; fine for a test-files-only run, never for the full suite.
  [ "$EC" -eq 5 ] && EC=0
fi
[ "$EC" -eq 0 ] || fail pytest
exit 0
