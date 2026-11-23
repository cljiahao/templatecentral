#!/usr/bin/env bash
# Exclude-reason gate: every coverage, Sonar and mutation-testing exclude needs a one-line reason. Offline; reads config files only.
# Usage: bash scripts/check-exclude-reasons.sh [project-dir]   (default: the current directory)
# Accepted reason, exactly: a comment line directly above the entry (no blank line between) that starts with "reason:" and has at
# least 3 different words of 3+ letters after it. Words that are a repeated single letter, digits, or a path segment of the entry do
# not count, and none may be TODO, TBD, FIXME, XXX, WIP, TEMP, LATER, HACK or another placeholder. Write it with // in JS and TS configs,
# with # in TOML, INI and properties files:
#     // reason: generated client code is not hand written
#     'src/gen/**',
# One entry per line. A list with exactly one non-default entry may carry its reason above the key instead. In a Sonar
# properties list with several entries a comment cannot sit between the entries (a continued line ends the comment), so put
# a "# reason:" line above the key for each entry and name the entry in it as a whole word: "# reason: src/gen/** generated client
# code". A reason belongs to one entry: it must name its own entry and no other entry of the list.
# A coverage include list is an exclude of every file it does not list; its reason goes on the line above the key. So is a Stryker
# mutate list with no ! entry, coverage.py source, and mutmut paths_to_mutate.
# No reason buys a whole source root or a whole source file type: an entry such as src/**, **, **/*.ts or src/**/*.{ts,tsx} fails
# whatever the comment says (rules in check-exclude-rules.sh, shared with the migrate audit). A sub-folder of a source root passes with a reason.
# Framework defaults need no reason and are only these: test files and test folders, type declarations, tool config files at the
# project root, and dependency or build output folders anchored at the project root (node_modules, .venv, venv, dist, build, coverage,
# .next). The same folder name deeper in the tree, such as **/build/**, can hide hand-written source, so it needs a reason.
# Checked: Vitest and Jest coverage exclude and include, coverage.py omit, exclude_lines, exclude_also, include and source in
# pyproject.toml, .coveragerc, setup.cfg and tox.ini, sonar.exclusions, sonar.coverage.exclusions, sonar.cpd.exclusions,
# sonar.test.exclusions, any other sonar.*.exclusions or sonar.*.inclusions key, sonar.issue.ignore.*, sonar.inclusions, Stryker mutate
# negations, ignorePatterns and mutator.excludedMutations, the mutmut do_not_mutate, paths_to_exclude and paths_to_mutate settings,
# every vitest*.config.*, jest*.config.*, stryker*.conf*, .nycrc* and .c8rc* file, package.json keys jest, nyc, c8, stryker and jscpd,
# and .jscpd.json ignore. A config imported from a relative file is followed one level. Any depth is scanned, except dependency and
# build output folders (never pruned by name alone: a folder named build or coverage inside src is scanned).
# Inline markers in source files (istanbul, c8 and v8 ignore comments, node:coverage, pragma: no cover) need "reason:" on the same or the
# previous line; an ignore-file marker fails like a broad exclude.
# Fails, because none can carry a reason or be read: a symlinked config or folder, a YAML nyc config, a karma, codecov or nyc.config.*
# file that sets an exclude, an exclude on a command line (-Dsonar.exclusions=, --coverage.exclude=, nyc, c8, jest, coverage.py and
# mutation flags in package.json scripts, CI workflows, lefthook, Makefile), a --config, --cov-config or --rcfile that points at a file the
# gate did not read, and a Sonar file with a NUL byte. A project with source files and no coverage config fails.
# Supported forms: JS, TS and JSON configs are read as syntax trees with the project's own typescript (never run) and the
# lists must be literal arrays of strings, with no spread, variable or call. TOML and INI lists must be literal strings. TOML needs
# a Python that has tomllib, or the tomli package, to cross-check the reader; without one a config with coverage or mutation settings fails.
# A config that cannot be read in these forms fails the gate. Nothing switches the gate off: no inline marker, no variable.
# Exit 0 when every exclude has a reason or is a framework default, 1 on a finding or an unreadable config, 2 on bad usage.
# Needs bash 3.2+, find, awk, grep; node for JS, TS and JSON configs; python3 for TOML and INI configs.
# Helpers beside this script: check-exclude-reasons.mjs (JS, TS, JSON), .py (TOML, INI), .awk (Sonar properties and inline markers) and
# check-exclude-rules.sh (which entries hide source). Each scanner prints tab separated records: E file line kind entry status (status
# reason, none, shared or default), I file line kind entries status for an allow-list, T file line key value for a coverage threshold,
# X file line message for a config that cannot be read, M file line marker text status for an inline marker.
set -uo pipefail
export LC_ALL=C

