#!/usr/bin/env bash
# Tests for the seeded gate skills/scaffold/shared/template/scripts/check-exclude-reasons.sh.
# Every failing fixture under tests/fixtures/exclusions/ has a clean control that differs only by the reason line. The gate runs on a
# copy of each fixture, so the fixtures stay untouched; their hashes are compared before and after the run.
# The JS and TS scanner needs a typescript install to read configs. This script uses TC_TEST_TYPESCRIPT_DIR, then ./node_modules, then
# the version pinned in skills/scaffold/shared/versions.txt installed once into a cache folder under $TMPDIR. It never scans a home folder.
# Usage: bash scripts/seeded-exclude-reasons.test.sh        Needs bash 3.2+, find, awk, node, Python (3.11 or newer) or the tomli package; npm and network only for the first cache install.
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

# The gate picks its Python the same way (rules.sh resolve_python): .venv/bin/python3, the highest python3.N, then python3; the first that
# can read TOML. Without one, every case that needs a TOML or INI reader is skipped and one failure says so, instead of one per case.
# shellcheck source=/dev/null
. "$root/skills/scaffold/shared/template/scripts/check-exclude-rules.sh"
if PYBIN=$(resolve_python "$root"); then
  echo "# python: $PYBIN ($("$PYBIN" -I -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'))"
else
  PYBIN=
  nok "no Python 3.11 or newer, or tomli package, was found, so every pyproject.toml, setup.cfg, tox.ini and .coveragerc case is skipped (tried: $RULES_PY_TRIED)"
fi
# needs_py DIR: true when the staged project holds a TOML or INI file the gate must read with Python.
needs_py() {
  [ -z "$PYBIN" ] || return 1
  [ -n "$(find "$1" \( -name node_modules \) -prune -o \( -name '*.toml' -o -name '*.cfg' -o -name '*.ini' -o -name '.coveragerc*' \) -print 2> /dev/null | head -n 1)" ]
}

# Fixture trees git cannot hold: a folder named build or coverage is ignored by .gitignore, and an empty folder is not stored. They are
# built here, so a fresh clone runs the same cases.
runtime_tree() { # runtime_tree NAME DIR
  local sub
  case "$1" in
    r2-pkg-build | r2-pkg-coverage)
      sub=${1#r2-pkg-}
      mkdir -p "$2/packages/$sub/src"
      printf '{\n  "name": "demo",\n  "version": "0.0.0",\n  "private": true\n}\n' > "$2/packages/$sub/package.json"
      printf "import { defineConfig } from 'vitest/config';\n\nexport default defineConfig({\n  test: {\n    coverage: {\n      exclude: ['src/**'],\n    },\n  },\n});\n" > "$2/packages/$sub/vitest.config.ts"
      printf 'export const a = 1;\n' > "$2/packages/$sub/src/index.ts"
      ;;
    r2-symlink-dir) mkdir -p "$2/src/real" ;;
  esac
}

# Copy fixture NAME to a fresh folder and link typescript into it (unless the second argument is "no-ts").
stage() {
  local d=$WORK/$1
  rm -rf "$d"
  mkdir -p "$d"
  cp -R "$FIX/$1/." "$d/"
  runtime_tree "$1" "$d"
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
  if needs_py "$d"; then return 0; fi
  run_gate "$d"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'OK\.'; then ok "$1 passes"; else nok "$1 should pass (exit $RC)" "$OUT"; fi
}
# expect_fail NAME PATTERN: exit 1 and PATTERN (extended regex) in the output.
expect_fail() {
  local d
  d=$(stage "$1")
  if needs_py "$d"; then return 0; fi
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
cp skills/scaffold/shared/template/scripts/check-exclude-reasons.* skills/scaffold/shared/template/scripts/check-exclude-rules.sh "$mut/"
sed -e 's/{2,}/{0,}/' -e 's/size >= 3/size >= 0/' "$mut/check-exclude-reasons.mjs" > "$mut/m.tmp" && mv "$mut/m.tmp" "$mut/check-exclude-reasons.mjs"
d=$(stage nextjs-short)
OUT=$(bash "$mut/check-exclude-reasons.sh" "$d" 2>&1)
RC=$?
if [ "$RC" -eq 0 ]; then ok "a gate with a weaker word rule lets nextjs-short through, so the fixture is a real test"; else nok "mutant did not change the result (exit $RC)" "$OUT"; fi

# One reason belongs to one entry: a reason that names a longer or shorter entry, or two entries, covers neither.
expect_fail sonar-substr-bad "sonar-project.properties:4 sonar-exclude entry 'gen/\*\*' has no reason\. Fix: .*names its own entry as a whole word and no other entry of the list"
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

# Framework defaults are compared after normalisation: a config glob at any depth needs a reason; root configs and test folders (test/*, tests/*) do not.
expect_fail defaults-config-bad "vitest.config.ts:7 coverage-exclude entry '\*\*/\*\.config\.\*' has no reason"
expect_ok defaults-config-reason
expect_ok defaults-root-config
expect_ok defaults-test-star
expect_fail defaults-py-bad "pyproject.toml:3 coverage-exclude entry '\*/test_\*\.py' has no reason"
expect_ok defaults-py-ok

# Python without tomllib or tomli: a failure that names the version needed, never a silent skip. The path holds links to every tool of
# the real path except Python, plus one python3 that cannot import tomllib or tomli.
shim=$WORK/shim
mkdir -p "$shim"
realpy=$(command -v python3)
if [ -n "$realpy" ]; then
  oldifs=$IFS
  IFS=:
  for pdir in $PATH; do
    [ -d "$pdir" ] || continue
    for tool in "$pdir"/*; do
      tname=${tool##*/}
      case "$tname" in python* | pip* | idle* | pydoc*) continue ;; esac
      if [ -x "$tool" ] && [ ! -e "$shim/$tname" ]; then ln -s "$tool" "$shim/$tname"; fi
    done
  done
  IFS=$oldifs
  cat > "$shim/blocked.py" <<'PYEND'
