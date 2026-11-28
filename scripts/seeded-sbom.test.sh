#!/usr/bin/env bash
# scripts/seeded-sbom.test.sh — the seeded generate-sbom gate: it writes a CycloneDX file, fails closed when it cannot, and never leaves a stale file.
# A stubbed pnpm and a fake Python environment read by the real metadata code cover every rule. The real run scaffolds all four stacks (fastapi from the exact seeded requirements.in), installs them
# (network to the public registries only, no key), generates real SBOMs twice and compares the runs apart from serialNumber and timestamp.
# A missing tool for the real run fails the test; ALLOW_SKIP_REAL=1 skips it with a SKIPPED: line.
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

hasnt() { # hasnt <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] is in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-sbom.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

BASH_BIN=$(command -v bash)
export BOM_FILE="$T/bom.json"
echo '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[{"bom-ref":"pkg:npm/a@1"}]}' > "$BOM_FILE"

# run <dir> [VAR=value ...]: sets OUT and EC from running the gate inside a fixture directory.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u VIRTUAL_ENV -u SBOM_OUT "$@" "$BASH_BIN" "$GATE" 2>&1)
  EC=$?
}
# stub <dir> <name>: an executable stub tool whose body is read from stdin.
stub() {
  mkdir -p "$1"
  rm -f "$1/$2"
  { echo '#!/bin/sh'; if [ "$2" = python ]; then echo 'case "$*" in *sys.base_prefix*) exit 0 ;; esac'; fi; cat; } > "$1/$2"
  chmod +x "$1/$2"
}
# exists <path>: 1 when the file exists and is not empty, else 0.
exists() { if [ -s "$1" ]; then echo 1; else echo 0; fi; }
# gone <path>: 1 when nothing is at the path, else 0.
gone() { if [ -e "$1" ]; then echo 0; else echo 1; fi; }

# pnpm_fixture <name>: a pnpm project whose stub pnpm prints a CycloneDX document; override the stub with stub "$D/stub" pnpm.
pnpm_fixture() {
  D="$T/$1"
  mkdir -p "$D"
  echo '{"dependencies":{"a":"1"}}' > "$D/package.json"
  echo "lockfileVersion: '9.0'" > "$D/pnpm-lock.yaml"
  stub "$D/stub" pnpm << 'EOS'
cat "$BOM_FILE"
EOS
}

pnpm_fixture good
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "control: pnpm sbom output is written ($OUT)"
check 1 "$(exists "$D/dist/sbom/bom.cdx.json")" "the SBOM sits under dist/sbom"
has "CycloneDX" "$(cat "$D/dist/sbom/bom.cdx.json")" "the file is a CycloneDX document"
has "(pnpm, CycloneDX)" "$OUT" "the output line names the kind"

pnpm_fixture args
stub "$D/stub" pnpm << 'EOS'
echo "$*" > "$PWD/args.txt"
cat "$BOM_FILE"
EOS
run "$D" PATH="$D/stub:$PATH"
has "sbom --sbom-format cyclonedx --lockfile-only" "$(cat "$D/args.txt")" "pnpm is called for the lockfile, CycloneDX"
hasnt "--prod" "$(cat "$D/args.txt")" "pnpm is asked for every dependency group, not production only"

pnpm_fixture sorted
stub "$D/stub" pnpm << 'EOS'
echo '{"bomFormat":"CycloneDX","components":[{"bom-ref":"pkg:npm/b@1"},{"bom-ref":"pkg:npm/a@1"}],"dependencies":[{"ref":"pkg:npm/b@1","dependsOn":["z","y"]},{"ref":"pkg:npm/a@1"}]}'
EOS
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "sorting accepts a document ($OUT)"
check '"bom-ref": "pkg:npm/a@1"' "$(grep -m1 '"bom-ref"' "$D/dist/sbom/bom.cdx.json" | sed 's/^ *//')" "components are sorted by reference"
check '"y",' "$(grep -A2 '"dependsOn"' "$D/dist/sbom/bom.cdx.json" | grep -m1 '"[yz]"' | sed 's/^ *//')" "dependsOn lists are sorted"

pnpm_fixture custom
run "$D" SBOM_OUT=build/out/x.json PATH="$D/stub:$PATH"
check 1 "$(exists "$D/build/out/x.json")" "SBOM_OUT moves the output ($OUT)"

