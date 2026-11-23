#!/usr/bin/env bash
# Exclude-reason gate: every coverage, Sonar and mutation-testing exclude needs a one-line reason. Offline; reads config files only.
# Usage: bash scripts/check-exclude-reasons.sh [project-dir]   (default: the current directory)
# Accepted reason, exactly: a comment line directly above the entry (no blank line between) that starts with "reason:" and has
# at least 3 different words of 3+ letters after it, none of them TODO, TBD, FIXME, XXX or another placeholder. Write it with // in JS and TS configs, with # in TOML, INI and properties files:
#     // reason: generated client code is not hand written
#     'src/gen/**',
# One entry per line. A list with exactly one non-default entry may carry its reason above the key instead. In a Sonar
# properties list with several entries a comment cannot sit between the entries (a continued line ends the comment), so put
# a "# reason:" line above the key for each entry and name the entry in it as a whole word: "# reason: src/gen/** generated client
# code". A reason belongs to one entry: it must name its own entry and no other entry of the list.
# A coverage include list is an exclude of every file it does not list; its reason goes on the line above the key.
# Checked: Vitest and Jest coverage exclude and include, coverage.py omit, exclude_lines, exclude_also and include in
# pyproject.toml, .coveragerc, setup.cfg and tox.ini, sonar.exclusions, sonar.coverage.exclusions, sonar.cpd.exclusions,
# sonar.test.exclusions, sonar.issue.ignore.*, sonar.inclusions, sonar.coverage.inclusions, Stryker mutate negations and the
# mutmut do_not_mutate and paths_to_exclude settings, jest.config.json, .nycrc*, .c8rc*, package.json keys jest, nyc and c8,
# .jscpd.json ignore, Stryker ignorePatterns and mutator.excludedMutations. A config imported from a relative file is followed one
# level. Any depth is scanned. A symlinked config, a YAML nyc config, or an exclude passed on a command line (-Dsonar.exclusions=,
# --coverage.exclude= in package.json scripts, CI workflows, lefthook) fails: none of them can carry a reason. A project with
# source files and no coverage config fails.
# Supported forms: JS, TS and JSON configs are read as syntax trees with the project's own typescript (never run) and the
# lists must be literal arrays of strings, with no spread, variable or call. TOML and INI lists must be literal strings.
# A config that cannot be read in these forms fails the gate. Nothing switches the gate off: no inline marker, no variable.
# Exit 0 when every exclude has a reason or is a framework default, 1 on a finding or an unreadable config, 2 on bad usage.
# Needs bash 3.2+, find, awk; node for JS, TS and JSON configs; python3 for TOML and INI configs.
# Helpers beside this script: check-exclude-reasons.mjs (JS, TS, JSON), .py (TOML, INI), .awk (Sonar properties). Each prints tab
# separated records: E file line kind entry status (status reason, none, shared or default), I file line kind entries status for an
# allow-list, T file line key value for a coverage threshold, X file line message for a config that cannot be read.
set -uo pipefail
export LC_ALL=C

die() {
  printf 'check-exclude-reasons: %s\n' "$1" >&2
  exit 2
}