import runpy
import sys

sys.modules["tomllib"] = None
sys.modules["tomli"] = None
args = sys.argv[1:]
if args and args[0] == "-c":
    sys.argv = ["-c"] + args[2:]
    exec(compile(args[1], "<string>", "exec"), {"__name__": "__main__"})
else:
    sys.argv = args
    runpy.run_path(args[0], run_name="__main__")
PYEND
  printf $'#!/bin/sh\nif [ "$1" = -I ]; then shift; fi\nexec "%s" -I "%s" "$@"\n' "$realpy" "$shim/blocked.py" > "$shim/python3"
  chmod +x "$shim/python3"
  d=$(stage fastapi-omit-ok)
  OUT=$(PATH="$shim" bash "$root/$GATE" "$d" 2>&1)
  RC=$?
  n=$(printf '%s\n' "$OUT" | grep -c 'needs 3\.11 or newer (tomllib), or the tomli package')
  if [ "$n" -eq 1 ] && [ "$RC" -eq 1 ]; then ok "a Python without tomllib or tomli fails, names the version needed and what was tried"; else nok "expected one tomllib failure (exit 1), found $n (exit $RC)" "$OUT"; fi
else
  nok "no python3 on the path, so the no-tomllib case cannot run"
fi

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
expect_template_fail nextjs "vitest\.config\.ts:24 coverage-include list 'src/\*\*/\*\.ts, src/\*\*/\*\.tsx' is an allow-list that leaves out source files, so it excludes every file it does not list, and it has no reason"
expect_template_fail nestjs "vitest\.config\.ts:15 coverage-include list 'src/\*\*/\*\.ts' is an allow-list that leaves out source files, so it excludes every file it does not list, and it has no reason"
# vite-react: its include covers every source file, so it narrows nothing and is no finding; only the test folder exclude remains.
expect_template_fail vite-react "vite\.config\.ts:45 coverage-exclude entry 'src/test/\*\*' has no reason"
d=$(tpl_stage fastapi)
run_gate "$d"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'OK\.'; then ok "template fastapi passes"; else nok "template fastapi should pass (exit $RC)" "$OUT"; fi

