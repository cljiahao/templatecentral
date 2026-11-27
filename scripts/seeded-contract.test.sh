#!/usr/bin/env bash
# scripts/seeded-contract.test.sh — the seeded check-contract gate: each rule blocks a bad change and a clean control passes.
# Small fixture projects hold a stub export entry point (tests/fixtures/contract/export-openapi.stub.py and .mjs) that prints a chosen document, so no framework is installed and no server runs.
# CPU time is measured with the shell's times builtin, never wall time. Every local-run case clears CI, GITHUB_ACTIONS and TF_BUILD; each CI case sets them.
# Usage: bash scripts/seeded-contract.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${GATE:-$REPO_ROOT/skills/scaffold/shared/template/scripts/check-contract.sh}"
FIX="$REPO_ROOT/tests/fixtures/contract"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-contract.XXXXXX") || exit 2
trap 'chmod -R u+rwx "$T" 2> /dev/null; rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test

# run <dir> [VAR=value ...]: sets OUT and EC from the gate run in a local (non-CI) shell, base ref main.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u GATE_BASE STUB_OUT="$FIX/openapi.json" "$@" bash "$GATE" main 2>&1)
  EC=$?
}
# runci <dir> [VAR=value ...]: the same with CI markers set.
runci() {
  run "$1" CI=true GITHUB_ACTIONS=true "${@:2}"
}

# new_app <name> <fastapi|nestjs> [subdir]: a repository with the stack file, the stub entry point and the committed contract on main, then a work branch; sets D and A (the app folder).
new_app() {
  D="$T/$1"
  A="$D/${3:-.}"
  mkdir -p "$A/scripts"
  git -C "$D" init -q -b main
  if [ "$2" = fastapi ]; then
    printf 'fastapi==0.115.0\n' > "$A/requirements.txt"
    cp "$FIX/export-openapi.stub.py" "$A/scripts/export-openapi.py"
  else
    printf '{"dependencies":{"@nestjs/core":"^11.0.0"}}\n' > "$A/package.json"
    cp "$FIX/export-openapi.stub.mjs" "$A/scripts/export-openapi.mjs"
  fi
  cp "$FIX/openapi.json" "$A/openapi.json"
  git -C "$D" add -A
  git -C "$D" commit -q -m base
  git -C "$D" checkout -q -b work
}

# --- controls, both stacks
for stack in fastapi nestjs; do
  new_app "ctl-$stack" "$stack"
  run "$D"
  check 0 "$EC" "$stack control: a matching contract passes ($OUT)"
  has "ok (1 contract(s) match the code)" "$OUT" "$stack control prints the ok line"
  runci "$D"
  check 0 "$EC" "$stack control passes in CI ($OUT)"
  run "$D" STUB_OUT="$FIX/openapi.reordered.json"
  check 0 "$EC" "$stack control: the same document in another key order and layout passes ($OUT)"
  run "$D" STUB_OUT="$FIX/openapi.changed.json"
  check 1 "$EC" "$stack: a different generated document fails"
  has '+      "post": {' "$OUT" "$stack: the diff shows the added route"
  if [ "$stack" = fastapi ]; then
    has "regenerate with: cd . && python3 -I scripts/export-openapi.py > openapi.json" "$OUT" "fastapi: the exact regenerate command is printed"
  else
    has "regenerate with: cd . && node scripts/export-openapi.mjs > openapi.json" "$OUT" "nestjs: the exact regenerate command is printed"
  fi
  run "$D" STUB_OUT="$FIX/openapi.changed.json" STUB_EXIT=0
  runci "$D" STUB_OUT="$FIX/openapi.changed.json"
  check 1 "$EC" "$stack: a mismatch fails in CI"
done

