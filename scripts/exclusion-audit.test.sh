#!/usr/bin/env bash
# Tests for the migrate check skills/migrate/general/defects/exclusion-audit.sh, run through defect-report.sh as the real runner does.
# Fixtures live in tests/fixtures/exclusions/. Each runs on a copy; the copy and the fixtures are hashed before and after to prove the audit is read-only.
# The JS and TS scanner needs a typescript install: TC_TEST_TYPESCRIPT, ./node_modules, the global npm root, or a project folder under $HOME.
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
  echo "exclusion-audit.test: no typescript install found. Set TC_TEST_TYPESCRIPT to a typescript package folder." >&2
  exit 1
fi

tree_hash() {
  (cd "$1" && find . -path ./node_modules -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done | shasum | cut -d' ' -f1)
}

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
AUD=
RC=0
report() {
  local d
  d=$(stage "$1" "${2:-}")
  OUT=$(bash "$root/$REPORT" "$d" 2>&1)
  RC=$?
  AUD=$(printf '%s\n' "$OUT" | grep '  exclusion-audit  check  ' | sed 's/  exclusion-audit  check  .*//')
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

before=$(tree_hash "$FIX")

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
    want "fastapi-$key-$v" "entry is no reason" "^pyproject.toml:[0-9]+ coverage-exclude '(app/migrations/\*|if TYPE_CHECKING:)': no reason$"
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
report empty-project
if [ -z "$AUD" ] && printf '%s' "$OUT" | grep -q '0 matched'; then ok "empty-project: nothing to audit, nothing reported"; else nok "empty-project should report nothing" "$OUT"; fi

# Missing typescript is reported as unreadable, not as clean.
report nextjs-ok no-ts
if printf '%s\n' "$AUD" | grep -q 'cannot be read: typescript is not installed'; then ok "missing typescript is reported as unreadable"; else nok "missing typescript should be reported" "$OUT"; fi

# The audit lists; it does not fail the run. Exit 0 for every fixture.
bad=
for d in "$FIX"/*/; do
  n=$(basename "$d")
  report "$n"
  if [ "$RC" -ne 0 ]; then bad="$bad $n"; fi
done
if [ -z "$bad" ]; then ok "exit status is 0 for every fixture (level check)"; else nok "non-zero exit for:$bad"; fi

# Read-only: the audited copy and the fixtures hash the same before and after.
for n in nextjs-none fastapi-omit-none sonar-multi-none pnpm-yaml-none jest-collect-none shadow-tox-ini-none; do
  d=$(stage "$n")
  h1=$(tree_hash "$d")
  bash "$root/$REPORT" "$d" > /dev/null 2>&1
  h2=$(tree_hash "$d")
  if [ "$h1" = "$h2" ]; then ok "$n: audit leaves the project untouched"; else nok "$n: audit changed the project"; fi
done
after=$(tree_hash "$FIX")
if [ "$before" = "$after" ]; then ok "fixtures unchanged by the run"; else nok "fixtures changed during the run"; fi

# Self-contained: the audit's scanners are byte copies of the seeded gate's, and the default list matches the gate's.
for pair in "scan.awk:check-exclude-reasons.awk" "scan.py:check-exclude-reasons.py" "scan.mjs:check-exclude-reasons.mjs"; do
  a=${pair%%:*}
  g=${pair##*:}
  if cmp -s "$AUDITDIR/$a" "$GATEDIR/$g"; then ok "$a is a byte copy of $g"; else nok "$a differs from $g"; fi
done
awk '/^DEFAULTS=/ { f = 1; sub(/^DEFAULTS=\x27/, "") } f { if ($0 ~ /\x27$/) { sub(/\x27$/, ""); print; exit } print }' "$GATEDIR/check-exclude-reasons.sh" > "$WORK/gate-defaults.txt"
if cmp -s "$WORK/gate-defaults.txt" "$AUDITDIR/defaults.txt" && [ -s "$AUDITDIR/defaults.txt" ]; then ok "defaults.txt equals the gate's DEFAULTS list"; else nok "defaults.txt differs from the gate's DEFAULTS list"; fi
# The audit runs with nothing from the adopted project except its own typescript: a project with no scripts folder is audited.
report nextjs-none
if [ ! -e "$WORK/nextjs-none/scripts" ] && printf '%s\n' "$AUD" | grep -q 'no reason$'; then ok "audit needs no seeded file in the project"; else nok "audit depended on a seeded file" "$OUT"; fi

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
