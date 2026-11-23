#!/usr/bin/env bash
# scripts/seeded-comments.test.sh — tests for the seeded scripts/check-comments.sh (and its node and python readers).
# Typescript: TC_TEST_TYPESCRIPT_DIR (a typescript package folder), else the exact version pinned in skills/scaffold/shared/versions.txt
# is installed once from the public npm registry (no login) into a cache folder under TMPDIR and reused.
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

TS_VERSION=$(awk '$1 == "npm" && $2 == "typescript" { v = $3; gsub(/[^0-9.]/, "", v); print v }' "$SHARED/versions.txt")
if [[ -z "$TS_VERSION" ]]; then
  echo "seeded-comments.test: no typescript version pinned in skills/scaffold/shared/versions.txt." >&2
  exit 2
fi
TS_CACHE="${TMPDIR:-/tmp}/tc-seeded-comments-typescript-$TS_VERSION"
TSPKG=${TC_TEST_TYPESCRIPT_DIR:-}
if [[ -n "$TSPKG" ]]; then
  if [[ ! -f "$TSPKG/package.json" && -f "$TSPKG/node_modules/typescript/package.json" ]]; then TSPKG=$TSPKG/node_modules/typescript; fi
  if [[ ! -f "$TSPKG/package.json" ]]; then
    echo "seeded-comments.test: TC_TEST_TYPESCRIPT_DIR has no typescript package. Fix: point it at a typescript package folder, or unset it to install the pinned version." >&2
    exit 2
  fi
else
  TSPKG=$TS_CACHE/node_modules/typescript
  if [[ ! -f "$TSPKG/package.json" ]]; then
    if ! command -v npm > /dev/null 2>&1; then
      echo "seeded-comments.test: npm is missing, so typescript $TS_VERSION cannot be installed. Fix: install Node.js, or set TC_TEST_TYPESCRIPT_DIR to a typescript package folder." >&2
      exit 2
    fi
    stage=$(mktemp -d "$TS_CACHE.stage.XXXXXX") || exit 2
    if ! npm install --prefix "$stage" --cache "$stage.cache" --no-audit --no-fund --ignore-scripts --loglevel=error "typescript@$TS_VERSION" > "$stage.log" 2>&1; then
      echo "seeded-comments.test: npm install typescript@$TS_VERSION failed: $(tail -n 1 "$stage.log"). Fix: check network access to the public npm registry, or set TC_TEST_TYPESCRIPT_DIR." >&2
      rm -rf "$stage" "$stage.log"
      exit 2
    fi
    rm -f "$stage.log"
    if [[ -f "$TSPKG/package.json" ]]; then rm -rf "$stage"; else mv "$stage" "$TS_CACHE"; fi
  fi
  got_version=$(node -p "require('$TSPKG/package.json').version" 2> /dev/null || true)
  if [[ "$got_version" != "$TS_VERSION" ]]; then
    echo "seeded-comments.test: cached typescript is $got_version, pinned is $TS_VERSION. Fix: delete $TS_CACHE and re-run." >&2
    exit 2
  fi
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
expect_rule ts/jsx.bad.tsx trailing 2
expect_clean ts/config.ok.ts
expect_rule ts/list.bad.ts placement 2
expect_rule ts/arrow.bad.ts placement 2
expect_rule ts/nested.bad.ts placement 3
expect_clean ts/jsdoc.ok.ts
expect_rule ts/jsdoc.bad.ts length 1
expect_clean ts/coderef.ok.ts
expect_clean py/config.ok.py
expect_rule py/list.bad.py placement 2
expect_rule py/nested.bad.py placement 3
expect_clean py/docstring.ok.py
expect_rule py/docstring.bad.py length 2
expect_clean py/coderef.ok.py

# inline <file> <content> — writes a one-file project (content goes through printf %b) and judges it; sets OUT and EC.
inline() {
  local d
  d=$(mktemp -d "$T/inl.XXXXXX")
  printf '%b' "$2" > "$d/$1"
  gate_all "$d" --full
}
# inline_rule <file> <rule> <line> <content> — exactly one finding of that rule at that line.
inline_rule() {
  inline "$1" "$4"
  check 1 "$EC" "$1 [$2]: exits 1 ($OUT)"
  check 1 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "$1 [$2]: one finding ($OUT)"
  has "$1:$3: comments/$2:" "$OUT" "$1 [$2]: names file, line and rule"
}
inline_clean() {
  inline "$1" "$2"
  check 0 "$EC" "$1: clean control exits 0 ($OUT)"
}

