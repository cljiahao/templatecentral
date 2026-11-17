#!/usr/bin/env bash
# scripts/measure-outcomes.test.sh — tests for scripts/measure-outcomes.sh.
# Usage: bash scripts/measure-outcomes.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/measure-outcomes.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/measure-outcomes.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

# fixture: a minimal repo with the four stack templates and both CI template families
mk() {
  local r=$1 s
  for s in fastapi nestjs nextjs vite-react; do
    mkdir -p "$r/skills/scaffold/$s/template/src" "$r/skills/scaffold/$s/template/test"
  done
  printf 'def f():\n    return 1\n' > "$r/skills/scaffold/fastapi/template/src/a.py"
  printf 'from src.a import f\n\n\ndef test_f():\n    assert f() == 1\n' > "$r/skills/scaffold/fastapi/template/test/test_a.py"
  for s in nestjs nextjs vite-react; do
    printf 'export const a = 1;\n' > "$r/skills/scaffold/$s/template/src/a.ts"
    printf "it('a', () => {});\n" > "$r/skills/scaffold/$s/template/test/a.test.ts"
  done
  for d in github-ts azure-ts github-py azure-py; do
    mkdir -p "$r/skills/scaffold/shared/template-ci/$d"
    echo 'run: pipx run diff-cover c.xml --fail-under=80' > "$r/skills/scaffold/shared/template-ci/$d/ci.yml"
  done
}

mk "$TMP/ok"
out=$(bash "$MEASURE" "$TMP/ok" 2>&1); check 0 $? "clean fixture passes"
case "$out" in *"== nextjs =="*"OK: all outcome metrics"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: one table per stack"; esac

# suppressions over the limit fail
mk "$TMP/supp"
printf '// @ts-expect-error x\n// eslint-disable-next-line\nconst b = 1; // NOSONAR\n' >> "$TMP/supp/skills/scaffold/nestjs/template/src/a.ts"
out=$(MO_MAX_SUPPRESSIONS=2 bash "$MEASURE" "$TMP/supp" 2>&1); check 1 $? "suppressions over limit fail"
case "$out" in *"nestjs: suppressions"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: names the stack and metric"; esac

# comment noise: multi-line and parenthetical comments are counted
mk "$TMP/cm"
printf '// one (two)\n// three\nconst c = 2;\n' >> "$TMP/cm/skills/scaffold/vite-react/template/src/a.ts"
out=$(MO_MAX_MULTILINE=0 MO_MAX_PAREN=0 bash "$MEASURE" "$TMP/cm" 2>&1); check 1 $? "comment limits fail"
case "$out" in *"vite-react: multi-line comments 1.00"*"vite-react: parenthetical comments 1.00"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: comment counts"; esac

# CI: missing 80% gate fails; missing parallel only fails when required
mk "$TMP/ci"
echo 'run: pnpm test' > "$TMP/ci/skills/scaffold/shared/template-ci/github-ts/ci.yml"
bash "$MEASURE" "$TMP/ci" >/dev/null 2>&1; check 1 $? "missing diff-cover gate fails"
bash "$MEASURE" "$TMP/ok" >/dev/null 2>&1; check 0 $? "no parallel setting passes by default"
MO_REQUIRE_PARALLEL=1 bash "$MEASURE" "$TMP/ok" >/dev/null 2>&1; check 1 $? "no parallel setting fails when required"
printf 'strategy:\n  matrix:\n    shard: [1, 2]\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/github-ts/ci.yml"
printf 'run: pytest -n auto\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/github-py/ci.yml"
printf 'run: vitest --shard=1/2\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/azure-ts/ci.yml"
printf 'run: pytest -n 4\n' >> "$TMP/ok/skills/scaffold/shared/template-ci/azure-py/ci.yml"
MO_REQUIRE_PARALLEL=1 bash "$MEASURE" "$TMP/ok" >/dev/null 2>&1; check 0 $? "shard and xdist settings are detected"

# bad root is a usage error
bash "$MEASURE" "$TMP/nope" >/dev/null 2>&1; check 2 $? "missing scaffold dir exits 2"

# the real repo passes today
bash "$MEASURE" >/dev/null 2>&1; check 0 $? "repo templates within thresholds"

echo "measure-outcomes.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
