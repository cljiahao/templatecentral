#!/usr/bin/env bash
# scripts/measure-outcomes.test.sh — tests for scripts/measure-outcomes.sh.
# Usage: bash scripts/measure-outcomes.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/measure-outcomes.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/measure-outcomes.XXXXXX") || exit 1
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <haystack> <needle> <description>
  case "$1" in *"$2"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: $3 — missing [$2]"; esac
}
lacks() { # lacks <haystack> <needle> <description>
  case "$1" in *"$2"*) FAIL=$((FAIL + 1)); echo "FAIL: $3 — unexpected [$2]" ;; *) PASS=$((PASS + 1)) ;; esac
}

# template-mode fixture: four stack templates, both CI families, ~20 test LOC per 100 source LOC
mk() {
  local r=$1 s i
  for s in fastapi nestjs nextjs vite-react; do
    mkdir -p "$r/skills/scaffold/$s/template/src" "$r/skills/scaffold/$s/template/test"
  done
  for i in 1 2 3 4 5; do printf 'def f%s():\n    return 1\n' "$i"; done > "$r/skills/scaffold/fastapi/template/src/a.py"
  printf 'from src.a import f1\n\n\ndef test_f():\n    assert f1() == 1\n' > "$r/skills/scaffold/fastapi/template/test/test_a.py"
  for s in nestjs nextjs vite-react; do
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do printf 'export const a%s = %s;\n' "$i" "$i"; done > "$r/skills/scaffold/$s/template/src/a.ts"
    printf "it('a', () => {\n  expect(1).toBe(1);\n});\n" > "$r/skills/scaffold/$s/template/test/a.test.ts"
  done
  for d in github-ts azure-ts github-py azure-py; do
    mkdir -p "$r/skills/scaffold/shared/template-ci/$d"
    echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$r/skills/scaffold/shared/template-ci/$d/ci.yml"
  done
}
tm() { MO_REPO_ROOT="$1" bash "$MEASURE" 2>&1; }

mk "$TMP/ok"
out=$(tm "$TMP/ok"); check 0 $? "clean fixture passes"
has "$out" "== nextjs ==" "one table per stack"
has "$out" "Not measured here: cognitive complexity, duplication, coverage" "header states what is not measured"
has "$out" "Sonar: no sonar-project.properties found" "missing Sonar file is stated, not counted as 0"

# suppressions: counted in code files, not in docs/config text
mk "$TMP/supp"
printf '// @ts-expect-error x\n// eslint-disable-next-line\nconst b = 1; // NOSONAR\n' >> "$TMP/supp/skills/scaffold/nestjs/template/src/a.ts"
out=$(MO_REPO_ROOT="$TMP/supp" MO_MAX_SUPPRESSIONS=2 bash "$MEASURE" 2>&1); check 1 $? "suppressions over limit fail"
has "$out" "nestjs: suppressions" "names the stack and metric"
mk "$TMP/supp2"
printf '# noqa eslint-disable NOSONAR\n' > "$TMP/supp2/skills/scaffold/nestjs/template/NOTES.md"
out=$(MO_REPO_ROOT="$TMP/supp2" MO_MAX_SUPPRESSIONS=0 bash "$MEASURE" 2>&1); check 0 $? "suppression words in non-code files are ignored"

