#!/usr/bin/env bash
# scripts/seeded-gates.test.sh — behaviour tests for the seeded check-workarounds.sh, scan-secrets.sh and the ci-gates.sh nosonar and diffcover gates.
# Each gate gets a clean control case and a failing case whose message text is asserted.
# Usage: bash scripts/seeded-gates.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared/template"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
check() { if [[ "$1" == "$2" ]]; then ok; else bad "$3: expected [$1], got [$2]"; fi; }
has() { if [[ "$2" == *"$1"* ]]; then ok; else bad "$3: [$1] not in [$2]"; fi; }
hasnt() { if [[ "$2" != *"$1"* ]]; then ok; else bad "$3: [$1] found in output"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/sg.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

clean() { env -u CI -u GITHUB_ACTIONS -u TF_BUILD "$@"; }
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# newrepo <name>: a repo on main holding the seeded scripts and one source file with its test.
newrepo() {
  R="$T/$1"
  mkdir -p "$R/scripts" "$R/.claude" "$R/src" "$R/test"
  git -C "$R" init -q -b main
  cp "$SH/scripts/check-workarounds.sh" "$SH/scripts/scan-secrets.sh" "$R/scripts/"
  cp "$SH/.claude/ci-gates.sh" "$SH/.claude/gates.txt" "$R/.claude/"
  printf 'export const add = (a: number, b: number): number => a + b;\n' > "$R/src/add.ts"
  printf 'import { add } from "../src/add";\n' > "$R/test/add.test.ts"
  printf 'def add(a, b):\n    return a + b\n' > "$R/src/calc.py"
  printf 'from src.calc import add\n' > "$R/test/test_calc.py"
  g add -A
  g commit -q -m base
  g checkout -q -b work
}

# runwa <repo>: run the workaround detector against main, output in $OUT, status in $RC.
runwa() {
  OUT=$(cd "$R" && clean bash scripts/check-workarounds.sh main 2>&1)
  RC=$?
}

# ---- markers: each is added on its own line of a new file; the message names file, line and marker.
M_NOSONAR="NOSO""NAR"
check_marker() { # check_marker <file> <content> <label>
  newrepo "m$((++N))"
  printf '%s\n' "$2" > "$R/$1"
  g add -A
  g commit -q -m work
  runwa
  check 1 "$RC" "marker $3 is flagged"
  has "$1:1: $3" "$OUT" "marker $3 names file, line and marker"
  has "Fix the cause." "$OUT" "marker $3 message says how to fix"
}
N=0
check_marker src/a.py 'x = 1  # noqa: E501' '# noqa'
check_marker src/a.py 'x = 1  # type: ignore[assignment]' '# type: ignore'
check_marker src/a.py 'if x:  # pragma: no cover' '# pragma: no cover'
check_marker src/a.py '@pytest.mark.skip(reason="later")' '@pytest.mark.skip / skipif / xfail'
check_marker src/a.py "x = 1  # $M_NOSONAR" 'NOSONAR'
check_marker src/a.ts '// eslint-disable-next-line no-console' 'eslint-disable'
check_marker src/a.ts '/* eslint-disable */' 'eslint-disable'
check_marker src/a.ts '// @ts-ignore' '@ts-ignore'
check_marker src/a.ts '// @ts-expect-error legacy' '@ts-expect-error'
check_marker src/a.ts '/* istanbul ignore next */' 'istanbul ignore'
check_marker src/a.ts '/* v8 ignore next */' 'v8 ignore'
check_marker src/a.ts "// $M_NOSONAR" 'NOSONAR'
check_marker test/a.test.ts 'it.skip("later", () => {});' '.skip( / .skipIf( / .only('
check_marker test/a.test.ts 'it.only("only", () => {});' '.skip( / .skipIf( / .only('
check_marker test/a.test.ts 'xit("later", () => {});' 'xit( / xdescribe( / xtest( / fit( / fdescribe('
check_marker src/a.ts 'const v = JSON.parse(s) as any;' 'as any'
check_marker src/a.py 'x = 1  # NOQA' '# noqa'
check_marker src/a.py 'x = 1  # Noqa: E501' '# noqa'
check_marker src/a.py 'x = 1  #noqa' '# noqa'
check_marker src/a.py 'if x:  # pragma:no cover' '# pragma: no cover'
check_marker src/a.py 'if x:  # pragma:  no cover' '# pragma: no cover'
check_marker src/a.py 'if x:  # PRAGMA: NO COVER' '# pragma: no cover'
check_marker src/a.py 'import os  # pylint: disable=unused-import' '# pylint: disable'
check_marker src/a.py 'x = 1  # nosec' '# nosec'
check_marker src/a.py 'pytest.skip("later")' 'pytest.skip( / pytest.xfail('
check_marker src/a.py '@pytest.mark.xfail(reason="later")' '@pytest.mark.skip / skipif / xfail'
check_marker src/a.py '@pytest.mark.skipif(True, reason="later")' '@pytest.mark.skip / skipif / xfail'
check_marker src/a.pyi 'x: int  # type: ignore' '# type: ignore'
check_marker src/a.pyi 'x: int  # pyright: ignore' '# pyright: ignore'
check_marker src/a.ts 'const v = JSON.parse(s) as  any;' 'as any'
check_marker src/a.ts 'const v = <any>JSON.parse(s);' '<any> cast'
check_marker test/a.test.ts 'it.skipIf(cond)("later", () => {});' '.skip( / .skipIf( / .only('
check_marker test/a.test.ts 'it.skip.each([1])("later", () => {});' '.skip( / .skipIf( / .only('
check_marker test/a.test.ts 'test.skip.each([1])("later", () => {});' '.skip( / .skipIf( / .only('
check_marker test/a.test.ts 'it.todo("later");' '.todo('
check_marker test/a.test.ts 'fit("focused", () => {});' 'xit( / xdescribe( / xtest( / fit( / fdescribe('
check_marker test/a.test.ts 'fdescribe("focused", () => {});' 'xit( / xdescribe( / xtest( / fit( / fdescribe('
check_marker src/a.ts '/* istanbul  ignore next */' 'istanbul ignore'
check_marker src/a.ts '/* v8  ignore next */' 'v8 ignore'
check_marker src/a.ts '/* ISTANBUL IGNORE NEXT */' 'istanbul ignore'
check_marker src/a.mts '// @ts-ignore' '@ts-ignore'
check_marker src/a.cts '// @ts-ignore' '@ts-ignore'

# ---- clean control: ordinary changes, and the old suppression text, pass.
newrepo clean
printf 'export const sub = (a: number, b: number): number => a - b;\n' > "$R/src/sub.ts"
g add -A
g commit -q -m work
runwa
check 0 "$RC" "clean change passes"
has "no suppression markers added" "$OUT" "clean change prints one success line"

# Similar-looking text that is not a marker passes.
newrepo lookalikes
printf 'const hint = "skip the intro";\nconst gain = benefit(3);\nconst a = x as anything;\nconst b = model.fit(data);\nconst c: Promise<any> = load();\nconst d = Array<any>();\n' > "$R/src/look.ts"
printf 'note = "skip the noqa talk"\nskipped = 1\nunskip_all = 2\n' > "$R/src/look.py"
printf 'from typing import Any\nvalue: Any = 1\n' > "$R/src/look.pyi"
g add -A
g commit -q -m work
runwa
check 0 "$RC" "lookalike text (skip in a string, benefit(, as anything, model.fit(, Promise<any>) is not flagged"
has "no suppression markers added" "$OUT" "lookalike control prints the success line"

# A marker already on main is not this change's problem.
newrepo preexisting
printf '// @ts-ignore\nexport const old = 1;\n' > "$R/src/old.ts"
g add -A
g commit -q -m old
g checkout -q main
g merge -q --ff-only work
g checkout -q -b more
printf 'export const fresh = 2;\n' > "$R/src/fresh.ts"
g add -A
g commit -q -m fresh
runwa
check 0 "$RC" "a marker that is not in this diff is not flagged"

# The ESLint rule that bans the word is not itself a marker.
newrepo eslintword
printf "const terms = ['%s'];\n" "$(printf '%s' "$M_NOSONAR" | tr '[:upper:]' '[:lower:]')" > "$R/src/terms.ts"
g add -A
g commit -q -m work
runwa
check 0 "$RC" "the word in a string, not a comment, passes the workaround scan"

# ---- removed tests
newrepo removed
g rm -q test/add.test.ts
g commit -q -m work
runwa
check 1 "$RC" "deleting a covering test file is flagged"
has "removed test: test/add.test.ts (covers src/add.ts)" "$OUT" "removed test names the test and the source it covers"
has "Restore the test file" "$OUT" "removed test message says how to fix"

newrepo removed-py
g rm -q test/test_calc.py
g commit -q -m work
runwa
check 1 "$RC" "deleting a covering python test is flagged"
has "removed test: test/test_calc.py (covers src/calc.py)" "$OUT" "python removed test names the source"

newrepo removed-both
g rm -q test/add.test.ts src/add.ts
g commit -q -m work
runwa
check 0 "$RC" "deleting a test together with the source it covers passes"

newrepo renamed
g mv test/add.test.ts test/add-more.test.ts
g commit -q -m work
runwa
check 0 "$RC" "renaming a test file is not a removal"

# ---- fails closed when the base cannot be found
newrepo nobase
OUT=$(cd "$R" && clean bash scripts/check-workarounds.sh no-such-branch 2>&1)
RC=$?
check 1 "$RC" "an unknown base fails closed"
has "fetch-depth 0" "$OUT" "unknown base message says how to fix"

# ---- ci-gates.sh nosonar (A1): the eslint rule text passes, a real marker fails.
newrepo nosonar-clean
printf "export default [{ rules: { 'no-restricted-syntax': ['error', { terms: ['%s'] }] } }];\n" "$(printf '%s' "$M_NOSONAR" | tr '[:upper:]' '[:lower:]')" > "$R/lint.config.mjs"
printf "const terms = ['%s'];\n" "$(printf '%s' "$M_NOSONAR" | tr '[:upper:]' '[:lower:]')" > "$R/src/rule.ts"
g add -A
g commit -q -m work
OUT=$(cd "$R" && clean bash .claude/ci-gates.sh nosonar 2>&1)
check 0 "$?" "nosonar gate passes on the rule text and a quoted word"

newrepo nosonar-bad
printf 'export const x = 1; // %s\n' "$M_NOSONAR" > "$R/src/x.ts"
g add -A
g commit -q -m work
OUT=$(cd "$R" && clean bash .claude/ci-gates.sh nosonar 2>&1)
check 1 "$?" "nosonar gate fails on a real marker"
has "src/x.ts:1:" "$OUT" "nosonar message lists file and line"
has "Delete the marker and fix the finding" "$OUT" "nosonar message says how to fix"

# ---- ci-gates.sh diffcover: an empty coverage report fails closed when source changed.
dc_repo() { # dc_repo <name> <changed-file>
  newrepo "$1"
  printf 'export const more = 1;\n' > "$R/$2"
  g add -A
  g commit -q -m work
  git -C "$R" update-ref refs/remotes/origin/main main
}
dc() { OUT=$(cd "$R" && clean bash .claude/ci-gates.sh diffcover refs/heads/main 2>&1); RC=$?; }

dc_repo dc-empty src/more.ts
printf 'No lines with coverage information in this diff.\n' > "$R/diff-cover.txt"
dc
check 1 "$RC" "diffcover fails closed on an empty coverage report"
has "src/more.ts" "$OUT" "diffcover message names the changed source file"
has "Do not exclude the files." "$OUT" "diffcover message says how to fix"

dc_repo dc-good src/more.ts
printf -- '-------------\nDiff Coverage\nTotal:   3 lines\nCoverage: 100%%\n' > "$R/diff-cover.txt"
dc
check 0 "$RC" "diffcover passes when the report has lines"
has "covers the changed source lines" "$OUT" "diffcover prints one success line"

dc_repo dc-docs README.md
printf 'No lines with coverage information in this diff.\n' > "$R/diff-cover.txt"
dc
check 0 "$RC" "diffcover is skipped when no source file changed"
has "no source file changed" "$OUT" "diffcover skip says why"

dc_repo dc-tests test/more.test.ts
printf 'No lines with coverage information in this diff.\n' > "$R/diff-cover.txt"
dc
check 0 "$RC" "diffcover ignores a change that only touches tests"

dc_repo dc-missing src/more.ts
dc
check 1 "$RC" "diffcover fails when the diff-cover output is missing"
has "must run first" "$OUT" "diffcover missing-output message says how to fix"

# ---- scan-secrets.sh needs gitleaks; without it the test says so and moves on.
if command -v gitleaks > /dev/null 2>&1; then
  newrepo secret-clean
  OUT=$(cd "$R" && clean bash scripts/scan-secrets.sh git 2>&1)
  check 0 "$?" "scan-secrets passes on a clean repo"
  has "no secrets found" "$OUT" "scan-secrets prints one success line"

  newrepo secret-bad
  key="AKIA""QYLPMN5HHHFPZAM7"
  printf 'const awsKey = "%s";\n' "$key" > "$R/src/config.ts"
  g add -A
  g commit -q -m work
  OUT=$(cd "$R" && clean bash scripts/scan-secrets.sh git 2>&1)
  check 1 "$?" "scan-secrets fails on a committed key"
  has "src/config.ts:1" "$OUT" "scan-secrets names file and line"
  has "aws-access-token" "$OUT" "scan-secrets names the rule id"
  has "Fix: remove the value" "$OUT" "scan-secrets message says how to fix"
  hasnt "$key" "$OUT" "scan-secrets never prints the secret"
else
  echo "skip: gitleaks not installed, scan-secrets cases not run"
fi

# ---- hook messages (D2): each block says what is wrong and the next step.
HK="$REPO_ROOT/skills/scaffold/shared"
hookrepo="$T/hooks"
mkdir -p "$hookrepo"
git -C "$hookrepo" init -q -b main
ENVF=".""env"
printf "x=1\n" > "$hookrepo/$ENVF"
git -C "$hookrepo" -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
hook() { # hook <script> <json>: stderr and stdout together in $OUT, status in $RC
  OUT=$(cd "$hookrepo" && printf '%s' "$2" | clean env CLAUDE_PROJECT_DIR="$hookrepo" bash "$1" 2>&1)
  RC=$?
}
bash_msg() { # bash_msg <stack> <command> <expected text> <label>
  local j
  j=$(python3 -c 'import json, sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$2")
  hook "$HK/template-$1/.claude/hooks/block-no-verify.sh" "$j"
  check 2 "$RC" "[$1] $4 is blocked"
  has "$3" "$OUT" "[$1] $4 message"
}
for st in ts py; do
  bash_msg $st 'git commit --no-verify -m x' 'Fix the failure instead' 'no-verify'
  bash_msg $st 'git commit -n -m x' 'Fix the failure instead' 'commit -n'
  bash_msg $st 'LEFTHOOK=0 git commit -m x' 'Fix the failure instead' 'LEFTHOOK=0'
  bash_msg $st 'git -c core.hooksPath=/dev/null commit -m x' 'Fix the failure instead' 'core.hooksPath override'
  bash_msg $st 'git commit -m x' "git checkout -b <feature-branch>" 'commit on main'
  bash_msg $st 'git checkout -b feat && git commit -m x' "alone first, then run 'git commit' as a separate command" 'checkout -b chained with commit'
  bash_msg $st 'git push --force origin main' 'Open a PR instead' 'force push to main'
  bash_msg $st "cat $ENVF" 'use .env.example for placeholders' 'shell read of the env file'
  mkdir -p "$hookrepo/sub"
  bash_msg $st "cat .e\"\"nv" 'use .env.example for placeholders' 'quote-split env name (.e""nv)'
  bash_msg $st "cat .e'n'v" 'use .env.example for placeholders' "quote-split env name (.e'n'v)"
  bash_msg $st "cat sub/../$ENVF" 'use .env.example for placeholders' 'dot-dot path that resolves to the env file'
  bash_msg $st "git show HEAD:$ENVF" 'use .env.example for placeholders' 'git show of the env file'
  bash_msg $st "git cat-file -p HEAD:$ENVF" 'use .env.example for placeholders' 'git cat-file of the env file'
  bash_msg $st "git -C . show HEAD:$ENVF" 'use .env.example for placeholders' 'git show with a global option'
  for ok in "cat $ENVF.example" 'cat .envrc' "git show HEAD:$ENVF.example" 'git show HEAD:src/app.ts'; do
    j=$(python3 -c 'import json, sys; print(json.dumps({"tool_input": {"command": sys.argv[1]}}))' "$ok")
    hook "$HK/template-$st/.claude/hooks/block-no-verify.sh" "$j"
    check 0 "$RC" "[$st] '$ok' stays allowed"
  done
  bash_msg $st 'rm -rf src' 'Confirm with a human first' 'recursive rm of src'
  j=$(python3 -c 'import json; print(json.dumps({"tool_input": {"command": "cat .env.example"}}))')
  hook "$HK/template-$st/.claude/hooks/block-no-verify.sh" "$j"
  check 0 "$RC" "[$st] reading .env.example stays allowed"
  j=$(python3 -c 'import json; print(json.dumps({"tool_input": {"command": "git status"}}))')
  hook "$HK/template-$st/.claude/hooks/block-no-verify.sh" "$j"
  check 0 "$RC" "[$st] a plain git command passes"
done

prot_msg() { # prot_msg <stack> <path> <expected text> <label>
  local j
  j=$(python3 -c 'import json, sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$hookrepo/$2")
  hook "$HK/template-$1/.claude/hooks/protect-files.sh" "$j"
  has "$3" "$OUT" "[$1] $4 message"
}
for st in ts py; do
  prot_msg $st AGENTS.md 'Human approval needed' 'instruction file'
  prot_msg $st vitest.config.ts 'a lower threshold or a wider exclude hides untested' 'coverage config'
  prot_msg $st scripts/check-workarounds.sh 'workaround or secret-scan gate' 'workaround gate script'
  prot_msg $st "$ENVF" 'Add placeholders to .env.example' 'env file write'
  prot_msg $st secrets/x.txt 'secrets directory' 'secrets directory write'
  j=$(python3 -c 'import json, sys; print(json.dumps({"tool_input": {"file_path": sys.argv[1]}}))' "$hookrepo/src/ok.ts")
  hook "$HK/template-$st/.claude/hooks/protect-files.sh" "$j"
  check 0 "$RC" "[$st] an ordinary source file passes protect-files"
done

echo "seeded-gates: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