die() {
  printf 'check-exclude-reasons: %s\n' "$1" >&2
  exit 2
}

# Framework default excludes: entries the tools apply themselves. They need no reason. This is the only list; the scanners receive
# it through TC_EXCLUDE_DEFAULTS. Only test files, test folders, type declarations, root tool config files and root-anchored
# dependency and build output are here, because none of them can hide hand-written source. Anything else needs a reason.
DEFAULTS=
dflt() { DEFAULTS="$DEFAULTS$1
"; }
dflt 'node_modules/**' 'installed dependencies at the project root, not project code'
dflt '/node_modules/' 'installed dependencies at the project root, not project code'
dflt 'dist/**' 'build output at the project root'
dflt 'build/**' 'build output at the project root'
dflt 'coverage/**' 'coverage report output at the project root'
dflt '.next/**' 'Next.js build output at the project root'
dflt '.venv/*' 'Python virtual environment at the project root, installed dependencies'
dflt 'venv/*' 'Python virtual environment at the project root, installed dependencies'
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
n/a
wip
temp
temporary
later
hack'
TC_REASON_PLACEHOLDERS=$PLACEHOLDERS
export TC_REASON_PLACEHOLDERS

FORM='a comment line directly above it that starts with "reason:" and has at least 3 different words of 3 or more letters (not a repeated letter, not part of the entry path) and no placeholder (TODO, TBD, FIXME, XXX, WIP, TEMP, LATER, HACK), for example "// reason: generated client code is not hand written" (use # in TOML, INI and properties files)'
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


# shellcheck source=/dev/null
. "$here/check-exclude-rules.sh" || die "cannot load check-exclude-rules.sh from $here"

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
dirlink_files=()
other_files=()
cmd_files=()
NL='
'

# Folders never scanned by name: dependencies, VCS data, caches. Build output is NOT pruned by name: dist, build, coverage and
# .next are skipped only at the project root and beside a package.json or pyproject.toml (that package's own build output), so
# a folder named build or coverage inside the source tree is still read.
PRUNE=()
while IFS= read -r a; do
  PRUNE+=("$a")
done <<EOF
$(build_prune .)
EOF

while IFS= read -r f; do
  [ -n "$f" ] || continue
  f=${f#./}
  base=${f##*/}
  if [ -L "$f" ]; then
    if [ -d "$f" ]; then dirlink_files+=("$f"); else link_files+=("$f"); fi
    continue
  fi
  case "$base" in
    sonar-project*.properties) prop_files+=("$f") ;;
    pyproject.toml | .coveragerc | setup.cfg | tox.ini) py_files+=("$f") ;;
    package.json)
      cmd_files+=("$f")
      js_files+=("$f")
      ;;
    karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml) other_files+=("$f") ;;
    *) js_files+=("$f") ;;
  esac
done <<EOF
$(find . "${PRUNE[@]}" \( -type f -o -type l \) \( -name 'vitest*.config.*' -o -name 'vitest.workspace.*' -o -name 'vite.config.*' -o -name 'jest*.config.*' -o -name 'stryker*.conf*' -o -name '.stryker*.conf*' -o -name 'karma*.conf*' -o -name 'nyc.config.*' -o -name codecov.yml -o -name .codecov.yml -o -name package.json \
  -o -name '.nycrc*' -o -name '.c8rc*' -o -name .jscpd.json \
  -o -name pyproject.toml -o -name .coveragerc -o -name setup.cfg -o -name tox.ini -o -name 'sonar-project*.properties' \) -print | LC_ALL=C sort)
EOF

# A symlinked folder anywhere in the scanned tree: the gate never follows links out of the project, so what is behind it is unread.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  f=${f#./}
  if [ -d "$f" ]; then dirlink_files+=("$f"); fi
done <<EOF
$(find . "${PRUNE[@]}" -type l -print | LC_ALL=C sort)
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

records=
if [ "${#prop_files[@]}" -gt 0 ]; then
  for f in "${prop_files[@]}"; do
    if [ ! -r "$f" ]; then
      bad "$f cannot be read, so its excludes were not checked. Fix: make the file readable."
    elif is_binary "$f"; then
      bad "$f holds a NUL byte, so it is not a text file and its excludes cannot be read. Fix: save it as plain UTF-8 text."
    else
      records="$records
$(scan_properties "$f")"
    fi
  done
fi

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

