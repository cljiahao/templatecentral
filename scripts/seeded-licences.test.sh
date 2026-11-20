#!/usr/bin/env bash
# scripts/seeded-licences.test.sh — the seeded check-licences gate: each rule blocks a bad input and a clean control passes.
# Stubbed pnpm and awk, and a fake Python environment read by the real metadata code, cover every rule. The real run scaffolds each stack, installs the dependencies
# (network to the public registries only, no key) and runs the gate. A missing tool for the real run fails the test; ALLOW_SKIP_REAL=1 skips it with a SKIPPED: line.
# Usage: bash scripts/seeded-licences.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/check-licences.sh"
LIST="$SH/template/.claude/allowed-licences.txt"
EXC="$SH/template/.claude/licence-exceptions.txt"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
hasnt() { # hasnt <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] is in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-lic.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# run <dir> [VAR=value ...]: sets OUT and EC from running the gate inside a fixture directory.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS -u VIRTUAL_ENV -u LICENCES_SCOPE -u ALLOWED_LICENCES_FILE -u LICENCE_EXCEPTIONS_FILE "$@" bash "$GATE" 2>&1)
  EC=$?
}

# base_fixture <name>: a folder with the seeded lists; sets D.
base_fixture() {
  D="$T/$1"
  mkdir -p "$D/.claude" "$D/stub"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  cp "$EXC" "$D/.claude/licence-exceptions.txt"
}
# pnpm_fixture <name> <json>: a project whose stub pnpm prints <json> as its licence report.
pnpm_fixture() {
  base_fixture "$1"
  echo '{}' > "$D/package.json"
  printf '#!/bin/sh\ncat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$2" > "$D/stub/pnpm"
  chmod +x "$D/stub/pnpm"
}
report() { # report <licence> <package>: a one-package pnpm report
  printf '{"%s":[{"name":"%s","versions":["1.2.3"],"license":"%s"}]}' "$1" "$2" "$1"
}
# stub_tool <dir> <name>: an executable stub whose body is read from stdin.
stub_tool() {
  { echo '#!/bin/sh'; cat; } > "$1/$2"
  chmod +x "$1/$2"
}

pnpm_fixture good "$(report MIT left-pad)"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "control: an allowed licence passes ($OUT)"
has "ok (1 packages, pnpm)" "$OUT" "control reports the package count and stack"

pnpm_fixture gpl "$(report GPL-3.0-only copyleft-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a licence outside the list fails"
has "copyleft-lib@1.2.3 has licence GPL-3.0-only" "$OUT" "message names the package and its licence"
has "human decision" "$OUT" "message says how to fix"

pnpm_fixture unknown "$(report Unknown mystery-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "an unknown licence fails"
has "mystery-lib@1.2.3 has licence Unknown" "$OUT" "message names the unknown-licence package"

pnpm_fixture unlicensed "$(report 'SEE LICENSE IN LICENSE.txt' vague-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a 'see licence in' entry fails"

pnpm_fixture or-ok "$(report 'MIT OR GPL-3.0-only' dual-lib)"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "an OR expression with one allowed side passes ($OUT)"

pnpm_fixture and-bad "$(report 'MIT AND GPL-3.0-only' both-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "an AND expression with a disallowed side fails"
has "both-lib" "$OUT" "AND failure names the package"

pnpm_fixture mixed-bad "$(report '(MIT OR Apache-2.0) AND GPL-2.0-only' tangled-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a nested AND/OR expression fails closed"

pnpm_fixture mixed-two '{"MIT":[{"name":"a","versions":["1"]}],"AGPL-3.0-only":[{"name":"b","versions":["2"]}]}'
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "one bad package among good ones fails"
has "b@2" "$OUT" "only the bad package is named"
hasnt "a@1 has" "$OUT" "the good package is not named"

pnpm_fixture nolist "$(report MIT left-pad)"
rm "$D/.claude/allowed-licences.txt"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a missing allow list fails closed"
has "allowed-licences.txt is missing" "$OUT" "message names the missing list"

