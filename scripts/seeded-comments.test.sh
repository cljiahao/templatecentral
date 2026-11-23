#!/usr/bin/env bash
# scripts/seeded-comments.test.sh — tests for the seeded scripts/check-comments.sh (and its node and python readers).
# Needs the typescript package: set TC_TEST_TYPESCRIPT_DIR to a typescript package folder, or install it globally (npm i -g typescript).
# Usage: bash scripts/seeded-comments.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"
GATE="$SHARED/template/scripts/check-comments.sh"
FIX="$REPO_ROOT/tests/fixtures/seeded-comments"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/sc.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

TSPKG=${TC_TEST_TYPESCRIPT_DIR:-}
if [[ -z "$TSPKG" ]] && command -v npm > /dev/null 2>&1; then
  TSPKG=$(npm root -g 2> /dev/null)/typescript
fi
if [[ ! -f "$TSPKG/package.json" ]]; then
  echo "seeded-comments.test: no typescript package found. Fix: set TC_TEST_TYPESCRIPT_DIR to a typescript package folder, or run npm i -g typescript." >&2
  exit 2
fi
mkdir -p "$T/tsroot/node_modules"
ln -s "$TSPKG" "$T/tsroot/node_modules/typescript"

CLEAN_ENV=(env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME -u NODE_PATH)

# gate <dir> [args...] — runs the gate with no CI markers over a folder in --all mode; sets OUT and EC.
gate_all() {
  local d=$1
  shift
  OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d" --ts-from "$T/tsroot" "$@" --all . 2>&1)
  EC=$?
}

# one_file <fixture> — copies one fixture into its own folder and judges it.
one_file() {
  local d
  d=$(mktemp -d "$T/one.XXXXXX")
  cp "$FIX/$1" "$d/"
  gate_all "$d" --full
}

# expect_rule <fixture> <rule> <line> — the bad fixture yields exactly that one finding.
expect_rule() {
  one_file "$1"
  local base=${1##*/}
  check 1 "$EC" "$1: exits 1"
  check 1 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "$1: one finding ($OUT)"
  has "$base:$3: comments/$2:" "$OUT" "$1: names file, line and rule"
  has "Fix:" "$OUT" "$1: names the fix"
}

expect_clean() {
  one_file "$1"
  check 0 "$EC" "$1: clean control exits 0 ($OUT)"
  has "check-comments: ok" "$OUT" "$1: ok line"
}

for lang in ts py; do
  ext=$lang
  expect_rule "$lang/trailing.bad.$ext" trailing 1
  expect_clean "$lang/trailing.ok.$ext"
  expect_rule "$lang/body.bad.$ext" placement 2
  expect_clean "$lang/body.ok.$ext"
  expect_rule "$lang/length.bad.$ext" length 1
  expect_clean "$lang/length.ok.$ext"
  expect_rule "$lang/aside.bad.$ext" aside 1
  expect_clean "$lang/aside.ok.$ext"
  expect_rule "$lang/bracketed.bad.$ext" bracketed 1
  expect_clean "$lang/bracketed.ok.$ext"
  expect_clean "$lang/strings.ok.$ext"
  expect_clean "$lang/directives.ok.$ext"
done
expect_clean ts/jsx.ok.tsx

# a comment above a blank line is not directly above its declaration
d=$T/blank
mkdir -p "$d"
printf 'export const z = 0;\n// Note.\n\nexport const a = 1;\n// Second.\nexport const b = 2;\n' > "$d/a.ts"
gate_all "$d" --full
check 1 "$EC" "blank line before the declaration: exits 1"
has "a.ts:2: comments/placement" "$OUT" "blank line before the declaration: line 2 flagged"
lacks "a.ts:5:" "$OUT" "comment directly above the declaration stays clean"

# a trailing comment after a parenthetical is judged once per rule: a multi-line aside is found on its own line
d=$T/multi
mkdir -p "$d"
printf '// Starts here (an aside that\n// ends on the next line) and stops.\nexport const a = 1;\n' > "$d/a.ts"
gate_all "$d" --full
has "a.ts:1: comments/aside" "$OUT" "multi-line aside found at its opening line"

# skipped paths never produce findings
d=$T/skip
mkdir -p "$d/node_modules/x" "$d/src/components/ui" "$d/migrations" "$d/dist" "$d/src"
printf 'export const a = 1; // bad\n' | tee "$d/node_modules/x/index.js" "$d/src/components/ui/button.tsx" "$d/dist/a.js" > /dev/null
printf 'A = 1  # bad\n' > "$d/migrations/001.py"
gate_all "$d"
check 0 "$EC" "skip list: generated and vendored paths ignored ($OUT)"
printf 'export const a = 1; // bad\n' > "$d/src/a.ts"
gate_all "$d"
check 1 "$EC" "skip list control: a normal source path is judged"

# git helpers
GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main)
# repo <dir> — a project with a symlinked typescript, a bare origin and one base commit; files are added by the caller.
repo() {
  mkdir -p "$1/node_modules"
  ln -s "$TSPKG" "$1/node_modules/typescript"
  printf 'node_modules\n' > "$1/.gitignore"
  mkdir -p "$1/scripts"
  cp "$SHARED/template/scripts/check-comments."* "$1/scripts/"
}
commit_all() { (cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -q -m "$2"); }
# gate_diff <dir> [args...] — runs the seeded copy with no CI markers; sets OUT and EC.
gate_diff() {
  local d=$1
  shift
  OUT=$(cd "$d" && "${CLEAN_ENV[@]}" bash scripts/check-comments.sh "$@" 2>&1)
  EC=$?
}