# ---- Round 2 -----------------------------------------------------------------------------------------------------------------------
# Each failing fixture below has a clean control. Each major item also has a revert proof: a copy of the gate with the fix undone must
# stop reporting the finding, so the fixture is a real test of that fix.
SCRIPTS=skills/scaffold/shared/template/scripts
mutant_run() { # mutant_run NAME FILE OLD NEW: copy the gate, undo one fix, run the copy on fixture NAME
  local name=$1 file=$2 old=$3 new=$4 d
  rm -rf "$WORK/mut2"
  mkdir -p "$WORK/mut2"
  cp "$root/$SCRIPTS"/check-exclude-reasons.* "$root/$SCRIPTS"/check-exclude-rules.sh "$WORK/mut2/"
  if ! OLD=$old NEW=$new perl -0pi -e '$c += s/\Q$ENV{OLD}\E/$ENV{NEW}/g; END { $? = $c ? 0 : 3 }' "$WORK/mut2/$file"; then
    MOUT="the mutation '$old' did not apply to $file"
    MRC=99
    return
  fi
  d=$(stage "$name")
  MOUT=$(bash "$WORK/mut2/check-exclude-reasons.sh" "$d" 2>&1)
  MRC=$?
}
# revert_proof NAME PATTERN FILE OLD NEW: the real gate reports PATTERN on NAME; with the fix undone it does not.
revert_proof() {
  mutant_run "$1" "$3" "$4" "$5"
  if [ "$MRC" -ne 99 ] && ! printf '%s' "$MOUT" | grep -Eq -- "$2"; then ok "revert proof: $1 stops failing with the fix undone ($3)"; else nok "revert proof: $1 still fails with the fix undone ($3, exit $MRC)" "$MOUT"; fi
}
G=check-exclude-reasons.sh
RL=check-exclude-rules.sh

# 1 A broad exclude fails whatever its reason; a sub-folder of a source root passes with a reason.
for n in root type brace; do
  expect_fail "r2-broad-$n" "vitest.config.ts:8 coverage-exclude entry '[^']+' hides hand-written code \(it matches every source file of the project, of one package or of one top-level source folder, or every source file of one type there\), and no reason can cover it"
  revert_proof "r2-broad-$n" "hides hand-written code" "$G" $'hides_source "$entry" "$cdir"' 'false'
done
expect_ok r2-broad-ok
expect_fail r2-sonar-scoped "sonar-project.properties:3 sonar-python-coverage-exclude entry 'app/\*\*' hides hand-written code"

# 2 Defaults are narrow: root-anchored build output needs no reason, an unanchored build folder does.
expect_ok r2-anchored-defaults
expect_fail r2-unanchored-build "vitest.config.ts:7 coverage-exclude entry '\*\*/build/\*\*' has no reason"
expect_ok r2-unanchored-build-ok
revert_proof r2-unanchored-build "entry '\*\*/build/\*\*' has no reason" "$G" "dflt 'dist/**'" "dflt '**/build/**' 'x'
dflt 'dist/**'"
if grep -q "^dflt 'src/components/ui/\*\*'" "$GATE"; then nok "src/components/ui/** is a default"; else ok "src/components/ui/** is not a default"; fi

# 3 A folder named build or coverage below the root is read.
for n in build coverage; do
  expect_fail "r2-pkg-$n" "packages/$n/vitest.config.ts:6 coverage-exclude entry 'src/\*\*' hides hand-written code"
  revert_proof "r2-pkg-$n" "packages/$n/vitest.config.ts" "$RL" $'$0 ~ /(^|\\/)(node_modules|\\.git)\\// { next }' $'$0 ~ /(^|\\/)(node_modules|\\.git|build|coverage)\\// { next }'
done

# 4 A directory symlink inside the tree fails and is named.
expect_fail r2-symlink-dir "src/alias is a symlink that is not a link to a regular file"
revert_proof r2-symlink-dir "src/alias is a symlink" "$G" $'if [ -L "$f" ] && [ ! -f "$f" ]; then bad_links' $'if false; then bad_links'

# 5 Config variants are read by pattern; a file that sets an exclude the gate cannot parse fails closed.
expect_fail r2-vitest-unit "vitest.unit.config.ts:7 coverage-exclude entry 'src/gen/\*\*' has no reason"
expect_ok r2-vitest-unit-ok
expect_fail r2-vitest-ws "vitest.workspace.config.ts:7 coverage-exclude entry 'src/gen/\*\*' has no reason"
revert_proof r2-vitest-unit "vitest.unit.config.ts:7 coverage-exclude" "$G" 'vitest*.config.* | vitest.workspace.*' 'vitest.config.* | vitest.workspace.*'
expect_fail r2-codecov-bad "codecov.yml:1 sets an exclude in a file type the gate cannot read for reasons"
expect_ok r2-codecov-ok
revert_proof r2-codecov-bad "codecov.yml:1 sets an exclude" "$G" 'codecov.yml' 'zzz.yml'
expect_fail r2-karma-bad "karma.conf.js:2 sets an exclude in a file type the gate cannot read for reasons"
revert_proof r2-karma-bad "karma.conf.js:2 sets an exclude" "$RL" 'unparsed_exclude_line() {' 'unparsed_exclude_line() {
  return 0'

