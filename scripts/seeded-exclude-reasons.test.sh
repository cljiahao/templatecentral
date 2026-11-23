#!/usr/bin/env bash
# Tests for the seeded gate skills/scaffold/shared/template/scripts/check-exclude-reasons.sh.
# Every failing fixture under tests/fixtures/exclusions/ has a clean control that differs only by the reason line. The gate runs on a
# copy of each fixture, so the fixtures stay untouched; their hashes are compared before and after the run.
# The JS and TS scanner needs a typescript install to read configs. This script looks in TC_TEST_TYPESCRIPT, ./node_modules,
# the global npm root and the usual project folders under $HOME, and fails closed when it finds none.
# Usage: bash scripts/seeded-exclude-reasons.test.sh        Needs bash 3.2+, find, awk, node, python3. No network.
set -uo pipefail
export LC_ALL=C

root=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd) || exit 2
cd "$root" || exit 2
GATE=skills/scaffold/shared/template/scripts/check-exclude-reasons.sh
FIX=$root/tests/fixtures/exclusions
WORK=$(mktemp -d "${TMPDIR:-/tmp}/exclude-reasons-test.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

pass=0
failed=0
ok() {
  pass=$((pass + 1))
  printf 'ok - %s\n' "$1"
}
nok() {
  failed=$((failed + 1))
  printf 'not ok - %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | head -n 6 | sed 's/^/    /'; fi
}

find_typescript() {
  local c
  for c in "${TC_TEST_TYPESCRIPT:-}" "$root/node_modules/typescript" "$(npm root -g 2> /dev/null)/typescript" \
    "$HOME"/*/node_modules/typescript "$HOME"/*/*/node_modules/typescript; do
    if [ -n "$c" ] && [ -f "$c/package.json" ] && [ -f "$c/lib/typescript.js" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}
if ! TS=$(find_typescript); then
  echo "seeded-exclude-reasons.test: no typescript install found. Set TC_TEST_TYPESCRIPT to a typescript package folder." >&2
  exit 1
fi

tree_hash() {
  (cd "$1" && find . -path ./node_modules -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done | shasum | cut -d' ' -f1)
}

# Copy fixture NAME to a fresh folder and link typescript into it (unless the second argument is "no-ts").
stage() {
  local d=$WORK/$1
  rm -rf "$d"
  mkdir -p "$d"
  cp -R "$FIX/$1/." "$d/"
  if [ "${2:-}" != no-ts ]; then
    mkdir -p "$d/node_modules"
    ln -s "$TS" "$d/node_modules/typescript"
  fi
  printf '%s' "$d"
}

OUT=
RC=0
run_gate() {
  OUT=$(bash "$root/$GATE" "$1" 2>&1)
  RC=$?
}

expect_ok() {
  local d
  d=$(stage "$1")
  run_gate "$d"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'OK\.'; then ok "$1 passes"; else nok "$1 should pass (exit $RC)" "$OUT"; fi
}
# expect_fail NAME PATTERN: exit 1 and PATTERN (extended regex) in the output.
expect_fail() {
  local d
  d=$(stage "$1")
  run_gate "$d"
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -Eq -- "$2"; then ok "$1 fails with: $2"; else nok "$1 should fail with '$2' (exit $RC)" "$OUT"; fi
}

before=$(tree_hash "$FIX")

# Four stacks, each with a clean control and every failure form.
for stack in nextjs nestjs vite-react; do
  case "$stack" in vite-react) cfg=vite.config.ts ;; *) cfg=vitest.config.ts ;; esac
  expect_ok "$stack-ok"
  expect_ok "$stack-textonly"
  if printf '%s' "$OUT" | grep -Eq 'hidden|secret'; then nok "$stack-textonly reads an entry out of a string or comment" "$OUT"; else ok "$stack-textonly ignores entries inside a string and a comment"; fi
  for v in none blank below short nocolon twoabove; do
    expect_fail "$stack-$v" "$cfg:[0-9]+ coverage-exclude entry 'src/gen/\*\*' has no reason\. Fix: add a comment line directly above it"
  done
  expect_fail "$stack-include-noreason" "$cfg:[0-9]+ coverage-include list 'src/\*\*/\*\.ts' is an allow-list"
  for v in spread variable call; do
    expect_fail "$stack-$v" "$cfg:[0-9]+ the coverage exclude list is built dynamically .*literal"
  done
  expect_fail "$stack-unparseable" "$cfg:[0-9]+ config has a syntax error, so it cannot be read\. Supported forms:"