# Framework default excludes: entries the tools apply themselves. They need no reason. This is the only list; the scanners receive
# it through TC_EXCLUDE_DEFAULTS. Each entry names the reason it is safe, and none of them can hide hand-written source.
DEFAULTS=
dflt() { DEFAULTS="$DEFAULTS$1
"; }
dflt '**/node_modules/**' 'installed dependencies, not project code'
dflt 'node_modules/**' 'installed dependencies, not project code'
dflt '/node_modules/' 'installed dependencies, not project code'
dflt '**/dist/**' 'build output'
dflt 'dist/**' 'build output'
dflt '**/build/**' 'build output'
dflt 'build/**' 'build output'
dflt '**/coverage/**' 'coverage report output'
dflt 'coverage/**' 'coverage report output'
dflt '**/.next/**' 'Next.js build output'
dflt '.next/**' 'Next.js build output'
dflt '**/__pycache__/**' 'Python bytecode cache'
dflt '.venv/*' 'Python virtual environment, installed dependencies'
dflt 'venv/*' 'Python virtual environment, installed dependencies'
dflt '*/__pycache__/*' 'Python bytecode cache'
dflt '**/*.d.ts' 'type declarations, no runtime code'
dflt '**/*.{test,spec}.ts' 'test files, not shipped code'
dflt '**/*.{test,spec}.tsx' 'test files, not shipped code'
dflt '**/*.{test,spec}.{ts,tsx}' 'test files, not shipped code'
dflt '**/*.{test,spec}.{js,jsx}' 'test files, not shipped code'
dflt '**/*.test.ts' 'test files, not shipped code'
dflt '**/*.test.tsx' 'test files, not shipped code'
dflt '**/*.spec.ts' 'test files, not shipped code'
dflt '**/*.spec.tsx' 'test files, not shipped code'
dflt 'src/**/*.test.ts' 'test files, not shipped code'
dflt 'src/**/*.test.tsx' 'test files, not shipped code'
dflt 'src/**/*.spec.ts' 'test files, not shipped code'
dflt 'src/**/*.spec.tsx' 'test files, not shipped code'
dflt '**/test_*.py' 'pytest test files, not shipped code'
dflt 'test/**' 'the root test folder holds test code only'
dflt 'tests/**' 'the root tests folder holds test code only'
dflt '*.config.{js,ts,mjs,cjs}' 'tool config files at the project root, not shipped code'
dflt 'pragma: no cover' 'the coverage.py marker for a line already marked by hand'
dflt '# pragma: no cover' 'the coverage.py marker for a line already marked by hand'
TC_EXCLUDE_DEFAULTS=${DEFAULTS%?}
export TC_EXCLUDE_DEFAULTS

PLACEHOLDERS='todo
tbd
tbc
fixme
xxx
placeholder
changeme
lorem
ipsum
n/a'
TC_REASON_PLACEHOLDERS=$PLACEHOLDERS
export TC_REASON_PLACEHOLDERS

FORM='a comment line directly above it that starts with "reason:" and has at least 3 different words of 3 or more letters and no placeholder (TODO, TBD, FIXME, XXX), for example "// reason: generated client code is not hand written" (use # in TOML, INI and properties files)'
PROPS_NOTE=' In a Sonar properties list with several entries, put a "# reason:" line above the key for each entry; each reason names its own entry as a whole word and no other entry of the list.'
SUPPORTED='Supported forms: JS, TS and JSON configs with literal arrays of strings (no spread, computed key, variable or call), TOML and INI lists of literal strings, Sonar properties lists'

TARGET=
for arg in "$@"; do
  case "$arg" in
    -*) die "unknown option: $arg (usage: check-exclude-reasons.sh [project-dir])" ;;
    *) [ -z "$TARGET" ] || die "one project folder at most"; TARGET=$arg ;;
  esac
done
here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd) || die "cannot locate the script folder"
TARGET=${TARGET:-.}
[ -d "$TARGET" ] || die "not a folder: $TARGET"
cd "$TARGET" 2> /dev/null || die "cannot enter $TARGET"
for tool in find awk; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done

fail_count=0
checked=0
defaulted=0
bad() {
  printf 'check-exclude-reasons: %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

js_files=()
py_files=()
prop_files=()
link_files=()
cmd_files=()
PRUNE=(\( -name node_modules -o -name .venv -o -name venv -o -name .next -o -name dist -o -name build -o -name coverage -o -name .git -o -name __pycache__ \) -prune -o)

while IFS= read -r f; do
  [ -n "$f" ] || continue
  f=${f#./}
  if [ -L "$f" ]; then
    link_files+=("$f")
    continue
  fi
  case "$f" in
    *sonar-project.properties) prop_files+=("$f") ;;
    *pyproject.toml | *.coveragerc | *setup.cfg | *tox.ini) py_files+=("$f") ;;
    *package.json)
      cmd_files+=("$f")
      if grep -qE '"(jest|nyc|c8)"' "$f" 2> /dev/null; then js_files+=("$f"); fi
      ;;
    *) js_files+=("$f") ;;
  esac
done <<EOF
$(find . "${PRUNE[@]}" \( -type f -o -type l \) \( -name 'vitest.config.*' -o -name 'vitest.workspace.*' -o -name 'vite.config.*' -o -name 'jest.config.*' -o -name 'stryker.config.*' -o -name 'stryker.conf.*' -o -name '.stryker.conf.*' -o -name package.json \
  -o -name '.nycrc*' -o -name '.c8rc*' -o -name .jscpd.json \
  -o -name pyproject.toml -o -name .coveragerc -o -name setup.cfg -o -name tox.ini -o -name sonar-project.properties \) -print | LC_ALL=C sort)
EOF

while IFS= read -r f; do
  [ -n "$f" ] || continue
  cmd_files+=("${f#./}")
done <<EOF
$(find . "${PRUNE[@]}" -type f \( -path '*/.github/workflows/*.yml' -o -path '*/.github/workflows/*.yaml' -o -name 'lefthook*.yml' -o -name 'lefthook*.yaml' -o -name '.lefthook*.yml' -o -name '.gitlab-ci.yml' -o -name 'azure-pipelines*.yml' -o -name 'bitbucket-pipelines.yml' -o -name Jenkinsfile -o -name Makefile \) -print | LC_ALL=C sort)
EOF