# 6 Command-line excludes are a finding; a pointer at a config is read like any config, and a pointer at a missing file is a finding.
for k in nyc c8 jest omit makefile; do
  case "$k" in makefile) f='Makefile:2' ;; *) f='package.json:3' ;; esac
  expect_fail "r2-flag-$k" "$f passes an exclude or include on the command line, where it cannot carry a reason\. Fix: move it into the coverage, mutation or Sonar config file"
done
revert_proof r2-flag-nyc "passes an exclude or include on the command line" "$G" $'cmd_out=$(cmd_scan "${cmd_files[@]}")' $'cmd_out=$(true)'
expect_ok pkg-flag-clean
expect_fail r2-pointer-unread "conf/cov.cfg:2 coverage-exclude entry 'app/migrations/\*' has no reason"
expect_fail r2-pointer-jest "package.json:3 points jest at conf/jest.custom.js, which does not exist"
expect_ok r2-pointer-read
revert_proof r2-pointer-unread "conf/cov.cfg:2 coverage-exclude" "$G" $'cmd_out=$(cmd_scan "${cmd_files[@]}")' $'cmd_out=$(true)'
revert_proof r2-pointer-jest "points jest at conf/jest.custom.js" "$G" $'cmd_out=$(cmd_scan "${cmd_files[@]}")' $'cmd_out=$(true)'

# 7 Sonar properties do not fail open.
expect_fail r2-sonar-bom "sonar-project.properties:1 sonar-exclude entry 'src/gen/\*\*' has no reason"
expect_ok r2-sonar-bom-ok
revert_proof r2-sonar-bom "sonar-exclude entry 'src/gen/\*\*' has no reason" check-exclude-reasons.awk 'if (NR == 1) sub("^\357\273\277", "", raw)' 'if (0) sub("^\357\273\277", "", raw)'
expect_fail r2-sonar-scoped "sonar-project.properties:2 sonar-exclude entry 'src/gen/\*\*' has no reason"
revert_proof r2-sonar-scoped "sonar-exclude entry 'src/gen/\*\*' has no reason" check-exclude-reasons.awk 'else if (key ~ /(^|\.)sonar\.([A-Za-z0-9_-]+\.)*exclusions$/) {' 'else if (key ~ /^sonar\.exclusions$/) {'
expect_fail r2-sonar-unknown "sonar-project.properties:2 sonar.coverage.exclusion looks like an exclude setting, but the gate does not read it"
revert_proof r2-sonar-unknown "looks like an exclude setting" check-exclude-reasons.awk 'if (tracked) printf "X' 'if (0) printf "X'
expect_fail r2-sonar-binary "sonar-project.properties holds a NUL byte, so it is not a text file"
revert_proof r2-sonar-binary "holds a NUL byte" "$G" $'elif is_binary "$f"; then' 'elif false; then'

# 8 Inline coverage markers need a reason; a whole-file marker is a broad exclude.
expect_fail r2-marker-bad "src/index.ts:2 'istanbul ignore next' has no reason"
expect_ok r2-marker-ok
expect_fail r2-marker-file "src/whole.ts:1 'istanbul ignore file' marks a whole file as not covered, which hides hand-written code and no reason can cover it"
expect_fail r2-marker-py-bad "app/main.py:2 '# pragma: no cover' has no reason"
expect_ok r2-marker-py-ok
revert_proof r2-marker-bad "'istanbul ignore next' has no reason" "$G" $'if [ "${#mark_files[@]}" -gt 0 ]; then' $'if false; then'
revert_proof r2-marker-file "marks a whole file as not covered" "$G" $'if [ "${#mark_files[@]}" -gt 0 ]; then' $'if false; then'

# 10 Reason shape: digits, one repeated letter, the entry's own path words and filler phrases are not reasons.
for n in digits repeat path later; do
  case "$n" in path) e='src/api/handlers/\*\*' ;; *) e='src/gen/\*\*' ;; esac
  expect_fail "r2-shape-$n" "vitest.config.ts:8 coverage-exclude entry '$e' has no reason"
done
expect_ok r2-shape-ok
revert_proof r2-shape-digits "has no reason" check-exclude-reasons.mjs "return new Set(good).size >= 3;" "return words.length >= 3;"
revert_proof r2-shape-repeat "has no reason" check-exclude-reasons.mjs "new Set(letters).size > 1 && " ""
revert_proof r2-shape-path "has no reason" check-exclude-reasons.mjs " && !segs.has(w)" ""
revert_proof r2-shape-later "has no reason" "$G" "
later
" "
"