# directive lookalikes are prose and stay judged
inline_rule a.ts aside 1 '// eslint-disable-line -- see (note) essay prose here\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// This explains the thing @ts-ignore (aside here)\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// pragma is the thing (aside)\nexport const a = 1;\n'
inline_rule a.py trailing 1 'x = 1  # noqa: this is an essay\n'
inline_rule a.ts length 1 '// note one @ts-ignore\n// note two @ts-ignore\n// note three @ts-ignore\n// note four @ts-ignore\n// note five @ts-ignore\nexport const a = 1;\n'
inline_rule a.ts length 1 '// @ts-expect-error reason one\n// @ts-expect-error reason two\n// @ts-expect-error reason three\n// @ts-expect-error reason four\n// @ts-expect-error reason five\nexport const a: number = "x";\n'
inline_rule a.py length 1 '# noqa: this is an essay\n# noqa: this is an essay\n# noqa: this is an essay\n# noqa: this is an essay\n# noqa: this is an essay\nA = 1\n'
inline_rule a.py length 1 '# noqa: E501 reason one\n# noqa: E501 reason two\n# noqa: E501 reason three\n# noqa: E501 reason four\n# noqa: E501 reason five\nA = 1\n'
reason101=$(printf '%0101d' 0)
inline_rule a.ts length 1 "// @ts-ignore $reason101\nexport const a = 1;\n"
inline_rule a.py length 2 "A = 1\n# noqa: E501 $reason101\nB = 2\n"
inline_rule a.ts length 1 '/* eslint-disable no-console -- first part\n   second part */\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// @ts-ignore explained (here)\nexport const a = 1;\n'
reason100=$(printf '%0100d' 0)
inline_clean a.ts "// @ts-ignore $reason100\nexport const a: number = 'x';\n"
inline_clean a.ts '// eslint-disable-next-line no-console -- logs the boot banner\nexport const a = 1;\n'
inline_clean a.py 'import os  # noqa: F401 kept for the plugin\n'
inline_clean a.ts 'export const a = 1; // eslint-disable-line no-console, no-undef\n'

# a comment line is capped
long130=$(printf '%0130d' 0)
inline_rule a.ts length 1 "// $long130\nexport const a = 1;\n"
inline_rule a.py length 1 "# $long130\nA = 1\n"
long120=$(printf '%0120d' 0)
inline_clean a.ts "// $long120\nexport const a = 1;\n"

# placement: one rule for both languages
inline_rule a.ts placement 3 'export const z = 0;\nexport function f() {\n  // inside\n  return 1;\n}\n'
inline_rule a.ts placement 2 'export const z = 0;\n// above a closing brace\n'
inline_rule a.ts placement 3 'export const z = 0;\nconst v = [\n  // element\n  1,\n];\n'
inline_clean a.ts 'export const z = 0;\n// above a statement\nexport const y = 1;\n'
inline_clean a.ts 'export class C {\n  // above a member\n  m = 1;\n}\nexport interface I {\n  // above a signature\n  k: number;\n}\n'

# BOM and CRLF are read like plain files
inline_clean a.ts '\xef\xbb\xbf// Note.\r\nexport const a = 1;\r\n'
inline_clean a.py '\xef\xbb\xbf# Note.\r\nA = 1\r\n'
inline_rule a.ts trailing 2 '\xef\xbb\xbf// Note.\r\nexport const a = 1; // bad\r\n'
inline_rule a.py trailing 2 '\xef\xbb\xbf# Note.\r\nA = 1  # bad\r\n'

# a parse failure names the interpreter or the typescript version
inline a.ts 'export const = ;\n'
has "comments/parse" "$OUT" "parse failure in ts is reported"
has "typescript $TS_VERSION" "$OUT" "parse failure names the typescript version"
inline a.py 'def (:\n'
has "comments/parse" "$OUT" "parse failure in py is reported"
has "Python 3." "$OUT" "parse failure names the Python version"

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