# comments: multi-line runs, parenthetical, trailing, blank line resets the run
mk "$TMP/cm"
printf '// one (two)\n// three\nconst c = 2;\n' >> "$TMP/cm/skills/scaffold/vite-react/template/src/a.ts"
out=$(MO_REPO_ROOT="$TMP/cm" MO_MAX_MULTILINE=0 MO_MAX_PAREN=0 bash "$MEASURE" 2>&1); check 1 $? "comment limits fail"
has "$out" "vite-react: multi-line comments 1.00" "multi-line run counted"
has "$out" "vite-react: parenthetical comments 1.00" "parenthetical counted"
mk "$TMP/blank"
printf '// one\n\n// two\n\n// three\nconst c = 2;\n' >> "$TMP/blank/skills/scaffold/vite-react/template/src/a.ts"
out=$(MO_REPO_ROOT="$TMP/blank" MO_MAX_MULTILINE=0 bash "$MEASURE" 2>&1); check 0 $? "blank lines reset the comment run"
mk "$TMP/trail"
printf 'const u = "http://x.test"; // why\nconst v = 3; // again\nconst w = "a // not a comment";\n' >> "$TMP/trail/skills/scaffold/vite-react/template/src/a.ts"
out=$(MO_REPO_ROOT="$TMP/trail" MO_MAX_TRAILING=1 bash "$MEASURE" 2>&1); check 1 $? "trailing comments over limit fail"
has "$out" "vite-react: trailing inline comments 2.00" "trailing comments outside quotes counted"
printf 'x = 1  # why\ny = "#no"\n' >> "$TMP/trail/skills/scaffold/fastapi/template/src/a.py"
out=$(MO_REPO_ROOT="$TMP/trail" MO_MAX_TRAILING=0 bash "$MEASURE" 2>&1)
has "$out" "fastapi: trailing inline comments 1.00" "python trailing comment counted"

# test cases: regex .test( is not a case; tagged it.each counts
mk "$TMP/tc"
printf "const ok = /x/.test('x');\nit.each\`a\`('n', () => {});\ntest.each([1])('t', () => {});\n" >> "$TMP/tc/skills/scaffold/nextjs/template/test/a.test.ts"
out=$(tm "$TMP/tc"); has "$out" "test cases 3" "it, it.each tagged and test.each counted; /x/.test not"

# test band: no tests fails; oversized suite fails
mk "$TMP/notest"
rm "$TMP/notest/skills/scaffold/nestjs/template/test/a.test.ts"
out=$(tm "$TMP/notest"); check 1 $? "no tests fails"
has "$out" "nestjs: test cases 0.00 < 1" "zero test cases named"
mk "$TMP/big"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf "it('n%s', () => {\n  expect(1).toBe(1);\n});\n" "$i"; done >> "$TMP/big/skills/scaffold/nestjs/template/test/a.test.ts"
out=$(tm "$TMP/big"); check 1 $? "oversized suite fails the ceiling"
has "$out" "nestjs: test LOC per 100 src LOC" "ratio ceiling named"

# CI: missing 80% gate fails; missing parallel only fails when required
mk "$TMP/ci"
echo 'run: pnpm test' > "$TMP/ci/skills/scaffold/shared/template-ci/github-ts/ci.yml"
tm "$TMP/ci" >/dev/null; check 1 $? "missing diff-cover gate fails"
MO_REQUIRE_PARALLEL=1 tm "$TMP/ok" >/dev/null; check 1 $? "no parallel setting fails when required"
printf 'strategy:\n  matrix:\n    shard: [1, 2]\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/github-ts/ci.yml"
printf 'run: pytest -n auto\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/github-py/ci.yml"
printf 'run: vitest --shard=1/2\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/azure-ts/ci.yml"
printf 'run: pytest -n 4\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/azure-py/ci.yml"
MO_REQUIRE_PARALLEL=1 tm "$TMP/ok" >/dev/null; check 0 $? "shard and xdist settings are detected"