# 11 Narrowing lists are include records.
expect_fail r2-stryker-mutate "stryker.config.json:2 mutation-include list 'src/core/\*\*/\*\.ts' is an allow-list"
expect_ok r2-stryker-mutate-ok
expect_fail r2-pkg-stryker "package.json:3 mutation-include list 'src/core/\*\*/\*\.ts' is an allow-list"
expect_fail r2-cov-source "pyproject.toml:2 coverage-include list 'app/core' is an allow-list"
expect_ok r2-cov-source-ok
expect_fail r2-mutmut-paths "pyproject.toml:2 mutation-include list 'app/core/' is an allow-list"
expect_ok r2-mutmut-paths-ok
revert_proof r2-stryker-mutate "is an allow-list" check-exclude-reasons.mjs 'if (negated.length === 0) emitInclude' 'if (false) emitInclude'
revert_proof r2-pkg-stryker "is an allow-list" check-exclude-reasons.mjs 'if (negated.length === 0) emitInclude' 'if (false) emitInclude'
revert_proof r2-cov-source "is an allow-list" check-exclude-reasons.py '("source", "include"),' ''
revert_proof r2-mutmut-paths "is an allow-list" check-exclude-reasons.py '("paths_to_mutate", "mutation-include"),' ''

# 12 A key set twice in one object is a finding.
expect_fail r2-dup-key "\.c8rc\.json:3 the key 'exclude' appears twice in one object"
expect_ok r2-dup-key-ok
revert_proof r2-dup-key "appears twice in one object" check-exclude-reasons.mjs 'if (seen.has(key)) emit(' 'if (false) emit('

# 14 An invalid package.json reports the real JSON error.
expect_fail r2-badjson "package.json:1 package.json is not valid JSON, so it cannot be read: .*(line 4|position)"
revert_proof r2-badjson "is not valid JSON" check-exclude-reasons.mjs "pkg = JSON.parse(fs.readFileSync(abs, 'utf8'));" "pkg = {};"

# ---- Round 3 -----------------------------------------------------------------------------------------------------------------------
# These projects are built here at run time (a folder named .tox, env or lib may be ignored by git, and a git work tree is needed for
# some cases). Each failing case has a clean control, and a mutant copy of the gate with the fix undone must stop reporting it.
mk() { # mk DIR FILE CONTENT
  mkdir -p "$(dirname "$1/$2")"
  printf '%s' "$3" > "$1/$2"
}
r3dir() { # r3dir NAME: a fresh project with a package, two source files of two types, and typescript linked in
  local d=$WORK/r3-$1
  rm -rf "$d"
  mkdir -p "$d/node_modules"
  ln -s "$TS" "$d/node_modules/typescript"
  mk "$d" package.json $'{\n  "name": "demo",\n  "version": "0.0.0"\n}\n'
  mk "$d" src/a.ts $'export const a = 1;\n'
  mk "$d" src/b.js $'export const b = 1;\n'
  mk "$d" vitest.config.ts $'import { defineConfig } from \'vitest/config\';\n\nexport default defineConfig({\n  test: {\n    coverage: {\n      reporter: [\'text\'],\n    },\n  },\n});\n'
  printf '%s' "$d"
}
vcfg() { # vcfg DIR 'ENTRY' [PATH]: a vitest config with one commented exclude
  mk "$1" "${3:-vitest.config.ts}" "import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: [
        // reason: generated code that nobody writes by hand
        '$2',
      ],
    },
  },
});
"
}
r3_ok() { # r3_ok LABEL DIR
  run_gate "$2"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'OK\.'; then ok "$1 passes"; else nok "$1 should pass (exit $RC)" "$OUT"; fi
}
r3_fail() { # r3_fail LABEL DIR PATTERN
  run_gate "$2"
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -Eq -- "$3"; then ok "$1 fails with: $3"; else nok "$1 should fail with '$3' (exit $RC)" "$OUT"; fi
}
mutant_dir() { # mutant_dir DIR FILE OLD NEW: run a mutant gate on DIR; MRC 99 when the mutation did not apply
  local dir=$1 file=$2 old=$3 new=$4
  rm -rf "$WORK/mut3"
  mkdir -p "$WORK/mut3"
  cp "$root/$SCRIPTS"/check-exclude-reasons.* "$root/$SCRIPTS"/check-exclude-rules.sh "$WORK/mut3/"
  if ! OLD=$old NEW=$new perl -0pi -e '$c += s/\Q$ENV{OLD}\E/$ENV{NEW}/g; END { $? = $c ? 0 : 3 }' "$WORK/mut3/$file"; then
    MOUT="the mutation '$old' did not apply to $file"
    MRC=99
    return
  fi
  MOUT=$(bash "$WORK/mut3/check-exclude-reasons.sh" "$dir" 2>&1)
  MRC=$?
}
r3_lost() { # r3_lost LABEL DIR PATTERN FILE OLD NEW: with the fix undone, the finding PATTERN is gone
  mutant_dir "$2" "$4" "$5" "$6"
  if [ "$MRC" -ne 99 ] && ! printf '%s' "$MOUT" | grep -Eq -- "$3"; then ok "revert proof: $1 loses its finding with the fix undone ($4)"; else nok "revert proof: $1 still reports it with the fix undone ($4, exit $MRC)" "$MOUT"; fi
}
r3_flip() { # r3_flip LABEL DIR FILE OLD NEW: a clean control turns into a failure with the fix undone
  mutant_dir "$2" "$3" "$4" "$5"
  if [ "$MRC" -ne 99 ] && [ "$MRC" -ne 0 ]; then ok "revert proof: $1 fails with the fix undone ($3)"; else nok "revert proof: $1 still passes with the fix undone ($3, exit $MRC)" "$MOUT"; fi
}

