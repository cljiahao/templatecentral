#!/usr/bin/env bash
# scripts/seeded-sbom.test.sh — the seeded generate-sbom gate: it writes a CycloneDX file, fails closed when it cannot, and never leaves a stale file.
# Stubbed pnpm, pipx and uvx cover every rule. A real run scaffolds nextjs and fastapi and generates real SBOMs (network to the public registries only, no key),
# twice, and compares the two runs apart from serialNumber and timestamp. Without a package manager or network the real run prints a loud SKIP locally and fails when CI is set.
# Usage: bash scripts/seeded-sbom.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/generate-sbom.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-sbom.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

BASH_BIN=$(command -v bash)
export BOM_FILE="$T/bom.json"
echo '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[]}' > "$BOM_FILE"

# run <dir> [path]: sets OUT and EC from running the gate inside a fixture directory, with <path> as PATH when given.
run() {
  OUT=$(cd "$1" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS PATH="${2:-$PATH}" "$BASH_BIN" "$GATE" 2>&1)
  EC=$?
}
# stub <dir> <name>: an executable stub tool whose body is read from stdin.
stub() {
  mkdir -p "$1"
  { echo '#!/bin/sh'; cat; } > "$1/$2"
  chmod +x "$1/$2"
}
# exists <path>: 1 when the file exists and is not empty, else 0.
exists() { if [ -s "$1" ]; then echo 1; else echo 0; fi; }

# pnpm_fixture <name>: a pnpm project whose stub pnpm prints a CycloneDX document; override the stub with stub "$D/stub" pnpm.
pnpm_fixture() {
  D="$T/$1"
  mkdir -p "$D"
  echo '{}' > "$D/package.json"
  echo "lockfileVersion: '9.0'" > "$D/pnpm-lock.yaml"
  stub "$D/stub" pnpm << 'EOS'
cat "$BOM_FILE"
EOS
}

pnpm_fixture good
run "$D" "$D/stub:$PATH"
check 0 "$EC" "control: pnpm sbom output is written ($OUT)"
check 1 "$(exists "$D/dist/sbom/bom.cdx.json")" "the SBOM sits under dist/sbom"
has "CycloneDX" "$(cat "$D/dist/sbom/bom.cdx.json")" "the file is a CycloneDX document"

pnpm_fixture args
stub "$D/stub" pnpm << 'EOS'
echo "$*" > "$PWD/args.txt"
cat "$BOM_FILE"
EOS
run "$D" "$D/stub:$PATH"
has "sbom --sbom-format cyclonedx --lockfile-only --prod" "$(cat "$D/args.txt")" "pnpm is called for the lockfile, production dependencies, CycloneDX"

pnpm_fixture sorted
stub "$D/stub" pnpm << 'EOS'
echo '{"bomFormat":"CycloneDX","components":[{"bom-ref":"pkg:npm/b@1"},{"bom-ref":"pkg:npm/a@1"}],"dependencies":[{"ref":"pkg:npm/b@1","dependsOn":["z","y"]},{"ref":"pkg:npm/a@1"}]}'
EOS
run "$D" "$D/stub:$PATH"
check 0 "$EC" "sorting accepts a document ($OUT)"
check '"bom-ref": "pkg:npm/a@1"' "$(grep -m1 '"bom-ref"' "$D/dist/sbom/bom.cdx.json" | sed 's/^ *//')" "components are sorted by reference"
check '"y",' "$(grep -A2 '"dependsOn"' "$D/dist/sbom/bom.cdx.json" | grep -m1 '"[yz]"' | sed 's/^ *//')" "dependsOn lists are sorted"

pnpm_fixture custom
OUT=$(cd "$D" && env -u CI SBOM_OUT=build/out/x.json PATH="$D/stub:$PATH" "$BASH_BIN" "$GATE" 2>&1)
check 1 "$(exists "$D/build/out/x.json")" "SBOM_OUT moves the output ($OUT)"

pnpm_fixture stale
stub "$D/stub" pnpm << 'EOS'
echo boom >&2
exit 1
EOS
mkdir -p "$D/dist/sbom"
echo old > "$D/dist/sbom/bom.cdx.json"
run "$D" "$D/stub:$PATH"
check 1 "$EC" "a failing pnpm sbom fails"
has "pnpm sbom failed: boom" "$OUT" "message carries the tool error"
check 0 "$([ -e "$D/dist/sbom/bom.cdx.json" ] && echo 1 || echo 0)" "a failed run leaves no stale SBOM"

pnpm_fixture junk
stub "$D/stub" pnpm << 'EOS'
echo '{"hello":"world"}'
EOS
run "$D" "$D/stub:$PATH"
check 1 "$EC" "JSON that is not CycloneDX fails"
has "no CycloneDX document" "$OUT" "message says no CycloneDX document"

pnpm_fixture notjson
stub "$D/stub" pnpm << 'EOS'
echo 'not a bom'
EOS
run "$D" "$D/stub:$PATH"
check 1 "$EC" "output that is not JSON fails"

pnpm_fixture empty
stub "$D/stub" pnpm << 'EOS'
true
EOS
run "$D" "$D/stub:$PATH"
check 1 "$EC" "empty output fails"

