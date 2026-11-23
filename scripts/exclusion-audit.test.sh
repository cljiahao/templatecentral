#!/usr/bin/env bash
# Tests for the migrate check skills/migrate/general/defects/exclusion-audit.sh, run through defect-report.sh as the real runner does.
# Fixtures live in tests/fixtures/exclusions/. Each runs on a copy; the copy and the fixtures are hashed before and after to prove the audit is read-only.
# Every fixture is copied into one folder and audited by one runner call; a fixture's lines are the ones prefixed with its name. Only the
# missing-typescript, empty-project, leftover-file and CPU cases start their own runner. A file named .env* is left out of the copy by name; no .env file is opened.
# The JS and TS scanner needs a typescript install: TC_TEST_TYPESCRIPT_DIR, ./node_modules, or the pinned version installed once into
# a cache folder under $TMPDIR. It never scans a home folder.
# CPU budget for the large-project case: AUDIT_CPU_BUDGET seconds of user plus system time (default 30), measured with the shell's time keyword.
# Usage: bash scripts/exclusion-audit.test.sh        Needs bash 3.2+, find, awk, node, python3. No network.
set -uo pipefail
export LC_ALL=C

root=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd) || exit 2
cd "$root" || exit 2
REPORT=skills/migrate/general/defect-report.sh
AUDIT=skills/migrate/general/defects/exclusion-audit.sh
AUDITDIR=skills/migrate/general/defects/exclusion-audit
GATEDIR=skills/scaffold/shared/template/scripts
FIX=$root/tests/fixtures/exclusions
BUDGET=${AUDIT_CPU_BUDGET:-30}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/exclusion-audit-test.XXXXXX") || exit 2
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
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" | head -n 8 | sed 's/^/    /'; fi
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
  echo "exclusion-audit.test: no typescript found. Set TC_TEST_TYPESCRIPT_DIR to a typescript package folder, or allow the pinned version to install into \$TMPDIR." >&2
  exit 1
fi

# Hash a tree by file name and size from one listing. No file is opened, so a secret-named file in a fixture is never read.
tree_hash() {
  (cd "$1" && find . -path ./node_modules -prune -o -type f -exec ls -ln {} + | awk '{ print $5, $NF }' | LC_ALL=C sort | shasum | cut -d' ' -f1)
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

STAGE=$WORK/all
mkdir -p "$STAGE/node_modules"
ln -s "$TS" "$STAGE/node_modules/typescript"
tar -C "$FIX" --exclude='.env*' -cf - . | tar -C "$STAGE" -xf -

before=$(tree_hash "$FIX")
stage_before=$(tree_hash "$STAGE")
ALL=$(bash "$root/$REPORT" "$STAGE" 2>&1)
RC=$?
ALLAUD=$(printf '%s\n' "$ALL" | grep '  exclusion-audit  check  ' | sed 's/  exclusion-audit  check  .*//')
stage_after=$(tree_hash "$STAGE")

OUT=
AUD=
report() {
  AUD=$(printf '%s\n' "$ALLAUD" | awk -v p="$1/" 'index($0, p) == 1 { print substr($0, length(p) + 1) }')
  OUT=$AUD
}

# want NAME LABEL REGEX: the audit lines for the fixture match REGEX (extended).
want() {
  report "$1"
  if printf '%s\n' "$AUD" | grep -Eq -- "$3"; then ok "$1: $2"; else nok "$1: expected $2 /$3/" "$OUT"; fi
}
# unwanted NAME LABEL REGEX: no audit line matches.
unwanted() {
  report "$1"
  if printf '%s\n' "$AUD" | grep -Eq -- "$3"; then nok "$1: $2 /$3/" "$OUT"; else ok "$1: $2"; fi
}

# Stacks: a reasoned exclude is listed "has reason"; the same fixture without the reason line is listed "no reason".
for stack in nextjs nestjs vite-react; do
  case "$stack" in vite-react) cfg=vite.config.ts ;; *) cfg=vitest.config.ts ;; esac
  want "$stack-ok" "reasoned exclude is listed as has reason" "^$cfg:[0-9]+ coverage-exclude 'src/gen/\*\*': has reason$"
  want "$stack-ok" "framework default is listed as such" "^$cfg:[0-9]+ coverage-exclude '\*\*/\*\.d\.ts': framework default$"
  unwanted "$stack-ok" "clean control carries no no-reason line" "no reason$"
  for v in none blank below short nocolon twoabove; do
    want "$stack-$v" "exclude is listed as no reason" "^$cfg:[0-9]+ coverage-exclude 'src/gen/\*\*': no reason$"
  done
  want "$stack-include-noreason" "allow-list is reported" "^$cfg:[0-9]+ coverage-include list 'src/\*\*/\*\.ts' is an allow-list: it excludes every file it does not list, no reason$"
  want "$stack-ok" "allow-list with a reason is still reported" "coverage-include list 'src/\*\*/\*\.ts' is an allow-list: .*, has reason$"
  for v in spread variable call; do
    want "$stack-$v" "dynamic list is reported as unreadable" "^$cfg:[0-9]+ cannot be read: .*literal"
  done
  want "$stack-unparseable" "syntax error is reported as unreadable" "^$cfg:[0-9]+ cannot be read: config has a syntax error"
  unwanted "$stack-textonly" "an entry in a string or comment is not read as an exclude" "hidden|secret"