# 2 Broad is decided from the files on disk. Every form below hides all of a project, a package or a source folder.
broad_case() { # broad_case LAYOUT PATTERN: a project of LAYOUT where PATTERN covers all of one package, source folder or type
  local lay=$1 pat=$2 d
  d=$(r3dir "broad-$lay")
  case "$lay" in
    src) ;;
    pkg)
      rm -rf "$d/src"
      mk "$d" packages/p/package.json $'{\n  "name": "p"\n}\n'
      mk "$d" packages/p/src/x.ts $'export const x = 1;\n'
      mk "$d" apps/web/package.json $'{\n  "name": "web"\n}\n'
      mk "$d" apps/web/src/y.ts $'export const y = 1;\n'
      ;;
    frontend)
      rm -rf "$d/src"
      mk "$d" frontend/src/z.ts $'export const z = 1;\n'
      mk "$d" frontend/src/w.ts $'export const w = 1;\n'
      ;;
    py)
      rm -rf "$d/src"
      mk "$d" my_pkg/__init__.py $'x = 1\n'
      mk "$d" my_pkg/m.py $'y = 1\n'
      ;;
  esac
  vcfg "$d" "$pat"
  r3_fail "broad pattern '$pat'" "$d" "vitest\.config\.ts:8 coverage-exclude entry '.*' (hides hand-written code|uses a pattern)"
}
for pat in 'src/**/*.[jt]s' 'src/**/?*' 'src/./**' 'src//**' '**/*.(t|j)s' '**/*.?s'; do broad_case src "$pat"; done
broad_case pkg 'packages/*/src/**'
broad_case pkg 'apps/web/src/**'
broad_case frontend 'frontend/src/**'
broad_case py 'my_pkg/**'
d=$(r3dir broad-src)
mk "$d" src/gen/g.ts $'export const g = 1;\n'
vcfg "$d" 'src/gen/**'
r3_ok "narrow exclude src/gen/**" "$d"
vcfg "$d" 'src/**'
r3_lost "broad src/**" "$d" "hides hand-written code" "$G" $'hides_source "$entry" "$cdir"' 'false'
r3_lost "broad src/**" "$d" "hides hand-written code" "$RL" $'rules_eval excl "$p" "$dir"' 'return 1'

# 1 One file list: inside a git work tree it is what git lists; outside one, everything except dependencies, .git and virtualenvs.
d=$(r3dir venv)
mk "$d" env/pyvenv.cfg $'home = /usr/bin\n'
mk "$d" env/lib/site.py $'def f(x):\n    if x:  # pragma: no cover\n        return 1\n'
r3_ok "a virtual environment folder (pyvenv.cfg) is not scanned" "$d"
rm -f "$d/env/pyvenv.cfg"
r3_fail "the same folder without pyvenv.cfg is scanned" "$d" "env/lib/site\.py:2 '# pragma: no cover' has no reason"
mk "$d" env/pyvenv.cfg $'home = /usr/bin\n'
r3_flip "a virtual environment folder" "$d" "$RL" 'pyvenv.cfg' 'zzz.cfg'
d=$(r3dir gitlist)
mk "$d" .gitignore $'.tox/\n'
mk "$d" .tox/lib.py $'def f(x):\n    if x:  # pragma: no cover\n        return 1\n'
r3_fail "outside a git work tree an ignored folder is scanned" "$d" "\.tox/lib\.py:2 '# pragma: no cover' has no reason"
run_gate "$d"
case "$OUT" in *NOTE*) ok "outside a git work tree the gate prints one NOTE" ;; *) nok "no NOTE outside a git work tree" "$OUT" ;; esac
if (cd "$d" && git init -q . 2> /dev/null); then
  r3_ok "inside a git work tree an ignored folder is not scanned" "$d"
  r3_flip "git file list" "$d" "$RL" $'command -v git' 'false &&'
