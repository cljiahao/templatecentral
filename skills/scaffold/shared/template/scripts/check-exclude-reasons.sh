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
# and .jscpd.json ignore. A config imported from a relative file is followed one level. Any depth is scanned: a folder named build or
# coverage inside src is read like any other.
# Scope: the gate covers vitest, jest, pytest-cov and coverage.py, Sonar properties files, Stryker, mutmut and inline markers; c8 and nyc on the command line, mvn, a Sonar scan action, excludes of two tools that hide different halves, and a root, --root or workspace that hides source in another folder are outside it.
# Broad means judged from the files on disk (one list is judged as the union of its non-default entries, so splitting a broad pattern does not help): a pattern that matches every non-test source file of the project, of one package (a folder
# with its own package.json or pyproject.toml), of one top-level source folder, or every source file of one type in any of those. ./ and
# // are normalised first, and a pattern form the gate cannot evaluate (such as !(a)) is a finding too.
# Inline markers in source files (istanbul, c8 and v8 ignore comments, node:coverage, pragma: no cover, Stryker disable) count only as the
# first token of a comment; NOSONAR counts anywhere in a comment. Each needs "reason:" on the same or the previous line. An ignore-file
# marker, or a v8 or c8 "ignore start" or Stryker "disable" with no stop or "restore", fails like a broad exclude.
# Fails, because none can carry a reason or be read: a symlink that is not a link to a regular file (a folder link, a dangling link), a YAML nyc config, a karma, codecov or nyc.config.*
# file that sets an exclude, an exclude on a command line (-Dsonar.exclusions=, --coverage.exclude=, nyc, c8, jest, coverage.py and
# mutation flags in package.json scripts, CI workflows, lefthook, Makefile), a --config, --cov-config or --rcfile that points at a file the
# gate did not read, and a Sonar file with a NUL byte. A project with source files and no coverage config fails.
# Supported forms: JS, TS and JSON configs are read as syntax trees with the project's own typescript (never run) and the
# lists must be literal arrays of strings, with no spread, variable or call. TOML and INI lists must be literal strings. TOML needs
# Python (3.11 or newer) or the tomli package (the gate picks .venv/bin/python3, then the highest python3.N, then python3), to cross-check the reader; without one a config with coverage or mutation settings fails.
# A config that cannot be read in these forms fails the gate. Nothing switches the gate off: no inline marker, no variable.
# Reads every project file once: inside a git work tree the files git tracks or sees untracked and does not ignore, outside one every file
# except node_modules, .git and virtualenv folders. Config discovery, command lines and the marker scan all use that one list.
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
dflt 'dist/**/*' 'build output at the project root'
dflt 'build/**/*' 'build output at the project root'
dflt 'coverage/**/*' 'coverage report output at the project root'
dflt 'node_modules/**/*' 'installed dependencies at the project root, not project code'
dflt '.next/**/*' 'Next.js build output at the project root'
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
dflt '**/test/**' 'test folders hold test code only'
dflt '**/tests/**' 'test folders hold test code only'
dflt '**/__tests__/**' 'test folders hold test code only'
dflt '__tests__/**' 'test folders hold test code only'
dflt 'test/*' 'the root test folder holds test code only'
dflt 'tests/*' 'the root tests folder holds test code only'
dflt 'src/**/*.d.ts' 'type declarations, no runtime code'
dflt '*.config.ts' 'tool config files at the project root, not shipped code'
dflt '*.config.js' 'tool config files at the project root, not shipped code'
dflt '*.config.mjs' 'tool config files at the project root, not shipped code'
dflt '*.config.cjs' 'tool config files at the project root, not shipped code'
dflt 'vitest.config.ts' 'tool config files at the project root, not shipped code'
dflt 'vite.config.ts' 'tool config files at the project root, not shipped code'
dflt 'jest.config.js' 'tool config files at the project root, not shipped code'
dflt 'jest.config.ts' 'tool config files at the project root, not shipped code'
dflt 'node_modules' 'installed dependencies at the project root, not project code'
dflt 'node_modules/' 'installed dependencies at the project root, not project code'
dflt 'dist' 'build output at the project root'
dflt 'dist/' 'build output at the project root'
dflt '/dist/' 'build output at the project root'
dflt 'build' 'build output at the project root'
dflt 'build/' 'build output at the project root'
dflt '/build/' 'build output at the project root'
dflt 'coverage' 'coverage report output at the project root'
dflt 'coverage/' 'coverage report output at the project root'
dflt '/coverage/' 'coverage report output at the project root'
dflt '.next' 'Next.js build output at the project root'
dflt '.next/' 'Next.js build output at the project root'
dflt '/.next/' 'Next.js build output at the project root'
dflt '.venv/**' 'Python virtual environment at the project root, installed dependencies'
dflt 'venv/**' 'Python virtual environment at the project root, installed dependencies'
dflt 'conftest.py' 'pytest fixtures, test code'
dflt '**/conftest.py' 'pytest fixtures, test code'
dflt 'raise NotImplementedError' 'coverage.py stock non-executable line'
dflt 'if TYPE_CHECKING:' 'coverage.py stock non-executable line'
dflt 'if __name__ == .__main__.:' 'coverage.py stock non-executable line'
dflt '@abstractmethod' 'coverage.py stock non-executable line'
dflt '\.\.\.' 'coverage.py stock non-executable line'
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
js_modes=()
py_files=()
prop_files=()
link_files=()
bad_links=()
other_files=()
cmd_files=()
mark_files=()
seen=
NL='
'
tab=$(printf '\t')

