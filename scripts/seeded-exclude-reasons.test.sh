#!/usr/bin/env bash
# Tests for the seeded gate skills/scaffold/shared/template/scripts/check-exclude-reasons.sh.
# Every failing fixture under tests/fixtures/exclusions/ has a clean control that differs only by the reason line. The gate runs on a
# copy of each fixture, so the fixtures stay untouched; their hashes are compared before and after the run.
# The JS and TS scanner needs a typescript install to read configs. This script uses TC_TEST_TYPESCRIPT_DIR, then ./node_modules, then
# the version pinned in skills/scaffold/shared/versions.txt installed once into a cache folder under $TMPDIR. It never scans a home folder.
# Usage: bash scripts/seeded-exclude-reasons.test.sh        Needs bash 3.2+, find, awk, node, python3; npm and network only for the first cache install.
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

ts_ok() { [ -n "$1" ] && [ -f "$1/package.json" ] && [ -f "$1/lib/typescript.js" ]; }
find_typescript() {
  local c ver cache
  for c in "${TC_TEST_TYPESCRIPT_DIR:-}" "$root/node_modules/typescript"; do
    if ts_ok "$c"; then
      printf '%s' "$c"
      return 0
    fi
  done
  ver=$(awk '$1 == "npm" && $2 == "typescript" { v = $3; sub(/^[^0-9]*/, "", v); print v }' "$root/skills/scaffold/shared/versions.txt")
  [ -n "$ver" ] || return 1
  cache=${TMPDIR:-/tmp}/tc-test-typescript-$ver
  if ! ts_ok "$cache/node_modules/typescript"; then
    mkdir -p "$cache" && npm install --prefix "$cache" --no-audit --no-fund --silent "typescript@$ver" > /dev/null 2>&1
  fi
  if ts_ok "$cache/node_modules/typescript"; then
    printf '%s' "$cache/node_modules/typescript"
    return 0
  fi
  return 1
}
if ! TS=$(find_typescript); then
  echo "seeded-exclude-reasons.test: no typescript found. Set TC_TEST_TYPESCRIPT_DIR to a typescript package folder, or allow the pinned version to install into \$TMPDIR." >&2
  exit 1
fi