# Inline coverage markers in source files need "reason:" on the same or the previous line.
marks=$(find . "${PRUNE[@]}" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.mts' -o -name '*.cts' -o -name '*.vue' -o -name '*.svelte' -o -name '*.py' \) -exec awk -v mode=marks -f "$here/check-exclude-reasons.awk" {} + 2> /dev/null)
records="$records
$marks"

note() {
  case "$1" in
    *sonar-project*.properties) printf '%s' "$PROPS_NOTE" ;;
    *package.json) printf '%s' ' A package.json cannot hold a comment: move the Jest config to jest.config.js.' ;;
  esac
}

tab=$(printf '\t')
while IFS="$tab" read -r tag file line kind entry status; do
  case "$tag" in
    E)
      if [ "$kind" != sonar-issue-ignore ] && hides_source "$entry"; then
        bad "$file:$line $kind entry '$entry' excludes a whole source root or every file of a source type, so it hides hand-written code and no reason can cover it. Fix: narrow it to the folder or files that are really not hand-written (for example src/generated/**), with $FORM."
        continue
      fi
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
    M)
      case "$status" in
        reason) checked=$((checked + 1)) ;;
        file) bad "$file:$line '$kind' marks a whole file as not covered, which hides hand-written code and no reason can cover it. Fix: remove the marker and test the file, or mark only the lines that cannot run, each with a reason." ;;
        *) bad "$file:$line '$kind' has no reason. Fix: add \"reason: <why this line cannot be tested>\" (at least 3 different words) on the same line or the line above." ;;
      esac
      ;;
    X) bad "$file:$line $kind. $SUPPORTED" ;;
  esac
done <<EOF
$records
EOF

if [ "${#link_files[@]}" -gt 0 ]; then
  for f in "${link_files[@]}"; do bad "$f is a symlink, and the gate does not follow symlinks, so its excludes were not read. Fix: replace the link with the real file."; done
fi
if [ "${#dirlink_files[@]}" -gt 0 ]; then
  for f in "${dirlink_files[@]}"; do bad "$f is a symlink to a folder, and the gate does not follow links, so nothing behind it was read. Fix: replace the link with the real folder, or remove it."; done
fi
if [ "${#other_files[@]}" -gt 0 ]; then
  for f in "${other_files[@]}"; do
    hit=$(unparsed_exclude_line "$f")
    if [ -n "$hit" ]; then
      bad "$f:${hit%%:*} sets an exclude in a file type the gate cannot read for reasons. Fix: move the exclude into vitest.config.ts, jest.config.js, pyproject.toml or sonar-project.properties with $FORM."
    fi
  done
fi

# Files the gate read, to tell a --config pointing at one of them from a --config pointing elsewhere.
read_list=
for f in ${js_files[@]+"${js_files[@]}"} ${py_files[@]+"${py_files[@]}"} ${prop_files[@]+"${prop_files[@]}"}; do
  read_list="$read_list$f$NL"
done
was_read() {
  local r p=${1#./}
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ "$r" = "$p" ]; then return 0; fi
    case "$r" in */"$p") return 0 ;; esac
  done <<EOT
$read_list
EOT
  return 1
}

if [ "${#cmd_files[@]}" -gt 0 ]; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=${hit%%:*}
    rest=${hit#*:}
    ln=${rest%%:*}
    bad "$file:$ln passes an exclude or include on the command line, where it cannot carry a reason. Fix: move it into the coverage, mutation or Sonar config file with $FORM."
  done <<EOF
$(cmd_flag_lines "${cmd_files[@]}")
EOF
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=${hit%%:*}
    rest=${hit#*:}
    ln=${rest%%:*}
    text=${rest#*:}
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      pth=$m
      if ! was_read "$pth"; then
        bad "$file:$ln points a coverage tool at $pth, a config file the gate did not read, so its excludes are unchecked. Fix: use a config file the gate reads (vitest*.config.*, jest*.config.*, pyproject.toml, .coveragerc, sonar-project.properties) or move the settings there."
      fi
    done <<EOT
$(cmd_pointer_paths "$text")
EOT
  done <<EOF
$(cmd_pointer_lines "${cmd_files[@]}")
EOF
fi

# A package.json counts as a config only when it holds a tool key; it is in js_files either way so a broken one is reported.
nconf=$((${#py_files[@]} + ${#prop_files[@]} + ${#link_files[@]} + ${#other_files[@]}))
if [ "${#js_files[@]}" -gt 0 ]; then
  for f in "${js_files[@]}"; do
    case "${f##*/}" in
      package.json) if grep -qE '"(jest|nyc|c8|stryker|jscpd)"' "$f" 2> /dev/null; then nconf=$((nconf + 1)); fi ;;
      *) nconf=$((nconf + 1)) ;;
    esac
  done
fi
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