else
  nok "git init failed in the test folder"
fi

# 3 Command lines: only a coverage, mutation or Sonar tool is read, and only its own segment.
d=$(r3dir cmd)
mk "$d" package.json $'{\n  "name": "demo",\n  "scripts": {\n    "ci": "pnpm test:coverage && pnpm lint --config eslint.config.js",\n    "lint:jest": "eslint --config .eslintrc.jest.js tests",\n    "sync": "rsync -a coverage/ --exclude x out/",\n    "test:e2e": "jest --config ./test/jest-e2e.json"\n  }\n}\n'
mk "$d" test/jest-e2e.json $'{\n  "rootDir": ".",\n  "testRegex": ".e2e-spec.ts$"\n}\n'
r3_ok "command lines of other tools and a config pointer that exists" "$d"
mk "$d" package.json $'{\n  "name": "demo",\n  "scripts": {\n    "a": "echo x && nyc --exclude src/gen/** vitest run"\n  }\n}\n'
r3_fail "a tool segment after && is read" "$d" "package\.json:4 passes an exclude or include on the command line"
r3_lost "segment split" "$d" "passes an exclude or include on the command line" "$RL" $'gsub(/&&/, "\\001", line)' $'gsub(/&&/, " ", line)'
mk "$d" package.json $'{\n  "name": "demo",\n  "scripts": {\n    "a": "pnpm exec c8 --exclude x vitest run"\n  }\n}\n'
r3_fail "a wrapped tool is read" "$d" "package\.json:4 passes an exclude or include on the command line"
mk "$d" package.json $'{\n  "name": "demo"\n}\n'
mk "$d" .github/workflows/ci.yml $'jobs:\n  t:\n    steps:\n      - run: npx nyc --exclude src/gen/** vitest run\n'
r3_fail "a workflow file of GitHub is scanned" "$d" "ci\.yml:4 passes an exclude or include on the command line"
rm -rf "$d/.github"
mk "$d" ci/.gitlab-ci.yml $'test:\n  script:\n    - c8 --exclude src/gen/** vitest run\n'
r3_fail "a GitLab CI file is scanned" "$d" "\.gitlab-ci\.yml:3 passes an exclude or include on the command line"
rm -rf "$d/ci"
mk "$d" Taskfile.yml $'tasks:\n  t:\n    cmds:\n      - nyc --exclude src/gen/** vitest run\n'
r3_fail "a Taskfile is scanned" "$d" "Taskfile\.yml:4 passes an exclude or include on the command line"
rm -f "$d/Taskfile.yml"
mk "$d" justfile $'test:\n    nyc --exclude src/gen/** vitest run\n'
r3_fail "a justfile is scanned" "$d" "justfile:2 passes an exclude or include on the command line"
rm -f "$d/justfile"
mk "$d" Dockerfile.ci $'FROM node\nRUN nyc --exclude src/gen/** vitest run\n'
r3_fail "a Dockerfile is scanned" "$d" "Dockerfile\.ci:2 passes an exclude or include on the command line"
rm -f "$d/Dockerfile.ci"
mk "$d" scripts/t.sh $'#!/bin/sh\nc8 --exclude src/gen/** vitest run\n'
r3_fail "a shell script is scanned" "$d" "scripts/t\.sh:2 passes an exclude or include on the command line"
mk "$d" scripts/t.sh $'#!/bin/sh\nvitest run --exclude e2e\n'
r3_flip "command word restriction" "$d" "$RL" $'(cmd == "nyc" || cmd == "c8" || cmd == "coverage" || cmd == "mutmut") && ' ''