# --- diff is capped at 40 lines
new_app cap fastapi
python3 -I - "$T/big.json" << 'PY' || exit 2
import json, sys
paths = {"/p%d" % i: {"get": {"operationId": "op%d" % i, "responses": {"200": {"description": "ok"}}}} for i in range(120)}
json.dump({"openapi": "3.1.0", "info": {"title": "api", "version": "1"}, "paths": paths}, open(sys.argv[1], "w"))
PY
run "$D" STUB_OUT="$T/big.json"
check 1 "$EC" "a large difference fails"
n=$(printf '%s\n' "$OUT" | grep -c 'check-contract:   | ')
check 40 "$n" "the printed diff is capped at 40 lines"

# --- nothing checked
D="$T/plain"
mkdir -p "$D"
git -C "$D" init -q -b main
printf 'x\n' > "$D/x.txt"
git -C "$D" add -A
git -C "$D" commit -q -m base
run "$D"
check 0 "$EC" "a project with no app exits 0 ($OUT)"
has "nothing checked: no fastapi or nestjs app" "$OUT" "the nothing-checked line is distinct"
new_app none fastapi
rm "$A/openapi.json" "$A/scripts/export-openapi.py"
git -C "$D" add -A
git -C "$D" commit -q -m remove
run "$D"
check 0 "$EC" "an app with no contract and no entry point exits 0 ($OUT)"
has "nothing checked: the repository root (fastapi) has no committed openapi.json and no scripts/export-openapi.py" "$OUT" "the per-app nothing-checked line names the app"

# --- contract and entry point must come as a pair
new_app nogen fastapi
rm "$A/scripts/export-openapi.py"
run "$D"
check 1 "$EC" "a committed contract with no way to generate it fails ($OUT)"
has "cannot be generated from the code" "$OUT" "the no-generator failure says so"
new_app nocontract fastapi
rm "$A/openapi.json"
run "$D"
check 1 "$EC" "an entry point with no committed contract fails ($OUT)"
has "no openapi.json is committed" "$OUT" "the no-contract failure says so"
new_app wrongext nestjs
rm "$A/scripts/export-openapi.mjs"
printf 'console.log("{}")\n' > "$A/scripts/export.mjs"
run "$D"
check 1 "$EC" "an entry point under another name is not used ($OUT)"

# --- the generator is fixed by the stack
new_app fixedgen fastapi
mkdir -p "$A/.claude"
printf 'cat openapi.json\n' > "$A/.claude/contract-generator.txt"
printf '{"scripts":{"openapi":"cat openapi.json"}}\n' > "$A/package.json"
run "$D" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "a generator named in a project file is ignored ($OUT)"
new_app genchanged fastapi
printf '# changed\n' >> "$A/scripts/export-openapi.py"
run "$D"
check 0 "$EC" "a changed entry point alone passes with a notice ($OUT)"
has "notice: scripts/export-openapi.py changed in this diff" "$OUT" "a changed entry point is reported"
printf '\n' >> "$A/openapi.json"
run "$D"
check 1 "$EC" "a changed entry point and a changed contract in one diff fails ($OUT)"
has "both changed in this diff" "$OUT" "the pair failure says so"
new_app contractonly fastapi
cp "$FIX/openapi.changed.json" "$A/openapi.json"
run "$D"
check 1 "$EC" "a changed contract that no longer matches the code fails"
git -C "$D" commit -q -am "edit contract"
run "$D"
check 1 "$EC" "a committed contract edit that no longer matches still fails"

# --- committed contract faults
new_app bad fastapi
: > "$A/openapi.json"
run "$D"
check 1 "$EC" "an empty contract fails ($OUT)"
has "is empty" "$OUT" "the empty failure says so"
printf '{"openapi": "3.1.0", \n' > "$A/openapi.json"
run "$D"
check 1 "$EC" "a truncated contract fails ($OUT)"
has "is invalid" "$OUT" "the invalid failure says so"
printf '{}\n' > "$A/openapi.json"
run "$D"
check 1 "$EC" "a contract that is an empty object fails"
printf '[1]\n' > "$A/openapi.json"
run "$D"
check 1 "$EC" "a contract that is an array fails"
printf 'NaN\n' > "$A/openapi.json"
run "$D"
check 1 "$EC" "a contract that is NaN fails"
rm "$A/openapi.json"
cp "$FIX/openapi.json" "$A/real.json"
ln -s real.json "$A/openapi.json"
run "$D"
check 1 "$EC" "a symlink contract fails ($OUT)"
has "symlink" "$OUT" "the symlink failure says so"
rm "$A/openapi.json"
python3 -I - "$A/openapi.json" << 'PY' || exit 2
import json, sys
json.dump({"openapi": "3.1.0", "info": {"title": "x", "version": "1", "description": "a" * 5300000}}, open(sys.argv[1], "w"))
PY
run "$D"
check 1 "$EC" "a contract over 5 MB fails ($OUT)"
has "over the 5242880 limit" "$OUT" "the size failure says so"