# Sonar properties: logical lines with continuation, comments above the key, entries split on commas outside braces.
scan_properties() {
  awk -v file="$1" -f "$here/check-exclude-reasons.awk" "$1"
}

records=$(
  {
    if [ "${#prop_files[@]}" -gt 0 ]; then
      for f in "${prop_files[@]}"; do scan_properties "$f"; done
    fi
  }
)

if [ "${#js_files[@]}" -gt 0 ]; then
  if command -v node > /dev/null 2>&1; then
    out=$(node "$here/check-exclude-reasons.mjs" "${js_files[@]}" 2>&1) || bad "the JS config scanner failed: $(printf '%s' "$out" | head -n 1). $SUPPORTED"
    records="$records
$out"
  else
    bad "${js_files[0]} cannot be read because node is not installed. $SUPPORTED"
  fi
fi
if [ "${#py_files[@]}" -gt 0 ]; then
  if command -v python3 > /dev/null 2>&1; then
    out=$(python3 -I "$here/check-exclude-reasons.py" "${py_files[@]}" 2>&1) || bad "the TOML and INI scanner failed: $(printf '%s' "$out" | head -n 1). $SUPPORTED"
    records="$records
$out"
  else
    needs=
    for f in "${py_files[@]}"; do
      if grep -qE 'coverage|mutmut' "$f" 2> /dev/null; then needs=$f; fi
    done
    if [ -n "$needs" ]; then bad "$needs cannot be read because python3 is not installed. $SUPPORTED"; fi
  fi
fi

note() {
  case "$1" in
    *sonar-project.properties) printf '%s' "$PROPS_NOTE" ;;
    *package.json) printf '%s' ' A package.json cannot hold a comment: move the Jest config to jest.config.js.' ;;
  esac
}

tab=$(printf '\t')
while IFS="$tab" read -r tag file line kind entry status; do
  case "$tag" in
    E)
      case "$status" in
        default) defaulted=$((defaulted + 1)) ;;
        reason) checked=$((checked + 1)) ;;
        shared) bad "$file:$line $kind entry '$entry' shares its line with another exclude. Fix: put each exclude on its own line, each with $FORM.$(note "$file")" ;;
        *) bad "$file:$line $kind entry '$entry' has no reason. Fix: add $FORM.$(note "$file")" ;;
      esac
      ;;
    I)
      if [ "$status" = reason ]; then
        checked=$((checked + 1))
      else
        bad "$file:$line $kind list '$entry' is an allow-list: it excludes every file it does not list, and it has no reason. Fix: add $FORM, or remove the list.$(note "$file")"
      fi
      ;;
    X) bad "$file:$line $kind. $SUPPORTED" ;;
    N) printf 'check-exclude-reasons: note: %s: %s\n' "$file" "$entry" >&2 ;;
  esac
done <<EOF
$records
EOF

if [ "${#link_files[@]}" -gt 0 ]; then
  for f in "${link_files[@]}"; do bad "$f is a symlink, and the gate does not follow symlinks, so its excludes were not read. Fix: replace the link with the real file."; done
fi
if [ "${#cmd_files[@]}" -gt 0 ]; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    bad "${hit%%:*}:$(printf '%s' "${hit#*:}" | cut -d: -f1) passes an exclude or include on the command line, where it cannot carry a reason. Fix: move it into the coverage or Sonar config file with $FORM."
  done <<EOF
$(grep -nHE -e '-D[ ]?sonar\.((coverage|cpd|test)\.)?(exclusions|inclusions)|-D[ ]?sonar\.issue\.ignore|--coverage\.(exclude|include)' "${cmd_files[@]}" 2> /dev/null)
EOF
fi

nconf=$((${#js_files[@]} + ${#py_files[@]} + ${#prop_files[@]} + ${#link_files[@]}))
if [ "$nconf" -eq 0 ]; then
  src=$(find . "${PRUNE[@]}" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' \) -print -quit 2> /dev/null)
  if [ -n "$src" ]; then
    bad "no coverage, Sonar or mutation config found, but the project has source files (for example ${src#./}), so nothing proves what it excludes. Fix: add a coverage config (vitest.config.ts, jest.config.js, pyproject.toml or sonar-project.properties)."
  elif [ "$fail_count" -eq 0 ]; then
    echo "check-exclude-reasons: no source files and no coverage, Sonar or mutation config found; nothing to check."
    exit 0
  fi
fi
if [ "$fail_count" -gt 0 ]; then
  printf 'check-exclude-reasons: %d problem(s); see the Fix lines above.\n' "$fail_count" >&2
  exit 1
fi
echo "check-exclude-reasons: OK. $checked exclude(s) carry a reason, $defaulted framework default(s) need none."