# project mode
P="$TMP/proj"
mkdir -p "$P/src" "$P/test" "$P/node_modules/x" "$P/build"
echo '{}' > "$P/next.config.ts"
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'export const a%s = %s;\n' "$i" "$i"; done > "$P/src/a.ts"
printf "it('a', () => {\n  expect(1).toBe(1);\n});\n" > "$P/test/a.test.ts"
printf '// eslint-disable\n' > "$P/node_modules/x/i.ts"
printf '// eslint-disable\n' > "$P/build/o.ts"
out=$(bash "$MEASURE" "$P" 2>&1); check 1 $? "project without a CI coverage gate is a hard failure"
has "$out" "no CI file enforces the coverage gate" "missing gate named"
mkdir -p "$P/.github/workflows"
echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$P/.github/workflows/ci.yml"
out=$(bash "$MEASURE" "$P" 2>&1); check 0 $? "project with tests and a gate passes"
has "$out" "== nextjs (.) ==" "stack detected from project files"
has "$out" "found in .github/workflows/ci.yml" "gate file named"
MO_MAX_SUPPRESSIONS=0 bash "$MEASURE" "$P" >/dev/null 2>&1; check 0 $? "node_modules and build skipped"
printf 'sonar.exclusions=**/gen/**, **/*.d.ts\nsonar.coverage.exclusions=src/main.ts \\\n  ,src/boot.ts\nsonar.cpd.exclusions=**/*.test.ts\n' > "$P/sonar-project.properties"
out=$(bash "$MEASURE" "$P" 2>&1)
has "$out" "sonar.exclusions 2: **/gen/**, **/*.d.ts" "Sonar exclusions listed by key"
has "$out" "sonar.coverage.exclusions 2: src/main.ts, src/boot.ts" "continuation lines joined"
has "$out" "sonar.cpd.exclusions 1" "cpd exclusions listed"
printf 'export const z = 1;\n' > "$P/src/ignored.ts"; : > "$P/.gitignore"
mkdir -p "$P/backend"
git -C "$P" init -q 2>/dev/null && { printf 'src/ignored.ts\n' > "$P/.gitignore"
  out=$(bash "$MEASURE" "$P" 2>&1); has "$out" "source files 1," ".gitignore honoured in a git work tree"; }
rm -rf "$P/test"
bash "$MEASURE" "$P" >/dev/null 2>&1; check 1 $? "project without tests fails"

# project mode is a report: out-of-reference values WARN, exit code unaffected
R="$TMP/rep"; mkdir -p "$R/src" "$R/test" "$R/.github/workflows"
echo '{}' > "$R/next.config.ts"
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'export const a%s = %s; // x\n' "$i" "$i"; done > "$R/src/a.ts"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do printf "it('t%s', () => {\n  expect(1).toBe(1);\n});\n" "$i"; done > "$R/test/a.test.ts"
echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$R/.github/workflows/ci.yml"
out=$(bash "$MEASURE" "$R" 2>&1); check 0 $? "WARN values do not fail a project"
has "$out" "WARN" "values outside the reference are marked"
has "$out" "consolidate duplicate tests, not to delete coverage" "high ratio explained"
has "$out" "OK: no hard failure" "report ends OK"

# gate in one of many CI files is enough; the file is named
mkdir -p "$R/.claude/hooks" "$R/.claude/.harness-base"
echo 'run: x' > "$R/.github/workflows/lint.yml"; echo 'run: y' > "$R/.github/workflows/build.yml"
out=$(bash "$MEASURE" "$R" 2>&1); check 0 $? "gate in one of several CI files passes"
has "$out" "found in .github/workflows/ci.yml" "only the file with the gate is named"
printf '// eslint-disable\n' > "$R/.claude/hooks/h.ts"; printf '// eslint-disable\n' > "$R/.claude/.harness-base/b.ts"
out=$(MO_MAX_SUPPRESSIONS=0 bash "$MEASURE" "$R" 2>&1); lacks "$out" "suppressions                  1.00" ".claude/hooks and .harness-base are not scanned"