pnpm_fixture stale
stub "$D/stub" pnpm << 'EOS'
echo boom >&2
exit 1
EOS
mkdir -p "$D/dist/sbom"
echo old > "$D/dist/sbom/bom.cdx.json"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a failing pnpm sbom cannot generate (exit 2)"
has "pnpm sbom failed: boom" "$OUT" "message carries the tool error"
check 1 "$(gone "$D/dist/sbom/bom.cdx.json")" "a failed run leaves no stale SBOM"

pnpm_fixture junk
stub "$D/stub" pnpm << 'EOS'
echo '{"hello":"world"}'
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "JSON that is not CycloneDX fails"
has "no CycloneDX document" "$OUT" "message says no CycloneDX document"

pnpm_fixture nocomponents
stub "$D/stub" pnpm << 'EOS'
echo '{"bomFormat":"CycloneDX"}'
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a document without a components array fails"
has "no components array" "$OUT" "message names the components array"

pnpm_fixture emptycomponents
stub "$D/stub" pnpm << 'EOS'
echo '{"bomFormat":"CycloneDX","components":[]}'
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "an empty components array fails when package.json lists dependencies"
has "lists 1 dependencies, but the SBOM has no components" "$OUT" "message names the mismatch"
echo '{}' > "$D/package.json"
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "an empty components array passes when package.json lists no dependencies ($OUT)"

pnpm_fixture notjson
stub "$D/stub" pnpm << 'EOS'
echo 'not a bom'
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "output that is not JSON fails"
has "did not write valid JSON" "$OUT" "message says the JSON is invalid"

pnpm_fixture empty
stub "$D/stub" pnpm << 'EOS'
true
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "empty output fails"

pnpm_fixture nolock
rm "$D/pnpm-lock.yaml"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a missing lockfile cannot generate (exit 2)"
has "pnpm-lock.yaml is missing" "$OUT" "message names the lockfile"

pnpm_fixture nonode
mkdir -p "$D/bin"
for tool in dirname mkdir rm mv mktemp grep tr head cat wc; do ln -s "$(command -v "$tool")" "$D/bin/$tool"; done
run "$D" PATH="$D/stub:$D/bin"
check 2 "$EC" "without node the gate cannot generate"
has "node is not installed" "$OUT" "message says to install node"

D="$T/nostack"
mkdir -p "$D"
run "$D"
check 2 "$EC" "a folder with no stack file cannot generate"

# env_fixture <name> <requirements text>: a Python project with a real empty venv (no global site-packages; the gate reads it with python -I, so PYTHONPATH cannot feed it); sets D and SITE.
# raw_env_fixture <name> <requirements text>: like env_fixture, with the lock text written as given.
# env_fixture <name> <requirements text>: the lock text gets a --hash continuation under each bare name==version line, as uv pip compile writes it.
env_fixture() {
  raw_env_fixture "$1" "$2"
  awk '/\\$/ { print; next } /^[A-Za-z0-9][A-Za-z0-9._-]*==/ { print $0 " \\"; print "    --hash=sha256:aa"; next } { print }' "$D/requirements.txt" > "$D/requirements.hashed" && mv "$D/requirements.hashed" "$D/requirements.txt"
}
raw_env_fixture() {
  D="$T/$1"
  mkdir -p "$D"
  python3 -m venv --without-pip "$D/.venv" > /dev/null 2>&1 || { FAIL=$((FAIL + 1)); echo "FAIL: cannot create a venv for $1"; }
  SITE=$(echo "$D"/.venv/lib/python*/site-packages)
  printf '%s' "$2" > "$D/requirements.txt"
}
# dist <name> <version> [header line ...]: a fake installed distribution in $SITE.
dist() {
  local name=$1 version=$2
  shift 2
  mkdir -p "$SITE/$name-$version.dist-info"
  { printf 'Metadata-Version: 2.4\nName: %s\nVersion: %s\n' "$name" "$version"; for h in "$@"; do printf '%s\n' "$h"; done; } > "$SITE/$name-$version.dist-info/METADATA"
}

env_fixture py-good 'alpha==1.0
beta==2.0
'
dist beta 2.0 'Requires-Dist: alpha'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 0 "$EC" "python control from installed metadata ($OUT)"
has "(python, CycloneDX)" "$OUT" "the output line names the kind"
J="$D/dist/sbom/bom.cdx.json"
has '"bomFormat": "CycloneDX"' "$(cat "$J")" "python SBOM is CycloneDX"
has '"purl": "pkg:pypi/alpha@1.0"' "$(cat "$J")" "components carry a purl"
has '"expression": "MIT"' "$(cat "$J")" "the licence expression is kept"
check 'pkg:pypi/alpha@1.0' "$(grep -A2 'pkg:pypi/beta@2.0"' "$J" | grep -m1 'alpha' | sed 's/^ *"//; s/".*//')" "dependencies come from Requires-Dist"
check '"bom-ref": "pkg:pypi/alpha@1.0",' "$(grep -m1 '"bom-ref"' "$J" | sed 's/^ *//')" "components are sorted"