# Hash a tree by file name and size only. No file is opened, so a secret-named file in a fixture is never read.
fsize() { stat -f %z "$1" 2> /dev/null || stat -c %s "$1"; }
tree_hash() {
  (cd "$1" && find . -path ./node_modules -prune -o \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(fsize "$f")"; else printf '%s\n' "$f"; fi
  done | shasum | cut -d' ' -f1)
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

# An empty folder passes with its own line; a project with source files and no coverage config fails.
d=$(stage empty-project)
run_gate "$d"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'no source files and no coverage, Sonar or mutation config found; nothing to check'; then ok "empty-project passes with the nothing-to-check line"; else nok "empty-project should pass with the nothing-to-check line (exit $RC)" "$OUT"; fi
expect_fail no-coverage-ts "no coverage, Sonar or mutation config found, but the project has source files \\(for example src/index\\.ts\\)"
expect_ok no-coverage-py

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
sed -e 's/{2,}/{0,}/' -e 's/size >= 3/size >= 0/' "$mut/check-exclude-reasons.mjs" > "$mut/m.tmp" && mv "$mut/m.tmp" "$mut/check-exclude-reasons.mjs"
d=$(stage nextjs-short)
OUT=$(bash "$mut/check-exclude-reasons.sh" "$d" 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then ok "a gate with a weaker word rule lets nextjs-short through, so the fixture is a real test"; else nok "mutant did not change the result (exit $RC)" "$OUT"; fi

# One reason belongs to one entry: a reason that names a longer or shorter entry, or two entries, covers neither.
expect_fail sonar-substr-bad "sonar-project.properties:4 sonar-exclude entry '\*\*' has no reason\. Fix: .*names its own entry as a whole word and no other entry of the list"
expect_fail sonar-prefix-bad "sonar-project.properties:4 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_fail sonar-one-reason-two "sonar-project.properties:4 sonar-exclude entry 'src/legacy/\*\*' has no reason"
if printf '%s' "$OUT" | grep -q "entry 'src/gen/\*\*' has no reason"; then ok "one reason naming two entries covers neither"; else nok "one reason naming two entries covered an entry" "$OUT"; fi
expect_ok sonar-two-reasons-ok

# Filler reasons fail: placeholders, one repeated word, three one-letter words.
for n in todo abc fixme xxx tbd same; do
  expect_fail "vitest-filler-$n" "vitest.config.ts:8 coverage-exclude entry 'src/gen/\*\*' has no reason"
done
expect_fail vitest-filler-mixed "vitest.config.ts:8 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_fail sonar-filler-mixed "sonar-project.properties:4 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_fail py-filler-mixed "pyproject.toml:4 coverage-exclude entry 'app/migrations/\*' has no reason"
expect_ok vitest-filler-ok
expect_fail sonar-filler "sonar-project.properties:4 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_fail py-filler "pyproject.toml:4 coverage-exclude entry 'app/migrations/\*' has no reason"
expect_ok py-filler-ok

# Excludes in forms the gate must read or refuse.
expect_fail vitest-computed-bad "vitest.config.ts:7 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_ok vitest-computed-ok
expect_fail vitest-computed-dynamic "vitest.config.ts:7 a computed key can hide a coverage setting"
expect_fail vitest-root-spread "vitest.config.ts:6 a spread in the config root can hide a coverage setting"
expect_ok vitest-root-nospread
expect_fail vitest-merge-local-bad "vitest.base.ts:5 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_ok vitest-merge-local-ok
expect_fail vitest-merge-pkg "vitest.config.ts:1 the config uses '@acme/vitest-base' from another package"
expect_fail vitest-merge-missing "vitest.config.ts:1 the config imports './no-such-base', which cannot be found"
expect_fail vitest-merge-chain "a.ts:1 the config imports './b', which imports further"
expect_fail deep-bad "packages/a/b/c/vitest.config.ts:7 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_ok deep-ok
expect_fail jest-json-bad "jest.config.json:3 coverage-exclude entry '<rootDir>/src/gen/' has no reason"
expect_ok jest-json-ok
for n in nycrc nycrc-json c8rc c8rc-json; do
  expect_fail "$n-bad" "\.(nyc|c8)rc(\.json)?:3 coverage-exclude entry 'src/gen/\*\*' has no reason"
  expect_ok "$n-ok"
done
expect_fail nycrc-yaml "\.nycrc\.yml:1 a YAML coverage config cannot be read"
expect_fail nyc-include-bad "\.nycrc\.json:2 coverage-include list 'src/api/\*\*' is an allow-list"
expect_fail pkg-nyc-bad "package.json:3 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_fail pkg-c8-bad "package.json:3 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_ok pkg-nyc-clean
expect_fail pkg-flag-bad "package.json:3 passes an exclude or include on the command line"
expect_fail pkg-flag-include "package.json:3 passes an exclude or include on the command line"
expect_fail pkg-flag-sonar "package.json:3 passes an exclude or include on the command line"
expect_fail pkg-flag-sonar-cov "package.json:3 passes an exclude or include on the command line"
expect_ok pkg-flag-clean
expect_fail ci-sonar-flag "\.github/workflows/ci\.yml:7 passes an exclude or include on the command line"
expect_ok ci-clean
expect_fail lefthook-sonar-flag "lefthook\.yml:4 passes an exclude or include on the command line"
expect_fail jscpd-bad "\.jscpd\.json:3 cpd-ignore entry 'src/gen/\*\*' has no reason"
expect_ok jscpd-ok
expect_fail stryker-ignore-bad "stryker\.config\.json:3 mutation-exclude entry 'src/gen/\*\*' has no reason"
expect_ok stryker-ignore-ok
expect_fail stryker-mutation-bad "stryker\.config\.json:4 mutation-exclude entry 'StringLiteral' has no reason"
expect_ok stryker-mutation-ok

# A symlinked config is not followed, so the gate fails; the same config as a real file passes.
d=$(stage vitest-filler-ok)
mv "$d/vitest.config.ts" "$d/real-config.ts"
ln -s real-config.ts "$d/vitest.config.ts"
run_gate "$d"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'vitest.config.ts is a symlink'; then ok "a symlinked config fails"; else nok "a symlinked config should fail (exit $RC)" "$OUT"; fi

# Framework defaults are narrow: a config glob at any depth and a one-level test folder need a reason; root configs and test folders do not.
expect_fail defaults-config-bad "vitest.config.ts:7 coverage-exclude entry '\*\*/\*\.config\.\*' has no reason"
expect_ok defaults-config-reason
expect_ok defaults-root-config
expect_fail defaults-test-star "vitest.config.ts:7 coverage-exclude entry 'test/\*' has no reason"
expect_fail defaults-py-bad "pyproject.toml:3 coverage-exclude entry '\*/test_\*\.py' has no reason"
expect_ok defaults-py-ok

# Python without tomllib: one note line, no silent skip.
shim=$WORK/shim
mkdir -p "$shim"
realpy=$(command -v python3)
printf '#!/bin/sh\nshift\nexec "%s" -I -c %s "$@"\n' "$realpy" "'import sys; sys.modules[\"tomllib\"] = None; sys.argv = sys.argv[1:]; exec(compile(open(sys.argv[0]).read(), sys.argv[0], \"exec\"))'" > "$shim/python3"
chmod +x "$shim/python3"
d=$(stage fastapi-omit-ok)
OUT=$(PATH="$shim:$PATH" bash "$root/$GATE" "$d" 2>&1)
n=$(printf '%s\n' "$OUT" | grep -c 'this Python has no tomllib')
if [ "$n" -eq 1 ]; then ok "a Python without tomllib prints one note"; else nok "expected one tomllib note, found $n" "$OUT"; fi

# The four real stack templates, as they are today. Three fail because their excludes carry no "reason:" line; the wiring round adds the
# reasons and turns each expected failure below into expect_template_ok.
tpl_stage() {
  local d=$WORK/tpl-$1
  rm -rf "$d"
  mkdir -p "$d"
  cp -R "$root/skills/scaffold/$1/template/." "$d/"
  mkdir -p "$d/node_modules"
  ln -s "$TS" "$d/node_modules/typescript"
  printf '%s' "$d"
}
expect_template_fail() {
  local d stack=$1 pat
  shift
  d=$(tpl_stage "$stack")
  run_gate "$d"
  for pat in "$@"; do
    if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -Eq -- "$pat"; then ok "template $stack fails as expected: $pat"; else nok "template $stack should fail with '$pat' (exit $RC)" "$OUT"; fi
  done
}
expect_template_fail nextjs "vitest\.config\.ts:24 coverage-include list 'src/\*\*/\*\.ts, src/\*\*/\*\.tsx' is an allow-list: it excludes every file it does not list, and it has no reason"
expect_template_fail nestjs "vitest\.config\.ts:15 coverage-include list 'src/\*\*/\*\.ts' is an allow-list: it excludes every file it does not list, and it has no reason"
expect_template_fail vite-react "vite\.config\.ts:43 coverage-include list 'src/\*\*/\*\.\{ts,tsx\}' is an allow-list: it excludes every file it does not list, and it has no reason" "vite\.config\.ts:45 coverage-exclude entry 'src/test/\*\*' has no reason"
d=$(tpl_stage fastapi)
run_gate "$d"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'OK\.'; then ok "template fastapi passes"; else nok "template fastapi should pass (exit $RC)" "$OUT"; fi

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