done
want vitest-spread-test "spread in the test block is reported" "cannot be read: a spread inside the test block"

# Python, INI shadow files, mutmut.
for key in omit exclude-also exclude-lines; do
  want "fastapi-$key-ok" "reasoned entry is has reason" "^pyproject.toml:[0-9]+ coverage-exclude '[^']+': has reason$"
  unwanted "fastapi-$key-ok" "clean control carries no no-reason line" "no reason$"
  for v in none blank below short nocolon twoabove; do
    want "fastapi-$key-$v" "entry is no reason" "^pyproject.toml:[0-9]+ coverage-exclude '(app/migrations/\*|if DEBUG:)': no reason$"
  done
done
want fastapi-single-above-key "single entry takes its reason above the key" "^pyproject.toml:3 coverage-exclude 'app/migrations/\*': has reason$"
want fastapi-single-nokey "single entry with no reason" "^pyproject.toml:2 coverage-exclude 'app/migrations/\*': no reason$"
want fastapi-include-noreason "python include is an allow-list" "^pyproject.toml:2 coverage-include list 'app/api/\*' is an allow-list: .*, no reason$"
want fastapi-unparseable "broken toml is unreadable" "^pyproject.toml:[0-9]+ cannot be read: toml cannot be read"
unwanted fastapi-textonly "an entry in a string or comment is not read as an exclude" "hidden|secret"
want fastapi-textonly "the real omit is read" "coverage-exclude 'app/migrations/\*': has reason$"
for f in coveragerc setup-cfg tox-ini; do
  case "$f" in coveragerc) file=.coveragerc ;; setup-cfg) file=setup.cfg ;; *) file=tox.ini ;; esac
  want "shadow-$f-none" "shadow file entry is no reason" "^$file:[0-9]+ coverage-exclude 'app/migrations/\*': no reason$"
  want "shadow-$f-blank" "comment separated by a blank line does not count" "^$file:[0-9]+ coverage-exclude 'app/migrations/\*': no reason$"
  want "shadow-$f-ok" "shadow file entry with a reason" "^$file:[0-9]+ coverage-exclude 'app/migrations/\*': has reason$"
  unwanted "shadow-$f-ok" "clean control carries no no-reason line" "no reason$"
done
want mutmut-toml-none "mutmut do_not_mutate with no reason" "^pyproject.toml:2 mutation-exclude 'app/constants/\*': no reason$"
want mutmut-toml-ok "mutmut do_not_mutate with a reason" "^pyproject.toml:3 mutation-exclude 'app/constants/\*': has reason$"
want mutmut-cfg-none "mutmut paths_to_exclude with no reason" "^setup.cfg:2 mutation-exclude 'app/constants/\*': no reason$"
want mutmut-cfg-ok "mutmut paths_to_exclude with a reason" "^setup.cfg:3 mutation-exclude 'app/constants/\*': has reason$"
want ini-unparseable "broken ini is unreadable" "^setup.cfg:[0-9]+ cannot be read: ini cannot be read"

# Jest and Stryker.
want jest-none "jest exclude with no reason" "^jest.config.js:[0-9]+ coverage-exclude '<rootDir>/src/gen/': no reason$"
want jest-ok "jest exclude with a reason" "^jest.config.js:[0-9]+ coverage-exclude '<rootDir>/src/gen/': has reason$"
want jest-collect-none "collectCoverageFrom is an allow-list" "^jest.config.js:[0-9]+ coverage-include list .* no reason$"
want jest-collect-none "collectCoverageFrom negation is an exclude" "^jest.config.js:[0-9]+ coverage-exclude '!src/gen/\*\*': no reason$"
unwanted jest-collect-ok "clean control carries no no-reason line" "no reason$"
want jest-package-key "jest key in package.json is read" "^package.json:[0-9]+ coverage-exclude '<rootDir>/src/gen/': no reason$"
want jest-dynamic "dynamic jest list is unreadable" "^jest.config.js:[0-9]+ cannot be read: coveragePathIgnorePatterns is built dynamically"
want stryker-none "stryker negation with no reason" "^stryker.config.mjs:[0-9]+ mutation-exclude '!src/integrations/\*\*': no reason$"
want stryker-ok "stryker negation with a reason" "^stryker.config.mjs:[0-9]+ mutation-exclude '!src/integrations/\*\*': has reason$"
want stryker-dynamic "dynamic stryker list is unreadable" "^stryker.config.mjs:[0-9]+ cannot be read: the mutate list is built dynamically"