pnpm_fixture emptylist "$(report MIT left-pad)"
printf '# only a comment\n' > "$D/.claude/allowed-licences.txt"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "an allow list with no licence fails closed"

pnpm_fixture noinstall "$(report MIT left-pad)"
printf '#!/bin/sh\necho "ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND" >&2\nexit 1\n' > "$D/stub/pnpm"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a failing pnpm fails closed"
has "Run pnpm install first" "$OUT" "message says to install first"

pnpm_fixture empty '{}'
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "no installed packages fails closed"

base_fixture nostack
run "$D"
check 2 "$EC" "a folder with no stack file fails closed"

# LICENCES_SCOPE: prod by default, all on request, anything else is refused.
pnpm_fixture scope "$(report MIT left-pad)"
stub_tool "$D/stub" pnpm << 'EOS'
echo "$*" > "$PWD/args.txt"
echo '{"MIT":[{"name":"left-pad","versions":["1"]}]}'
EOS
run "$D" PATH="$D/stub:$PATH"
has "--prod" "$(cat "$D/args.txt")" "the default scope asks pnpm for production dependencies"
run "$D" PATH="$D/stub:$PATH" LICENCES_SCOPE=all
check 0 "$EC" "LICENCES_SCOPE=all runs ($OUT)"
hasnt "--prod" "$(cat "$D/args.txt")" "scope all asks pnpm for every dependency"
run "$D" PATH="$D/stub:$PATH" LICENCES_SCOPE=dev
check 2 "$EC" "an invalid LICENCES_SCOPE fails closed"
has "LICENCES_SCOPE must be prod or all (got 'dev')" "$OUT" "message names the bad scope"
run "$D" PATH="$D/stub:$PATH" LICENCES_SCOPE=
check 0 "$EC" "an empty LICENCES_SCOPE means the default ($OUT)"

# Exceptions: a licence allowed for named packages only.
pnpm_fixture lgpl "$(report LGPL-3.0-or-later '@img/sharp-libvips-darwin-arm64')"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "the seeded exception lets the sharp libvips package carry LGPL ($OUT)"
check 0 "$(grep -c "^LGPL" "$LIST")" "the global list does not allow LGPL for every package"
rm "$D/.claude/licence-exceptions.txt"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "without the exceptions file the same package fails"
has "@img/sharp-libvips-darwin-arm64@1.2.3 has licence LGPL-3.0-or-later" "$OUT" "message names the package and licence"
check 0 "$(grep -c "^MPL" "$LIST")" "the global list does not allow MPL-2.0 for every package"
pnpm_fixture mpl-certifi "$(report MPL-2.0 certifi)"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "the seeded exception lets certifi carry MPL-2.0 ($OUT)"
pnpm_fixture mpl-other "$(report MPL-2.0 other-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "the certifi exception does not cover another MPL-2.0 package"
pnpm_fixture mpl-certifi-gpl "$(report GPL-3.0-only certifi)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "the certifi exception covers only MPL-2.0, not another licence"
pnpm_fixture lgpl-other "$(report LGPL-3.0-or-later other-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "the exception does not cover another package"
pnpm_fixture lgpl-and "$(report 'Apache-2.0 AND LGPL-3.0-or-later' '@img/sharp-win32-x64')"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "an AND expression passes when the exception covers its other half ($OUT)"
pnpm_fixture lgpl-and-other "$(report 'Apache-2.0 AND LGPL-3.0-or-later' other-lib)"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "the same expression fails for a package without an exception"
pnpm_fixture glob "$(report GPL-2.0-only a.bc)"
printf 'a.b* GPL-2.0-only\n' > "$D/other-exc.txt"
run "$D" PATH="$D/stub:$PATH" LICENCE_EXCEPTIONS_FILE="$D/other-exc.txt"
check 0 "$EC" "a pattern matches a name with a dot ($OUT)"
pnpm_fixture glob-miss "$(report GPL-2.0-only axbc)"
printf 'a.b* GPL-2.0-only\n' > "$D/other-exc.txt"
run "$D" PATH="$D/stub:$PATH" LICENCE_EXCEPTIONS_FILE="$D/other-exc.txt"
check 1 "$EC" "a dot in a pattern is not a wildcard"