env_fixture py-missing 'alpha==1.0
ghost==2.0
'
dist alpha 1.0
mkdir -p "$D/dist/sbom"
echo old > "$D/dist/sbom/bom.cdx.json"
run "$D"
check 1 "$EC" "a requirement that is not installed fails"
has "requirements.txt lists ghost, which is not installed" "$OUT" "message names the missing package"
check 1 "$(gone "$D/dist/sbom/bom.cdx.json")" "a failed Python run leaves no stale SBOM"

raw_env_fixture py-formfeed $'alpha==1.0 \\\n    --hash=sha256:aa\n# c\x0cghost==2.0 --hash=sha256:aa\n'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 1 "$EC" "a form feed in a lock comment is refused, not read as a line break"
has "requirements.txt line 3: byte 0x0c is not allowed" "$OUT" "message names the line and the byte"
raw_env_fixture py-coding $'# coding: utf-7 +AAo-ghost==2.0\nalpha==1.0 \\\n    --hash=sha256:aa\n'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 1 "$EC" "a coding comment in a lock is refused"
has "a coding comment makes pip decode" "$OUT" "message says why"
raw_env_fixture py-trailing $'alpha==1.0 # c \\\n    --hash=sha256:aa\n'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 1 "$EC" "a trailing comment before a continuation is refused"
has "a # is only allowed at the start of a line" "$OUT" "message says why"
raw_env_fixture py-envvar $'--find-links ${X}\nalpha==1.0 \\\n    --hash=sha256:aa\n'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 1 "$EC" "an environment variable in a lock is refused"
has "a \$ is only allowed in a full-line comment" "$OUT" "message says why"
raw_env_fixture py-bomcrlf $'\xef\xbb\xbfalpha==1.0 \\\r\n    --hash=sha256:aa\r\n'
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 0 "$EC" "control: a lock with a BOM and CRLF line endings generates ($OUT)"

env_fixture py-empty 'alpha==1.0
'
run "$D"
check 1 "$EC" "an environment with nothing installed fails"

env_fixture py-noenv 'alpha==1.0
'
dist alpha 1.0
rm -r "$D/.venv"
run "$D"
check 2 "$EC" "no project environment cannot generate, even when the global python3 has packages"
has "no project Python environment" "$OUT" "message says there is no environment"
has "Create the environment and install first" "$OUT" "message says how to fix it"

env_fixture py-pyproject ''
rm "$D/requirements.txt"
echo '[project]' > "$D/pyproject.toml"
dist alpha 1.0 'License-Expression: MIT'
run "$D"
check 0 "$EC" "a pyproject-only project lists everything installed ($OUT)"
has '"purl": "pkg:pypi/alpha@1.0"' "$(cat "$D/dist/sbom/bom.cdx.json")" "the pyproject-only SBOM lists the installed package"

env_fixture py-badjson 'alpha==1.0
'
dist alpha 1.0
stub "$D/.venv/bin" python << 'EOS'
if [ "$3" = check ]; then exec python3 "$@"; fi
out=
for a in "$@"; do out=$a; done
echo 'not json' > "$out"
EOS
run "$D"
check 1 "$EC" "a generator that writes invalid JSON does not pass"
has "not valid JSON" "$OUT" "message says the document is invalid"
hasnt_ok=$(printf '%s' "$OUT" | grep -c 'wrote ')
check 0 "$hasnt_ok" "no wrote line after invalid JSON"

# Exit codes of the helpers: 3 is a bad document (exit 1), any other failure is a crash that cannot generate (exit 2).
env_fixture py-crash 'alpha==1.0
'
dist alpha 1.0
stub "$D/.venv/bin" python << 'EOS'
exit 5
EOS
run "$D"
check 2 "$EC" "a Python helper that crashes cannot generate (exit 2, not a finding)"
has "cannot read the installed Python packages" "$OUT" "message says the helper crashed"
stub "$D/.venv/bin" python << 'EOS'
echo "bad document" >&2
exit 3
EOS
run "$D"
check 1 "$EC" "a Python helper that reports a bad document fails (exit 1)"