# 4 A marker counts only as the first token of a comment, and a start without a stop marks the file.
d=$(r3dir mark)
mk "$d" src/a.ts $'const s = "istanbul ignore next";\n// This sentence names the istanbul ignore next marker in prose.\nconst t = `/* istanbul ignore next */`;\nexport const a = s + t;\n'
r3_ok "markers inside strings and prose are not markers" "$d"
r3_flip "marker is the first token of a comment" "$d" check-exclude-reasons.awk $'match(low, /^(istanbul|c8|v8)[ \\t]+ignore' $'match(low, /(istanbul|c8|v8)[ \\t]+ignore'
mk "$d" src/a.ts $'/* istanbul ignore next */\nexport const a = 1;\n'
r3_fail "a block-comment marker without a reason" "$d" "src/a\.ts:1 'istanbul ignore next' has no reason"
mk "$d" src/a.ts $'/* v8 ignore start */\nexport const a = 1;\n'
r3_fail "v8 ignore start with no stop is a whole-file marker" "$d" "src/a\.ts:1 .*marks a whole file"
mk "$d" src/a.ts $'// reason: generated by the build tool, not hand written\n/* v8 ignore start */\nexport const a = 1;\n/* v8 ignore stop */\n'
r3_ok "a matched start and stop with a reason" "$d"
mk "$d" src/a.ts $'/* v8 ignore start */\nexport const a = 1;\n'
mk "$d" src/c.py $'"""Docstring that says pragma: no cover in prose."""\nx = 1\n'
r3_lost "unmatched start" "$d" "marks a whole file" check-exclude-reasons.awk $'"file"' $'"x"'

# 5 Defaults are compared after normalisation.
dn=0
for e in '**/test/**' '**/tests/**' '**/__tests__/**' 'tests/*' 'src/**/*.d.ts' '*.config.ts' 'vitest.config.ts' 'dist' 'dist/' '/dist/'; do
  dn=$((dn + 1))
  d=$(r3dir dflt$dn)
  mk "$d" vitest.config.ts "import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      exclude: ['$e'],
    },
  },
});
"
  r3_ok "default entry '$e' needs no reason" "$d"
  r3_flip "default entry '$e'" "$d" "$G" "dflt '$e'" "dflt 'zzzunused'"
done
d=$(r3dir pydefault)
mk "$d" pyproject.toml $'[tool.coverage.report]\nexclude_lines = [\n    "pragma: no cover",\n    "raise NotImplementedError",\n    "if TYPE_CHECKING:",\n]\n\n[tool.coverage.run]\nomit = ["conftest.py", "**/conftest.py"]\n'
r3_ok "stock coverage.py lines and conftest.py need no reason" "$d"
mk "$d" pyproject.toml $'[tool.coverage.run]\nomit = ["*/__init__.py"]\n'
r3_fail "*/__init__.py still needs a reason" "$d" "pyproject\.toml:2 coverage-exclude entry '\*/__init__\.py' has no reason"

# 6 An include that covers a whole source root needs no reason; a narrow one fails.
d=$(r3dir incl)
mk "$d" vitest.config.ts $'import { defineConfig } from \'vitest/config\';\n\nexport default defineConfig({\n  test: {\n    coverage: {\n      include: [\'src/**/*.ts\', \'src/**/*.js\'],\n    },\n  },\n});\n'
r3_ok "an include that covers every source file" "$d"
r3_flip "include_covers" "$d" "$G" $'include_covers "$entry" "$cdir"' 'false'
mk "$d" vitest.config.ts $'import { defineConfig } from \'vitest/config\';\n\nexport default defineConfig({\n  test: {\n    coverage: {\n      include: [\'src/**/*.ts\'],\n    },\n  },\n});\n'
r3_fail "an include that leaves out src/b.js" "$d" "vitest\.config\.ts:6 coverage-include list 'src/\*\*/\*\.ts' is an allow-list"

# 7 sonar.test.inclusions is not an allow-list of covered code.
d=$(r3dir sonar)
mk "$d" sonar-project.properties $'sonar.test.inclusions=**/*.test.ts\nsonar.javascript.test.inclusions=**/*.spec.ts\n'
r3_ok "sonar.test.inclusions and sonar.javascript.test.inclusions" "$d"
r3_flip "sonar test inclusions" "$d" check-exclude-reasons.awk $'if (key ~ /(^|\\.)sonar\\.([A-Za-z0-9_-]+\\.)*test\\.inclusions$/) return' ''

# 8 Every symlink that is not a link to a regular file is reported, a dangling directory link included.
d=$(r3dir links)
ln -s a.ts "$d/src/alias.ts"
r3_ok "a link to a regular file" "$d"
ln -s no-such-folder "$d/src/gone"
r3_fail "a dangling link" "$d" "src/gone is a symlink that is not a link to a regular file"
r3_lost "dangling link" "$d" "src/gone is a symlink" "$G" $'if [ -L "$f" ] && [ ! -f "$f" ]; then bad_links' $'if false; then bad_links'

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