# A failing or lying awk must never read as a pass.
pnpm_fixture awk-fail "$(report MIT left-pad)"
stub_tool "$D/stub" awk << 'EOS'
exit 2
EOS
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "an awk that exits 2 fails closed"
has "the licence check failed to run" "$OUT" "message says the check failed to run"
hasnt "ok (" "$OUT" "no ok line after an awk failure"
stub_tool "$D/stub" awk << 'EOS'
exit 0
EOS
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "an awk that prints nothing fails closed"
has "did not look at all 1 packages" "$OUT" "message says the packages were not all checked"
stub_tool "$D/stub" awk << 'EOS'
printf '__judged__\t0\n'
EOS
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "an awk that judged fewer packages than listed fails closed"

# Python with a stub interpreter, for the judging rules.
# py_fixture <name> <stub output>: a Python project whose .venv/bin/python stub prints <stub output>.
py_fixture() {
  base_fixture "$1"
  mkdir -p "$D/.venv/bin"
  : > "$D/requirements.txt"
  printf '#!/bin/sh\nprintf '"'"'%s\\n'"'"'\n' "$2" > "$D/.venv/bin/python"
  chmod +x "$D/.venv/bin/python"
}
py_fixture py-good 'fastapi@0.1	MIT'
run "$D"
check 0 "$EC" "python control passes ($OUT)"
has "ok (1 packages, python)" "$OUT" "python control names the stack"
py_fixture py-label 'old-lib@1.0	BSD License'
run "$D"
check 0 "$EC" "python classifier label in the list passes ($OUT)"
py_fixture py-bad 'gpl-lib@3.0	GPL-3.0-only'
run "$D"
check 1 "$EC" "python licence outside the list fails"
has "gpl-lib@3.0 has licence GPL-3.0-only" "$OUT" "python message names the package and licence"

# Python read by the real metadata code from a fake environment.
# env_fixture <name> <requirements text>: a Python project whose .venv/bin/python is the real interpreter without the global site-packages; sets D and SITE.
env_fixture() {
  base_fixture "$1"
  SITE="$D/site"
  mkdir -p "$D/.venv/bin" "$SITE"
  printf '#!/bin/sh\nexec python3 -S "$@"\n' > "$D/.venv/bin/python"
  chmod +x "$D/.venv/bin/python"
  printf '%s' "$2" > "$D/requirements.txt"
}
# dist <name> <version> [header line ...]: a fake installed distribution in $SITE.
dist() {
  local name=$1 version=$2
  shift 2
  mkdir -p "$SITE/$name-$version.dist-info"
  { printf 'Metadata-Version: 2.4\nName: %s\nVersion: %s\n' "$name" "$version"; for h in "$@"; do printf '%s\n' "$h"; done; } > "$SITE/$name-$version.dist-info/METADATA"
}

env_fixture py-meta 'okpkg==1.0
nopkg==1.0
'
dist okpkg 1.0 'License-Expression: MIT'
dist nopkg 1.0
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "real metadata: a package with no licence fails"
has "nopkg@1.0 has licence Unknown" "$OUT" "real metadata: names the unlicensed package"

env_fixture py-covered 'ok_pkg==1.0 \
    --hash=sha256:aa
'
dist ok-pkg 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "real metadata: a requirement that is installed passes, names normalised ($OUT)"

env_fixture py-marker 'okpkg==1.0
winonly==1.0 ; sys_platform == '"'win32'"' \
    --hash=sha256:aa
'
dist okpkg 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "real metadata: a requirement behind a marker that is not installed does not fail ($OUT)"