done
expect_fail vitest-spread-test "a spread inside the test block can hide the coverage block"

# Python: pyproject.toml for FastAPI.
expect_ok fastapi-clean
expect_ok fastapi-textonly
if printf '%s' "$OUT" | grep -Eq 'hidden|secret'; then nok "fastapi-textonly reads an entry out of a string or comment" "$OUT"; else ok "fastapi-textonly ignores entries inside a string and a comment"; fi
for key in omit exclude-also exclude-lines; do
  expect_ok "fastapi-$key-ok"
  for v in none blank below short nocolon twoabove; do
    expect_fail "fastapi-$key-$v" "pyproject.toml:[0-9]+ coverage-exclude entry '[^']+' has no reason\. Fix:"
  done
done
expect_ok fastapi-single-above-key
expect_fail fastapi-single-nokey "pyproject.toml:2 coverage-exclude entry 'app/migrations/\*' has no reason"
expect_ok fastapi-include-ok
expect_fail fastapi-include-noreason "pyproject.toml:2 coverage-include list 'app/api/\*' is an allow-list"
expect_fail fastapi-unparseable "pyproject.toml:[0-9]+ toml cannot be read"
expect_ok mutmut-toml-ok
expect_fail mutmut-toml-none "pyproject.toml:2 mutation-exclude entry 'app/constants/\*' has no reason"

# Shadow files: coverage settings in .coveragerc, setup.cfg and tox.ini beside a clean pyproject.toml.
for f in coveragerc setup-cfg tox-ini; do
  case "$f" in coveragerc) file=.coveragerc ;; setup-cfg) file=setup.cfg ;; *) file=tox.ini ;; esac
  expect_ok "shadow-$f-ok"
  expect_fail "shadow-$f-none" "$file:[0-9]+ coverage-exclude entry 'app/migrations/\*' has no reason"
  expect_fail "shadow-$f-blank" "$file:[0-9]+ coverage-exclude entry 'app/migrations/\*' has no reason"
done
expect_ok mutmut-cfg-ok
expect_fail mutmut-cfg-none "setup.cfg:2 mutation-exclude entry 'app/constants/\*' has no reason"
expect_fail ini-unparseable "setup.cfg:[0-9]+ ini cannot be read"

# Jest and Stryker.
expect_ok jest-ok
expect_fail jest-none "jest.config.js:[0-9]+ coverage-exclude entry '<rootDir>/src/gen/' has no reason"
expect_ok jest-collect-ok
expect_fail jest-collect-none "jest.config.js:[0-9]+ coverage-(include list|exclude entry)"
expect_fail jest-package-key "package.json:[0-9]+ coverage-exclude entry '<rootDir>/src/gen/' has no reason\. .*package.json cannot hold a comment"
expect_fail jest-dynamic "jest.config.js:[0-9]+ coveragePathIgnorePatterns is built dynamically"
expect_ok stryker-ok
expect_fail stryker-none "stryker.config.mjs:[0-9]+ mutation-exclude entry '!src/integrations/\*\*' has no reason"
expect_fail stryker-dynamic "stryker.config.mjs:[0-9]+ the mutate list is built dynamically"

# Sonar properties.
expect_ok sonar-ok
expect_ok sonar-multi-ok
expect_ok sonar-include-ok
expect_ok sonar-issue-ok
expect_ok sonar-comment-text
if printf '%s' "$OUT" | grep -q hidden; then nok "sonar-comment-text reads a commented key" "$OUT"; else ok "sonar-comment-text ignores a commented key"; fi
expect_fail sonar-none "sonar-project.properties:3 sonar-exclude entry 'src/gen/\*\*' has no reason\. Fix: .*# reason:"
expect_fail sonar-blank "sonar-project.properties:5 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_fail sonar-short "sonar-project.properties:4 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_fail sonar-multi-none "sonar-project.properties:5 sonar-exclude entry 'src/legacy/\*\*' has no reason"
expect_fail sonar-include "sonar-project.properties:3 coverage-include list 'src/api/\*\*' is an allow-list"
expect_fail sonar-cpd "sonar-project.properties:3 sonar-cpd-exclude entry 'src/gen/\*\*' has no reason"
expect_fail sonar-test "sonar-project.properties:3 sonar-test-exclude entry 'src/fixtures/\*\*' has no reason"
expect_fail sonar-issue "sonar-project.properties:3 sonar-issue-ignore entry"