# mixed-language project: each app counted in its own language only
M="$TMP/mixed"; mkdir -p "$M/backend/src/static" "$M/backend/test" "$M/web/src" "$M/web/test" "$M/.github/workflows"
echo 'fastapi' > "$M/backend/requirements.txt"; echo '{}' > "$M/web/next.config.ts"
for i in 1 2 3 4 5; do printf 'def f%s():\n    return 1\n' "$i"; done > "$M/backend/src/a.py"
for i in $(seq 1 50); do printf 'var a%s = 1;\n' "$i"; done > "$M/backend/src/static/app.js"
printf 'def test_a():\n    assert True\n' > "$M/backend/test/test_a.py"
for i in 1 2 3; do printf 'export const w%s = 1;\n' "$i"; done > "$M/web/src/a.ts"
printf 'def not_counted():\n    pass\n' > "$M/web/src/x.py"
printf "it('w', () => {\n  expect(1).toBe(1);\n});\n" > "$M/web/test/a.test.ts"
echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$M/.github/workflows/ci.yml"
out=$(bash "$MEASURE" "$M" 2>&1); check 0 $? "mixed project passes"
has "$out" "== fastapi (backend) ==" "python app reported on its own"
has "$out" "== nextjs (web) ==" "ts app reported on its own"
has "$out" "source files 1, source LOC 10," "python app ignores .js files"
has "$out" "source files 1, source LOC 3," "ts app ignores .py files"

# hard failure: zero test cases
Z="$TMP/zero"; mkdir -p "$Z/src" "$Z/.github/workflows"; echo '{}' > "$Z/next.config.ts"; echo 'export const a = 1;' > "$Z/src/a.ts"
echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$Z/.github/workflows/ci.yml"
out=$(bash "$MEASURE" "$Z" 2>&1); check 1 $? "zero test cases is a hard failure"
has "$out" "zero test cases" "reason named"

# --baseline then --compare ratchet
B="$TMP/rat"; cp -R "$R" "$B"; rm -rf "$B/.claude"
bash "$MEASURE" --baseline "$TMP/base.txt" "$B" >/dev/null 2>&1; check 0 $? "--baseline writes and exits 0"
has "$(cat "$TMP/base.txt")" "nextjs@root.suppressions=0" "baseline is plain key=value"
has "$(cat "$TMP/base.txt")" "project.coverage_gate=1" "gate recorded"
out=$(bash "$MEASURE" --compare "$TMP/base.txt" "$B" 2>&1); check 0 $? "--compare passes when nothing got worse"
printf 'export const s = 1; // eslint-disable-line\n' >> "$B/src/a.ts"
out=$(bash "$MEASURE" --compare "$TMP/base.txt" "$B" 2>&1); check 1 $? "--compare fails when suppressions rise"
has "$out" "ratchet: nextjs@root.suppressions" "regression named"
cp -R "$R" "$TMP/rat2"; rm -rf "$TMP/rat2/.claude"
printf '// a\n// b\n\nconst k = 1;\n' >> "$TMP/rat2/src/a.ts"
bash "$MEASURE" --compare "$TMP/base.txt" "$TMP/rat2" >/dev/null 2>&1; check 1 $? "--compare fails when comment blocks rise"
rm -rf "$TMP/rat3"; cp -R "$R" "$TMP/rat3"; rm -rf "$TMP/rat3/.claude" "$TMP/rat3/.github"
bash "$MEASURE" --compare "$TMP/base.txt" "$TMP/rat3" >/dev/null 2>&1; check 1 $? "--compare fails when the coverage gate disappears"
# baseline without a gate: unchanged compare passes with a WARN; baseline with a gate then removal fails
NG="$TMP/nogate"; cp -R "$R" "$NG"; rm -rf "$NG/.claude" "$NG/.github"
bash "$MEASURE" --baseline "$TMP/ng.txt" "$NG" >/dev/null 2>&1; check 1 $? "--baseline run keeps exit 1 for a project with no gate"
has "$(cat "$TMP/ng.txt")" "project.coverage_gate=0" "gate 0 recorded"
out=$(bash "$MEASURE" --compare "$TMP/ng.txt" "$NG" 2>&1); check 0 $? "unchanged compare with baseline gate 0 passes"
has "$out" "WARN: no CI file enforces the coverage gate" "missing gate stays a WARN"
bash "$MEASURE" "$NG" >/dev/null 2>&1; check 1 $? "plain run without a gate still fails"
# baseline from another stack: unmatched keys fail
printf 'fastapi@backend.suppressions=0\nproject.coverage_gate=1\n' > "$TMP/other.txt"
out=$(bash "$MEASURE" --compare "$TMP/other.txt" "$B" 2>&1); check 1 $? "baseline from another stack fails"
has "$out" "fastapi@backend.suppressions" "unmatched key named"
bash "$MEASURE" --compare "$TMP/missing.txt" "$B" >/dev/null 2>&1; check 2 $? "unreadable baseline exits 2"
bash "$MEASURE" --baseline "$TMP/x.txt" >/dev/null 2>&1; check 2 $? "--baseline without a project is a usage error"