env_fixture py-missing 'okpkg==1.0
fastapi==0.1 \
    --hash=sha256:aa
'
dist okpkg 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 2 "$EC" "a package named in requirements.txt but not installed fails closed"
has "requirements.txt lists fastapi, which is not installed" "$OUT" "message names the missing package"
hasnt "ok (" "$OUT" "no ok line when a requirement is missing"

env_fixture py-empty 'fastapi==0.1
'
run "$D" PYTHONPATH="$SITE"
check 2 "$EC" "an environment with nothing installed fails closed"

env_fixture py-noenv 'okpkg==1.0
'
rm -r "$D/.venv"
dist okpkg 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 2 "$EC" "no project environment fails, even when the global python3 has packages"
has "no project Python environment" "$OUT" "message says there is no environment"
has "Create the environment and install first" "$OUT" "message says how to fix it"

env_fixture py-virtualenv 'okpkg==1.0
'
dist okpkg 1.0 'License-Expression: MIT'
mkdir -p "$D/venvx/bin"
mv "$D/.venv/bin/python" "$D/venvx/bin/python"
rm -r "$D/.venv"
run "$D" PYTHONPATH="$SITE" VIRTUAL_ENV="$D/venvx"
check 0 "$EC" "VIRTUAL_ENV names the environment ($OUT)"

env_fixture py-two-classifiers 'twolic==1.0
'
dist twolic 1.0 'Classifier: License :: OSI Approved :: MIT License' 'Classifier: License :: OSI Approved :: BSD License'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "several allowed classifiers on one package pass ($OUT)"
env_fixture py-two-classifiers-bad 'twolic==1.0
'
dist twolic 1.0 'Classifier: License :: OSI Approved :: MIT License' 'Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)'
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "several classifiers are joined with AND, so one outside the list fails"
has "twolic@1.0 has licence GNU General Public License v3 (GPLv3) AND MIT License" "$OUT" "message shows the joined classifiers"

# A Python project with a package.json for tooling: both are checked, neither is skipped.
both_fixture() { # both_fixture <name> <pnpm licence> <python licence>
  env_fixture "$1" 'okpkg==1.0
'
  dist okpkg 1.0 "License-Expression: $3"
  echo '{}' > "$D/package.json"
  printf '#!/bin/sh\ncat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$(report "$2" tool-lib)" > "$D/stub/pnpm"
  chmod +x "$D/stub/pnpm"
}
both_fixture both-good MIT MIT
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 0 "$EC" "python plus package.json: both clean passes ($OUT)"
has "ok (2 packages, pnpm+python)" "$OUT" "both stacks are counted"
both_fixture both-pnpm-bad GPL-3.0-only MIT
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 1 "$EC" "python plus package.json: a bad pnpm package fails"
has "tool-lib@1.2.3 has licence GPL-3.0-only" "$OUT" "the pnpm finding is named"
both_fixture both-py-bad MIT GPL-3.0-only
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 1 "$EC" "python plus package.json: a bad Python package fails"
has "okpkg@1.0 has licence GPL-3.0-only" "$OUT" "the Python finding is named"
both_fixture both-noenv MIT MIT
rm -r "$D/.venv"
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 2 "$EC" "python plus package.json: a missing Python environment is not skipped"
has "no project Python environment" "$OUT" "the missing environment is named"
both_fixture both-nopnpm MIT MIT
printf '#!/bin/sh\nexit 1\n' > "$D/stub/pnpm"
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 2 "$EC" "python plus package.json: a failing pnpm is not skipped"

# A distribution with no Name is a finding named by its folder, never skipped.
env_fixture py-nameless 'okpkg==1.0
'
dist okpkg 1.0 'License-Expression: MIT'
mkdir -p "$SITE/nameless-1.0.dist-info"
printf 'Metadata-Version: 2.4\nVersion: 1.0\n' > "$SITE/nameless-1.0.dist-info/METADATA"
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "a Python distribution with no Name fails instead of being skipped"
has "nameless-1.0.dist-info" "$OUT" "the finding names the dist-info folder"
has "Unknown" "$OUT" "the nameless distribution has an unknown licence"