# A planted python must not pass for a virtual environment: a real venv is the control; a missing pyvenv.cfg, a failing probe or a non-executable file stop the gate (exit 2).
env_fixture py-realvenv 'alpha==1.0
'
dist alpha 1.0
run "$D"
check 0 "$EC" "a real venv passes the interpreter check ($OUT)"
env_fixture py-nocfg 'alpha==1.0
'
dist alpha 1.0
rm -f "$D/.venv/pyvenv.cfg"
run "$D"
check 2 "$EC" "a python without pyvenv.cfg beside bin/ is refused"
has "has no pyvenv.cfg" "$OUT" "message says pyvenv.cfg is missing"
env_fixture py-noprobe 'alpha==1.0
'
dist alpha 1.0
rm -f "$D/.venv/bin/python"
printf '#!/bin/sh\nexit 1\n' > "$D/.venv/bin/python"
chmod +x "$D/.venv/bin/python"
run "$D"
check 2 "$EC" "a python that is not a venv interpreter is refused although pyvenv.cfg exists"
has "does not run as a virtual environment interpreter" "$OUT" "message says the interpreter is not a venv"
env_fixture py-noexec 'alpha==1.0
'
dist alpha 1.0
rm -f "$D/.venv/bin/python"
printf '#!/bin/sh\nexit 0\n' > "$D/.venv/bin/python"
chmod -x "$D/.venv/bin/python"
run "$D"
check 2 "$EC" "a non-executable python is refused"
env_fixture py-dir 'alpha==1.0
'
dist alpha 1.0
rm -f "$D/.venv/bin/python"
mkdir "$D/.venv/bin/python"
run "$D"
check 2 "$EC" "a python that is a directory is refused"
has "is not a regular file" "$OUT" "message says bin/python is not a regular file"
pnpm_fixture node-crash
stub "$D/stub" node << 'EOS'
echo "node blew up" >&2
exit 5
EOS
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a node that crashes cannot generate (exit 2, not a finding)"
has "node could not read the SBOM" "$OUT" "message says node failed"
check 1 "$(gone "$D/dist/sbom/bom.cdx.json")" "a node crash leaves no SBOM"
stub "$D/stub" node << 'EOS'
echo "bad document" >&2
exit 3
EOS
run "$D" PATH="$D/stub:$PATH"
check 1 "$EC" "a node that reports a bad document fails (exit 1)"

# A distribution with no Name cannot be listed, so it fails instead of being skipped.
env_fixture py-nameless 'alpha==1.0
'
dist alpha 1.0 'License-Expression: MIT'
mkdir -p "$SITE/nameless-1.0.dist-info"
printf 'Metadata-Version: 2.4\nVersion: 1.0\n' > "$SITE/nameless-1.0.dist-info/METADATA"
run "$D"
check 1 "$EC" "a package with no Name fails the SBOM"
has "nameless-1.0.dist-info" "$OUT" "message names the dist-info folder"

# The licence fallback matches check-licences.sh: License-Expression, then License, then classifiers.
env_fixture py-lic 'a==1
b==1
c==1
d==1
'
dist a 1 'License-Expression: Apache-2.0'
dist b 1 'License: BSD-3-Clause'
dist c 1 'Classifier: License :: OSI Approved :: MIT License'
dist d 1
run "$D"
check 0 "$EC" "licence fallbacks generate ($OUT)"
J="$D/dist/sbom/bom.cdx.json"
has '"expression": "Apache-2.0"' "$(cat "$J")" "License-Expression becomes an expression"
has '"name": "BSD-3-Clause"' "$(cat "$J")" "the License field is the fallback"
has '"name": "MIT License"' "$(cat "$J")" "a classifier is the last fallback"
check 3 "$(grep -c '"licenses"' "$J")" "a package with no licence gets no licences entry"

# Both manifests: two files, neither skipped.
env_fixture both 'alpha==1.0
'
dist alpha 1.0 'License-Expression: MIT'
echo '{"dependencies":{"a":"1"}}' > "$D/package.json"
echo "lockfileVersion: '9.0'" > "$D/pnpm-lock.yaml"
stub "$D/stub" pnpm << 'EOS'
cat "$BOM_FILE"
EOS
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "python plus package.json both generate ($OUT)"
check 1 "$(exists "$D/dist/sbom/bom.cdx-pnpm.json")" "the pnpm file is written"
check 1 "$(exists "$D/dist/sbom/bom.cdx-python.json")" "the Python file is written"
check 1 "$(gone "$D/dist/sbom/bom.cdx.json")" "no single file when both manifests exist"
rm -r "$D/.venv"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "python plus package.json: a missing Python environment is not skipped"
check 1 "$(gone "$D/dist/sbom/bom.cdx-pnpm.json")" "a failed run leaves no half-written pnpm file"

