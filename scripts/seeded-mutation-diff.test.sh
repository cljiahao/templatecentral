#!/usr/bin/env bash
# scripts/seeded-mutation-diff.test.sh — the seeded check-mutation-diff gate: each rule blocks a bad change and a clean control passes.
# The tests run stub tools (tests/fixtures/mutation-diff/bin) whose output copies the structure of two real runs, saved under tests/fixtures/mutation-diff/real:
# StrykerJS 10.1.1 (@stryker-mutator/core and vitest-runner 10.1.1, vitest 5.1.2; json reporter, schemaVersion "1.0") and mutmut 3.8.1 (pytest 9.2.0, python 3.14; `mutmut results --all true` and `mutmut show`).
# Each ran on a three-file toy project with the seeded config. The real-format cases at the end feed those saved files to the gate unchanged.
# CPU time is measured with the shell's times builtin, never wall time. Every local-run case clears CI, GITHUB_ACTIONS and TF_BUILD; each CI case sets them.
# Usage: bash scripts/seeded-mutation-diff.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${GATE:-$REPO_ROOT/skills/scaffold/shared/template/scripts/check-mutation-diff.sh}"
FIX="$REPO_ROOT/tests/fixtures/mutation-diff"
SEEDED_CFG="$REPO_ROOT/skills/add/mutation-testing/typescript/template/stryker.config.mjs"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-mut.XXXXXX") || exit 2
trap 'chmod -R u+rwx "$T" 2> /dev/null; rm -rf "$T"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test

# A python3 that has tomllib (3.11 or newer): the first of these on PATH.
PYBIN="$T/pybin"
mkdir -p "$PYBIN"
for cand in python3.15 python3.14 python3.13 python3.12 python3.11 python3; do
  p=$(command -v "$cand" 2> /dev/null) || continue
  if "$p" -c 'import tomllib' 2> /dev/null; then ln -s "$p" "$PYBIN/python3"; break; fi
done
[ -e "$PYBIN/python3" ] || { echo "FAIL: no python3 3.11 or newer on PATH for the mutmut cases"; exit 2; }

# run <dir> [VAR=value ...]: sets OUT and EC from the gate run in a local (non-CI) shell, base ref main, stub tools on PATH.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u GATE_BASE -u MUTATION_DIFF_CPU_SECONDS PATH="$FIX/bin:$PYBIN:$PATH" "$@" bash "$GATE" main 2>&1)
  EC=$?
}
# runci <dir> [VAR=value ...]: the same with CI markers set.
runci() {
  run "$1" CI=true GITHUB_ACTIONS=true "${@:2}"
}

# stryker_cfg <break> [extra mutate entry]: writes the seeded config, with thresholds.break and one extra mutate entry changed.
stryker_cfg() {
  sed -e "s/thresholds: { break: null }/thresholds: { break: $1 }/" -e "s|\"!src/\*\*/\*.test.tsx\"\]|\"!src/**/*.test.tsx\"${2:+, \"$2\"}]|" "$SEEDED_CFG" > "$D/${3:-.}/stryker.config.mjs"
}

# new_repo <name> [subdir]: a git repository with the seeded Stryker config, src/a.ts and a test, committed on main; sets D. The app sits in <subdir> when given.
new_repo() {
  D="$T/$1"
  local sub=${2:-.}
  mkdir -p "$D/$sub/src"
  git -C "$D" init -q -b main
  stryker_cfg null "" "$sub"
  printf 'export function a(x: number): boolean {\n  return x > 0;\n}\n' > "$D/$sub/src/a.ts"
  printf 'import { a } from "./a";\n' > "$D/$sub/src/a.test.ts"
  printf 'readme\n' > "$D/README.md"
  git -C "$D" add -A
  git -C "$D" commit -q -m base
  git -C "$D" checkout -q -b work
}
# touch_src <path>: changes a source file so it shows in the diff.
touch_src() {
  printf '// changed\n' >> "$D/$1"
}

# --- controls and the survivor rule
new_repo ctl
touch_src src/a.ts
run "$D"
check 0 "$EC" "control: a changed file whose mutants are all killed passes ($OUT)"
has "ok (1 changed source files mutated" "$OUT" "control prints the ok line"
runci "$D"
check 0 "$EC" "control in CI passes ($OUT)"