# --- generator faults
new_app gen fastapi
: > "$T/empty.out"
run "$D" STUB_OUT="$T/empty.out"
check 1 "$EC" "a generator that exits 0 with empty output fails ($OUT)"
has "printed nothing" "$OUT" "the empty-output failure says so"
run "$D" STUB_EXIT=3 STUB_ERR=boom
check 1 "$EC" "a generator that exits non-zero fails ($OUT)"
has "exited 3: boom" "$OUT" "the exit failure shows the generator's error"
printf 'not json\n' > "$T/junk.out"
run "$D" STUB_OUT="$T/junk.out"
check 1 "$EC" "a generator that prints invalid JSON fails ($OUT)"
has "printed an invalid document" "$OUT" "the invalid-output failure says so"
run "$D" STUB_OUT="$T/nonexistent.out"
check 1 "$EC" "a generator that crashes fails"

# --- isolated python
mkdir "$T/evilpy"
printf 'raise ImportError("evil json")\n' > "$T/evilpy/json.py"
new_app iso fastapi
run "$D" PYTHONPATH="$T/evilpy"
check 0 "$EC" "python runs isolated: a PYTHONPATH module cannot replace json ($OUT)"

# --- missing interpreter
NOBIN="$T/nobin"
mkdir -p "$NOBIN"
for c in bash env git dirname mktemp grep sed cut tr sort mv cp cat rm head tail wc diff cmp basename; do
  p=$(command -v "$c") && ln -s "$p" "$NOBIN/$c"
done
for stack in fastapi nestjs; do
  new_app "nointerp-$stack" "$stack"
  OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$NOBIN" "$(command -v bash)" "$GATE" main 2>&1)
  check 1 "$?" "$stack: a missing interpreter fails ($OUT)"
  has "is not installed" "$OUT" "$stack: the missing interpreter line says so"
  OUT=$(cd "$D" && env CI=true PATH="$NOBIN" "$(command -v bash)" "$GATE" main 2>&1)
  check 1 "$?" "$stack: a missing interpreter fails in CI"
done

# --- app in a subfolder, gate run from a subfolder
new_app sub fastapi backend
run "$D" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "an app in backend/ is found and judged ($OUT)"
has "cd backend && python3 -I scripts/export-openapi.py > openapi.json" "$OUT" "the subfolder regenerate command names the folder"
TOP_OUT=$OUT
run "$D/backend/scripts" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "the gate run from a subfolder gives the same exit code"
check "$TOP_OUT" "$OUT" "the gate run from a subfolder prints the same result"
run "$D/backend/scripts"
check 0 "$EC" "control: the subfolder app passes from a subfolder ($OUT)"
new_app two nestjs apps/api
mkdir -p "$D/backend/scripts" "$D/frontend"
printf 'fastapi\n' > "$D/backend/requirements.txt"
cp "$FIX/export-openapi.stub.py" "$D/backend/scripts/export-openapi.py"
cp "$FIX/openapi.json" "$D/backend/openapi.json"
printf 'export default {};\n' > "$D/frontend/next.config.mjs"
git -C "$D" add -A
git -C "$D" commit -q -m more
git -C "$D" branch -f main HEAD
run "$D"
check 0 "$EC" "a frontend, a fastapi app and a nestjs app in one repository pass ($OUT)"
has "ok (2 contract(s) match the code)" "$OUT" "both backends are judged"
has "nothing checked: frontend is a frontend and the scaffold seeds no generated API types" "$OUT" "the frontend prints its own nothing-checked line"
run "$D" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "both backends fail on a mismatch"
n=$(printf '%s\n' "$OUT" | grep -c 'FAIL:')
check 2 "$n" "each backend reports its own failure"
mkdir -p "$D/both"
printf 'fastapi\n' > "$D/both/requirements.txt"
printf '{"dependencies":{"@nestjs/core":"1"}}\n' > "$D/both/package.json"
run "$D"
check 1 "$EC" "a folder with both stack files fails ($OUT)"
has "cannot be chosen" "$OUT" "the ambiguity failure says so"