# build and dist folders are skipped at the project root only
d=$T/anchor
mkdir -p "$d/src/build" "$d/src/dist"
printf 'export const a = 1; // bad\n' | tee "$d/src/build/x.ts" "$d/src/dist/y.ts" > /dev/null
gate_all "$d" --full
check 1 "$EC" "skip list: nested build and dist folders are judged"
has "src/build/x.ts:1" "$OUT" "skip list: src/build judged"
has "src/dist/y.ts:1" "$OUT" "skip list: src/dist judged"
d=$T/anchor-root
mkdir -p "$d/build" "$d/dist"
printf 'export const a = 1; // bad\n' | tee "$d/build/x.ts" "$d/dist/y.ts" > /dev/null
gate_all "$d"
check 0 "$EC" "skip list control: root build and dist folders are skipped ($OUT)"
check 0 "$(grep -c '/dev/stderr' "$GATE")" "the shell script holds no /dev/stderr write"
has "call foo() first" "$(cat "$GATE")" "header documents the code-reference allowance"

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
for tool in bash git awk sort mktemp rm find dirname wc tr head tail cat sed; do
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
mkdir -p "$d/node_modules"
ln -s "$TSPKG" "$d/node_modules/typescript"
OUT=$(env -u NODE_PATH PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --all . 2>&1)
check 2 "$?" "no typescript package: exits 2 even with a typescript in a parent folder"
has "typescript package is missing" "$OUT" "no typescript package: message names the cause"
has "pnpm install" "$OUT" "no typescript package: message names the fix"
lacks "check-comments: check-comments:" "$OUT" "no typescript package: the message carries one prefix"
OUT=$(env NODE_PATH="$T/tsroot/node_modules" PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --all . 2>&1)
check 2 "$?" "no typescript package: NODE_PATH does not supply one"
rm "$d/node_modules/typescript"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all nonexistent 2>&1)
check 0 "$?" "a path with no source files is clean, not an error ($OUT)"
mkdir -p "$d/empty"
OUT=$("${CLEAN_ENV[@]}" /bin/bash "$GATE" --root "$d/empty" 2>&1)
check 2 "$?" "outside a git work tree: exits 2"
has "not a git work tree" "$OUT" "outside a git work tree: message names the cause"

# a typescript release without the scanner API fails closed and names its version
mkdir -p "$d/fakeroot/node_modules/typescript"
printf '{"name":"typescript","version":"9.9.9","main":"index.js"}\n' > "$d/fakeroot/node_modules/typescript/package.json"
printf 'module.exports = { version: "9.9.9" };\n' > "$d/fakeroot/node_modules/typescript/index.js"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d/tsproj" --ts-from "$d/fakeroot" --all . 2>&1)
check 2 "$?" "typescript without the scanner API: exits 2"
has "typescript 9.9.9 lacks the compiler API" "$OUT" "typescript without the scanner API: names the version"
has "ScriptTarget" "$OUT" "typescript without the scanner API: names the missing member"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d/tsproj" --ts-from "$T/tsroot" --all . 2>&1)
check 1 "$?" "typescript with the scanner API: the control run judges the file"

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

# CI push to the target branch: nothing to compare, said out loud
rm -rf "$T/push"
git clone -q "$T/origin.git" "$T/push" 2> /dev/null
run_push() { # run_push <env assignments...> — the gate over a clean clone whose HEAD is the base.
  OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME "$@" bash "$GATE" --root "$T/push" 2>&1)
  EC=$?
}
run_push CI=true GITHUB_ACTIONS=true
check 0 "$EC" "ci push: exits 0 ($OUT)"
has "nothing to compare" "$OUT" "ci push: says there is nothing to compare"
has "judges pull requests" "$OUT" "ci push: says the gate judges pull requests"
has "nothing checked" "$OUT" "ci push: final line says nothing was checked"
lacks "check-comments: ok" "$OUT" "ci push: no green ok line"
run_push A=1
check 0 "$EC" "non-ci, HEAD is the base: exits 0"
has "check-comments: ok (0 file(s) checked)" "$OUT" "non-ci, HEAD is the base: plain ok line"
lacks "nothing to compare" "$OUT" "non-ci, HEAD is the base: no push message"
ci CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=main --
lacks "nothing to compare" "$OUT" "ci pull request with changes: no push message"
check 1 "$EC" "ci pull request with changes: still judged"

# a project in a git subfolder judges its own changed and new files, with paths relative to the project
d=$T/nest
mkdir -p "$d"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
repo "$d/backend"
mkdir -p "$d/backend/src" "$d/other"
printf 'export const old = 1;\n' > "$d/backend/src/old.ts"
printf 'export const x = 1;\n' > "$d/other/x.ts"
printf 'node_modules\n' > "$d/.gitignore"
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const old = 1;\nexport const more = 2; // bad\n' > "$d/backend/src/old.ts"
printf 'export const n = 1; // bad\n' > "$d/backend/src/new.ts"
printf 'export const x = 1; // bad\n' > "$d/other/x.ts"
gate_diff "$d/backend" main
check 1 "$EC" "subfolder project: judged, not a runtime error ($OUT)"
has "src/old.ts:2: comments/trailing" "$OUT" "subfolder project: changed file named relative to the project"
has "src/new.ts:1: comments/trailing" "$OUT" "subfolder project: untracked file named relative to the project"
lacks "other/" "$OUT" "subfolder project: a file outside the project is not judged"
commit_all "$d" topic
gate_diff "$d/backend" main
check 1 "$EC" "subfolder project: committed changes judged ($OUT)"
check 2 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "subfolder project: exactly the two project findings"