ARGS="$T/args.log"
: > "$ARGS"
run "$D" STUB_ARGS_LOG="$ARGS"
hasnt "thresholds" "$(cat "$ARGS")" "the gate passes no threshold to the tool"
has "--mutate src/a.ts" "$(cat "$ARGS")" "the tool is told to mutate only the changed file"
hasnt "src/a.test.ts" "$(cat "$ARGS")" "the unchanged test file is not mutated"

run "$D" STUB_STATUS=Survived
check 1 "$EC" "a surviving mutant fails"
has "src/a.ts line 3, mutator EqualityOperator (Survived)" "$OUT" "the survivor message names file, line and mutator"
run "$D" STUB_STATUS=NoCoverage
check 1 "$EC" "an uncovered mutant fails"
has "NoCoverage" "$OUT" "the uncovered message names its status"
run "$D" STUB_EXIT=1
check 1 "$EC" "the tool failing its own threshold with no survivor listed fails"
has "exited 1 with no survivor listed" "$OUT" "the threshold failure says so"

# --- nothing to judge
new_repo none
printf 'more\n' >> "$D/README.md"
run "$D"
check 0 "$EC" "no changed source file exits 0 ($OUT)"
has "nothing checked: no changed source file in mutation scope" "$OUT" "the nothing-checked line is distinct"
runci "$D"
check 0 "$EC" "no changed source file exits 0 in CI"
touch_src src/a.test.ts
run "$D"
has "nothing checked" "$OUT" "a changed test file the config excludes is not judged"

# --- not set up, tool missing
D="$T/noconfig"
mkdir -p "$D"
git -C "$D" init -q -b main
printf 'x\n' > "$D/x.txt"
git -C "$D" add -A
git -C "$D" commit -q -m base
run "$D"
check 0 "$EC" "no mutation config exits 0 ($OUT)"
has "not set up" "$OUT" "the not-set-up line is printed"
has "templatecentral:add mutation-testing" "$OUT" "the not-set-up line says how to add it"
runci "$D"
check 0 "$EC" "no mutation config exits 0 in CI"

new_repo notool
touch_src src/a.ts
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
EC=$?
check 0 "$EC" "a config with the tool missing exits 0 locally ($OUT)"
has "not set up" "$OUT" "tool missing locally prints the not-set-up line"
OUT=$(cd "$D" && env CI=true GITHUB_ACTIONS=true PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
EC=$?
check 1 "$EC" "a config with the tool missing fails in CI"
has "the tool is not installed" "$OUT" "tool missing in CI says so"
OUT=$(cd "$D" && env -u GITHUB_ACTIONS -u TF_BUILD CI=1 PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
check 1 "$?" "CI alone marks a CI run"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS TF_BUILD=True PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
check 1 "$?" "TF_BUILD alone marks a CI run"

# --- base ref
new_repo nobase
touch_src src/a.ts
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$FIX/bin:$PYBIN:$PATH" bash "$GATE" no-such-ref 2>&1)
check 0 "$?" "an unresolved base exits 0 locally ($OUT)"
has "nothing checked: base ref 'no-such-ref' not found" "$OUT" "an unresolved base prints a nothing-checked line"
OUT=$(cd "$D" && env CI=true PATH="$FIX/bin:$PYBIN:$PATH" bash "$GATE" no-such-ref 2>&1)
check 2 "$?" "an unresolved base fails in CI"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD GATE_BASE=main PATH="$FIX/bin:$PYBIN:$PATH" bash "$GATE" 2>&1)
check 0 "$?" "GATE_BASE names the base ($OUT)"
has "against main" "$OUT" "GATE_BASE is the base used"

# --- cpu cap
run "$D" STUB_SPIN=1 MUTATION_DIFF_CPU_SECONDS=1
check 1 "$EC" "a run the cpu cap ends fails ($OUT)"
has "used more than 1 CPU seconds" "$OUT" "the cap failure has its own message"
runci "$D" MUTATION_DIFF_CPU_SECONDS=100000
check 2 "$EC" "a cap above the default is refused in CI"
run "$D" MUTATION_DIFF_CPU_SECONDS=abc
check 2 "$EC" "a bad cap is refused"

# --- report faults
for mode in empty truncated malformed nofiles; do
  case "$mode" in
    empty) : > "$T/raw.json" ;;
    truncated) printf '{"schemaVersion":"1","files":{"src/a.ts":{"mutants":[{"id":"0","mut' > "$T/raw.json" ;;
    malformed) printf 'not json at all\n' > "$T/raw.json" ;;
    nofiles) printf '{"schemaVersion":"1"}\n' > "$T/raw.json" ;;
  esac
  run "$D" STUB_RAW="$T/raw.json"
  check 1 "$EC" "a $mode report fails ($OUT)"
  case "$mode" in
    empty) has "wrote no report" "$OUT" "an empty report is named" ;;
    truncated | malformed) has "is not valid JSON" "$OUT" "a $mode report is named" ;;
    nofiles) has "no schemaVersion or files object" "$OUT" "a report without files is named" ;;
  esac