new_app orphan fastapi
mkdir -p "$D/other"
cp "$FIX/openapi.json" "$D/other/openapi.json"
run "$D"
check 1 "$EC" "a committed contract in a folder with no stack or entry point fails ($OUT)"
has "no stack or entry point says how to generate it" "$OUT" "the orphan contract failure says so"

# --- attributes, names, base ref
new_app attr fastapi
printf '*.json -diff linguist-generated=true\n*.py binary\n' > "$D/.gitattributes"
printf 'src/ -diff\n' > "$D/.git/info/attributes"
run "$D" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "-diff, binary and linguist-generated lines do not hide a mismatch ($OUT)"
new_app magic fastapi ':(glob)app'
run "$D" STUB_OUT="$FIX/openapi.changed.json"
check 1 "$EC" "an app folder named like pathspec magic is judged ($OUT)"
has ":(glob)app" "$OUT" "the pathspec-named folder is named in the failure"
run "$D"
check 0 "$EC" "control: the pathspec-named folder passes when it matches ($OUT)"

new_app base fastapi
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD STUB_OUT="$FIX/openapi.json" bash "$GATE" no-such-ref 2>&1)
check 0 "$?" "an unresolved base passes the comparison locally ($OUT)"
has "changed-generator rule is skipped locally" "$OUT" "an unresolved base is reported locally"
OUT=$(cd "$D" && env CI=true STUB_OUT="$FIX/openapi.json" bash "$GATE" no-such-ref 2>&1)
check 2 "$?" "an unresolved base fails in CI"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD GATE_BASE=main STUB_OUT="$FIX/openapi.json" bash "$GATE" 2>&1)
check 0 "$?" "GATE_BASE names the base ($OUT)"
hasnt "skipped locally" "$OUT" "GATE_BASE resolves"

# --- hidden errors: unwritable TMPDIR
mkdir "$T/ro"
chmod 500 "$T/ro"
run "$D" TMPDIR="$T/ro"
check 2 "$EC" "an unwritable TMPDIR fails ($OUT)"
has "cannot create a temporary folder" "$OUT" "the TMPDIR failure says so"
runci "$D" TMPDIR="$T/ro"
check 2 "$EC" "an unwritable TMPDIR fails in CI"

# --- cpu time of the largest fixture: a 4 MB contract
new_app large nestjs
python3 -I - "$T/large.json" << 'PY' || exit 2
import json, sys
paths = {"/p%d" % i: {"get": {"operationId": "op%d" % i, "description": "d" * 300, "responses": {"200": {"description": "ok"}}}} for i in range(9000)}
json.dump({"openapi": "3.1.0", "info": {"title": "api", "version": "1"}, "paths": paths}, open(sys.argv[1], "w"))
PY
cp "$T/large.json" "$A/openapi.json"
git -C "$D" add -A
git -C "$D" commit -q -m large
times > "$T/t0"
run "$D" STUB_OUT="$T/large.json"
times > "$T/t1"
check 0 "$EC" "a 4 MB contract matches ($OUT)"
echo "cpu (user+sys, shell and children), $(wc -c < "$T/large.json" | tr -d ' ') byte contract: before [$(tr '\n' ' ' < "$T/t0")] after [$(tr '\n' ' ' < "$T/t1")]"

echo "seeded-contract: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