# Sonar.
want sonar-none "sonar.exclusions with no reason" "^sonar-project.properties:3 sonar-exclude 'src/gen/\*\*': no reason$"
want sonar-ok "sonar.exclusions with a reason" "^sonar-project.properties:4 sonar-exclude 'src/gen/\*\*': has reason$"
unwanted sonar-ok "clean control carries no no-reason line" "no reason$"
want sonar-blank "comment separated by a blank line does not count" "^sonar-project.properties:5 sonar-exclude 'src/gen/\*\*': no reason$"
want sonar-short "two-word reason does not count" "^sonar-project.properties:4 sonar-exclude 'src/gen/\*\*': no reason$"
want sonar-multi-none "one of two entries has no reason" "^sonar-project.properties:5 sonar-exclude 'src/legacy/\*\*': no reason$"
want sonar-multi-none "the other entry has one" "^sonar-project.properties:4 sonar-exclude 'src/gen/\*\*': has reason$"
unwanted sonar-multi-ok "clean control carries no no-reason line" "no reason$"
want sonar-include "sonar.inclusions is an allow-list" "^sonar-project.properties:3 coverage-include list 'src/api/\*\*' is an allow-list: .*, no reason$"
want sonar-cpd "sonar.cpd.exclusions is read" "^sonar-project.properties:3 sonar-cpd-exclude 'src/gen/\*\*': no reason$"
want sonar-test "sonar.test.exclusions is read" "^sonar-project.properties:3 sonar-test-exclude 'src/fixtures/\*\*': no reason$"
want sonar-issue "sonar.issue.ignore is read" "^sonar-project.properties:3 sonar-issue-ignore 'sonar.issue.ignore.allfile=a1': no reason$"
unwanted sonar-issue-ok "clean control carries no no-reason line" "no reason$"
unwanted sonar-comment-text "a commented key is not read" "hidden"

# The one seeded exclude is marked as such, with or without a reason.
want ui-seeded "src/components/ui/** is the seeded exclude" "^vitest.config.ts:[0-9]+ coverage-exclude 'src/components/ui/\*\*': seeded exclude \(templateCentral adds it on purpose\), has reason$"
want ui-seeded-noreason "seeded exclude without a reason is still flagged" "'src/components/ui/\*\*': seeded exclude \(templateCentral adds it on purpose\), no reason$"
unwanted nextjs-ok "a non-seeded exclude is not marked seeded" "seeded exclude"

# pnpm release-age excludes.
want pnpm-yaml-ok "yaml entry with a reason above the key" "^pnpm-workspace.yaml:3 minimumReleaseAgeExclude entry 'next' .*: has reason$"
want pnpm-yaml-none "yaml entries with no reason" "^pnpm-workspace.yaml:3 minimumReleaseAgeExclude entry 'react' .*: no reason$"
want pnpm-yaml-multi "yaml: the entry with a reason above it" "^pnpm-workspace.yaml:3 minimumReleaseAgeExclude entry 'next' .*: has reason$"
want pnpm-yaml-multi "yaml: the next entry has none" "^pnpm-workspace.yaml:4 minimumReleaseAgeExclude entry 'react' .*: no reason$"
want pnpm-npmrc ".npmrc entry" "^\.npmrc:1 minimumReleaseAgeExclude entry 'next' .*: no reason$"
want pnpm-json "package.json entry" "^package.json:4 minimumReleaseAgeExclude entry 'next' .*cannot hold a comment"

# Thresholds below 80.
want thresholds-low "vitest threshold of 60" "^vitest.config.ts:[0-9]+ coverage threshold lines is 60, below 80$"
unwanted thresholds-low "a threshold of 80 is not reported" "functions is 80"
want thresholds-low-py "fail_under of 70" "^pyproject.toml:2 coverage threshold fail_under is 70, below 80$"
unwanted nextjs-ok "thresholds at 80 are not reported" "below 80"

# Source with no coverage config.
want no-coverage-ts "TypeScript source and no coverage config" "^package.json:1 no coverage config: .*src/index.ts"
want no-coverage-py "Python source and no coverage config" "^pyproject.toml:1 no coverage config: .*app/main.py"
unwanted nextjs-ok "a project with coverage config is not reported" "no coverage config"
unwanted fastapi-clean "a python project with coverage config is not reported" "no coverage config"
d=$(stage empty-project)
OUT=$(bash "$root/$REPORT" "$d" 2>&1)
if ! printf '%s\n' "$OUT" | grep -q '  exclusion-audit  check  ' && printf '%s' "$OUT" | grep -q '0 matched'; then ok "empty-project: nothing to audit, nothing reported"; else nok "empty-project should report nothing" "$OUT"; fi

# Missing typescript is reported as unreadable, not as clean.
d=$(stage nextjs-ok no-ts)
OUT=$(bash "$root/$REPORT" "$d" 2>&1)
if printf '%s\n' "$OUT" | grep -q 'cannot be read: typescript is not installed'; then ok "missing typescript is reported as unreadable"; else nok "missing typescript should be reported" "$OUT"; fi

# The audit lists; it does not fail the run. Exit 0 for the whole fixture set.
if [ "$RC" -eq 0 ]; then ok "exit status is 0 (level check)"; else nok "non-zero exit $RC" "$ALL"; fi

# Read-only: the audited copy and the fixtures hash the same before and after.
if [ "$stage_before" = "$stage_after" ]; then ok "audit leaves the project untouched"; else nok "audit changed the project"; fi
after=$(tree_hash "$FIX")
if [ "$before" = "$after" ]; then ok "fixtures unchanged by the run"; else nok "fixtures changed during the run"; fi

# No file left behind: the runner run with its own empty temporary folder leaves that folder empty.
mkdir "$WORK/tmpd"
d=$(stage nextjs-none)
TMPDIR=$WORK/tmpd bash "$root/$REPORT" "$d" > "$WORK/leftover.out" 2>&1
left=$(find "$WORK/tmpd" -mindepth 1)
if [ -z "$left" ] && grep -q '  exclusion-audit  check  ' "$WORK/leftover.out"; then ok "no temporary file is left behind"; else nok "temporary files left behind (or no audit ran)" "$left"; fi