# The verdict comes from the findings, not from a sort that could succeed with no output.
pnpm_fixture sort-lie "$(report GPL-3.0-only copyleft-lib)"
stub_tool "$D/stub" sort << 'EOS'
exit 0
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a sort that prints nothing still fails a bad package"
has "copyleft-lib@1.2.3 has licence GPL-3.0-only" "$OUT" "the finding is printed from the unsorted list"
pnpm_fixture sort-fail "$(report GPL-3.0-only copyleft-lib)"
stub_tool "$D/stub" sort << 'EOS'
exit 1
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a failing sort cannot read as a pass"
has "copyleft-lib@1.2.3 has licence GPL-3.0-only" "$OUT" "the finding is printed from the unsorted list when sort fails"

# An exception pattern needs a literal prefix of 3 characters before its first '*'.
pnpm_fixture star "$(report GPL-3.0-only any-lib)"
for pat in '*' '  *  ' '*a*' '*g' '*-*' '@*/*' 'ba*' 'ab*'; do
  printf '%s GPL-3.0-only\n' "$pat" > "$D/star-exc.txt"
  run "$D" PATH="$D/stub:$PATH" LICENCE_EXCEPTIONS_FILE="$D/star-exc.txt"
  check 2 "$EC" "exception pattern '$pat' is refused"
  has "literal prefix of at least 3 characters before the first '*'" "$OUT" "message states the rule for '$pat'"
done
for pat in 'any-*' '@img/sharp-libvips-*' 'copyleft-lib' 'abc*'; do
  printf '%s GPL-3.0-only\n' "$pat" > "$D/star-exc.txt"
  run "$D" PATH="$D/stub:$PATH" LICENCE_EXCEPTIONS_FILE="$D/star-exc.txt"
  hasnt "literal prefix" "$OUT" "pattern '$pat' is accepted by the rule"
done

# A tab inside a licence string must not cut it short.
pnpm_fixture tab-node "$(printf '{"MIT\\tGPL-3.0-only":[{"name":"tab-lib","versions":["1.0.0"]}]}')"
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a pnpm licence with a tab inside fails"
has "tab-lib@1.0.0 has licence MIT GPL-3.0-only" "$OUT" "the full licence string is named"
env_fixture py-tab 'tabpkg==1.0
'
dist tabpkg 1.0 "License: MIT$(printf '\t')GPL-3.0-only"
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "a Python licence with a tab inside fails"
has "tabpkg@1.0 has licence MIT GPL-3.0-only" "$OUT" "the full Python licence string is named"
env_fixture py-tab-ok 'tabpkg==1.0
'
dist tabpkg 1.0 "License: MIT$(printf '\t')BSD License"
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "a tab-joined unknown pair still fails (control for the allowed list)"

# A lock line behind an environment marker is still checked when it is installed, and may be absent when it is not.
env_fixture py-marker-bad 'ok==1.0
uvloop==1.0 ; sys_platform != '"'win32'"' \
    --hash=sha256:aa
'
dist ok 1.0 'License-Expression: MIT'
dist uvloop 1.0 'License-Expression: GPL-3.0-only'
run "$D" PYTHONPATH="$SITE" PATH="$D/stub:$PATH"
check 1 "$EC" "a marker line that is installed with a bad licence fails"
has "uvloop@1.0 has licence GPL-3.0-only" "$OUT" "the marker-line finding is named"
env_fixture py-marker-good 'ok==1.0
uvloop==1.0 ; sys_platform != '"'win32'"' \
    --hash=sha256:aa
