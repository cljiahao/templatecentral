#!/usr/bin/env bash
# scripts/gate-ratchet.test.sh — tests for the seeded scripts/gate-ratchet.sh against the real seeded configs.
# Usage: bash scripts/gate-ratchet.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
RATCHET="$SH/template/scripts/gate-ratchet.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/gr.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

git_() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# seed <stack>: a repo holding the seeded gate config of one stack, committed on main.
seed() {
  R="$T/$1"
  rm -rf "$R"
  mkdir -p "$R/.claude" "$R/scripts" "$R/.github/workflows"
  cp "$SH/template/.claude/gates.txt" "$R/.claude/gates.txt"
  cp "$SH/template/scripts/test-budget.sh" "$R/scripts/test-budget.sh"
  cp "$SH/template/.gitleaks.toml" "$R/.gitleaks.toml"
  if [[ "$1" == ts ]]; then
    cp "$SH/../nestjs/template/eslint.config.mjs" "$SH/../nestjs/template/vitest.config.ts" "$R/"
    cp "$SH/template-ts/.jscpd.json" "$R/.jscpd.json"
    cp "$SH/template-ci/github-ts/.github/workflows/ci.yml" "$R/.github/workflows/ci.yml"
    python3 - "$R/vitest.config.ts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("      include: ['src/**/*.ts'],", "      include: ['src/**/*.ts'],\n      thresholds: { lines: 80, branches: 70 },", 1)
open(p, "w").write(s)
PY
  else
    cp "$SH/../fastapi/template/pyproject.toml" "$R/pyproject.toml"
    cp "$SH/template-py/.jscpd.json" "$R/.jscpd.json"
    cp "$SH/template-ci/github-py/.github/workflows/ci.yml" "$R/.github/workflows/ci.yml"
    printf '\n[tool.coverage.report]\nfail_under = 80\n' >> "$R/pyproject.toml"
  fi
  git -C "$R" init -q -b main
  git_ add -A
  git_ commit -q -m base
}

# edit <file> <old> <new>: literal replace in the working tree, then commit on a branch off main.
edit() {
  git_ checkout -q -B work main
  python3 - "$R/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit("fixture text not found: " + old)
open(p, "w").write(s.replace(old, new, 1))
PY
  git_ commit -q -am work
}

# ratchet: sets OUT and EC from running the script on the current branch against main.
ratchet() {
  OUT=$(cd "$R" && bash "$RATCHET" main 2>&1)
  EC=$?
}

# weakens <file> <old> <new> <fragments...>: the edit must exit 1 and name the file, old and new values.
weakens() {
  local file=$1 old=$2 new=$3 label=$4 frag
  shift 4
  edit "$file" "$old" "$new"
  ratchet
  check 1 "$EC" "$label: exits 1 ($OUT)"
  has "$file" "$OUT" "$label: names the file"
  for frag in "$@"; do has "$frag" "$OUT" "$label: reports $frag"; done
}

# passes <file> <old> <new> <label>: a tightening or unrelated edit must exit 0.
passes() {
  edit "$1" "$2" "$3"
  ratchet
  check 0 "$EC" "$4: exits 0 ($OUT)"
}

seed ts
ratchet
check 0 "$EC" "unchanged branch passes ($OUT)"
git_ checkout -q -B work main
ratchet
check 0 "$EC" "branch equal to main passes ($OUT)"

weakens eslint.config.mjs "['error', 15]" "['error', 25]" "complexity limit raised" "was 15" "now 25"
weakens eslint.config.mjs "['error', 15]" "['warn', 15]" "complexity severity downgraded" "was error" "now warn"
weakens eslint.config.mjs "'sonarjs/no-commented-code': 'error'" "'sonarjs/no-commented-code': 'off'" "rule turned off" "sonarjs/no-commented-code" "was error" "now off"
weakens eslint.config.mjs "      'sonarjs/no-commented-code': 'error',
" "" "rule removed" "sonarjs/no-commented-code" "now removed"
weakens eslint.config.mjs "'sonarjs/todo-tag': 'warn'" "'sonarjs/todo-tag': 'off'" "warn lowered to off" "sonarjs/todo-tag" "now off"
weakens eslint.config.mjs "ignores: ['eslint.config.mjs'," "ignores: ['src/legacy/**', 'eslint.config.mjs'," "new eslint ignore" "src/legacy/**"
weakens eslint.config.mjs "  eslint.configs.recommended,
" "" "eslint preset dropped" "eslint.configs.recommended"
weakens vitest.config.ts "lines: 80" "lines: 60" "coverage threshold lowered" "was 80" "now 60"
weakens vitest.config.ts "branches: 70" "branches: 0" "branch threshold zeroed" "was 70" "now 0"
weakens vitest.config.ts "exclude: ['**/*.{test,spec}.ts'," "exclude: ['src/big/**', '**/*.{test,spec}.ts'," "new coverage exclude" "src/big/**"
weakens vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "" "coverage thresholds removed" "coverage-lines" "now removed"
weakens .jscpd.json '"threshold": 3' '"threshold": 5' "duplication limit raised" "was 3" "now 5"
weakens .jscpd.json '"ignore": [' '"ignore": ["src/gen/**", ' "new jscpd ignore" "src/gen/**"
weakens .gitleaks.toml "'''\\.env\\.example\$''',
" "'''\\.env\\.example\$''',
  '''fixtures/.*''',