# One file list for config discovery, the command-line scan and the marker scan. Inside a git work tree it is every tracked and untracked file
# a .gitignore does not hide; outside one it is every file except node_modules, .git and virtualenv folders. No folder is skipped by name.
FILES=$(rules_files .)
if ! rules_in_git .; then printf 'check-exclude-reasons: NOTE %s\n' "$RULES_NOTE" >&2; fi
rules_init "$FILES"

# Put FILE into the scanner list for its type; false when no scanner can read it. With a TOOL (the tool word of the command line that pointed
# at the file) the tool decides the scan mode, never the file name: jest, vitest, stryker, nyc and c8 read a JS, TS or JSON file in their
# own mode, pytest, coverage and mutmut read a TOML or INI file, sonar-scanner reads a properties file. A file no mode applies to is false.
add_config() {
  local f=${1#./} tool=${2:-} base jsmode=
  case "$seen" in *"$NL$f$NL"*) return 0 ;; esac
  base=${f##*/}
  if [ -n "$tool" ]; then
    case "$tool" in
      jest | vitest | stryker) jsmode=$tool ;;
      nyc | c8) jsmode=nyc ;;
      pytest | py.test | coverage | mutmut)
        case "$base" in
          *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | *.properties | *.yml | *.yaml) return 1 ;;
        esac
        py_files+=("$f")
        seen="$seen$NL$f$NL"
        return 0
        ;;
      sonar-scanner | sonar-scanner-cli)
        case "$base" in
          *.properties) prop_files+=("$f") ;;
          *) return 1 ;;
        esac
        seen="$seen$NL$f$NL"
        return 0
        ;;
      *) return 1 ;;
    esac
    case "$base" in
      *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | .nycrc* | .c8rc*) ;;
      *) return 1 ;;
    esac
    js_files+=("$f")
    js_modes+=("$jsmode")
    seen="$seen$NL$f$NL"
    return 0
  fi
  case "$base" in
    *.properties) prop_files+=("$f") ;;
    pyproject.toml | .coveragerc | setup.cfg | tox.ini | *.toml | *.ini | *.cfg | .coveragerc*) py_files+=("$f") ;;
    karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml) other_files+=("$f") ;;
    *.js | *.cjs | *.mjs | *.ts | *.mts | *.cts | *.json | .nycrc* | .c8rc*) js_files+=("$f"); js_modes+=("") ;;
    *) return 1 ;;
  esac
  seen="$seen$NL$f$NL"
  return 0
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  base=${f##*/}
  if [ -L "$f" ] && [ ! -f "$f" ]; then bad_links+=("$f"); fi
  case "$f" in
    *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.mts | *.cts | *.vue | *.svelte | *.py)
      if [ -f "$f" ] && [ ! -L "$f" ]; then mark_files+=("$f"); fi
      ;;
  esac
  case "$base" in
    *.properties)
      # Any properties file that holds a sonar. key is a Sonar config, whatever its name (.sonarcloud.properties, sonar.properties).
      if [ -f "$f" ] && ! [ -L "$f" ] && grep -qaE '^[[:space:]]*sonar\.[A-Za-z]' "$f" 2> /dev/null; then add_config "$f" || true; fi
      ;;
  esac
  case "$base" in
    vitest*.config.* | vitest.workspace.* | vite.config.* | jest*.config.* | stryker*.conf* | .stryker*.conf* | .nycrc* | .c8rc* | .jscpd.json | sonar-project*.properties | pyproject.toml | .coveragerc | setup.cfg | tox.ini | karma*.conf* | nyc.config.* | codecov.yml | .codecov.yml | package.json)
      if [ -L "$f" ]; then
        if [ -f "$f" ]; then link_files+=("$f"); fi
      else
        add_config "$f" || true
      fi
      ;;
  esac
  case "$f" in
    package.json | */package.json | *.sh | *.bash | Makefile | */Makefile | Makefile.* | */Makefile.* | *.mk | Taskfile* | */Taskfile* | justfile | */justfile | Justfile | */Justfile | Dockerfile* | */Dockerfile* | *.dockerfile | \
      .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml | .github/actions/*/*.yml | .github/actions/*/*.yaml | \
      lefthook*.yml | */lefthook*.yml | lefthook*.yaml | */lefthook*.yaml | .lefthook*.yml | .gitlab-ci.yml | */.gitlab-ci.yml | .gitlab/*.yml | azure-pipelines*.yml | */azure-pipelines*.yml | bitbucket-pipelines.yml | Jenkinsfile | */Jenkinsfile | \
      pyproject.toml | */pyproject.toml | pytest.ini | */pytest.ini | tox.ini | */tox.ini | setup.cfg | */setup.cfg | \
      .circleci/*.yml | .travis.yml | appveyor.yml | .drone.yml | cloudbuild.y*ml | .buildkite/*.yml | .woodpecker/*.yml | .woodpecker.yml)
      if [ -f "$f" ] && [ ! -L "$f" ]; then cmd_files+=("$f"); fi
      ;;
  esac
done <<EOT
$FILES
EOT

# Interpreter for TOML and INI files: .venv/bin/python3, then the highest python3.N, then python3; the first that can read TOML.
PY=$(resolve_python .) || PY=

# A command line may pass an exclude to a coverage, mutation or Sonar tool (a finding) or point the tool at a config file (read it).
pending_pointers=
if [ "${#cmd_files[@]}" -gt 0 ]; then
  cmd_out=$(cmd_scan "${cmd_files[@]}")
  while IFS="$tab" read -r ctag cfile cline ctool cpath; do
    case "$ctag" in
      F) bad "$cfile:$cline passes an exclude or include on the command line, where it cannot carry a reason. Fix: move it into the coverage, mutation or Sonar config file with $FORM." ;;
      P) pending_pointers="$pending_pointers$cfile$tab$cline$tab$ctool$tab$cpath$NL" ;;
      Q) bad "$ctool" ;;
    esac
  done <<EOT
$cmd_out
EOT
fi

# Config pointers: read the pointed file too; fail only when it is missing, outside the project or not a type the gate can read.
while IFS="$tab" read -r pfile pline ptool ppath; do
  [ -n "$pfile" ] || continue
  case "$ppath" in
    *'$'* | *'`'*)
      bad "$pfile:$pline points $ptool at '$ppath', a path built from a variable, so the config it uses was not read. Fix: write the config path out, or use a config file the gate reads."
      continue
      ;;
    /* | ../* | */../* | ..)
      bad "$pfile:$pline points $ptool at '$ppath', which is outside the project, so its excludes were not read. Fix: keep the config inside the project."
      continue
      ;;
  esac
  ppath=${ppath#./}
  target=
  if [ -f "$ppath" ]; then
    target=$ppath
  else
    pdir=${pfile%/*}
    if [ "$pdir" != "$pfile" ] && [ -f "$pdir/$ppath" ]; then target=$pdir/$ppath; fi
  fi
  if [ -z "$target" ]; then
    bad "$pfile:$pline points $ptool at $ppath, which does not exist, so its excludes were not read. Fix: correct the path or add the file."
    continue
  fi
  if [ -L "$target" ]; then
    link_files+=("$target")
  elif ! add_config "$target" "$ptool"; then
    bad "$pfile:$pline points $ptool at $target, a file type the gate cannot read. Fix: use a config file the gate reads (vitest*.config.*, jest*.config.*, a .json config, pyproject.toml, .coveragerc, sonar-project.properties)."
  fi
done <<EOT
$pending_pointers
EOT

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
    jargs=()
    ji=0
    for f in "${js_files[@]}"; do
      jargs+=("--as=${js_modes[$ji]}" "$f")
      ji=$((ji + 1))
    done
    out=$(node "$here/check-exclude-reasons.mjs" "${jargs[@]}" 2>&1) || bad "the JS config scanner failed: $(printf '%s' "$out" | head -n 1). $SUPPORTED"
    records="$records
$out"
  else
    bad "${js_files[0]} cannot be read because node is not installed. $SUPPORTED"
  fi
fi
if [ "${#py_files[@]}" -gt 0 ]; then
  if [ -z "$PY" ] && command -v python3 > /dev/null 2>&1; then PY=python3; fi
  if [ -n "$PY" ]; then
    out=$("$PY" -I "$here/check-exclude-reasons.py" "${py_files[@]}" 2>&1) || bad "the TOML and INI scanner failed: $(printf '%s' "$out" | head -n 1). It needs Python (3.11 or newer) or the tomli package. Interpreters tried: $RULES_PY_TRIED. $SUPPORTED"
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
if [ "${#mark_files[@]}" -gt 0 ]; then
  marks=$(printf '%s\0' "${mark_files[@]}" | xargs -0 awk -v mode=marks -f "$here/check-exclude-reasons.awk" 2>&1) || bad "the inline marker scanner failed, so no source file was checked for markers: $(printf '%s' "$marks" | head -n 1)"
  records="$records
$marks"
fi

# "py" for a coverage.py config file (its omit and include patterns are fnmatch patterns on the absolute path), else nothing.
py_flag() {
  local b=${1##*/}
  case "$b" in
    pyproject.toml | .coveragerc* | setup.cfg | tox.ini | *.toml | *.ini | *.cfg) printf py ;;
  esac
}

