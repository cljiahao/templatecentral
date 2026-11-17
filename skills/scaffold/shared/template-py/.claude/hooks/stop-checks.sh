#!/usr/bin/env bash
# Stop — typecheck + run only the tests related to changed files; exit 2 (stderr to Claude) forces a fix.
# The full suite runs in pre-push and CI. stop_hook_active guard prevents re-entry after an exit-2 block.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
active=$(printf '%s' "$input" | python3 -c "import json,sys
try: print('true' if json.loads(sys.stdin.read() or '{}').get('stop_hook_active') is True else 'false')
except Exception: print('false')" 2>/dev/null)
[ "$active" = "true" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
files=$( { git diff --name-only --relative --diff-filter=d HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u)
src_changed=""
full=""
tests=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  base=${f##*/}; stem=${base%.py}
  # Config, lock and shared-fixture files can break every test: typecheck and run all of test/.
  case "$base" in
    pyproject.toml|uv.lock|requirements*.txt|pytest.ini|conftest.py) src_changed=1; full=1; continue ;;
  esac
  case "$f" in *.py) ;; *) continue ;; esac
  case "$f" in
    test/*|*/test/*|tests/*|*/tests/*)
      case "$stem" in
        test_*|*_test) tests="$tests
$f" ;;
        *) full=1 ;;  # conftest.py, factories, helpers: any test may depend on them
      esac ;;
    *)
      src_changed=1
      [ "$stem" = "__init__" ] && continue
      # (a) tests matching the changed module by name; (b) tests importing it.
      match=$(find test -type f \( -name "test_${stem}.py" -o -name "${stem}_test.py" \) 2>/dev/null)
      [ -n "$match" ] && tests="$tests
$match"
      dotted=$(printf '%s' "${f%.py}" | sed 's|^src/||; s|/|.|g')
      imp=$(grep -rlE --include='*.py' "^[[:space:]]*(from|import)[[:space:]]+(.*[[:space:].,])?(${dotted}|${stem})([[:space:].,]|$)" test 2>/dev/null)
      [ -n "$imp" ] && tests="$tests
$imp" ;;
  esac
done <<EOF2
$files
EOF2
[ -n "$tests$src_changed$full" ] || exit 0
[ -f .venv/bin/activate ] && . .venv/bin/activate
python -m pytest --version >/dev/null 2>&1 || { echo "pytest unavailable — skipping Stop gate" >&2; exit 0; }
if [ -n "$src_changed" ] && python -m pyright --version >/dev/null 2>&1; then
  OUTPUT=$(python -m pyright src/ 2>&1); EC=$?
  if [ "$EC" -ne 0 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
fi
# Changed/matching test files. A source change that selects none, or a test-support change, runs all of test/.
set --
while IFS= read -r t; do [ -n "$t" ] && set -- "$@" "$t"; done <<EOF2
$(printf '%s\n' "$tests" | sort -u)
EOF2
if [ -n "$full" ] || [ "$#" -eq 0 ]; then
  [ -d test ] || exit 0
  OUTPUT=$(python -m pytest -q test 2>&1); EC=$?
else
  OUTPUT=$(python -m pytest -q "$@" 2>&1); EC=$?
fi
# 5 = nothing collected.
if [ "$EC" -ne 0 ] && [ "$EC" -ne 5 ]; then echo "$OUTPUT" | tail -20 >&2; exit 2; fi
exit 0
