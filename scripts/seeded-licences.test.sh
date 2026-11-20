#!/usr/bin/env bash
# scripts/seeded-licences.test.sh — the seeded check-licences gate: each rule blocks a bad input and a clean control passes.
# Stubbed pnpm and python cover every rule. A real run scaffolds nextjs and fastapi, installs dependencies (network to the public registries only, no key)
# and runs the gate. Without a package manager or network the real run prints a loud SKIP locally and fails when CI is set.
# Usage: bash scripts/seeded-licences.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/check-licences.sh"
LIST="$SH/template/.claude/allowed-licences.txt"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-lic.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

# run <dir> [path-prefix]: sets OUT and EC from running the gate inside a fixture directory.
run() {
  OUT=$(cd "$1" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="${2:+$2:}$PATH" bash "$GATE" 2>&1)
  EC=$?
}

# pnpm_fixture <name> <json>: a project whose stub pnpm prints <json> as its licence report.
pnpm_fixture() {
  D="$T/$1"
  mkdir -p "$D/.claude" "$D/stub"
  echo '{}' > "$D/package.json"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  printf '#!/bin/sh\ncat <<'"'"'EOF'"'"'\n%s\nEOF\n' "$2" > "$D/stub/pnpm"
  chmod +x "$D/stub/pnpm"
}
report() { # report <licence> <package>: a one-package pnpm report
  printf '{"%s":[{"name":"%s","versions":["1.2.3"],"license":"%s"}]}' "$1" "$2" "$1"
}

pnpm_fixture good "$(report MIT left-pad)"
run "$D" "$D/stub"
check 0 "$EC" "control: an allowed licence passes ($OUT)"
has "ok (1 packages" "$OUT" "control reports the package count"

pnpm_fixture gpl "$(report GPL-3.0-only copyleft-lib)"
run "$D" "$D/stub"
check 1 "$EC" "a licence outside the list fails"
has "copyleft-lib@1.2.3 has licence GPL-3.0-only" "$OUT" "message names the package and its licence"
has "human decision" "$OUT" "message says how to fix"

pnpm_fixture unknown "$(report Unknown mystery-lib)"
run "$D" "$D/stub"
check 1 "$EC" "an unknown licence fails"
has "mystery-lib@1.2.3 has licence Unknown" "$OUT" "message names the unknown-licence package"

pnpm_fixture unlicensed "$(report 'SEE LICENSE IN LICENSE.txt' vague-lib)"
run "$D" "$D/stub"
check 1 "$EC" "a 'see licence in' entry fails"

pnpm_fixture or-ok "$(report 'MIT OR GPL-3.0-only' dual-lib)"
run "$D" "$D/stub"
check 0 "$EC" "an OR expression with one allowed side passes ($OUT)"

pnpm_fixture and-bad "$(report 'MIT AND GPL-3.0-only' both-lib)"
run "$D" "$D/stub"
check 1 "$EC" "an AND expression with a disallowed side fails"
has "both-lib" "$OUT" "AND failure names the package"

pnpm_fixture mixed-bad "$(report '(MIT OR Apache-2.0) AND GPL-2.0-only' tangled-lib)"
run "$D" "$D/stub"
check 1 "$EC" "a nested AND/OR expression fails closed"

pnpm_fixture mixed-two '{"MIT":[{"name":"a","versions":["1"]}],"AGPL-3.0-only":[{"name":"b","versions":["2"]}]}'
run "$D" "$D/stub"
check 1 "$EC" "one bad package among good ones fails"
has "b@2" "$OUT" "only the bad package is named"
case "$OUT" in *"a@1 has"*) check no yes "the good package is not named" ;; *) check no no "the good package is not named" ;; esac

pnpm_fixture nolist "$(report MIT left-pad)"
rm "$D/.claude/allowed-licences.txt"
run "$D" "$D/stub"
check 2 "$EC" "a missing allow list fails closed"
has "allowed-licences.txt is missing" "$OUT" "message names the missing list"

pnpm_fixture emptylist "$(report MIT left-pad)"
printf '# only a comment\n' > "$D/.claude/allowed-licences.txt"
run "$D" "$D/stub"
check 2 "$EC" "an allow list with no licence fails closed"

pnpm_fixture noinstall "$(report MIT left-pad)"
printf '#!/bin/sh\necho "ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND" >&2\nexit 1\n' > "$D/stub/pnpm"
run "$D" "$D/stub"
check 2 "$EC" "a failing pnpm fails closed"
has "Run pnpm install first" "$OUT" "message says to install first"

pnpm_fixture empty '{}'
run "$D" "$D/stub"
check 2 "$EC" "no installed packages fails closed"

D="$T/nostack"
mkdir -p "$D/.claude"
cp "$LIST" "$D/.claude/allowed-licences.txt"
run "$D"
check 2 "$EC" "a folder with no stack file fails closed"