done
printf '{"schemaVersion":"1","files":{"src/a.ts":{"mutants":[{"id":"0","status":"Killed"}]}}}\n' > "$T/raw.json"
run "$D" STUB_RAW="$T/raw.json"
check 1 "$EC" "a mutant with no mutator or line fails"
run "$D" STUB_OMIT=1
check 1 "$EC" "a report without the judged file fails"
has "is not in the mutation report" "$OUT" "the missing-file failure says so"
run "$D" STUB_COUNT=0
check 1 "$EC" "a report with no mutant for a file with code fails"
has "was not mutated" "$OUT" "the zero-mutant failure says so"
run "$D" STUB_STATUS=Ignored
check 1 "$EC" "a report where every mutant is ignored fails"
printf 'export type A = { b: number };\nexport interface C {\n  d: string;\n}\n' > "$D/src/a.ts"
run "$D" STUB_COUNT=0
check 0 "$EC" "control: a type-only file with no mutant passes ($OUT)"
printf 'export const K = 5;\n' > "$D/src/a.ts"
run "$D" STUB_COUNT=0
check 0 "$EC" "control: a constant-only file with no mutant passes ($OUT)"

# --- config tampering in the same change
new_repo excl
stryker_cfg null '!src/a.ts'
touch_src src/a.ts
run "$D"
check 1 "$EC" "a new mutate exclude in the same change fails ($OUT)"
has "gained an exclude" "$OUT" "the exclude failure says so"
has '!src/a.ts' "$OUT" "the exclude failure names the exclude"

new_repo narrow
sed -i.bak 's|"src/\*\*/\*.tsx", ||' "$D/stryker.config.mjs"
rm -f "$D/stryker.config.mjs.bak"
touch_src src/a.ts
run "$D"
check 1 "$EC" "a removed mutate entry fails ($OUT)"
has "mutate entry removed" "$OUT" "the removed entry failure says so"

new_repo thr
git -C "$D" checkout -q main
stryker_cfg 70 ""
git -C "$D" commit -q -am setbreak
git -C "$D" checkout -q -b thr2
stryker_cfg 50 ""
touch_src src/a.ts
run "$D"
check 1 "$EC" "a lowered threshold in the same change fails ($OUT)"
has "thresholds.break went from 70 to 50" "$OUT" "the threshold failure names both values"
stryker_cfg null ""
run "$D"
check 1 "$EC" "a removed threshold in the same change fails"
stryker_cfg 80 ""
run "$D"
check 0 "$EC" "control: a raised threshold passes ($OUT)"

new_repo disable
printf '// Stryker disable all\n' >> "$D/src/a.ts"
run "$D"
check 1 "$EC" "a new Stryker disable comment fails ($OUT)"
has "Stryker disable" "$OUT" "the disable failure says so"

new_repo delcfg
git -C "$D" rm -q -f stryker.config.mjs
touch_src src/a.ts
run "$D"
check 1 "$EC" "a deleted mutation config fails ($OUT)"
has "gone" "$OUT" "the deleted config failure says so"