# Entries that match the project's own source roots are marked, with or without a reason; other entries are not.
want audit-hides "src/** with a reason is still marked" "^vitest.config.ts:[0-9]+ coverage-exclude 'src/\*\*': hides hand-written source .*, has reason$"
want audit-hides "**/*.py with no reason is marked" "^vitest.config.ts:[0-9]+ coverage-exclude '\*\*/\*\.py': hides hand-written source .*, no reason$"
want audit-hides "lib/**/*.ts with no reason is marked" "'lib/\*\*/\*\.ts': hides hand-written source .*, no reason$"
want audit-hides "a generated folder with a reason is not marked" "'src/gen/\*\*': has reason$"
unwanted audit-hides "a generated folder is not marked as hiding source" "'src/(gen|legacy)/\*\*': hides"
want audit-hides "an exclude with no reason that hides nothing" "'src/legacy/\*\*': no reason$"
unwanted nextjs-ok "clean control hides nothing" "hides"

# Output is grouped by state: no reason, hides source, has reason, framework default.
report audit-hides
order=$(printf '%s\n' "$AUD" | awk '
  { r = 0 }
  /: no reason$/ && !/hides hand-written/ { r = 1 }
  /hides hand-written/ { r = 2 }
  /: has reason$/ && !/hides hand-written/ { r = 3 }
  /framework default$/ { r = 4 }
  r > 0 { if (r < last) bad = 1; last = r; seen[r] = 1 }
  END { n = 0; for (k in seen) n++; print (bad || n < 4) ? "bad" : "ok" }')
if [ "$order" = ok ]; then ok "audit-hides: lines come out in state order, all four states present"; else nok "audit-hides: lines are not grouped by state" "$AUD"; fi

# The reason rule matches the gate: filler and a reason that names another entry do not count.
want vitest-filler-todo "TODO filler is no reason" "'src/gen/\*\*': no reason$"
want vitest-filler-ok "a real reason counts" "'src/gen/\*\*': has reason$"
want sonar-substr-bad "a reason for src/gen/** does not cover gen/**" "sonar-exclude 'gen/\*\*': .*no reason$"
want sonar-two-reasons-ok "each entry carries its own reason" "sonar-exclude 'src/gen/\*\*': has reason$"

# Configs the audit now reads.
want nycrc-bad ".nycrc exclude with no reason" "^\.nycrc:[0-9]+ .*'src/gen/\*\*': no reason$"
want nycrc-ok ".nycrc exclude with a reason" "^\.nycrc:[0-9]+ .*'src/gen/\*\*': has reason$"
want c8rc-bad ".c8rc exclude with no reason" "^\.c8rc:[0-9]+ .*'src/gen/\*\*': no reason$"
want jscpd-bad ".jscpd.json ignore with no reason" "^\.jscpd\.json:[0-9]+ .*'src/gen/\*\*': no reason$"
want pkg-nyc-bad "nyc key in package.json" "^package\.json:[0-9]+ .*'src/gen/\*\*': no reason$"
want stryker-ignore-bad "stryker ignorePatterns" "no reason$"

# ---- Round 2 -----------------------------------------------------------------------------------------------------------------------
# A mutant copy of the migrate folder with one fix undone, run over one staged fixture: the finding must disappear.
audit_mutant() { # audit_mutant NAME FILE OLD NEW PATTERN (FILE is relative to skills/migrate/general)
  local name=$1 file=$2 old=$3 new=$4 pat=$5 d mout
  rm -rf "$WORK/mutaudit"
  mkdir -p "$WORK/mutaudit"
  cp -R "$root/skills/migrate/general" "$WORK/mutaudit/general"
  if ! OLD=$old NEW=$new perl -0pi -e '$c += s/\Q$ENV{OLD}\E/$ENV{NEW}/g; END { $? = $c ? 0 : 3 }' "$WORK/mutaudit/general/$file"; then
    nok "revert proof: the mutation '$old' did not apply to $file"
    return
  fi
  d=$(stage "$name")
  mout=$(bash "$WORK/mutaudit/general/defect-report.sh" "$d" 2>&1 | grep '  exclusion-audit  check  ' | sed 's/  exclusion-audit  check  .*//')
  if printf '%s\n' "$mout" | grep -Eq -- "$pat"; then nok "revert proof: $name still reports /$pat/ with the fix undone ($file)" "$mout"; else ok "revert proof: $name stops reporting /$pat/ with the fix undone ($file)"; fi
}

# 1 and 9 A broad exclude hides source whatever its reason; braces are expanded; any other exclude under a source root is on its own line.
for n in root type brace; do
  want "r2-broad-$n" "broad exclude with a reason is marked as hiding source" "^vitest.config.ts:8 coverage-exclude '[^']+': hides hand-written source \(it matches every source file of the project, of one package or of one top-level source folder, or every source file of one type there, and no reason can cover that\), has reason$"
done
audit_mutant r2-broad-brace defects/exclusion-audit/rules.sh $'$(expand_braces "$1")' "\$(printf '%s\\n' \"\$1\")" "hides hand-written source"
want r2-broad-ok "a sub-folder of a source root is has reason" "^vitest.config.ts:8 coverage-exclude 'src/gen/\*\*': has reason$"
want r2-broad-ok "a sub-folder of a source root is reported as covering hand-written code on its own line" "^vitest.config.ts:8 coverage-exclude 'src/gen/\*\*': covers hand-written code \(it sits under the source root src/"
unwanted r2-broad-ok "a sub-folder of a source root is not reported as hiding the whole root" "hides hand-written source"
audit_mutant r2-broad-ok defects/exclusion-audit.sh 'covers hand-written code (it sits under' 'zz (it sits under' "covers hand-written code"
want ui-seeded "the seeded src/components/ui/** keeps its reason" "coverage-exclude 'src/components/ui/\*\*': seeded exclude \(templateCentral adds it on purpose\), has reason$"
unwanted ui-seeded "the seeded src/components/ui/** is not reported as covering hand-written code" "src/components/ui/\*\*': (covers|hides|no reason)"
want ui-seeded-noreason "the seeded src/components/ui/** without its reason line is no reason" "coverage-exclude 'src/components/ui/\*\*': seeded exclude \(templateCentral adds it on purpose\), no reason$"

# 2 Defaults are narrow.
for e in 'dist/\*\*' 'build/\*\*' 'coverage/\*\*' '\.next/\*\*'; do
  want r2-anchored-defaults "root-anchored $e is a framework default" "coverage-exclude '$e': framework default$"
done
want r2-unanchored-build "an unanchored build folder needs a reason" "coverage-exclude '\*\*/build/\*\*': no reason$"
want r2-unanchored-build-ok "an unanchored build folder with a reason is has reason" "coverage-exclude '\*\*/build/\*\*': has reason$"
audit_mutant r2-unanchored-build defects/exclusion-audit/defaults.txt 'dist/**' '**/build/**
dist/**' "'\*\*/build/\*\*': no reason"

# 4 and 7 to 8 Findings the audit reports.
want r2-vitest-unit "vitest.unit.config.ts is read" "^vitest.unit.config.ts:7 coverage-exclude 'src/gen/\*\*': no reason$"
want r2-vitest-unit-ok "a reasoned vitest.unit.config.ts is has reason" "^vitest.unit.config.ts:8 coverage-exclude 'src/gen/\*\*': has reason$"
want r2-codecov-bad "codecov.yml with an ignore is reported unreadable" "^codecov.yml:1 cannot be read: this file type sets an exclude that the audit does not parse"
unwanted r2-codecov-ok "codecov.yml without an exclude is not reported" "codecov.yml"
want r2-karma-bad "karma.conf.js with an exclude is reported unreadable" "^karma.conf.js:2 cannot be read: this file type sets an exclude that the audit does not parse"
for k in nyc c8 jest omit; do
  want "r2-flag-$k" "command-line exclude in package.json is a finding" "^package.json:3 passes an exclude or include on the command line, where it cannot carry a reason: move it into the config file with a reason$"
done
want r2-flag-makefile "command-line exclude in a Makefile is a finding" "^Makefile:2 passes an exclude or include on the command line"
unwanted pkg-flag-clean "a clean package.json has no command-line finding" "passes an exclude"
audit_mutant r2-flag-nyc defects/exclusion-audit.sh 'passes an exclude or include on the command line' 'zz' "passes an exclude or include on the command line"
want r2-pointer-unread "--cov-config at a file is read, and its exclude with no reason is a finding" "^conf/cov.cfg:[0-9]+ coverage-exclude 'app/migrations/\*': no reason$"
want r2-pointer-jest "--config at a missing file is a finding" "^package.json:3 points jest at conf/jest.custom.js, which does not exist"
unwanted r2-pointer-read "--rcfile at a read file is not a finding" "points a coverage tool"
want r2-sonar-bom "Sonar file with a byte order mark is read" "^sonar-project.properties:1 sonar-exclude 'src/gen/\*\*': no reason$"
unwanted r2-sonar-bom-ok "Sonar file with a byte order mark and a reason is clean" "no reason$"
want r2-sonar-scoped "a key at module scope is read" "^sonar-project.properties:2 sonar-exclude 'src/gen/\*\*': no reason$"
want r2-sonar-scoped "a language scoped coverage exclude is read, and it hides source" "^sonar-project.properties:3 sonar-python-coverage-exclude 'app/\*\*': hides hand-written source"
want r2-sonar-unknown "an unrecognised exclusion key is reported" "^sonar-project.properties:2 cannot be read: sonar.coverage.exclusion looks like an exclude setting"
want r2-sonar-binary "a Sonar file with a NUL byte is reported" "^sonar-project.properties:1 cannot be read: the file holds a NUL byte"
want r2-marker-bad "an istanbul marker with no reason" "^src/index.ts:2 inline coverage marker 'istanbul ignore next': no reason$"
want r2-marker-ok "an istanbul marker with a reason" "^src/index.ts:2 inline coverage marker 'istanbul ignore next': has reason$"
want r2-marker-py-bad "a pragma marker with no reason" "^app/main.py:2 inline coverage marker '# pragma: no cover': no reason$"
want r2-marker-file "a whole-file marker hides source" "^src/whole.ts:1 inline coverage marker 'istanbul ignore file': hides hand-written source"
for n in nyc c8; do want "r2-flag-$n" "a flag is found" "passes an exclude"; done

# 10 to 12 Reason shape, include lists, duplicate keys.
for n in digits repeat later; do want "r2-shape-$n" "filler reason is no reason" "^vitest.config.ts:8 coverage-exclude 'src/gen/\*\*': no reason$"; done
want r2-shape-path "a reason made of the entry's own path words is no reason" "coverage-exclude 'src/api/handlers/\*\*': no reason$"
want r2-shape-ok "a real reason is has reason" "coverage-exclude 'src/api/handlers/\*\*': has reason$"
want r2-stryker-mutate "a mutate list with no ! entry is an allow-list" "^stryker.config.json:2 mutation-include list 'src/core/\*\*/\*\.ts' is an allow-list: .*no reason$"
want r2-pkg-stryker "the stryker key in package.json is read" "^package.json:3 mutation-include list 'src/core/\*\*/\*\.ts' is an allow-list"
want r2-cov-source "coverage source is an allow-list" "^pyproject.toml:2 coverage-include list 'app/core' is an allow-list"
want r2-cov-source-ok "coverage source with a reason is has reason" "coverage-include list 'app/core' is an allow-list: .*has reason$"
want r2-mutmut-paths "mutmut paths_to_mutate is an allow-list" "^pyproject.toml:2 mutation-include list 'app/core/' is an allow-list"
want r2-dup-key "a key set twice in one object is reported" "^\.c8rc\.json:3 cannot be read: the key 'exclude' appears twice in one object"

# ---- Round 3 -----------------------------------------------------------------------------------------------------------------------
# Projects built at run time, one audit run over all of them. Each one has a twin that differs only in the thing under test.
R3=$WORK/r3a
mk() { # mk FILE CONTENT (relative to $R3)
  mkdir -p "$(dirname "$R3/$1")"
  printf '%s' "$2" > "$R3/$1"
}
mkdir -p "$R3/node_modules"
ln -s "$TS" "$R3/node_modules/typescript"
vc() { # vc DIR ENTRY: a vitest config with one commented exclude, in a project with src/a.ts and src/b.js
  mk "$1/package.json" $'{\n  "name": "demo"\n}\n'
  mk "$1/src/a.ts" $'export const a = 1;\n'
  mk "$1/src/b.js" $'export const b = 1;\n'
  mk "$1/vitest.config.ts" "export default {
  test: {
    coverage: {
      exclude: [
        // reason: generated code that nobody writes by hand
        '$2',
      ],
    },
  },
};
"
}
vc broad1 'src/**/*.[jt]s'
vc broad2 'src//**'
vc broad3 '**/*.?s'
vc narrow 'src/gen/**'
mk narrow/src/gen/g.ts $'export const g = 1;\n'
mk broad4/package.json $'{\n  "name": "demo"\n}\n'
mk broad4/my_pkg/__init__.py $'x = 1\n'
mk broad4/my_pkg/m.py $'y = 1\n'
mk broad4/pyproject.toml $'[tool.coverage.run]\nomit = [\n    # reason: generated code that nobody writes by hand\n    "my_pkg/**",\n]\n'
mk venv1/env/pyvenv.cfg $'home = /usr/bin\n'
mk venv1/env/lib/site.py $'def f(x):\n    if x:  # pragma: no cover\n        return 1\n'
mk venv2/env/lib/site.py $'def f(x):\n    if x:  # pragma: no cover\n        return 1\n'
mk cmd1/package.json $'{\n  "name": "demo",\n  "scripts": {\n    "ci": "pnpm test:coverage && pnpm lint --config eslint.config.js",\n    "lint:jest": "eslint --config .eslintrc.jest.js tests",\n    "sync": "rsync -a coverage/ --exclude x out/",\n    "unit": "vitest run --exclude e2e",\n    "test:e2e": "jest --config ./test/jest-e2e.json"\n  }\n}\n'
mk cmd1/test/jest-e2e.json $'{\n  "rootDir": "."\n}\n'
mk cmd2/package.json $'{\n  "name": "demo",\n  "scripts": {\n    "a": "echo x && nyc --exclude src/gen/** vitest run"\n  }\n}\n'
mk cmd3/.github/workflows/ci.yml $'jobs:\n  t:\n    steps:\n      - run: npx nyc --exclude src/gen/** vitest run\n'
mk cmd3/package.json $'{\n  "name": "demo"\n}\n'
mk mark1/src/a.ts $'const s = "istanbul ignore next";\n// This sentence names the istanbul ignore next marker in prose.\nexport const a = s;\n'
mk mark2/src/a.ts $'/* istanbul ignore next */\nexport const a = 1;\n'
mk mark3/src/a.ts $'/* v8 ignore start */\nexport const a = 1;\n'
mk sonar1/sonar-project.properties $'sonar.test.inclusions=**/*.test.ts\nsonar.javascript.test.inclusions=**/*.spec.ts\n'
mk dflt1/vitest.config.ts $'export default {\n  test: {\n    coverage: {\n      exclude: [\'**/tests/**\', \'src/**/*.d.ts\', \'dist/\'],\n    },\n  },\n};\n'
mk dflt1/package.json $'{\n  "name": "demo"\n}\n'
mk py1/pyproject.toml $'[tool.coverage.report]\nexclude_lines = [\n    "pragma: no cover",\n    "if TYPE_CHECKING:",\n]\n\n[tool.coverage.run]\nomit = ["conftest.py"]\n'
mk py2/pyproject.toml $'[tool.coverage.run]\nomit = ["*/__init__.py"]\n'
mk incl1/package.json $'{\n  "name": "demo"\n}\n'
mk incl1/src/a.ts $'export const a = 1;\n'
mk incl1/vitest.config.ts $'export default {\n  test: {\n    coverage: {\n      include: [\'src/**/*.ts\'],\n    },\n  },\n};\n'
mk links1/package.json $'{\n  "name": "demo"\n}\n'
mk links1/src/a.ts $'export const a = 1;\n'
ln -s a.ts "$R3/links1/src/alias.ts"
mkdir -p "$R3/links2/src"
mk links2/package.json $'{\n  "name": "demo"\n}\n'
ln -s no-such-folder "$R3/links2/src/gone"
SAVED_AUD=$ALLAUD
R3ALL=$(bash "$root/$REPORT" "$R3" 2>&1)
ALLAUD=$(printf '%s\n' "$R3ALL" | grep '  exclusion-audit  check  ' | sed 's/  exclusion-audit  check  .*//')
H='hides hand-written source'
for n in broad1 broad2 broad3 broad4; do want "$n" "a broad exclude hides source" "coverage-(exclude|exclude) '[^']+': $H"; done
unwanted narrow "a narrow exclude hides nothing" "$H"
want venv2 "a folder without pyvenv.cfg is audited" "^env/lib/site\.py:2 inline coverage marker '# pragma: no cover': no reason$"
unwanted venv1 "a virtual environment folder is not audited" "pragma"
unwanted cmd1 "other tools' command lines are not findings" "passes an exclude"
want cmd2 "a tool segment after && is a finding" "passes an exclude"
want cmd3 "a CI workflow is scanned" "ci\.yml:4 passes an exclude"
unwanted mark1 "markers in strings and prose are not markers" "inline coverage marker"
want mark2 "a block-comment marker without a reason" "src/a\.ts:1 inline coverage marker 'istanbul ignore next': no reason$"
want mark3 "v8 ignore start with no stop is whole-file" "src/a\.ts:1 inline coverage marker .*start.*hides hand-written source"
unwanted sonar1 "sonar test inclusions are not an allow-list" "allow-list"
unwanted dflt1 "normalised defaults are framework defaults only" "no reason"
unwanted py1 "stock python lines and conftest.py are defaults" "no reason"
want py2 "*/__init__.py still needs a reason" "coverage-exclude '\*/__init__\.py': no reason$"
unwanted incl1 "an include that covers every source file is no allow-list finding" "allow-list"
want links2 "a dangling directory link is reported" "^src/gone:1 is a symlink that is not a link to a regular file"
unwanted links1 "a link to a regular file is fine" "symlink"
# Revert proofs: a mutant copy of the migrate folder run over the same projects. PREFIX/PAT is a line the real audit gives and the mutant must lose;
# with "gain" the mutant must give a line the real audit does not.
audit_mutant3() { # audit_mutant3 lose|gain PREFIX PAT FILE OLD NEW
  local mode=$1 pre=$2 pat=$3 file=$4 old=$5 new=$6 mout
  rm -rf "$WORK/mutaudit3"
  mkdir -p "$WORK/mutaudit3"
  cp -R "$root/skills/migrate/general" "$WORK/mutaudit3/general"
  if ! OLD=$old NEW=$new perl -0pi -e '$c += s/\Q$ENV{OLD}\E/$ENV{NEW}/g; END { $? = $c ? 0 : 3 }' "$WORK/mutaudit3/general/$file"; then
    nok "revert proof: the mutation '$old' did not apply to $file"
    return
  fi
  mout=$(bash "$WORK/mutaudit3/general/defect-report.sh" "$R3" 2>&1 | grep '  exclusion-audit  check  ' | sed 's/  exclusion-audit  check  .*//' | awk -v p="$pre/" 'index($0, p) == 1 { print substr($0, length(p) + 1) }')
  if printf '%s\n' "$mout" | grep -Eq -- "$pat"; then
    if [ "$mode" = gain ]; then ok "revert proof: $pre gains /$pat/ with the fix undone ($file)"; else nok "revert proof: $pre still reports /$pat/ with the fix undone ($file)" "$mout"; fi
  else
    if [ "$mode" = lose ]; then ok "revert proof: $pre stops reporting /$pat/ with the fix undone ($file)"; else nok "revert proof: $pre does not gain /$pat/ with the fix undone ($file)" "$mout"; fi
  fi
}
AR=defects/exclusion-audit/rules.sh
audit_mutant3 gain venv1 "pragma" "$AR" 'pyvenv.cfg' 'zzz.cfg'
audit_mutant3 gain cmd1 "passes an exclude" "$AR" $'(cmd == "nyc" || cmd == "c8" || cmd == "coverage" || cmd == "mutmut") && ' ''
audit_mutant3 lose cmd2 "passes an exclude" "$AR" $'gsub(/&&/, "\\001", line)' $'gsub(/&&/, " ", line)'
audit_mutant3 gain mark1 "inline coverage marker" defects/exclusion-audit/scan.awk $'match(low, /^(istanbul|c8|v8)[ \\t]+ignore' $'match(low, /(istanbul|c8|v8)[ \\t]+ignore'
audit_mutant3 gain sonar1 "allow-list" defects/exclusion-audit/scan.awk $'if (key ~ /(^|\\.)sonar\\.([A-Za-z0-9_-]+\\.)*test\\.inclusions$/) return' ''
audit_mutant3 lose broad1 "$H" "$AR" $'rules_eval excl "$p" "$dir"' 'return 1'
audit_mutant3 gain dflt1 "no reason" defects/exclusion-audit/defaults.txt '**/tests/**' 'zzzunused'
audit_mutant3 lose links2 "^src/gone:1 is a symlink" defects/exclusion-audit.sh 'is a symlink that is not a link to a regular file, so nothing behind it was audited' 'zz'
ALLAUD=$SAVED_AUD