" "new gitleaks allowlist path" "fixtures/.*"
weakens .gitleaks.toml "useDefault = true" "useDefault = false" "gitleaks default rules off" "useDefault"
weakens .claude/gates.txt "deps|-|ci-gates.sh deps
" "" "gate removed from the manifest" "gate 'deps'" "now removed"
weakens .claude/gates.txt "secrets|gitleaks|ci-gates.sh secrets" "secrets|-|ci-gates.sh secrets" "gate dropped from lefthook" "gate-in-lefthook" "secrets"
weakens scripts/test-budget.sh "TEST_BUDGET_MAX_RATIO-35}" "TEST_BUDGET_MAX_RATIO-50}" "test ratio raised" "was 35" "now 50"
weakens .github/workflows/ci.yml "--fail-under=80" "--fail-under=50" "diff coverage lowered" "was 80" "now 50"

edit .jscpd.json '"threshold": 3' '"threshold": 2'
git_ rm -q .jscpd.json
git_ commit -q -m "drop jscpd"
ratchet
check 1 "$EC" "deleted config file: exits 1 ($OUT)"
has ".jscpd.json" "$OUT" "deleted config file: names it"

passes eslint.config.mjs "['error', 15]" "['error', 10]" "complexity limit lowered"
passes .jscpd.json '"threshold": 3' '"threshold": 2' "duplication limit lowered"
passes vitest.config.ts "lines: 80" "lines: 90" "coverage threshold raised"
passes scripts/test-budget.sh "TEST_BUDGET_MAX_RATIO-35}" "TEST_BUDGET_MAX_RATIO-30}" "test ratio lowered"
passes .github/workflows/ci.yml "--fail-under=80" "--fail-under=90" "diff coverage raised"
passes eslint.config.mjs "'sonarjs/todo-tag': 'warn'" "'sonarjs/todo-tag': 'error'" "rule upgraded"
passes eslint.config.mjs "      'sonarjs/no-commented-code': 'error'," "      'sonarjs/no-commented-code': 'error',
      'no-debugger': 'error'," "rule added"
passes eslint.config.mjs "// @ts-check" "// @ts-check
// ignores: ['src/commented/**']" "ignore inside a comment"
passes .gitleaks.toml "description = \"Known non-secrets\"" "description = \"Known non-secrets and lockfiles\"" "gitleaks description edit"
passes .claude/gates.txt "secrets|gitleaks|ci-gates.sh secrets" "secrets|gitleaks|ci-gates.sh secrets
extra|-|ci-gates.sh extra" "gate added"

edit eslint.config.mjs "ignores: ['eslint.config.mjs'," "ignores: ['eslint.config.mjs"
ratchet
check 2 "$EC" "broken eslint config: exits 2 ($OUT)"
has "UNREADABLE eslint.config.mjs" "$OUT" "broken eslint config: names the file"
edit .jscpd.json '"threshold": 3,' ''
ratchet
check 2 "$EC" "jscpd without a threshold: exits 2 ($OUT)"
edit .claude/gates.txt "deps|-|ci-gates.sh deps" "deps broken"
ratchet
check 2 "$EC" "malformed gate line: exits 2 ($OUT)"
has "three | separated fields" "$OUT" "malformed gate line: says why"
edit .gitleaks.toml "paths = [" "paths = [ '''x"
ratchet
check 2 "$EC" "gitleaks unterminated string: exits 2 ($OUT)"
has "UNREADABLE .gitleaks.toml" "$OUT" "gitleaks unterminated string: names the file"

OUT=$(cd "$R" && bash "$RATCHET" no-such-ref 2>&1)
check 2 "$?" "unknown base ref: exits 2 ($OUT)"
OUT=$(cd "$R" && bash "$RATCHET" 2>&1)
check 2 "$?" "missing argument: exits 2 ($OUT)"
OUT=$(cd "$T" && bash "$RATCHET" main 2>&1)
check 2 "$?" "outside a git repository: exits 2 ($OUT)"

seed py
git_ checkout -q -B work main
ratchet
check 0 "$EC" "python: branch equal to main passes ($OUT)"
weakens pyproject.toml "max-complexity = 15" "max-complexity = 20" "ruff complexity raised" "was 15" "now 20"
weakens pyproject.toml "max-args = 7" "max-args = 9" "ruff max-args raised" "was 7" "now 9"
weakens pyproject.toml '  "ERA", ' '  ' "ruff rule dropped from select" "'ERA'"
weakens pyproject.toml '"test/**/*.py" = ["S101", "S105"]' '"test/**/*.py" = ["S101", "S105", "S106"]' "ruff per-file ignore widened" "S106"
weakens pyproject.toml '"test/**/*.py" = ["S101", "S105"]' '"test/**/*.py" = ["S101", "S105"]
"src/**/*.py" = ["S608"]' "ruff per-file ignore added" "S608"
weakens pyproject.toml "[tool.ruff.lint]
" "[tool.ruff.lint]
ignore = [\"E501\"]
" "ruff ignore added" "E501"
weakens pyproject.toml "fail_under = 80" "fail_under = 70" "python coverage threshold lowered" "was 80" "now 70"
weakens .jscpd.json '"threshold": 3' '"threshold": 9' "python duplication limit raised" "was 3" "now 9"
passes pyproject.toml "max-complexity = 15" "max-complexity = 12" "ruff complexity lowered"
passes pyproject.toml "fail_under = 80" "fail_under = 85" "python coverage raised"
passes pyproject.toml "line-length = 88" "line-length = 100" "line length edit"
git_ checkout -q -B work main
sed -i.bak 's/tool[.]ruff/tool.rff/g' "$R/pyproject.toml" && rm -f "$R/pyproject.toml.bak"
git_ commit -q -am rename
ratchet
check 2 "$EC" "pyproject without [tool.ruff]: exits 2 ($OUT)"

echo "gate-ratchet.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