# --- app in a subfolder, gate run from a subfolder
new_repo sub backend
touch_src backend/src/a.ts
run "$D" STUB_STATUS=Survived
check 1 "$EC" "an app in backend/ is found and judged ($OUT)"
has "backend/src/a.ts line 3" "$OUT" "the subfolder survivor names the full path"
SUB_ROOT=$OUT
run "$D/backend/src" STUB_STATUS=Survived
check 1 "$EC" "the gate run from a subfolder judges the same file"
check "$SUB_ROOT" "$OUT" "the gate run from a subfolder prints the same result"
STUB_STATUS=Killed run "$D/backend/src"
check 0 "$EC" "control: the subfolder app with all mutants killed passes ($OUT)"
new_repo sub2 backend
mkdir -p "$D/frontend/src"
cp "$D/backend/stryker.config.mjs" "$D/frontend/stryker.config.mjs"
printf 'export const F = (x: number) => x > 1;\n' > "$D/frontend/src/f.ts"
git -C "$D" add -A
git -C "$D" commit -q -m front
touch_src frontend/src/f.ts
touch_src backend/src/a.ts
: > "$ARGS"
run "$D" STUB_ARGS_LOG="$ARGS"
check 0 "$EC" "two apps in one repository are both judged ($OUT)"
check 2 "$(wc -l < "$ARGS" | tr -d ' ')" "the tool runs once per app"

# --- attributes and file names
# Regression guards for a later switch to per-file diffs: today file lists come from --name-only, which no attribute or pathspec line can change.
new_repo attr
printf 'src/a.ts -diff\n*.ts binary\nsrc/** linguist-generated=true\n' > "$D/.gitattributes"
touch_src src/a.ts
run "$D" STUB_STATUS=Survived
check 1 "$EC" "-diff, binary and linguist-generated lines do not hide a changed file ($OUT)"
has "src/a.ts line 3" "$OUT" "the attribute probe names the file"
printf 'x\n' > "$D/.git/info/attributes"
printf 'src/a.ts -diff\n' > "$D/.git/info/attributes"
run "$D" STUB_STATUS=Survived
check 1 "$EC" "a local info/attributes line does not hide a changed file"

new_repo names
printf 'export const Z = (x: number) => x > 1;\n' > "$D/src/:name.ts"
printf 'export const Y = (x: number) => x > 1;\n' > "$D/src/:(glob)x.ts"
printf 'export const W = (x: number) => x > 1;\n' > "$D/src/[id].ts"
run "$D"
check 1 "$EC" "files named like pathspec magic or globs are not hidden ($OUT)"
has "src/:name.ts" "$OUT" "the :name file is named"
has "src/:(glob)x.ts" "$OUT" "the :(glob)x file is named"
has "src/[id].ts" "$OUT" "the glob-character file is named"

# --- hidden errors: unwritable TMPDIR, missing interpreter
new_repo tmpd
touch_src src/a.ts
mkdir "$T/ro"
chmod 500 "$T/ro"
run "$D" TMPDIR="$T/ro"
check 2 "$EC" "an unwritable TMPDIR fails ($OUT)"
has "cannot create a temporary folder" "$OUT" "the TMPDIR failure says so"
runci "$D" TMPDIR="$T/ro"
check 2 "$EC" "an unwritable TMPDIR fails in CI"

# A PATH with the tools the gate needs and no node.
NONODE="$T/nonode"
mkdir -p "$NONODE"
for c in bash env git dirname mktemp grep sed cut tr sort mv cp cat rm head tail wc awk tee basename sleep; do
  p=$(command -v "$c") && ln -s "$p" "$NONODE/$c"
done
ln -s "$FIX/bin/stryker" "$NONODE/stryker"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$NONODE" "$(command -v bash)" "$GATE" main 2>&1)
check 1 "$?" "a missing node fails ($OUT)"
has "node is not installed" "$OUT" "the missing node line says so"
OUT=$(cd "$D" && env CI=true PATH="$NONODE" "$(command -v bash)" "$GATE" main 2>&1)
check 1 "$?" "a missing node fails in CI"