'
dist ok 1.0 'License-Expression: MIT'
dist uvloop 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "control: a marker line installed with an allowed licence passes ($OUT)"
has "ok (2 packages, python)" "$OUT" "the marker package is counted"
env_fixture py-marker-absent 'ok==1.0
uvloop==1.0 ; sys_platform == '"'win32'"'
'
dist ok 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "a marker line that is not installed passes ($OUT)"
env_fixture py-plain-absent 'ok==1.0
uvloop==1.0
'
dist ok 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 2 "$EC" "a line without a marker that is not installed fails closed"
has "requirements.txt lists uvloop, which is not installed" "$OUT" "message names the missing package"

# An included file would escape the prod closure, so the lock must be self-contained.
for inc in '-r other.txt' '--requirement=other.txt' '-c cons.txt' '--constraint cons.txt' '-rother.txt' '-cother.txt' '  -r other.txt' '--unknown-flag' '-X'; do
  env_fixture py-include "ok==1.0
$inc
"
  dist ok 1.0 'License-Expression: MIT'
  dist bad 1.0 'License-Expression: GPL-3.0-only'
  run "$D" PYTHONPATH="$SITE"
  check 2 "$EC" "'$inc' in the lock is refused in prod scope"
  has "must be self-contained" "$OUT" "message says the lock must be self-contained for '$inc'"
  has "'$(printf '%s' "$inc" | sed 's/^ *//')'" "$OUT" "message names the offending line '$inc'"
  hasnt "Create the environment and install first" "$OUT" "the self-contained error carries no install hint for '$inc'"
done
for opt in '--require-hashes' '--index-url https://example.invalid/simple' '-i https://example.invalid/simple' '--extra-index-url x' '-f x' '--find-links x' '--no-binary :all:' '--only-binary :all:' '--trusted-host x' '--prefer-binary' '-e .' '--editable .'; do
  env_fixture py-opt-ok "$opt
ok==1.0
"
  dist ok 1.0 'License-Expression: MIT'
  run "$D" PYTHONPATH="$SITE"
  check 0 "$EC" "control: the allowed option '$opt' is not refused ($OUT)"
done

# A leading-space line after a line without a backslash is not a continuation; after a backslash it is.
env_fixture py-lead 'ok==1.0
  uvloop==1.0
'
dist ok 1.0 'License-Expression: MIT'
dist uvloop 1.0 'License-Expression: GPL-3.0-only'
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "an indented requirement line is still read, not skipped as a continuation"
has "uvloop@1.0 has licence GPL-3.0-only" "$OUT" "the indented line is checked"
env_fixture py-cont 'ok==1.0 \
    --hash=sha256:aa \
    --hash=sha256:bb
'
dist ok 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "control: hash continuation lines are skipped ($OUT)"
# A comment holding a semicolon does not make a required line optional.
env_fixture py-comment 'ok==1.0
uvloop==1.0 # a;b
'
dist ok 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 2 "$EC" "a ; inside a trailing comment does not make a missing line optional"
has "requirements.txt lists uvloop, which is not installed" "$OUT" "the commented line is still required"
dist uvloop 1.0 'License-Expression: GPL-3.0-only'
run "$D" PYTHONPATH="$SITE"
check 1 "$EC" "the commented line is checked when installed"
env_fixture py-include-all 'ok==1.0
-r other.txt
'
dist ok 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE" LICENCES_SCOPE=all
check 0 "$EC" "scope all does not read the lock, so an include line is not refused ($OUT)"

# Python prod scope checks the locked names only; all checks the whole environment.
env_fixture py-scope 'okpkg==1.0
'
dist okpkg 1.0 'License-Expression: MIT'
dist devtool 2.0 'License-Expression: GPL-3.0-only'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "prod scope ignores an installed package that is not locked ($OUT)"
has "ok (1 packages, python)" "$OUT" "prod scope counts the locked package only"
run "$D" PYTHONPATH="$SITE" LICENCES_SCOPE=all
check 1 "$EC" "all scope checks the whole environment"
has "devtool@2.0 has licence GPL-3.0-only" "$OUT" "all scope names the dev package"