# Project code must not run inside the gate: the helper is read with python -I, so a module named like a standard one next to it or in the working folder, PYTHONPATH and PYTHONSTARTUP have no effect.
# shadow_case <name> <folder under the project> <module>: a project holding a copy of the gate and helper, and a hostile <module>.py in <folder>.
shadow_case() {
  env_fixture "$1" 'okpkg==1.0
'
  dist okpkg 1.0 'License-Expression: MIT'
  mkdir -p "$D/scripts"
  cp "$GATE" "$D/scripts/generate-sbom.sh"
  cp "$(dirname "$GATE")/py-env.py" "$D/scripts/py-env.py"
  if [ -n "$3" ]; then printf 'print("PWNED")\nraise SystemExit(0)\n' > "$D/$2/$3.py"; fi
}
REALGATE=$GATE
shadow_run() { # shadow_run [VAR=value ...]: runs the project's own copy of the gate
  GATE="$D/scripts/generate-sbom.sh"
  run "$D" "$@"
  GATE=$REALGATE
}
shadow_case shadow-clean . ''
shadow_run
check 0 "$EC" "control: a project with no shadow module passes ($OUT)"
for mod in json uuid shlex re datetime; do
  shadow_case "shadow-s-$mod" scripts "$mod"
  shadow_run
  check 0 "$EC" "a $mod.py next to the helper does not run ($OUT)"
  hasnt "PWNED" "$OUT" "a $mod.py next to the helper printed nothing"
  shadow_case "shadow-c-$mod" . "$mod"
  shadow_run
  check 0 "$EC" "a $mod.py in the working folder does not run ($OUT)"
  hasnt "PWNED" "$OUT" "a $mod.py in the working folder printed nothing"
done
shadow_case shadow-env . ''
mkdir -p "$D/evil"
printf 'print("PWNED")\nraise SystemExit(0)\n' > "$D/evil/json.py"
printf 'print("PWNED")\nraise SystemExit(0)\n' > "$D/startup.py"
shadow_run PYTHONPATH="$D/evil" PYTHONSTARTUP="$D/startup.py"
check 0 "$EC" "PYTHONPATH and PYTHONSTARTUP do not run project code ($OUT)"
hasnt "PWNED" "$OUT" "PYTHONPATH and PYTHONSTARTUP printed nothing"