# --- committed change, not only the working tree
new_repo committed
touch_src src/a.ts
git -C "$D" commit -q -am change
run "$D" STUB_STATUS=Survived
check 1 "$EC" "a committed change is judged ($OUT)"
new_repo untracked
printf 'export const U = (x: number) => x > 1;\n' > "$D/src/new.ts"
run "$D" STUB_STATUS=Survived
check 1 "$EC" "an untracked source file is judged ($OUT)"

# --- real saved reports
new_repo realts
touch_src src/a.ts
printf 'export const b = 1;\n' > "$D/src/b.ts"
printf 'export const c = 1;\n' > "$D/src/c.ts"
run "$D" STUB_RAW="$FIX/real/stryker-10.1.1.report.json"
check 1 "$EC" "the real Stryker 10.1.1 report with survivors fails ($OUT)"
has "src/b.ts line 2, mutator EqualityOperator (Survived)" "$OUT" "the real report names the survivor in b.ts"
has "src/c.ts line 1, mutator BlockStatement (NoCoverage)" "$OUT" "the real report names the uncovered mutant in c.ts"
hasnt "src/a.ts line" "$OUT" "the real report's killed file a.ts is not named"

# --- mutmut (fastapi)
# new_py <name>: a repository with the seeded mutmut table and src/app.py, committed on main; sets D.
new_py() {
  D="$T/$1"
  mkdir -p "$D/src" "$D/test"
  git -C "$D" init -q -b main
  printf '[tool.mutmut]\nsource_paths = ["src/"]\npytest_add_cli_args_test_selection = ["test/"]\n' > "$D/pyproject.toml"
  printf 'def handler(x):\n    y = x\n    return y > 0\n' > "$D/src/app.py"
  printf 'def test_x():\n    pass\n' > "$D/test/test_app.py"
  git -C "$D" add -A
  git -C "$D" commit -q -m base
  git -C "$D" checkout -q -b work
  printf '# changed\n' >> "$D/src/app.py"
}
new_py py1
printf 'def clamp(n, mx):\n    return n\n' > "$D/src/b.py"
printf 'def untested(a):\n    return a\n' > "$D/src/c.py"
printf 'def is_positive(n):\n    return n > 0\n' > "$D/src/a.py"
run "$D" STUB_RESULTS="$FIX/real/mutmut-3.8.1.results.txt" STUB_SHOW="$FIX/real/mutmut-3.8.1.show.txt"
check 1 "$EC" "the real mutmut 3.8.1 results with survivors fail ($OUT)"
has "b.x_clamp__mutmut_1 (survived) in src/b.py line 2, changed source if n > mx: -> if n >= mx:" "$OUT" "the real results name the survivor in b.py"
has "c.x_untested__mutmut_1 (no tests) in src/c.py" "$OUT" "the real results name the uncovered mutant in c.py"
hasnt "a.x_is_positive" "$OUT" "the real results' killed module a is not named"
rm -f "$D/src/b.py" "$D/src/c.py" "$D/src/a.py"
run "$D" STUB_MODULES=app
check 0 "$EC" "mutmut control: all mutants killed passes ($OUT)"
: > "$ARGS"
run "$D" STUB_MODULES=app STUB_ARGS_LOG="$ARGS"
has "run app*" "$(cat "$ARGS")" "mutmut is run on the changed module only"
run "$D" STUB_MODULES=app STUB_UNJUDGED="other core.logging"
check 0 "$EC" "mutmut control: a mutant of a module the change did not touch is not judged ($OUT)"
hasnt "other" "$OUT" "an unchanged module's mutant is not named"
run "$D" STUB_MODULES=app STUB_STATUS=survived
check 1 "$EC" "a surviving mutmut mutant fails ($OUT)"
has "app.x_handler__mutmut_1 (survived) in src/app.py line 3, changed source return y > 0 -> return y >= 0" "$OUT" "the mutmut survivor names file, line and the changed source"
run "$D" STUB_MODULES=app STUB_STATUS="no tests"
check 1 "$EC" "a mutmut mutant with no tests fails"
run "$D" STUB_MODULES=app STUB_COUNT=0
check 1 "$EC" "mutmut listing no mutant for a file with code fails"
has "was not mutated" "$OUT" "the zero-mutant failure says so"
run "$D" STUB_MODULES=app STUB_EXIT=1
check 1 "$EC" "mutmut run failing fails"
run "$D" STUB_MODULES=app STUB_SPIN=1 MUTATION_DIFF_CPU_SECONDS=1
check 1 "$EC" "mutmut cpu cap fails ($OUT)"
has "used more than 1 CPU seconds" "$OUT" "the mutmut cap failure has its own message"
printf 'import os\n"""doc"""\n' > "$D/src/app.py"
run "$D" STUB_MODULES=app STUB_COUNT=0
check 0 "$EC" "mutmut control: an imports-and-docstring file with no mutant passes ($OUT)"