# diff scope: old violations are not flagged, new and changed lines are
for lang in ts py; do
  d=$T/diff-$lang
  repo "$d"
  mkdir -p "$d/src"
  cp "$FIX/diff/base.$lang" "$d/src/mod.$lang"
  (cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
  commit_all "$d" base
  (cd "$d" && "${GIT[@]}" checkout -q -b topic)
  gate_diff "$d" main
  check 0 "$EC" "diff[$lang]: untouched old violations pass ($OUT)"
  cp "$FIX/diff/new.$lang" "$d/src/mod.$lang"
  gate_diff "$d" main
  check 1 "$EC" "diff[$lang]: new violations fail"
  check 2 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "diff[$lang]: exactly the two new findings ($OUT)"
  lacks "mod.$lang:1:" "$OUT" "diff[$lang]: old line 1 not flagged"
  has "diff base: base ref taken from the command-line argument" "$OUT" "diff[$lang]: report states how the base was chosen"
  commit_all "$d" topic
  gate_diff "$d" main
  check 1 "$EC" "diff[$lang]: committed new violations still fail against the base"
  gate_diff "$d" HEAD
  check 0 "$EC" "diff[$lang]: nothing changed against HEAD passes ($OUT)"
  cp "$FIX/$lang/trailing.bad.$lang" "$d/src/untracked.$lang"
  gate_diff "$d" HEAD
  check 1 "$EC" "diff[$lang]: an untracked file is judged whole"
  has "untracked.$lang:1: comments/trailing" "$OUT" "diff[$lang]: untracked finding named"
done

# editing an old comment line makes it a changed line
d=$T/edit
repo "$d"
mkdir -p "$d/src"
printf '// Old note.\nexport const keep = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
printf '// Old note (reworded).\nexport const keep = 1;\n' > "$d/src/a.ts"
gate_diff "$d" main
has "a.ts:1: comments/aside" "$OUT" "edited comment line is judged"

# ADR folder changes the length message
d=$T/adr
repo "$d"
mkdir -p "$d/src"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/src/a.ts"
commit_all "$d" base
cp "$FIX/ts/length.bad.ts" "$d/src/b.ts"
gate_diff "$d" main
has "comments/length" "$OUT" "adr: length finding without an ADR folder"
lacks "ADR" "$OUT" "adr: no ADR advice when the project has no ADR folder"
mkdir -p "$d/docs/adr"
gate_diff "$d" main
has "Cite the ADR by number" "$OUT" "adr: advice to cite the ADR by number when docs/adr exists"
rm -r "$d/docs/adr"
mkdir -p "$d/docs/decisions"
gate_diff "$d" main
has "Cite the ADR by number" "$OUT" "adr: docs/decisions counts as well"

# missing runtime or package fails closed with the fix named
d=$T/norun
mkdir -p "$d/bin"
for tool in bash git awk sort mktemp rm find dirname wc tr head cat sed; do
  ln -s "$(command -v "$tool")" "$d/bin/$tool"
done
mkdir -p "$d/tsproj" "$d/pyproj"
cp "$FIX/ts/trailing.bad.ts" "$d/tsproj/"
cp "$FIX/py/trailing.bad.py" "$d/pyproj/"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --ts-from "$T/tsroot" --all . 2>&1)
check 2 "$?" "no node: exits 2"
has "node is missing" "$OUT" "no node: message names the cause"
has "Fix:" "$OUT" "no node: message names the fix"
ln -s "$(command -v node)" "$d/bin/node"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all . 2>&1)
check 2 "$?" "no python3: exits 2"
has "python3 is missing" "$OUT" "no python3: message names the cause"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --all . 2>&1)
check 2 "$?" "no typescript package: exits 2"
has "typescript package is missing" "$OUT" "no typescript package: message names the cause"
has "pnpm install" "$OUT" "no typescript package: message names the fix"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all nonexistent 2>&1)
check 0 "$?" "a path with no source files is clean, not an error ($OUT)"
mkdir -p "$d/empty"
OUT=$("${CLEAN_ENV[@]}" /bin/bash "$GATE" --root "$d/empty" 2>&1)
check 2 "$?" "outside a git work tree: exits 2"
has "not a git work tree" "$OUT" "outside a git work tree: message names the cause"