# rename-only changes are not re-judged, a reindented line counts as changed
d=$T/rename
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1; // old\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic && "${GIT[@]}" mv src/a.ts src/b.ts)
commit_all "$d" rename
gate_diff "$d" main
check 0 "$EC" "rename only: the old violation is not re-judged ($OUT)"
printf '  export const a = 1; // old\n' > "$d/src/b.ts"
gate_diff "$d" main
check 1 "$EC" "whitespace-only edit: the reindented line counts as changed"
has "src/b.ts:1: comments/trailing" "$OUT" "whitespace-only edit: finding named"

# deleted and binary files are not judged
d=$T/delbin
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1; // old\n' > "$d/src/gone.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic && "${GIT[@]}" rm -q src/gone.ts)
printf '\x89PNG\r\n\x1a\n\0\0\0' > "$d/logo.png"
commit_all "$d" "delete and binary"
gate_diff "$d" main
check 0 "$EC" "deleted and binary files: clean ($OUT)"
has "ok (0 file(s) checked)" "$OUT" "deleted and binary files: nothing to judge"

# a path with a space is read whole
d=$T/space
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const a = 1;\nexport const b = 2; // bad\n' > "$d/src/a.ts"
cp "$d/src/a.ts" "$d/src/my file.ts"
commit_all "$d" "spaces"
gate_diff "$d" main
has "src/my file.ts:2: comments/trailing" "$OUT" "path with a space: judged and named"

# an extra positional argument is refused
gate_diff "$d" main extra
check 2 "$EC" "extra argument: exits 2"
has "unexpected extra argument" "$OUT" "extra argument: message names the cause"

# a shallow clone with no merge base fails closed
d=$T/hist
mkdir -p "$d"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/a.ts"
commit_all "$d" one
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const b = 1;\n' > "$d/b.ts"
commit_all "$d" two
printf 'export const c = 1;\n' > "$d/c.ts"
commit_all "$d" three
(cd "$d" && "${GIT[@]}" checkout -q main)
printf 'export const m = 1;\n' > "$d/m.ts"
commit_all "$d" four
printf 'export const n = 1;\n' > "$d/n.ts"
commit_all "$d" five
git init -q --bare "$T/hist-origin.git"
(cd "$d" && "${GIT[@]}" push -q "$T/hist-origin.git" main topic 2> /dev/null)
git clone -q --depth 1 --branch topic "file://$T/hist-origin.git" "$T/shallow" 2> /dev/null
git -C "$T/shallow" fetch -q --depth 1 origin main:refs/remotes/origin/main 2> /dev/null
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$T/shallow" origin/main 2>&1)
check 2 "$?" "shallow clone: no merge base exits 2 ($OUT)"
has "no merge base" "$OUT" "shallow clone: message names the cause"
has "fetch-depth: 0" "$OUT" "shallow clone: message names the fix"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d" main 2>&1)
check 0 "$?" "full history control: the same refs run ($OUT)"

# a non-CI BASE_REF other than main is honoured
d=$T/branches
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b develop)
printf 'export const dev = 1; // bad\n' > "$d/src/dev.ts"
commit_all "$d" develop
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const top = 1; // bad\n' > "$d/src/top.ts"
commit_all "$d" topic
OUT=$(cd "$d" && "${CLEAN_ENV[@]}" env BASE_REF=develop bash scripts/check-comments.sh 2>&1)
check 1 "$?" "BASE_REF=develop: judged"
has "src/top.ts:1" "$OUT" "BASE_REF=develop: the topic change is judged"
lacks "src/dev.ts" "$OUT" "BASE_REF=develop: the develop change is not"
has "BASE_REF from the environment (not CI)" "$OUT" "BASE_REF=develop: report states the decision"
gate_diff "$d"
has "src/dev.ts:1" "$OUT" "default base (main): the develop change is judged too"

# the project's own .venv interpreter is preferred for Python
d=$T/venv
mkdir -p "$d/.venv/bin"
printf '#!/bin/sh\ntouch "%s/venv-used"\nexec "%s" "$@"\n' "$d" "$(command -v python3)" > "$d/.venv/bin/python3"
chmod +x "$d/.venv/bin/python3"
printf 'A = 1  # bad\n' > "$d/a.py"
gate_all "$d"
check 1 "$EC" "venv: the gate still judges ($OUT)"
check yes "$([[ -f "$d/venv-used" ]] && echo yes || echo no)" "venv: the project interpreter ran"
d=$T/novenv
mkdir -p "$d"
printf 'A = 1  # bad\n' > "$d/a.py"
gate_all "$d"
check no "$([[ -f "$d/venv-used" ]] && echo yes || echo no)" "no venv: the system interpreter runs"

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