# py_fixture <name> <stub output>: a Python project whose .venv/bin/python stub prints <stub output>.
py_fixture() {
  D="$T/$1"
  mkdir -p "$D/.claude" "$D/.venv/bin"
  : > "$D/requirements.txt"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  printf '#!/bin/sh\ncat > /dev/null\nprintf '"'"'%s\\n'"'"'\n' "$2" > "$D/.venv/bin/python"
  chmod +x "$D/.venv/bin/python"
}
py_fixture py-good 'fastapi@0.1	MIT'
run "$D"
check 0 "$EC" "python control passes ($OUT)"
py_fixture py-label 'old-lib@1.0	BSD License'
run "$D"
check 0 "$EC" "python classifier label in the list passes ($OUT)"
py_fixture py-bad 'gpl-lib@3.0	GPL-3.0-only'
run "$D"
check 1 "$EC" "python licence outside the list fails"
has "gpl-lib@3.0 has licence GPL-3.0-only" "$OUT" "python message names the package and licence"

# Real python metadata reader, no stub: a fake installed distribution with and without a licence.
D="$T/py-meta"
mkdir -p "$D/.claude" "$D/site/okpkg-1.0.dist-info" "$D/site/nopkg-1.0.dist-info"
: > "$D/requirements.txt"
cp "$LIST" "$D/.claude/allowed-licences.txt"
printf 'Metadata-Version: 2.4\nName: okpkg\nVersion: 1.0\nLicense-Expression: MIT\n' > "$D/site/okpkg-1.0.dist-info/METADATA"
printf 'Metadata-Version: 2.4\nName: nopkg\nVersion: 1.0\n' > "$D/site/nopkg-1.0.dist-info/METADATA"
OUT=$(cd "$D" && env -u CI PYTHONPATH="$D/site" bash "$GATE" 2>&1)
EC=$?
check 1 "$EC" "real metadata: a package with no licence fails"
has "nopkg@1.0 has licence Unknown" "$OUT" "real metadata: names the unlicensed package"

# The seeded list must accept the licences the stack templates ship; the real runs below prove it.

in_ci=0
for v in "${CI:-}" "${TF_BUILD:-}" "${GITHUB_ACTIONS:-}"; do
  case "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" in "" | false | 0 | no) ;; *) in_ci=1 ;; esac
done
real_ok=1
for tool in pnpm uv; do
  command -v "$tool" > /dev/null 2>&1 || real_ok=0
done
if [ "$real_ok" -eq 0 ]; then
  if [ "$in_ci" -eq 1 ]; then
    echo "seeded-licences.test: FAIL pnpm or uv is not available in CI, so the real run did not happen." >&2
    FAIL=$((FAIL + 1))
  else
    echo "SKIPPED: pnpm or uv is not installed, so the real scaffold runs did NOT happen and the gate was NOT proven on a real project."
  fi
else
  # Fresh nextjs scaffold, real pnpm install, real licence report.
  D="$T/real-next"
  mkdir -p "$D"
  TC_STACK=nextjs TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "nextjs scaffold copies"
  mkdir -p "$D/.claude"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  (cd "$D" && pnpm install > "$T/next-install.log" 2>&1)
  check 0 $? "nextjs scaffold installs: $(tail -n 3 "$T/next-install.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real nextjs scaffold passes the licence gate ($OUT)"
  echo "real run nextjs: $OUT"
  grep -v '^CC-BY-4.0$' "$LIST" > "$D/.claude/allowed-licences.txt"
  run "$D"
  check 1 "$EC" "real nextjs scaffold fails once CC-BY-4.0 leaves the list"
  has "caniuse-lite" "$OUT" "real failure names caniuse-lite"

  # Fresh fastapi scaffold with a compiled hashed requirements.txt, installed into .venv.
  D="$T/real-py"
  mkdir -p "$D"
  TC_STACK=fastapi TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "fastapi scaffold copies"
  mkdir -p "$D/.claude"
  cp "$LIST" "$D/.claude/allowed-licences.txt"
  printf 'fastapi\npydantic\nstructlog\nuvicorn\n' > "$D/requirements.in"
  (cd "$D" && uv pip compile requirements.in --universal --generate-hashes -o requirements.txt > "$T/py-compile.log" 2>&1 \
    && uv venv .venv > /dev/null 2>&1 \
    && uv pip install --python .venv/bin/python --require-hashes -r requirements.txt > "$T/py-install.log" 2>&1)
  check 0 $? "fastapi scaffold compiles and installs: $(tail -n 3 "$T/py-compile.log" "$T/py-install.log" 2> /dev/null | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real fastapi scaffold passes the licence gate ($OUT)"
  echo "real run fastapi: $OUT"
fi

echo "seeded-licences.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