# The one seeded exclude needs a reason like any other.
expect_ok ui-seeded
expect_fail ui-seeded-noreason "vitest.config.ts:9 coverage-exclude entry 'src/components/ui/\*\*' has no reason"

# No config at all, and a project with source but no coverage config, pass with a clear line.
for n in empty-project no-coverage-ts; do
  d=$(stage "$n")
  run_gate "$d"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'no coverage, Sonar or mutation config found; nothing to check'; then ok "$n passes with the nothing-to-check line"; else nok "$n should pass with the nothing-to-check line (exit $RC)" "$OUT"; fi
done

# A config exists but typescript is not installed: fail closed and say what is supported.
d=$(stage nextjs-ok no-ts)
run_gate "$d"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'typescript is not installed' && printf '%s' "$OUT" | grep -q 'Supported forms:'; then ok "missing typescript fails closed"; else nok "missing typescript should fail closed (exit $RC)" "$OUT"; fi

# Nothing switches the gate off.
d=$(stage nextjs-none)
OUT=$(CI=true GITHUB_ACTIONS=true TC_SKIP=1 SKIP=1 SKIP_EXCLUDE_REASONS=1 TC_SKIP_EXCLUDE_REASONS=1 CHECK_EXCLUDE_REASONS=0 bash "$root/$GATE" "$d" 2>&1)
RC=$?
if [ "$RC" -eq 1 ]; then ok "no environment variable skips the gate"; else nok "an environment variable changed the result (exit $RC)" "$OUT"; fi
d=$(stage nextjs-none)
{ printf '// check-exclude-reasons: off\n// eslint-disable\n'; cat "$d/vitest.config.ts"; } > "$d/v.tmp" && mv "$d/v.tmp" "$d/vitest.config.ts"
run_gate "$d"
if [ "$RC" -eq 1 ]; then ok "no inline marker switches the gate off"; else nok "an inline marker changed the result (exit $RC)" "$OUT"; fi

# The default list lives in one place.
n=$(grep -c '^DEFAULTS=' "$GATE")
if [ "$n" -eq 1 ]; then ok "one DEFAULTS list in the gate"; else nok "expected one DEFAULTS list, found $n"; fi
leak=$(grep -l "node_modules/\*\*" skills/scaffold/shared/template/scripts/check-exclude-reasons.mjs skills/scaffold/shared/template/scripts/check-exclude-reasons.py skills/scaffold/shared/template/scripts/check-exclude-reasons.awk 2> /dev/null || true)
if [ -z "$leak" ]; then ok "no scanner carries its own default list"; else nok "a scanner repeats the default list" "$leak"; fi

# Usage errors exit 2.
usage_case() {
  local label=$1
  shift
  OUT=$(bash "$root/$GATE" "$@" 2>&1)
  RC=$?
  if [ "$RC" -eq 2 ]; then ok "usage error ($label) exits 2"; else nok "usage error ($label) should exit 2 (got $RC)" "$OUT"; fi
}
usage_case "unknown option" --bogus
usage_case "two folders" "$WORK" "$WORK"
usage_case "missing folder" "$WORK/no-such-folder"

# Sensitivity: weaken the 3-word rule in a copy of the gate; the short-reason fixture must then pass, which shows the real test bites.
mut=$WORK/mutant
mkdir -p "$mut"
cp skills/scaffold/shared/template/scripts/check-exclude-reasons.* "$mut/"
sed 's/{2,}/{0,}/' "$mut/check-exclude-reasons.mjs" > "$mut/m.tmp" && mv "$mut/m.tmp" "$mut/check-exclude-reasons.mjs"
d=$(stage nextjs-short)
OUT=$(bash "$mut/check-exclude-reasons.sh" "$d" 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then ok "a gate with a weaker word rule lets nextjs-short through, so the fixture is a real test"; else nok "mutant did not change the result (exit $RC)" "$OUT"; fi

# Read-only: the gate never changes a project, and the fixtures are as they were.
d=$(stage jest-none)
h1=$(tree_hash "$d")
run_gate "$d"
h2=$(tree_hash "$d")
if [ "$h1" = "$h2" ]; then ok "the gate leaves the project untouched"; else nok "the gate changed the project"; fi
after=$(tree_hash "$FIX")
if [ "$before" = "$after" ]; then ok "fixtures unchanged by the run"; else nok "fixtures changed during the run"; fi

printf '%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