# A committed environment is not trusted: a tracked .venv (or a tracked VIRTUAL_ENV folder) is refused before anything is read from it, and a .pth planted in it never runs.
# tracked_case <name> <tracked path relative to the project>: a git project that tracks <path>.
tracked_case() {
  env_fixture "$1" 'okpkg==1.0
'
  dist okpkg 1.0 'License-Expression: MIT'
  SITE=$(echo "$D"/.venv/lib/python*/site-packages)
  if [ "$2" != package.json ]; then printf 'import os; print("PWNED")\n' > "$SITE/evil.pth"; fi
  (cd "$D" && git init -q . && git add -f "$2" > /dev/null 2>&1)
}
tracked_case tracked-clean package.json
run "$D" PATH="$D/stub:$PATH"
check 0 "$EC" "control: a git project with no tracked environment passes ($OUT)"
tracked_case tracked-venv .venv/pyvenv.cfg
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a tracked .venv is refused"
has "tracked by git" "$OUT" "message says the environment is tracked"
has ".venv/pyvenv.cfg" "$OUT" "message names the tracked path"
hasnt "PWNED" "$OUT" "a tracked .venv printed nothing"
tracked_case tracked-pth ".venv/${SITE#"$D"/.venv/}/evil.pth"
run "$D" PATH="$D/stub:$PATH"
check 2 "$EC" "a tracked .pth plant in the .venv is refused"
hasnt "PWNED" "$OUT" "the planted .pth never ran"
tracked_case tracked-venvx .venv/pyvenv.cfg
(cd "$D" && git rm -r -q --cached .venv && mv .venv venvx && git add -f venvx > /dev/null 2>&1)
run "$D" PATH="$D/stub:$PATH" VIRTUAL_ENV="$D/venvx"
check 2 "$EC" "a tracked VIRTUAL_ENV folder is refused"
has "tracked by git" "$OUT" "message says the VIRTUAL_ENV folder is tracked"

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
# stable <file>: the file without the two documented per-run fields.
stable() { grep -vE '"(serialNumber|timestamp)"' "$1"; }
if [ "$real_ok" -eq 1 ]; then
  D="$T/real-next"
  mkdir -p "$D"
  TC_STACK=nextjs TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "nextjs scaffold copies"
  (cd "$D" && pnpm install > "$T/next-install.log" 2>&1)
  check 0 $? "nextjs scaffold installs: $(tail -n 3 "$T/next-install.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real nextjs scaffold produces an SBOM ($OUT)"
  echo "real run nextjs: $OUT ($(wc -c < "$D/dist/sbom/bom.cdx.json" | tr -d ' ') bytes, $(grep -c '"purl"' "$D/dist/sbom/bom.cdx.json") components with a purl)"
  has "eslint-plugin-sonarjs" "$(cat "$D/dist/sbom/bom.cdx.json")" "real nextjs SBOM lists a devDependency, not production only"
  cp "$D/dist/sbom/bom.cdx.json" "$T/first.json"
  run "$D"
  check 0 "$EC" "a second real run succeeds"
  check "$(stable "$T/first.json" | cksum)" "$(stable "$D/dist/sbom/bom.cdx.json" | cksum)" "two nextjs runs agree apart from serialNumber and timestamp"

  for stack in vite-react nestjs; do
    D="$T/real-$stack"
    mkdir -p "$D"
    TC_STACK=$stack TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
    check 0 $? "$stack scaffold copies"
    (cd "$D" && env -u CI pnpm install > "$T/$stack-install.log" 2>&1)
    check 0 $? "$stack scaffold installs: $(tail -n 3 "$T/$stack-install.log" | tr '\n' ' ')"
    run "$D"
    check 0 "$EC" "real $stack scaffold produces an SBOM ($OUT)"
    echo "real run $stack: $OUT ($(grep -c '"purl"' "$D/dist/sbom/bom.cdx.json") components with a purl)"
    has "eslint-plugin-sonarjs" "$(cat "$D/dist/sbom/bom.cdx.json")" "real $stack SBOM lists a devDependency, not production only"
  done

  D="$T/real-py"
  mkdir -p "$D"
  TC_STACK=fastapi TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
  check 0 $? "fastapi scaffold copies"
  # The exact requirements.in the scaffold writes, read from its source file so the two cannot drift.
  awk '/^cat > requirements.in <<.REQ.$/ { on = 1; next } /^REQ$/ { on = 0 } on' "$SH/../fastapi/source-files.md" > "$D/requirements.in"
  check 1 "$(grep -c '^certifi' "$D/requirements.in")" "the seeded requirements.in was extracted"
  sed -n '/^cat > requirements.in <<.REQ.$/,/^REQ$/p' "$SH/../fastapi/source-files.md" | sed '1d;$d' > "$T/req-expected.in"
  check 0 "$(cmp -s "$T/req-expected.in" "$D/requirements.in"; echo $?)" "the extracted requirements.in equals the seeded block"
  check 1 "$([ -s "$D/requirements.in" ] && echo 1)" "the extracted requirements.in is not empty"
  (cd "$D" && uv pip compile requirements.in --universal --generate-hashes -o requirements.txt > "$T/py-compile.log" 2>&1)
  check 0 $? "fastapi requirements.txt compiles: $(tail -n 3 "$T/py-compile.log" | tr '\n' ' ')"
  run "$D"
  check 2 "$EC" "real fastapi project without an environment cannot generate"
  has "no project Python environment" "$OUT" "real failure says to create the environment"
  (cd "$D" && uv venv .venv > /dev/null 2>&1 && uv pip install --python .venv/bin/python --require-hashes -r requirements.txt > "$T/py-install.log" 2>&1)
  check 0 $? "fastapi scaffold installs: $(tail -n 3 "$T/py-install.log" | tr '\n' ' ')"
  run "$D"
  check 0 "$EC" "real fastapi scaffold produces an SBOM ($OUT)"
  echo "real run fastapi: $OUT ($(grep -c '"purl"' "$D/dist/sbom/bom.cdx.json") components with a purl)"
  cp "$D/dist/sbom/bom.cdx.json" "$T/first-py.json"
  run "$D"
  check "$(stable "$T/first-py.json" | cksum)" "$(stable "$D/dist/sbom/bom.cdx.json" | cksum)" "two fastapi runs agree apart from serialNumber and timestamp"
fi

echo "seeded-sbom.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