mkdir "$T/evilpy"
printf 'raise ImportError("evil tomllib")\n' > "$T/evilpy/tomllib.py"
run "$D" STUB_MODULES=app PYTHONPATH="$T/evilpy"
check 0 "$EC" "python runs isolated: a PYTHONPATH module cannot replace tomllib ($OUT)"

new_py py2
printf 'do_not_mutate = ["src/app.py"]\n' >> "$D/pyproject.toml"
run "$D" STUB_MODULES=app
check 1 "$EC" "a new do_not_mutate entry in the same change fails ($OUT)"
has "do_not_mutate gained an entry" "$OUT" "the do_not_mutate failure says so"
new_py py3
printf '[tool.mutmut]\nsource_paths = ["lib/"]\n' > "$D/pyproject.toml"
run "$D" STUB_MODULES=app
check 1 "$EC" "a removed source_paths entry fails ($OUT)"
new_py py4
printf 'x = 1  # pragma: no mutate\n' >> "$D/src/app.py"
run "$D" STUB_MODULES=app
check 1 "$EC" "a new pragma: no mutate comment fails ($OUT)"
new_py py5
printf '[project]\nname = "x"\n' > "$D/pyproject.toml"
run "$D" STUB_MODULES=app
check 1 "$EC" "a removed [tool.mutmut] table fails ($OUT)"
new_py py6
D="$T/py6"
OUT=$(cd "$D" && env CI=true PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
check 1 "$?" "mutmut missing fails in CI ($OUT)"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$PYBIN:$PATH" bash "$GATE" main 2>&1)
check 0 "$?" "mutmut missing exits 0 locally ($OUT)"
has "not set up" "$OUT" "mutmut missing locally prints the not-set-up line"
new_py py7
mkdir -p "$D/backend"
git -C "$D" mv pyproject.toml backend/pyproject.toml
git -C "$D" mv src backend/src
git -C "$D" mv test backend/test
git -C "$D" commit -q -m move
printf '# again\n' >> "$D/backend/src/app.py"
run "$D" STUB_MODULES=app STUB_STATUS=survived
check 1 "$EC" "a fastapi app in backend/ is found and judged ($OUT)"
has "backend/src/app.py" "$OUT" "the backend survivor names the full path"
new_py py8
OLDPY=$PYBIN
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD PATH="$NONODE:$FIX/bin" STUB_MODULES=app "$(command -v bash)" "$GATE" main 2>&1)
check 1 "$?" "a missing python3 fails ($OUT)"
has "python3 is not installed" "$OUT" "the missing python3 line says so"
PYBIN=$OLDPY

# --- cpu time of the largest fixture: many changed files in one app
new_repo big
i=0
while [ "$i" -lt 150 ]; do
  printf 'export const f%s = (x: number) => x > %s;\n' "$i" "$i" > "$D/src/f$i.ts"
  i=$((i + 1))
done
git -C "$D" add -A
git -C "$D" commit -q -m many
i=0
while [ "$i" -lt 150 ]; do
  printf '// c\n' >> "$D/src/f$i.ts"
  i=$((i + 1))
done
times > "$T/t0"
run "$D"
times > "$T/t1"
check 0 "$EC" "150 changed files in one app pass ($OUT)"
echo "cpu (user+sys, shell and children), 150 changed files: before [$(tr '\n' ' ' < "$T/t0")] after [$(tr '\n' ' ' < "$T/t1")]"

echo "seeded-mutation-diff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