pnpm_fixture nolock
rm "$D/pnpm-lock.yaml"
run "$D" "$D/stub:$PATH"
check 1 "$EC" "a missing lockfile fails"
has "pnpm-lock.yaml is missing" "$OUT" "message names the lockfile"

D="$T/nostack"
mkdir -p "$D"
run "$D"
check 1 "$EC" "a folder with no stack file fails"

# py_fixture <name>: a Python project with a PATH folder $D/bin of only the tools the gate needs.
py_fixture() {
  D="$T/$1"
  mkdir -p "$D/bin"
  : > "$D/requirements.txt"
  for tool in dirname mkdir rm mv mktemp grep tr head cat wc; do ln -s "$(command -v "$tool")" "$D/bin/$tool"; done
}
# write_pipx <dir> <name>: a stub that records its arguments and writes the CycloneDX file named after -o.
write_pipx() {
  stub "$1/stub" "$2" << 'EOS'
echo "$*" > "$PWD/args.txt"
out=
while [ $# -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; fi
  shift
done
cat "$BOM_FILE" > "$out"
EOS
}
py_fixture py-good
write_pipx "$D" pipx
run "$D" "$D/stub:$PATH"
check 0 "$EC" "python control with pipx ($OUT)"
check 1 "$(exists "$D/dist/sbom/bom.cdx.json")" "python SBOM is written"
has "cyclonedx-bom==8.0.1" "$(cat "$D/args.txt")" "the generator is pinned exactly"
has "requirements requirements.txt" "$(cat "$D/args.txt")" "the generator reads requirements.txt"

py_fixture py-uvx
write_pipx "$D" uvx
run "$D" "$D/stub:$D/bin"
check 0 "$EC" "python control falls back to uvx ($OUT)"

py_fixture py-none
run "$D" "$D/bin"
check 1 "$EC" "python without pipx or uvx fails"
has "neither pipx nor uvx" "$OUT" "message says to install one"

py_fixture py-nolock
rm "$D/requirements.txt"
echo '[project]' > "$D/pyproject.toml"
write_pipx "$D" pipx
run "$D" "$D/stub:$PATH"
check 1 "$EC" "python without requirements.txt fails"
has "requirements.txt is missing" "$OUT" "message says to compile the lockfile"

in_ci=0
for v in "${CI:-}" "${TF_BUILD:-}" "${GITHUB_ACTIONS:-}"; do
  case "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" in "" | false | 0 | no) ;; *) in_ci=1 ;; esac
done
real_ok=1
for tool in pnpm uv; do
  command -v "$tool" > /dev/null 2>&1 || real_ok=0
done
# stable <file>: the file without the two documented per-run fields.
stable() { grep -vE '"(serialNumber|timestamp)"' "$1"; }
if [ "$real_ok" -eq 0 ]; then
  if [ "$in_ci" -eq 1 ]; then
    echo "seeded-sbom.test: FAIL pnpm or uv is not available in CI, so the real run did not happen." >&2
    FAIL=$((FAIL + 1))
  else
    echo "SKIPPED: pnpm or uv is not installed, so the real scaffold runs did NOT happen and the gate was NOT proven on a real project."
  fi
else
  D="$T/real-next"
  mkdir -p "$D"
  TC_STACK=nextjs TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "nextjs scaffold copies"
  (cd "$D" && pnpm install > "$T/next-install.log" 2>&1)
  check 0 $? "nextjs scaffold installs: $(tail -n 3 "$T/next-install.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real nextjs scaffold produces an SBOM ($OUT)"
  echo "real run nextjs: $OUT ($(wc -c < "$D/dist/sbom/bom.cdx.json" | tr -d ' ') bytes, $(grep -c '"purl"' "$D/dist/sbom/bom.cdx.json") components with a purl)"
  cp "$D/dist/sbom/bom.cdx.json" "$T/first.json"
  run "$D"
  check 0 "$EC" "a second real run succeeds"
  check "$(stable "$T/first.json" | cksum)" "$(stable "$D/dist/sbom/bom.cdx.json" | cksum)" "two nextjs runs agree apart from serialNumber and timestamp"

  D="$T/real-py"
  mkdir -p "$D"
  TC_STACK=fastapi TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "fastapi scaffold copies"
  printf 'fastapi\npydantic\nstructlog\nuvicorn\n' > "$D/requirements.in"
  (cd "$D" && uv pip compile requirements.in --universal --generate-hashes -o requirements.txt > "$T/py-compile.log" 2>&1)
  check 0 $? "fastapi requirements.txt compiles: $(tail -n 3 "$T/py-compile.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real fastapi scaffold produces an SBOM ($OUT)"
  echo "real run fastapi: $OUT ($(grep -c '"purl"' "$D/dist/sbom/bom.cdx.json") components with a purl)"
  cp "$D/dist/sbom/bom.cdx.json" "$T/first-py.json"
  run "$D"
  check "$(stable "$T/first-py.json" | cksum)" "$(stable "$D/dist/sbom/bom.cdx.json" | cksum)" "two fastapi runs agree apart from serialNumber and timestamp"
fi

echo "seeded-sbom.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