note() {
  case "$1" in
    *sonar-project*.properties) printf '%s' "$PROPS_NOTE" ;;
    *package.json) printf '%s' ' A package.json cannot hold a comment: move the Jest config to jest.config.js.' ;;
  esac
}

# Judge each exclude list as a whole too: entries that are narrow alone but together leave out a whole source scope fail as one finding.
unions=$(printf '%s\n' "$records" | rules_union_groups)
while IFS="$tab" read -r ufile ukind uline ulist; do
  [ -n "$ufile" ] || continue
  ucdir=${ufile%/*}
  [ "$ucdir" != "$ufile" ] || ucdir=.
  keep=
  while IFS= read -r uentry; do
    [ -n "$uentry" ] || continue
    if ! hides_source "$uentry" "$ucdir" "$(py_flag "$ufile")"; then keep="$keep$uentry$NL"; fi
  done <<EOT
$(printf '%s' "$ulist" | tr '\001' '\n')
EOT
  [ "$(printf '%s' "$keep" | grep -c .)" -ge 2 ] || continue
  if hides_union "${keep%?}" "$ucdir" "$(py_flag "$ufile")"; then
    bad "$ufile:$uline the $ukind exclude entries together hide hand-written code (between them they match every source file of the project, of one package or of one top-level source folder, or every source file of one type there), and no reason can cover it. Fix: remove or narrow the entries so the list leaves out only what is really not hand-written."
  fi
done <<EOT
$unions
EOT

while IFS="$tab" read -r tag file line kind entry status; do
  case "$tag" in
    E)
      cdir=${file%/*}
      [ "$cdir" != "$file" ] || cdir=.
      if [ "$kind" != sonar-issue-ignore ] && hides_source "$entry" "$cdir" "$(py_flag "$file")"; then
        why=${RULES_WHY:-it matches every source file of the project, of one package or of one top-level source folder, or every source file of one type there}
        bad "$file:$line $kind entry '$entry' hides hand-written code ($why), and no reason can cover it. Fix: narrow it to the folder or files that are really not hand-written (for example src/generated/**), with $FORM."
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
      cdir=${file%/*}
      [ "$cdir" != "$file" ] || cdir=.
      if [ "$status" = reason ]; then
        checked=$((checked + 1))
      elif include_covers "$entry" "$cdir" "$(py_flag "$file")"; then
        :
      else
        bad "$file:$line $kind list '$entry' is an allow-list that leaves out source files, so it excludes every file it does not list, and it has no reason. Fix: add $FORM, or remove the list.$(note "$file")"
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
if [ "${#bad_links[@]}" -gt 0 ]; then
  for f in "${bad_links[@]}"; do bad "$f is a symlink that is not a link to a regular file (a folder, or a target that does not exist), and the gate does not follow links, so nothing behind it was read. Fix: replace the link with the real file or folder, or remove it."; done
fi
if [ "${#other_files[@]}" -gt 0 ]; then
  for f in "${other_files[@]}"; do
    hit=$(unparsed_exclude_line "$f")
    if [ -n "$hit" ]; then
      bad "$f:${hit%%:*} sets an exclude in a file type the gate cannot read for reasons. Fix: move the exclude into vitest.config.ts, jest.config.js, pyproject.toml or sonar-project.properties with $FORM."
    fi
  done
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
  src=$(printf '%s\n' "$FILES" | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py)$' | head -n 1)
  if [ -n "$src" ]; then
    bad "no coverage, Sonar or mutation config found, but the project has source files (for example $src), so nothing proves what it excludes. Fix: add a coverage config (vitest.config.ts, jest.config.js, pyproject.toml or sonar-project.properties)."
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
