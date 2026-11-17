#!/usr/bin/env bash
# Stop — typecheck + tests; exit 2 (stderr to Claude) forces a fix. stop_hook_active guard prevents re-entry after an exit-2 block.
# Selection is sound or it is the full suite: when every changed file is a test file, run just those files;
# any other changed file (source, config, fixture, data, deletion, rename) or more than 50 changed files runs all of test/.
# Only docs and images are inert. Timeout: see docs/harness.md.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print('true' if json.loads(sys.stdin.read() or '{}').get('stop_hook_active') is True else 'false')
except Exception: print('false')" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
files=$( { git -c core.quotePath=false diff --name-only --no-renames HEAD; git -c core.quotePath=false ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
[ -n "$files" ] || exit 0
n=0; src_changed=""; full=""; tests=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  case "$f" in
    *.md|docs/*|*/docs/*|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|LICENSE|*/LICENSE|CHANGELOG*|*/CHANGELOG*) continue ;;
  esac
  case "$f" in
    test/*|*/test/*|tests/*|*/tests/*)
      case "${f##*/}" in
        # A deleted test file leaves nothing to run.
        test_*.py|*_test.py) [ -f "$f" ] && tests="$tests
$f"; continue ;;
      esac ;;
  esac
  src_changed=1; full=1
done <<EOF2
$files
EOF2
[ "$n" -gt 50 ] && { src_changed=1; full=1; }
[ -n "$tests$full" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
if [ -n "$src_changed" ] && python -m pyright --version >/dev/null 2>&1; then
  OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
  if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
if [ -n "$full" ]; then
  [ -d test ] || exit 0
  OUTPUT=$(python -m pytest -q test 2>&1); EC=$?
else
  set --
  while IFS= read -r t; do [ -n "$t" ] && set -- "$@" "$t"; done <<EOF2
$(printf '%s\n' "$tests" | sort -u)
EOF2
  OUTPUT=$(python -m pytest -q "$@" 2>&1); EC=$?
  # 5 = nothing collected; fine for a test-files-only run, never for the full suite.
  [ "$EC" -eq 5 ] && EC=0
fi
if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