# File overrides can widen the gate, so CI refuses them.
pnpm_fixture ci "$(report GPL-3.0-only copyleft-lib)"
printf 'copyleft-lib GPL-3.0-only\n' > "$D/ok-exc.txt"
printf 'MIT\nGPL-3.0-only\n' > "$D/wide-list.txt"
for ci in GITHUB_ACTIONS=true TF_BUILD=True; do
  run "$D" PATH="$D/stub:$PATH" "$ci" LICENCE_EXCEPTIONS_FILE="$D/ok-exc.txt"
  check 2 "$EC" "LICENCE_EXCEPTIONS_FILE is refused with $ci"
  has "not allowed in CI" "$OUT" "exceptions refusal under $ci says why"
  run "$D" PATH="$D/stub:$PATH" "$ci" ALLOWED_LICENCES_FILE="$D/wide-list.txt"
  check 2 "$EC" "ALLOWED_LICENCES_FILE is refused with $ci"
done
run "$D" PATH="$D/stub:$PATH" LICENCE_EXCEPTIONS_FILE="$D/ok-exc.txt"
check 0 "$EC" "LICENCE_EXCEPTIONS_FILE is allowed outside CI ($OUT)"
run "$D" PATH="$D/stub:$PATH" ALLOWED_LICENCES_FILE="$D/wide-list.txt"
check 0 "$EC" "ALLOWED_LICENCES_FILE is allowed outside CI ($OUT)"
run "$D" PATH="$D/stub:$PATH" GITHUB_ACTIONS=true
check 1 "$EC" "CI without overrides still judges against the seeded lists"

# pyproject only (no requirements.txt): everything installed is listed.
env_fixture py-pyproject ''
rm "$D/requirements.txt"
: > "$D/pyproject.toml"
dist okpkg 1.0 'License-Expression: MIT'
run "$D" PYTHONPATH="$SITE"
check 0 "$EC" "a pyproject-only project lists everything installed ($OUT)"

# real_required <what>: the real run needs tools that are missing.
real_required() {
  if [ "${ALLOW_SKIP_REAL:-}" = 1 ]; then
    echo "SKIPPED: $1 is not installed, so the real scaffold runs did NOT happen and the gate was NOT proven on a real project (ALLOW_SKIP_REAL=1)."
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 is not installed, so the real scaffold runs cannot happen. Install it, or set ALLOW_SKIP_REAL=1 to skip them on purpose."
  fi
}
real_ok=1
for tool in pnpm uv; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    real_required "$tool"
    real_ok=0
  fi
done