# 15 The audit says its exit code stays 0 by design.
if [ "$(printf '%s\n' "$ALL" | grep -c 'the audit exit code stays 0 by design, so the findings are in these lines')" -gt 0 ]; then ok "the audit output says the findings are in the lines, not the exit code"; else nok "the audit output does not say the exit code stays 0 by design"; fi

# Self-contained: the audit's scanners are byte copies of the seeded gate's, and the default list matches the gate's.
for pair in "scan.awk:check-exclude-reasons.awk" "scan.py:check-exclude-reasons.py" "scan.mjs:check-exclude-reasons.mjs" "rules.sh:check-exclude-rules.sh"; do
  a=${pair%%:*}
  g=${pair##*:}
  if cmp -s "$AUDITDIR/$a" "$GATEDIR/$g"; then ok "$a is a byte copy of $g"; else nok "$a differs from $g"; fi
done
sed -n "s/^dflt '\([^']*\)'.*/\1/p" "$GATEDIR/check-exclude-reasons.sh" > "$WORK/gate-defaults.txt"
if cmp -s "$WORK/gate-defaults.txt" "$AUDITDIR/defaults.txt" && [ -s "$AUDITDIR/defaults.txt" ]; then ok "defaults.txt equals the gate's default entries"; else nok "defaults.txt differs from the gate's default entries"; fi
awk "/^PLACEHOLDERS='/ { f = 1; sub(/^PLACEHOLDERS='/, \"\") } f { if (\$0 ~ /'\$/) { sub(/'\$/, \"\"); print; exit } print }" "$GATEDIR/check-exclude-reasons.sh" > "$WORK/gate-words.txt"
if cmp -s "$WORK/gate-words.txt" "$AUDITDIR/placeholders.txt" && [ -s "$AUDITDIR/placeholders.txt" ]; then ok "placeholders.txt equals the gate's placeholder words"; else nok "placeholders.txt differs from the gate's placeholder words"; fi
# The audit runs with nothing from the adopted project except its own typescript: a project with no scripts folder is audited.
report nextjs-none
if [ ! -e "$STAGE/nextjs-none/scripts" ] && printf '%s\n' "$AUD" | grep -q 'no reason$'; then ok "audit needs no seeded file in the project"; else nok "audit depended on a seeded file" "$OUT"; fi

# Secrets: no code line in the audit or its scanners names a dotenv file.
hits=$(for f in "$AUDIT" "$AUDITDIR"/scan.awk "$AUDITDIR"/scan.py "$AUDITDIR"/scan.mjs "$AUDITDIR"/scan-pnpm.awk; do
  grep -v '^[[:space:]]*\(#\|//\)' "$f" | grep -nE '(^|[^A-Za-z0-9_.])\.env' | sed "s|^|$f:|"
done)
if [ -z "$hits" ]; then ok "no code line names a dotenv file"; else nok "a code line names a dotenv file" "$hits"; fi

# Large project: CPU time (user plus system) of the whole runner, not wall time.
big=$WORK/big
mkdir -p "$big/node_modules"
ln -s "$TS" "$big/node_modules/typescript"
i=1
while [ "$i" -le 150 ]; do
  p=$big/packages/p$i
  mkdir -p "$p/src"
  cp "$FIX/nextjs-ok/vitest.config.ts" "$p/vitest.config.ts"
  cp "$FIX/nextjs-ok/package.json" "$p/package.json"
  echo 'export const a = 1;' > "$p/src/index.ts"
  i=$((i + 1))
done
TIMEFORMAT='%U %S'
cpu=$({ time bash "$root/$REPORT" "$big" > "$WORK/big.out" 2>&1; } 2>&1)
sum=$(printf '%s' "$cpu" | awk '{ printf "%.2f", $1 + $2 }')
lines=$(grep -c 'exclusion-audit' "$WORK/big.out" || true)
printf '# large project: 150 packages, %s audit lines, %s CPU seconds (budget %s)\n' "$lines" "$sum" "$BUDGET"
if [ "$lines" -ge 300 ] && awk -v s="$sum" -v b="$BUDGET" 'BEGIN { exit !(s + 0 <= b + 0) }'; then ok "150-package project audited within the CPU budget"; else nok "large project outside budget or incomplete ($lines lines, $sum CPU seconds)"; fi

printf '%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