# CI refuses a BASE_REF override that is not the pipeline target branch
d=$T/ci
repo "$d"
mkdir -p "$d/src" "$T/origin.git"
git init -q --bare "$T/origin.git"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/src/a.ts"
commit_all "$d" base
(cd "$d" && "${GIT[@]}" remote add origin "$T/origin.git" && "${GIT[@]}" push -q origin main 2> /dev/null && "${GIT[@]}" fetch -q origin)
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
cp "$FIX/ts/trailing.bad.ts" "$d/src/b.ts"
ci() { # ci <env assignments...> -- <gate args...> — runs with CI markers set.
  local envs=()
  while [[ "$1" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME "${envs[@]}" bash scripts/check-comments.sh "$@" 2>&1)
  EC=$?
}
ci CI=true GITHUB_ACTIONS=true BASE_REF=HEAD~5 --
check 2 "$EC" "ci: BASE_REF with no pipeline target is refused"
has "refused in CI" "$OUT" "ci: refusal message"
ci CI=true GITHUB_ACTIONS=true BASE_REF=topic GITHUB_BASE_REF=main --
check 2 "$EC" "ci: BASE_REF that is not the target branch is refused"
has "not the pipeline target branch (main)" "$OUT" "ci: message names the target"
ci CI=true GITHUB_ACTIONS=true BASE_REF=origin/main GITHUB_BASE_REF=main --
check 1 "$EC" "ci: BASE_REF equal to origin/<target> is accepted and judges the diff"
has "accepted because it names the pipeline target branch (main)" "$OUT" "ci: report states the decision"
ci TF_BUILD=True BASE_REF=main SYSTEM_PULLREQUEST_TARGETBRANCH=refs/heads/main --
check 1 "$EC" "ci: Azure target branch variable accepted"
ci TF_BUILD=True BASE_REF=topic SYSTEM_PULLREQUEST_TARGETBRANCHNAME=main --
check 2 "$EC" "ci: Azure override that is not the target is refused"
ci CI=true GITHUB_BASE_REF=main --
check 1 "$EC" "ci: no override uses the pipeline target branch"
has "pipeline target branch (main)" "$OUT" "ci: report states the target decision"
ci CI=true GITHUB_ACTIONS=true BASE_REF=topic -- main
check 1 "$EC" "ci: an explicit argument in the pipeline step is accepted"
has "command-line argument" "$OUT" "ci: report states the argument decision"
ci CI=false BASE_REF=main --
check 1 "$EC" "ci: CI=false is not CI, so a BASE_REF override works"
has "BASE_REF from the environment (not CI)" "$OUT" "ci: report states the non-CI decision"
ci CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=gone --
check 2 "$EC" "ci: target branch missing from the clone fails closed"
has "base ref not found" "$OUT" "ci: missing base message"

# real scaffolds parse: every stack reads through both tokenizers with no parse failure or crash
scaffold() { # scaffold <stack> <dir>
  mkdir -p "$2"
  local part
  for part in stack base agents settings late; do
    TC_STACK=$1 TC_PART=$part bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
  done
}
for stack in nextjs nestjs vite-react fastapi; do
  d=$T/scaffold-$stack
  scaffold "$stack" "$d"
  gate_all "$d" --full
  if [[ "$EC" -le 1 ]]; then got=judged; else got="exit $EC"; fi
  check judged "$got" "scaffold[$stack]: reads every file without a runtime error ($OUT)"
  lacks "comments/parse" "$OUT" "scaffold[$stack]: no parse failure"
done

echo "seeded-comments.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