# Sonar exclusions passed in the pipeline are reported with file:line
S="$TMP/sonarci"; cp -R "$R" "$S"; rm -rf "$S/.claude"
printf 'steps:\n  - script: sonar-scanner -Dsonar.exclusions=**/gen/**,**/*.d.ts -Dsonar.coverage.exclusions=src/main.ts\n  - task: SonarQubePrepare@5\n    inputs:\n      extraProperties: |\n        sonar.cpd.exclusions=**/*.test.ts\n' > "$S/azure-pipelines.yml"
out=$(bash "$MEASURE" "$S" 2>&1)
has "$out" "azure-pipelines.yml:2 sonar.exclusions: **/gen/**, **/*.d.ts" "-D exclusions listed with file:line"
has "$out" "azure-pipelines.yml:2 sonar.coverage.exclusions: src/main.ts" "second -D key on the same line"
has "$out" "azure-pipelines.yml:6 sonar.cpd.exclusions: **/*.test.ts" "extraProperties entry listed"
has "$out" "passed in CI: 4" "CI entries counted"
bash "$MEASURE" --baseline "$TMP/sb.txt" "$S" >/dev/null 2>&1
has "$(cat "$TMP/sb.txt")" "project.sonar_entries=4" "CI Sonar entries recorded in the baseline"

# TS test-case regex skips commented-out cases; it.each is one case
T2="$TMP/tcc"; mkdir -p "$T2/src" "$T2/test" "$T2/.github/workflows"; echo '{}' > "$T2/next.config.ts"; echo 'export const a = 1;' > "$T2/src/a.ts"
echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$T2/.github/workflows/ci.yml"
printf "// it('old', () => {});\n/* test('x', () => {}); */\nit.each([1, 2])('n %%s', () => {});\nit('real', () => {});\n" > "$T2/test/a.test.ts"
out=$(bash "$MEASURE" "$T2" 2>&1); has "$out" "test cases 2," "commented-out cases skipped, it.each is one"

# usage and crash exit codes
bash "$MEASURE" "$TMP/nope" >/dev/null 2>&1; check 2 $? "unusable path exits 2"
MO_REPO_ROOT="$TMP/nope" bash "$MEASURE" >/dev/null 2>&1; check 2 $? "template mode without scaffold dir exits 2"
mkdir -p "$TMP/crash/src"
echo '{}' > "$TMP/crash/next.config.ts"; echo 'export const a = 1;' > "$TMP/crash/src/a.ts"; chmod 000 "$TMP/crash/src/a.ts"
if [[ -r "$TMP/crash/src/a.ts" ]]; then echo "skip: crash test (files stay readable, running as root)"; else
  bash "$MEASURE" "$TMP/crash" >/dev/null 2>&1; check 2 $? "an internal error exits 2, not 1"
fi
lacks "$out" "Traceback" "no traceback on normal runs"

# the real templates pass today
bash "$MEASURE" >/dev/null 2>&1; check 0 $? "repo templates within thresholds"

echo "measure-outcomes.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