if [ "$real_ok" -eq 1 ]; then
  # real_pnpm <stack>: scaffold, install and run the gate; sets D, OUT and EC.
  real_pnpm() {
    D="$T/real-$1"
    mkdir -p "$D"
    TC_STACK=$1 TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
    check 0 $? "$1 scaffold copies"
    mkdir -p "$D/.claude"
    cp "$LIST" "$D/.claude/allowed-licences.txt"
    cp "$EXC" "$D/.claude/licence-exceptions.txt"
    (cd "$D" && env -u CI pnpm install > "$T/$1-install.log" 2>&1)
    check 0 $? "$1 scaffold installs: $(tail -n 3 "$T/$1-install.log" | tr '\n' ' ')"
    run "$D"
  }
  for stack in nextjs vite-react nestjs; do
    real_pnpm "$stack"
    check 0 "$EC" "real $stack scaffold passes the licence gate ($OUT)"
    echo "real run $stack: $OUT"
    has "packages, pnpm)" "$OUT" "real $stack run checked pnpm packages and was not skipped"
    if [ "$stack" = nextjs ]; then
      grep -v '^CC-BY-4.0$' "$LIST" > "$D/.claude/allowed-licences.txt"
      run "$D"
      check 1 "$EC" "real nextjs scaffold fails once CC-BY-4.0 leaves the list"
      has "caniuse-lite" "$OUT" "real failure names caniuse-lite"
      cp "$LIST" "$D/.claude/allowed-licences.txt"
      rm "$D/.claude/licence-exceptions.txt"
      run "$D"
      check 1 "$EC" "real nextjs scaffold without the exceptions file fails on the sharp libvips LGPL"
      has "@img/sharp-libvips" "$OUT" "real failure names the sharp libvips package"
      has "has licence LGPL-3.0-or-later" "$OUT" "real failure names the licence"
      cp "$EXC" "$D/.claude/licence-exceptions.txt"
      run "$D" LICENCES_SCOPE=all
      check 1 "$EC" "real nextjs scaffold with scope all fails on a dev-only licence"
      has "has licence" "$OUT" "scope all names the finding"
      echo "real run nextjs scope all: EC=$EC"
      printf '%s\n' "$OUT"
    fi
  done

  # The fastapi tree is built from the exact requirements.in the scaffold writes (read from its source file, so the two cannot drift).
  D="$T/real-py"
  mkdir -p "$D"
  TC_STACK=fastapi TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "fastapi scaffold copies"
  mkdir -p "$D/.claude"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  cp "$EXC" "$D/.claude/licence-exceptions.txt"
  awk '/^cat > requirements.in <<.REQ.$/ { on = 1; next } /^REQ$/ { on = 0 } on' "$SH/../fastapi/source-files.md" > "$D/requirements.in"
  check 1 "$(grep -c '^certifi' "$D/requirements.in")" "the seeded requirements.in was extracted and lists certifi"
  sed -n '/^cat > requirements.in <<.REQ.$/,/^REQ$/p' "$SH/../fastapi/source-files.md" | sed '1d;$d' > "$T/req-expected.in"
  check 0 "$(cmp -s "$T/req-expected.in" "$D/requirements.in"; echo $?)" "the extracted requirements.in equals the seeded block"
  check 1 "$([ -s "$D/requirements.in" ] && echo 1)" "the extracted requirements.in is not empty"
  has "fastapi>=" "$(cat "$D/requirements.in")" "the seeded requirements.in lists fastapi"
  (cd "$D" && uv pip compile requirements.in --universal --generate-hashes -o requirements.txt > "$T/py-compile.log" 2>&1)
  check 0 $? "fastapi requirements.txt compiles: $(tail -n 3 "$T/py-compile.log" | tr '\n' ' ')"
  run "$D"
  check 2 "$EC" "real fastapi project without an environment fails closed"
  has "no project Python environment" "$OUT" "real failure says to create the environment"
  (cd "$D" && uv venv .venv > /dev/null 2>&1 && uv pip install --python .venv/bin/python --require-hashes -r requirements.txt > "$T/py-install.log" 2>&1)
  check 0 $? "fastapi scaffold installs: $(tail -n 3 "$T/py-install.log" | tr '\n' ' ')"
  (cd "$D" && uv pip install --python .venv/bin/python -r requirements-dev.txt > "$T/py-install-dev.log" 2>&1)
  check 0 $? "fastapi dev requirements install as scaffold Step 4 does: $(tail -n 3 "$T/py-install-dev.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real fastapi scaffold passes the licence gate in prod scope ($OUT)"
  echo "real run fastapi: $OUT"
  has "packages, python)" "$OUT" "real fastapi run checked python packages and was not skipped"
  run "$D" LICENCES_SCOPE=all
  check 1 "$EC" "real fastapi scaffold with scope all fails on a dev-only package"
  has "nodeenv@" "$OUT" "scope all names nodeenv"
  has "nodeenv@1" "$OUT" "scope all finding carries a version"
  rm "$D/.claude/licence-exceptions.txt"
  run "$D"
  check 1 "$EC" "real fastapi scaffold without the exceptions file fails on certifi"
  has "certifi@" "$OUT" "real failure names certifi"
  has "has licence MPL-2.0" "$OUT" "real failure names MPL-2.0"
fi

echo "seeded-licences.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
