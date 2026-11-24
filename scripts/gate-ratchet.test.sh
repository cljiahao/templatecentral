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
  cp "$RATCHET" "$R/scripts/gate-ratchet.sh"
  cp "$SH/template/scripts/check-docs.sh" "$R/scripts/check-docs.sh"
  cp "$SH/template/.claude/comment-hygiene-patterns.txt" "$R/.claude/comment-hygiene-patterns.txt"
  printf '# advisory allow-list\nGHSA-aaaa-bbbb-cccc 2099-01-01 reason\n' > "$R/.claude/dep-audit-allow.txt"
  printf '{}\n' > "$R/.claude/settings.json"
  cp "$SH/template/.claude/ci-gates.sh" "$SH/template/.claude/verify-harness.sh" "$R/.claude/"
  cp "$SH/template-$1/lefthook.yml" "$R/lefthook.yml"
  if [[ "$1" == ts ]]; then
    cp "$SH/../nestjs/template/eslint.config.mjs" "$R/" && cp "$SH/../nestjs/template/vitest.config.mts" "$R/vitest.config.ts"
    cp "$SH/template-ts/.jscpd.json" "$R/.jscpd.json"
    cp "$SH/template-ts/sonar-project.properties" "$R/sonar-project.properties"
    cp "$SH/../nestjs/template/package.json" "$R/package.json"
    cp "$SH/../nestjs/template/tsconfig.json" "$R/tsconfig.json"
    cp "$SH/../nestjs/template/pnpm-workspace.yaml" "$R/pnpm-workspace.yaml"
    cp "$SH/template/.claude/registry-hosts.txt" "$R/.claude/registry-hosts.txt"
    mkdir -p "$R/.github"
    cp "$SH/template-ci/github-ts/.github/dependabot.yml" "$R/.github/dependabot.yml"
    printf '# note\n' > "$R/.npmrc"
    printf '# note\n' > "$R/.hadolint.yaml"
    for sc in check-supply-chain check-workflows check-env-example check-dockerfile; do cp "$SH/template/scripts/$sc.sh" "$R/scripts/$sc.sh"; done
    cp "$SH/template-ci/github-ts/.github/workflows/ci.yml" "$R/.github/workflows/ci.yml"
    mkdir -p "$R/.claude/hooks" "$R/azure-pipelines"
    cp "$SH/template-ts/.claude/hooks/protect-files.sh" "$R/.claude/hooks/protect-files.sh"
    cp "$SH/template-ci/azure/azure-pipelines/templatecentral-gates.yml" "$R/azure-pipelines/templatecentral-gates.yml"
    cp "$SH/template-ci/azure-ts/azure-pipelines.yml" "$R/azure-pipelines.yml"
    python3 - "$R/vitest.config.ts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("thresholds: { lines: 80 },", "thresholds: { lines: 80, branches: 70 },", 1)
open(p, "w").write(s)
PY
  else
    cp "$SH/../fastapi/template/pyproject.toml" "$R/pyproject.toml"
    cp "$SH/../fastapi/template/pyrightconfig.json" "$R/pyrightconfig.json"
    cp "$SH/template-py/.jscpd.json" "$R/.jscpd.json"
    cp "$SH/template-py/sonar-project.properties" "$R/sonar-project.properties"
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

# edit_more <file> <old> <new>: like edit, but stacks on the current branch.
edit_more() {
  python3 - "$R/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit("fixture text not found: " + old)
open(p, "w").write(s.replace(old, new, 1))
PY
  git_ commit -q -am more
}

# ci_gate <labels>: sets OUT and EC from the CI entry point on the current branch against main.
ci_gate() {
  git_ update-ref refs/remotes/origin/main main
  OUT=$(cd "$R" && LABELS="$1" bash .claude/ci-gates.sh ratchet main 2>&1)
  EC=$?
}

# run_step <gh|az> <base branch>: sets OUT and EC from the seeded CI ratchet step script, run in the current repo.
run_step() {
  mkdir -p "$T/rt"
  rm -f "$T/rt"/*
  git_ update-ref refs/remotes/origin/main main
  OUT=$(cd "$R" && BASE_REF="$2" SYSTEM_PULLREQUEST_TARGETBRANCH="refs/heads/$2" RUNNER_TEMP="$T/rt" AGENT_TEMPDIRECTORY="$T/rt" LABELS="" bash "$T/step-$1.sh" 2>&1)
  EC=$?
  LEFT=$(find "$T/rt" -type f | wc -l | tr -d ' ')
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

# drop <file>: delete a tracked file on a branch off main.
drop() {
  git_ checkout -q -B work main
  git_ rm -q "$1"
  git_ commit -q -m drop
}

# passes <file> <old> <new> <label>: a tightening or unrelated edit must exit 0.
passes() {
  edit "$1" "$2" "$3"
  ratchet
  check 0 "$EC" "$4: exits 0 ($OUT)"
}

# add_file <path> <content>: a new file on a branch off main.
add_file() {
  git_ checkout -q -B work main
  mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$2" > "$R/$1"
  git_ add -A
  git_ commit -q -m add
}

# expect <exit code> <label> <fragments...>: run the ratchet on the current branch and check its exit code and output.
expect() {
  local want=$1 label=$2 frag
  shift 2
  ratchet
  check "$want" "$EC" "$label: exits $want ($OUT)"
  for frag in "$@"; do has "$frag" "$OUT" "$label: reports $frag"; done
}

NEWSHA=$(printf 'a%.0s' {1..40})
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

weakens scripts/gate-ratchet.sh "set -uo pipefail" "set -uo pipefail
exit 0" "ratchet script replaced by exit 0" "gate script, runner or manifest changed"
weakens scripts/test-budget.sh "#!/usr/bin/env bash
" "#!/usr/bin/env bash
exit 0
" "exit 0 injected into the test budget" "gate script, runner or manifest changed"
weakens scripts/test-budget.sh "#!/usr/bin/env bash
" "#!/usr/bin/env bash
TEST_BUDGET_MAX_RATIO=9999
" "ratio forced by assignment" "gate script, runner or manifest changed"
weakens .github/workflows/ci.yml "runs-on: ubuntu-latest" "runs-on: ubuntu-latest
    if: false" "CI job disabled" "gate script, runner or manifest changed"
weakens .github/workflows/ci.yml "runs-on: ubuntu-latest" "runs-on: ubuntu-latest
    continue-on-error: true" "CI job may fail" "gate script, runner or manifest changed"
weakens .claude/gates.txt "ratchet|scripts/gate-ratchet.sh|ci-gates.sh ratchet" "ratchet|scripts/gate-ratchet.sh|ratchet" "gate needle rewritten" "gate script, runner or manifest changed"
weakens .claude/ci-gates.sh "set -uo pipefail" "set -uo pipefail
exit 0" "ci-gates changed" "gate script, runner or manifest changed"
weakens .claude/verify-harness.sh "set -euo pipefail" "set -euo pipefail
exit 0" "verify-harness changed" "gate script, runner or manifest changed"
weakens lefthook.yml "parallel: false" "parallel: true" "lefthook changed" "gate script, runner or manifest changed"

add_file eslint.config.js "export default [];"
expect 1 "second eslint config" "eslint.config.js" "competes"
add_file vitest.config.mts "export default {};"
expect 1 "second vitest config" "vitest.config.mts" "competes"
add_file vite.config.js "export default {};"
expect 1 "vite config competes with vitest config" "vite.config.js" "competes"
add_file jest.config.js "module.exports = {};"
expect 0 "first jest config in a repo without one"
add_file .gitleaksignore "abc"
expect 1 ".gitleaksignore" ".gitleaksignore" "competes"
add_file .eslintignore "src"
expect 1 ".eslintignore" ".eslintignore" "competes"
add_file jscpd.json '{ "threshold": 99 }'
expect 1 "jscpd.json variant" "jscpd.json" "competes"
add_file .jscpdrc '{ "threshold": 99 }'
expect 1 ".jscpdrc variant" ".jscpdrc" "competes"
git_ checkout -q -B work main
git_ mv eslint.config.mjs eslint.config.js
git_ commit -q -m rename
expect 1 "eslint config renamed" "eslint.config.mjs" "renamed to eslint.config.js"

weakens eslint.config.mjs "  {
    // Test fixtures" "  {
    rules: { 'sonarjs/no-hardcoded-secrets': 'off' },
  },
  {
    // Test fixtures" "global rule off while a test override already has it off" "sonarjs/no-hardcoded-secrets" "is off"
weakens eslint.config.mjs "// @ts-check" "/* eslint-disable */" "file-level eslint-disable in the config" "eslint-disable-comments" "now 1"
weakens eslint.config.mjs "      'sonarjs/todo-tag': 'warn'," "      'sonarjs/todo-tag': 'warn',
      'sonarjs/cognitive-complexity': 'off'," "second global entry turns a rule off" "sonarjs/cognitive-complexity"
weakens eslint.config.mjs "'sonarjs/no-clear-text-protocols': 'off'," "'sonarjs/no-clear-text-protocols': 'off',
      'sonarjs/no-commented-code': 'warn'," "new scoped block lowers a rule below the base" "sonarjs/no-commented-code"
weakens vitest.config.ts "include: ['src/**/*.ts']," "include: ['src/app/**/*.ts']," "coverage include narrowed" "src/**/*.ts" "now removed"
weakens .jscpd.json '"threshold": 3' '"threshold": 3, "minTokens": 500' "jscpd minTokens raised" "jscpd-minTokens" "now 500"
weakens .jscpd.json '"threshold": 3' '"threshold": 3, "minLines": 50' "jscpd minLines raised" "jscpd-minLines" "now 50"
weakens .jscpd.json '"path": ["src"]' '"path": ["src/app"]' "jscpd path narrowed" "src"
weakens .jscpd.json '"threshold": 3' '"threshold": 3, "gitignore": true' "jscpd gitignore on" "gitignore"
weakens .jscpd.json '"threshold": 3' '"threshold": 3, "skipLocal": true' "jscpd skipLocal on" "skipLocal"
weakens .gitleaks.toml "useDefault = true" "useDefault = true
disabledRules = [\"generic-api-key\"]" "gitleaks disabledRules" "generic-api-key"

for bad in 'lines: 80 - 79' 'lines: Number(process.env.COV)' 'lines: LIMIT'; do
  edit vitest.config.ts "lines: 80" "$bad"
  expect 2 "unreadable vitest threshold [$bad]" "UNREADABLE vitest.config.ts" "plain decimal"
done
edit .jscpd.json '"threshold": 3' '"threshold": 1e2'
expect 2 "jscpd threshold in exponent form" "UNREADABLE .jscpd.json" "plain decimal"
edit .jscpd.json '"threshold": 3' '"threshold": $''{JSCPD_MAX}'
expect 2 "jscpd threshold from the environment" "UNREADABLE .jscpd.json"
edit .jscpd.json '"threshold": 3,' '"threshold": 3, "threshold": 99,'
expect 2 "jscpd duplicate key" "UNREADABLE .jscpd.json" "duplicate JSON key"
edit .github/workflows/ci.yml "--fail-under=80" "--fail-under=80-1"
expect 2 "diff coverage not a plain literal" "UNREADABLE .github/workflows/ci.yml"

passes .claude/gates.txt "# Required merge gates" "# Required merge gates (edited comment)" "gates comment edit"
passes eslint.config.mjs "        { ignore: ['eslint-enable'] }," "        { ignore: ['eslint-enable'] }, // note" "trailing comment"

git_ checkout -q -B work main
sed -i.bak 's/lines: 80/lines: 60/' "$R/vitest.config.ts" && rm -f "$R/vitest.config.ts.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/test-budget.sh"
python3 - "$R/.github/workflows/ci.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("gate-ratchet:")
j = s.index("dependency-review:")
blk = s[i:j]
blk = blk.replace("""          LABELS: "${{ join(github.event.pull_request.labels.*.name, ' ') }}\"""", "          LABELS: allow-gate-change")
k = blk.index("        run: |")
blk = blk[:k] + "        run: bash .claude/ci-gates.sh ratchet \"$BASE_REF\"\n  "
open(p, "w").write(s[:i] + blk + s[j:])
PY
git_ commit -q -am "self-granted waiver"
ci_gate ""
check 1 "$EC" "waiver M1: CI file grants its own label, exits 1 ($OUT)"
has "cannot waive a change to the files that enforce" "$OUT" "waiver M1: says the label cannot waive enforcer files"
has "WEAKENED" "$OUT" "waiver M1: still prints the findings"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver M1: label with enforcer change still exits 1 ($OUT)"
has "cannot waive" "$OUT" "waiver M1: label does not waive an enforcer change"

git_ checkout -q -B work main
sed -i.bak 's/lines: 80/lines: 60/' "$R/vitest.config.ts" && rm -f "$R/vitest.config.ts.bak"
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/test-budget.sh"
sed -i.bak 's/LABELS: [$](LABELS)/LABELS: allow-gate-change/' "$R/azure-pipelines/templatecentral-gates.yml" && rm -f "$R/azure-pipelines/templatecentral-gates.yml.bak"
git_ commit -q -am "azure self-granted waiver"
ci_gate ""
check 1 "$EC" "waiver M1: azure gates file, exits 1 ($OUT)"
has "cannot waive" "$OUT" "waiver M1: azure says the label cannot waive"

edit eslint.config.mjs "['error', 15]" "['error', 25]"
ci_gate ""
check 1 "$EC" "waiver: non-enforcer finding without the label exits 1 ($OUT)"
ci_gate "allow-gate-change"
check 0 "$EC" "waiver: non-enforcer finding with the label exits 0 ($OUT)"
has "waived every finding printed above" "$OUT" "waiver: visible waiver line"
has "WEAKENED" "$OUT" "waiver: findings are still printed"

edit .claude/hooks/protect-files.sh "#!/usr/bin/env bash" "#!/usr/bin/env bash
exit 0"
expect 1 "protect-files hook change" ".claude/hooks/protect-files.sh" "gate script, runner or manifest changed"

for sc in check-supply-chain check-workflows check-env-example check-dockerfile; do
  edit "scripts/$sc.sh" "set -uo pipefail" "set -uo pipefail
exit 0"
  expect 1 "$sc script change" "scripts/$sc.sh" "gate script, runner or manifest changed"
done
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 60" "release age lowered" "minimumReleaseAge"
passes pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 20000" "release age raised"
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 10080
minimumReleaseAgeExclude:
  - left-pad" "release age exclusion added" "minimumReleaseAgeExclude"
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 10080
dangerouslyAllowAllBuilds: true" "all builds allowed" "dangerouslyAllowAllBuilds"
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 10080
strictDepBuilds: False" "strictDepBuilds False spelling" "strictDepBuilds"
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 10080
\"ignoreScripts\": FALSE" "quoted ignoreScripts key" "ignoreScripts"
weakens pnpm-workspace.yaml "minimumReleaseAge: 10080" "minimumReleaseAge: 10080
\"minimumReleaseAgeExclude\":
  - left-pad" "quoted exclusion key" "minimumReleaseAgeExclude"
weakens .github/dependabot.yml "default-days: 7" "default-days: 0" "dependabot cooldown zeroed" "dependabot-cooldown"
passes .github/dependabot.yml "default-days: 7" "default-days: 14" "dependabot cooldown raised"
weakens .github/dependabot.yml "default-days: 7" "default-days: \"0\"" "dependabot cooldown zeroed with quotes" "dependabot-cooldown"
passes .github/dependabot.yml "default-days: 7" "default-days: \"14\"" "dependabot cooldown raised with quotes"
edit scripts/check-dockerfile.sh 'DOCKERFILE_IGNORED_RULES="DL3008 DL3018"' 'DOCKERFILE_IGNORED_RULES="DL3008 DL3018 DL3013"'
expect 1 "dockerfile gate ignore list grown" "scripts/check-dockerfile.sh" "gate script, runner or manifest changed"
weakens .npmrc "# note" "# note
ignore-scripts=false" "npmrc re-enables scripts" "ignore-scripts=false"
weakens .npmrc "# note" "# note
registry=https://evil.example.com/" "npmrc registry redirect" "registry"
weakens .hadolint.yaml "# note" "# note
ignored:
  - DL3008" "hadolint ignore added" "DL3008"
git_ checkout -q -B work main
printf '  esbuild: true\n' >> "$R/pnpm-workspace.yaml"
git_ commit -q -am allowbuild
expect 1 "allowBuilds entry added" "esbuild"
git_ checkout -q -B work main
printf 'registry.example.com\n' >> "$R/.claude/registry-hosts.txt"
git_ commit -q -am host
expect 1 "registry host added" ".claude/registry-hosts.txt" "registry.example.com"
ci_gate "allow-gate-change"
check 1 "$EC" "registry host addition cannot be waived by label ($OUT)"
passes .claude/registry-hosts.txt "#" "# note" "registry hosts comment edit"

passes .github/workflows/ci.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "actions/checkout@${NEWSHA} # v7.0.2" "pinned action bump"
passes azure-pipelines.yml "NodeTool@0" "NodeTool@1" "azure task version bump"
weakens .github/workflows/ci.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "evil/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "action swapped for another repo" "gate script, runner or manifest changed"
weakens azure-pipelines.yml "NodeTool@0" "OtherTool@0" "azure task swapped" "gate script, runner or manifest changed"

git_ checkout -q -B work main
mv "$R/.claude/gates.txt" "$R/.claude/gates.txt.gone"
OUT=$(cd "$R" && bash .claude/ci-gates.sh list 2>&1)
check 1 "$?" "list: missing manifest exits 1 ($OUT)"
mv "$R/.claude/gates.txt.gone" "$R/.claude/gates.txt"
printf '# nothing\n' > "$R/.claude/gates.txt"
OUT=$(cd "$R" && bash .claude/ci-gates.sh list 2>&1)
check 1 "$?" "list: empty manifest exits 1 ($OUT)"
git_ checkout -q -f work
git_ checkout -q -B work main

for pair in 'format|"format": ["css"]' 'maxSize|"maxSize": "1b"' 'maxLines|"maxLines": 1' 'mode|"mode": "weak"' 'ignorePattern|"ignorePattern": ["x"]' 'exitCode|"exitCode": 0'; do
  edit .jscpd.json '"threshold": 3' "\"threshold\": 3, ${pair#*|}"
  expect 1 "jscpd unknown key ${pair%%|*}" ".jscpd.json" "does not know"
done
passes .jscpd.json '"reporters": ["console"]' '"reporters": ["console", "json"]' "jscpd neutral reporters key"
weakens .gitleaks.toml "useDefault = true" "useDefault = true

[[rules]]
id = \"generic-api-key\"
regex = '''zzz-never'''
" "gitleaks rule reusing a default id" "generic-api-key"
weakens vitest.config.ts "include: ['src/**/*.ts']," "include: ['src/**/*.ts'],
      all: false," "vitest coverage all: false" "coverage.all"
weakens vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { lines: 80, branches: 70, perFile: false }," "vitest perFile false" "perFile"
passes vitest.config.ts "reporter: ['text', 'cobertura', 'lcov']," "reporter: ['text']," "vitest coverage reporter edit"
weakens eslint.config.mjs "  eslint.configs.recommended,
" "" "eslint entry removed (M4)" "eslint.configs.recommended"
passes eslint.config.mjs "// @ts-check" "// @ts-check
import globals from 'globals';" "new eslint import"
passes eslint.config.mjs "  eslint.configs.recommended," "  eslint.configs.recommended,
  { languageOptions: { globals: { process: 'readonly' } } }," "new eslint config object"

R_TS=$R
R="$T/next"
rm -rf "$R"
mkdir -p "$R/.claude" "$R/scripts"
cp "$SH/template/.claude/gates.txt" "$R/.claude/gates.txt"
cp "$RATCHET" "$R/scripts/gate-ratchet.sh"
cp "$SH/../nextjs/template/eslint.config.mjs" "$R/"
git -C "$R" init -q -b main
git_ add -A
git_ commit -q -m base
ratchet
check 0 "$EC" "nextjs eslint seed: unchanged passes ($OUT)"
weakens eslint.config.mjs "  ...typescript,
" "" "nextjs: typescript preset spread removed" "typescript"
weakens eslint.config.mjs "  ...coreWebVitals,
" "" "nextjs: coreWebVitals preset spread removed" "coreWebVitals"
for UI in next:nextjs/template/vitest.config.ts vite:vite-react/template/vite.config.ts; do
  R="$T/ui-${UI%%:*}"
  CFG=$(basename "${UI#*:}")
  rm -rf "$R"
  mkdir -p "$R/.claude" "$R/scripts"
  cp "$SH/template/.claude/gates.txt" "$R/.claude/gates.txt"
  cp "$RATCHET" "$R/scripts/gate-ratchet.sh"
  cp "$SH/../${UI#*:}" "$R/$CFG"
  git -C "$R" init -q -b main
  git_ add -A
  git_ commit -q -m base
  ratchet
  check 0 "$EC" "${UI%%:*}: seeded coverage exclude with src/components/ui/** passes ($OUT)"
  weakens "$CFG" "'src/components/ui/**']" "'src/components/ui/**', 'src/lib/**']" "${UI%%:*}: src/lib/** added to the coverage exclude" "src/lib/**" "new ignore or exclude"
  passes "$CFG" "'src/components/ui/**']" "]" "${UI%%:*}: dropping the ui exclude is a tightening"
done
R=$R_TS

R="$T/adopt"
rm -rf "$R"
mkdir -p "$R/src"
echo 'export const a = 1;' > "$R/src/a.ts"
cp "$SH/../nestjs/template/eslint.config.mjs" "$R/" && cp "$SH/../nestjs/template/vitest.config.mts" "$R/vitest.config.ts"
git -C "$R" init -q -b main
git_ add -A
git_ commit -q -m "plain project"
git_ checkout -q -b work
mkdir -p "$R/.claude" "$R/scripts"
cp "$SH/template/.claude/gates.txt" "$R/.claude/gates.txt"
cp "$SH/template-ts/.jscpd.json" "$R/.jscpd.json"
cp "$SH/template/.gitleaks.toml" "$R/.gitleaks.toml"
echo "abc" > "$R/.gitleaksignore"
echo "src" > "$R/.eslintignore"
git_ add -A
git_ commit -q -m "adopt the harness"
expect 0 "first adoption: base without gates.txt" "first adoption"

seed ts
git_ checkout -q -B work main
git_ rm -q .jscpd.json
git_ commit -q -m "base without jscpd"
git_ checkout -q -B main work
git_ checkout -q -B work main
cp "$SH/template-ts/.jscpd.json" "$R/.jscpd.json"
git_ add -A
git_ commit -q -m "add jscpd"
expect 0 "base without a jscpd config: adding one is not a shadow"
git_ checkout -q -B main work~1
git_ checkout -q -B work main
git_ rm -q .gitleaks.toml
git_ commit -q -m "base drop gitleaks"
git_ checkout -q -B main work
git_ checkout -q -B work main
echo abc > "$R/.gitleaksignore"
git_ add -A
git_ commit -q -m "add ignore"
expect 0 "base without .gitleaks.toml: .gitleaksignore is not a shadow"
seed ts

python3 - "$T" "$SH" <<'PY'
import sys, yaml
t, sh = sys.argv[1:3]
y = yaml.safe_load(open(sh + "/template-ci/github-ts/.github/workflows/ci.yml"))
open(t + "/step-gh.sh", "w").write(y["jobs"]["gate-ratchet"]["steps"][1]["run"])
a = yaml.safe_load(open(sh + "/template-ci/azure/azure-pipelines/templatecentral-gates.yml"))
steps = a if isinstance(a, list) else a["steps"]
open(t + "/step-az.sh", "w").write(steps[-1]["bash"])
PY
git_ checkout -q -B main main
printf '#!/usr/bin/env bash\necho BASE-ENTRY\nexit 9\n' > "$R/.claude/ci-gates.sh"
git_ commit -q -am "base entry"
git_ checkout -q -B work main
cp "$SH/template/.claude/ci-gates.sh" "$R/.claude/ci-gates.sh"
git_ commit -q -am "head entry"
for kind in gh az; do
  run_step "$kind" main
  check 9 "$EC" "ci step $kind: the merge-base entry point runs ($OUT)"
  has "BASE-ENTRY" "$OUT" "ci step $kind: output from the base entry point"
  check 0 "$LEFT" "ci step $kind: temporary copy removed"
  git_ checkout -q -f work
done
for kind in gh az; do
  run_step "$kind" no-such-branch
  check 1 "$EC" "ci step $kind: missing base ref exits 1 ($OUT)"
  has "fetch" "$OUT" "ci step $kind: says how to fix a missing base ref"
  if [[ "$OUT" == *BASE-ENTRY* ]]; then check no yes "ci step $kind: head script must not run when the base ref is missing"; fi
  git_ diff --quiet
  check 0 "$?" "ci step $kind: entry point untouched when the base ref is missing"
done
git_ checkout -q --orphan lone
git_ commit -q -m lone
for kind in gh az; do
  run_step "$kind" main
  check 1 "$EC" "ci step $kind: no merge base exits 1 ($OUT)"
  has "no merge base" "$OUT" "ci step $kind: names the missing merge base"
done
seed ts
git_ checkout -q -B main main
git_ rm -q .claude/ci-gates.sh .claude/gates.txt
git_ commit -q -m "base without the harness entry"
git_ checkout -q -B work main
git_ checkout main~1 -- .claude/ci-gates.sh .claude/gates.txt
git_ commit -q -m "adopt"
for kind in gh az; do
  run_step "$kind" main
  check 0 "$EC" "ci step $kind: first adoption falls back to the head entry point ($OUT)"
  has "first adoption" "$OUT" "ci step $kind: first adoption reported"
done
seed ts

TAGREF=v4
weakens .github/workflows/ci.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "actions/checkout@${TAGREF}" "action pin moved to a tag" "gate script, runner or manifest changed"
ci_gate "allow-gate-change"
check 1 "$EC" "pin moved to a tag: label cannot waive it ($OUT)"
has "cannot waive" "$OUT" "pin moved to a tag: says the label cannot waive it"
weakens azure-pipelines.yml "NodeTool@0" "NodeTool@latest" "azure task moved off a numeric version" "gate script, runner or manifest changed"
passes .github/workflows/ci.yml "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" "pin comment dropped"

edit eslint.config.mjs "ignores: ['eslint.config.mjs'," "ignores: ['eslint.config.mjs"
ci_gate "allow-gate-change"
check 1 "$EC" "unreadable config: the label does not waive it ($OUT)"
has "cannot waive an unreadable config" "$OUT" "unreadable config: says why"
if [[ "$OUT" == *"waived every finding"* ]]; then check no yes "unreadable config must not print the waiver line"; fi

git_ checkout -q -B main main
printf '#!/usr/bin/env bash\necho BASE-COPY-RAN\nexit 7\n' > "$R/scripts/gate-ratchet.sh"
git_ commit -q -am "base ratchet"
git_ checkout -q -B work main
cp "$RATCHET" "$R/scripts/gate-ratchet.sh"
git_ commit -q -am "head ratchet"
expect 7 "the merge-base copy of the ratchet is the one that runs" "BASE-COPY-RAN"

OUT=$(cd "$R" && bash "$RATCHET" no-such-ref 2>&1)
check 2 "$?" "unknown base ref: exits 2 ($OUT)"
OUT=$(cd "$R" && bash "$RATCHET" 2>&1)
check 2 "$?" "missing argument: exits 2 ($OUT)"
OUT=$(cd "$T" && bash "$RATCHET" main 2>&1)
check 2 "$?" "outside a git repository: exits 2 ($OUT)"

seed ts
# Sonar scope: exclusions may only shrink, inclusions only grow, the file may not go or be shadowed.
weakens sonar-project.properties "**/*.d.ts,src/components/ui/**" "**/*.d.ts,src/components/ui/**,src/**" "sonar exclusions widened" "src/**" "sonar.exclusions"
passes sonar-project.properties "**/*.d.ts,src/components/ui/**" "**/*.d.ts" "sonar exclusions shrunk"
weakens sonar-project.properties "sonar.exclusions=" "sonar.coverage.exclusions=src/**
sonar.exclusions=" "sonar coverage exclusions added" "src/**" "sonar.coverage.exclusions"
weakens sonar-project.properties "sonar.exclusions=" "sonar.cpd.exclusions=src/**
sonar.exclusions=" "sonar cpd exclusions added" "sonar.cpd.exclusions"
weakens sonar-project.properties "sonar.exclusions=" "sonar.issue.ignore.multicriteria=e1
sonar.exclusions=" "sonar issue ignore added" "sonar.issue.ignore.multicriteria"
weakens sonar-project.properties "sonar.exclusions=" "sonar.inclusions=src/only/**
sonar.exclusions=" "sonar inclusions added narrows the scan" "sonar-inclusions"
weakens sonar-project.properties "**/*.test.ts,**/*.test.tsx" "**/*.test.ts,**/*.test.tsx,**" "sonar test inclusions widened" "sonar.test.inclusions"
weakens sonar-project.properties "sonar.exclusions=" "sonar.projectBaseDir=src
sonar.exclusions=" "sonar unknown key added" "sonar.projectBaseDir"
passes sonar-project.properties "sonar.exclusions=" "sonar.projectKey=demo
sonar.exclusions=" "sonar neutral key added"
weakens sonar-project.properties "sonar.exclusions=**/node_modules/**,**/.next/**," "sonar.exclusions=**/node_modules/**,\
  **/.next/**,\
  src/**,\
  " "sonar widened through a continuation line" "src/**"
passes sonar-project.properties "sonar.exclusions=**/node_modules/**,**/.next/**," "sonar.exclusions=**/node_modules/**,\
  **/.next/**,\
  " "sonar same items re-flowed through a continuation line"
drop sonar-project.properties
expect 1 "sonar file deleted" "sonar-project.properties" "now removed"
add_file a/sonar-project.properties "sonar.exclusions=**"
expect 1 "nested sonar file shadows the root one" "a/sonar-project.properties" "competes"
add_file .sonarcloud.properties "sonar.exclusions=**"
expect 1 ".sonarcloud.properties shadows sonar-project.properties" ".sonarcloud.properties" "competes"
edit sonar-project.properties "sonar.exclusions=" "sonar.exclusions=src/**
sonar.exclusions="
expect 2 "sonar repeated key cannot be read" "given twice"
edit sonar-project.properties "sonar.exclusions=**/node_modules/**" "sonar.exclusions=**/node_modules/**,\\,x"
expect 2 "sonar value with an escape cannot be read" "escape sequence"
edit sonar-project.properties "sonar.exclusions=**/node_modules/**" "sonar.exclusions=\${EXTRA},**/node_modules/**"
expect 2 "sonar value with interpolation cannot be read" "interpolation"
add_file docs/sonar-project.properties.md "not a sonar file"
expect 0 "a file that only starts like the sonar file is not a shadow"

# Coverage arrays: bare literals of strings, nothing chained, no repeated key; anything else is unreadable.
EXC="exclude: ['**/*.{test,spec}.ts', '**/*.d.ts'],"
weakens vitest.config.ts "$EXC" "'exclude': ['**/*.{test,spec}.ts', '**/*.d.ts', 'src/**']," "quoted exclude key with a new item" "src/**"
passes vitest.config.ts "$EXC" "'exclude': ['**/*.{test,spec}.ts', '**/*.d.ts']," "quoted exclude key with the same items"
passes vitest.config.ts "$EXC" "exclude: [ '**/*.{test,spec}.ts', '**/*.d.ts', ]," "exclude array with a trailing comma"
edit vitest.config.ts "$EXC" "exclude: ['**/*.{test,spec}.ts', '**/*.d.ts'].concat(['src/**']),"
expect 2 "exclude with .concat" "has something chained after it"
edit vitest.config.ts "$EXC" "exclude: ['**/*.{test,spec}.ts', '**/*.d.ts'].filter(Boolean).concat(process.env.X ? ['src/**'] : []),"
expect 2 "exclude with filter and a conditional concat" "has something chained after it"
edit vitest.config.ts "$EXC" "exclude: EXCL,"
expect 2 "exclude through a constant" "not a bare array literal"
edit vitest.config.ts "$EXC" "exclude: [...BASE, '**/*.d.ts'],"
expect 2 "exclude with a spread" "other than a string literal"
edit vitest.config.ts "$EXC" "exclude: ['a', \`src/\${X}\`],"
expect 2 "exclude with a template expression" "template string"
edit vitest.config.ts "$EXC" "exclude,"
expect 1 "exclude as a shorthand property" "new setting"
edit vitest.config.ts "include: ['src/**/*.ts']," "include: ['src/**/*.ts'].slice(1),"
expect 2 "include with .slice" "has something chained after it"
edit vitest.config.ts "include: ['src/**/*.ts']," "include: ['src/**/*.ts'],
      include: ['x'],"
expect 2 "include given twice" "given twice"
edit vitest.config.ts "include: ['src/**/*.ts']," "'include': ['src/**/*.ts'],"
expect 0 "quoted include key with the same items"
edit vitest.config.ts "include: ['src/**/*.ts']," "'include': ['x'],"
expect 1 "quoted include key that drops the item" "required include 'src/**/*.ts'"

# Thresholds: a quoted key is read, and a repeated key is unreadable.
edit vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { lines: 80, branches: 70, 'lines': 1 },"
expect 2 "quoted duplicate threshold key" "given twice"
edit vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { lines: 80, branches: 70, lines: 1 },"
expect 2 "plain duplicate threshold key" "given twice"
weakens vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { 'lines': 60, branches: 70 }," "quoted threshold key lowered" "was 80" "now 60"
passes vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { 'lines': 90, branches: 70 }," "quoted threshold key raised"
edit vitest.config.ts "thresholds: { lines: 80, branches: 70 }," "thresholds: { lines: 80x, branches: 70 },"
expect 2 "threshold that is not a plain number" "plain decimal"
edit vitest.config.ts "coverage: {" "coverage: COV, xcoverage: {"
expect 2 "coverage that is not an object" "not an object literal"
weakens vitest.config.ts "reporter: ['text', 'cobertura', 'lcov']," "passWithNoTests: true," "passWithNoTests added" "passWithNoTests"
weakens vitest.config.ts "reporter: ['text', 'cobertura', 'lcov']," "'passWithNoTests': !!1," "passWithNoTests as a quoted truthy expression" "passWithNoTests"
passes vitest.config.ts "globals: false," "globals: false, passWithNoTests: false," "passWithNoTests set to false"
add_file vitest.workspace.ts "export default ['packages/*'];"
expect 1 "workspace file competes with the vitest config" "vitest.workspace.ts" "competes"

# package.json scripts: flags that override the coverage config, and a dropped --coverage, are findings; forms the base had stay allowed.
TCI='"test:ci": "vitest --run --coverage",'
for flag in '--coverage.thresholds.lines=0' '--coverage.exclude=src/**' '--coverage.include=nothing/**' '--coverage.all=false' '--coverage.enabled=false' '--coverage=false' '--no-coverage' '--passWithNoTests' '--pass-with-no-tests' '--config=weak.config.ts' '--coverage.thresholds.autoUpdate=true'; do
  weakens package.json "$TCI" "\"test:ci\": \"vitest --run --coverage $flag\"," "script flag $flag" "$flag" "script-flag"
done
weakens package.json "$TCI" '"test:ci": "vitest --run --coverage --config weak.config.ts",' "script --config added" "weak.config.ts"
weakens package.json "$TCI" '"test:ci": "pnpm test -- --coverage.thresholds.lines=0",' "flag passed through pnpm" "--coverage.thresholds.lines=0"
weakens package.json "$TCI" '"test:ci": "vitest --run",' "--coverage dropped from the CI script" "coverage-flag" "test:ci"
weakens package.json "$TCI" '"test:ci": "vitest --run --coverage",
    "test:cheat": "vitest --run --no-coverage",' "flag in a new script" "test:cheat: --no-coverage"
passes package.json "$TCI" '"test:ci": "vitest --run --coverage --coverage.reporter=text --reporter=dot",' "benign coverage reporter flag"
passes package.json "$TCI" '"test:ci": "vitest --run --coverage",
    "test:more": "vitest --run src/x.test.ts",' "new script without flags"
passes package.json '"name":' '"name":' "package.json untouched"
edit package.json "$TCI" '"test:ci": "vitest --run --coverage",
    "test:ci": "vitest --run",'
expect 2 "repeated script name" "duplicate JSON key"
edit package.json "$TCI" '"test:ci": "vitest --run --no-cover\u0061ge",'
expect 2 "script hidden behind a \u escape" "escape"
edit package.json "$TCI" '"test:ci": 3,'
expect 2 "script that is not a string" "not a string"

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
weakens pyproject.toml "line-length = 88" "line-length = 88
lint.ignore = [\"E501\"]" "dotted lint.ignore" "E501"
weakens pyproject.toml "[tool.ruff.lint]
" "[tool.ruff.lint]
per-file-ignores = { \"src/**\" = [\"S608\"] }
" "inline per-file-ignores table" "S608"
weakens pyproject.toml "[tool.ruff.lint]
" "[tool.ruff.lint]
extend-per-file-ignores = { \"src/**\" = [\"S608\"] }
" "extend-per-file-ignores" "S608"
weakens pyproject.toml "[tool.ruff.lint.per-file-ignores]
" "[tool.ruff.lint.extend-per-file-ignores]
\"src/**/*.py\" = [\"S608\"]
[tool.ruff.lint.per-file-ignores]
" "extend-per-file-ignores section" "S608"
for bad in '15 + 5' '1e1' '"15"'; do
  edit pyproject.toml "max-complexity = 15" "max-complexity = $bad"
  expect 2 "unreadable ruff complexity [$bad]" "UNREADABLE pyproject.toml"
done
edit pyproject.toml "fail_under = 80" "fail_under = 1e2"
expect 2 "coverage fail_under in exponent form" "UNREADABLE pyproject.toml" "plain decimal"
add_file ruff.toml "line-length = 100"
expect 1 "ruff.toml shadows pyproject" "ruff.toml" "competes"
add_file .ruff.toml "line-length = 100"
expect 1 ".ruff.toml shadows pyproject" ".ruff.toml" "competes"
add_file .coveragerc "[run]"
expect 1 ".coveragerc" ".coveragerc" "competes"
for kv in 'fix = true' 'preview = true' 'exclude = ["src"]'; do
  edit pyproject.toml "line-length = 88" "line-length = 88
$kv"
  expect 1 "ruff unknown key [$kv]" "pyproject.toml"
done
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.report]
exclude_lines = [\"def \"]" "coverage exclude_lines" "exclude_lines"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.run]
source = [\"x\"]
[tool.coverage.report]" "coverage run source" "source"
passes pyproject.toml "[tool.coverage.report]" "[tool.ruff.format]
quote-style = \"single\"
[tool.coverage.report]" "ruff format quote-style"
weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"-q\"
[tool.coverage.report]" "pytest options edit" "addopts"
git_ checkout -q -B work main
sed -i.bak 's/tool[.]ruff/tool.rff/g' "$R/pyproject.toml" && rm -f "$R/pyproject.toml.bak"
git_ commit -q -am rename
ratchet
check 2 "$EC" "pyproject without [tool.ruff]: exits 2 ($OUT)"

# Python: coverage and pytest bypasses, Sonar scope, and shadow config files.
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.run]
'omit' = [\"src/**\"]
[tool.coverage.report]" "single-quoted omit key" "src/**"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.run]
\"omit\" = [\"src/**\"]
[tool.coverage.report]" "double-quoted omit key" "src/**"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.run]
omit = [\"src/**\"]
[tool.coverage.report]" "plain omit key" "src/**"
weakens pyproject.toml "[tool.coverage.report]" "[ tool . coverage . run ]
omit = [\"src/**\"]
[tool.coverage.report]" "omit under a spaced header" "src/**"
weakens pyproject.toml "[tool.coverage.report]" "[tool.\"coverage\".run]
omit = [\"src/**\"]
[tool.coverage.report]" "omit under a quoted header" "src/**"
weakens pyproject.toml "[tool.coverage.report]" "[tool]
coverage = { run = { omit = [\"src/**\"] } }
[tool.coverage.report]" "coverage inside an inline table of [tool]" "new setting"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage]
run = { omit = [\"src/**\"] }
[tool.coverage.report]" "run as an inline table" "new setting"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.report]
exclude_also = [\"def \"]" "coverage exclude_also" "exclude_also"
weakens pyproject.toml "[tool.coverage.report]" "[tool.coverage.run]
source = [\"x\"]
[tool.coverage.report]" "coverage source" "source"
passes pyproject.toml "[tool.coverage.report]" "[tool.coverage.report]
precision = 1" "neutral coverage key"
for fl in '--no-cov' '--cov-config=weak.rc' '-p no:cov' '-p no:pytest_cov' '-c weak.ini'; do
  weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"$fl\"
[tool.coverage.report]" "addopts $fl" "pytest-flag"
done
weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = [\"-q\", \"-p\", \"no:cov\"]
[tool.coverage.report]" "addopts split -p no:cov" "pytest-flag"
weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"--cov-fail-under=1\"
[tool.coverage.report]" "addopts --cov-fail-under=1" "pytest-cov-fail-under" "was 80" "now 1"
weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = [\"--cov-fail-under\", \"0\"]
[tool.coverage.report]" "addopts split --cov-fail-under 0" "pytest-cov-fail-under" "now 0"
passes pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"--cov-fail-under=90\"
[tool.coverage.report]" "addopts --cov-fail-under raised"
weakens pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"--no-cov-on-fail\"
[tool.coverage.report]" "addopts --no-cov-on-fail is no longer a known-safe edit" "addopts"
edit pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"--cov-fail-under=abc\"
[tool.coverage.report]"
expect 2 "addopts --cov-fail-under not a number" "--cov-fail-under"
weakens sonar-project.properties "sonar.sources=src" "sonar.sources=" "sonar sources emptied" "sonar.sources" "was present"
passes sonar-project.properties "sonar.sources=src" "sonar.sources=src,lib" "sonar sources grown"
for f in pytest.ini tox.ini setup.cfg; do
  add_file "$f" "[pytest]"
  expect 1 "$f shadows pyproject" "$f" "competes"
done


# Round 3: test-script words are an allow-list.
seed ts
for fl in '--dir test/x' '--exclude **/*' '--changed' '-t nothing' '--bail=1' '--shard=1/2' '--testNamePattern=none'; do
  weakens package.json '"test:ci": "vitest --run --coverage"' "\"test:ci\": \"vitest --run --coverage $fl\"" "test:ci word $fl" "known-safe words" "test:ci"
done
weakens package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run"' "test:ci loses --coverage" "known-safe words" "test:ci"
weakens package.json '"test:cov": "vitest --run --coverage"' '"test:cov": "vitest --run --coverage --changed"' "test:cov word added" "test:cov"
passes package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --reporter=verbose"' "test:ci --reporter=verbose is known-safe"
passes package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --silent"' "test:ci --silent is known-safe"
passes package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --coverage.reporter=text"' "test:ci --coverage.reporter is known-safe"

# Round 3: pytest keys.
seed py
for fl in '--cov=src/narrow' '-m unit' '--ignore=test' '--deselect=test/a' '-k nothing' '-o addopts=' '--lf' '--co'; do
  weakens pyproject.toml '"--import-mode=importlib",' "\"--import-mode=importlib\", \"$fl\"," "addopts adds $fl" "addopts"
done
for key in 'testpaths = ["test/x"]' 'python_files = ["nomatch_*.py"]' 'python_classes = ["Nothing"]' 'python_functions = ["nothing_*"]' 'norecursedirs = ["test"]' 'filterwarnings = ["ignore"]'; do
  weakens pyproject.toml 'asyncio_mode = "auto"' "$key
asyncio_mode = \"auto\"" "pytest key $key" "new setting" "${key%% =*}"
done
passes pyproject.toml '"--import-mode=importlib",' '"--import-mode=importlib", "--cov-fail-under=90",' "pytest --cov-fail-under raised from nothing"
passes pyproject.toml '"--import-mode=importlib",' '"--import-mode=importlib", "--cov-fail-under", "90",' "pytest --cov-fail-under split form raised"
passes pyproject.toml '  "integration: needs a running service",' '  "integration: needs a running service",
  "slow: takes a while",' "pytest new marker"

# Round 3: gate-bearing files that were never compared.
seed ts
weakens scripts/check-docs.sh "" "exit 0
" "gate script gets an early exit" "scripts/check-docs.sh" "content differs"
weakens .claude/settings.json "{}" '{"hooks": {}}' "settings.json edited" ".claude/settings.json" "content differs"
weakens .claude/hooks/protect-files.sh "#!/usr/bin/env bash" "#!/usr/bin/env bash
exit 0" "hook edited" ".claude/hooks/protect-files.sh" "content differs"
edit .claude/dep-audit-allow.txt "reason
" "reason
GHSA-dddd-eeee-ffff 2099-01-01 new
"
expect 1 "allow-list gains a line" ".claude/dep-audit-allow.txt" "advisory allow-list gained a line"
passes .claude/dep-audit-allow.txt "GHSA-aaaa-bbbb-cccc 2099-01-01 reason
" "" "allow-list loses a line"
passes .claude/dep-audit-allow.txt "# advisory allow-list" "# advisory allow-list, reviewed" "allow-list comment edit"
git_ checkout -q -B work main
: > "$R/.claude/comment-hygiene-patterns.txt"
git_ commit -q -am "empty patterns"
expect 1 "patterns emptied" ".claude/comment-hygiene-patterns.txt" "patterns were removed"
git_ checkout -q -B work main
printf '^[Nn]ote[[:space:]]\n' >> "$R/.claude/comment-hygiene-patterns.txt"
git_ commit -q -am "append pattern"
expect 0 "patterns appended"
weakens tsconfig.json '"strict": true' '"strict": false' "tsconfig strict off" "tsconfig.json" "strictness option strict was on, now off"
weakens tsconfig.json '"strict": true' '"strict": true, "noImplicitAny": false' "tsconfig noImplicitAny off" "noImplicitAny"
passes tsconfig.json '"strictPropertyInitialization": false' '"strictPropertyInitialization": true' "tsconfig tightened"
add_file tsconfig.spec.json '{"extends": "./tsconfig.json", "compilerOptions": {"strict": false}}'
expect 1 "new tsconfig with strict off" "tsconfig.spec.json" "strictness option strict is off"
add_file tsconfig.spec.json '{"extends": "./tsconfig.json", "compilerOptions": {"strict": true}}'
expect 0 "new tsconfig with strict on"
seed py
weakens pyrightconfig.json '"venvPath": "."' '"typeCheckingMode": "off", "venvPath": "."' "pyright mode off" "pyrightconfig.json" "typeCheckingMode"
passes pyrightconfig.json '"venvPath": "."' '"typeCheckingMode": "strict", "venvPath": "."' "pyright mode strict"
weakens pyrightconfig.json '"venvPath": "."' '"reportMissingImports": "none", "venvPath": "."' "pyright rule none" "reportMissingImports"

# Round 3: the guarded set is derived from the tree.
seed ts
printf '#!/usr/bin/env bash\necho gate\n' > "$R/scripts/check-extra.sh"
printf '# runs scripts/check-extra.sh\n' >> "$R/.claude/gates.txt"
git_ add -A
git_ commit -q -m "gate script named by gates.txt"
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/scripts/check-extra.sh"
git_ commit -q -am "sabotage"
expect 1 "a script named by the manifest is guarded" "scripts/check-extra.sh" "content differs"
LISTED=$(cd "$R" && bash scripts/gate-ratchet.sh --list-guarded HEAD)
for g in scripts/check-extra.sh scripts/check-docs.sh .claude/settings.json .claude/hooks/protect-files.sh .claude/dep-audit-allow.txt .claude/comment-hygiene-patterns.txt tsconfig.json; do
  has "$g" "$LISTED" "list-guarded names $g"
done

# Round 3: auto base with nothing to compare against.
seed ts
git_ checkout -q -B work main
OUT=$(cd "$R" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD bash scripts/gate-ratchet.sh auto 2>&1)
EC=$?
check 0 "$EC" "auto base without upstream exits 0 outside CI ($OUT)"
has "DID NOT RUN" "$OUT" "auto base without upstream says it did not run"
OUT=$(cd "$R" && env -u TF_BUILD -u GITHUB_ACTIONS CI=true bash scripts/gate-ratchet.sh auto 2>&1)
EC=$?
check 2 "$EC" "auto base without upstream fails closed in CI ($OUT)"
has "no base branch found" "$OUT" "auto base in CI names the cause"
OUT=$(cd "$R" && env -u CI -u TF_BUILD GITHUB_ACTIONS=true bash scripts/gate-ratchet.sh auto 2>&1)
check 2 "$?" "auto base without upstream fails closed under GITHUB_ACTIONS ($OUT)"

# Round 3: the merge base must carry the ratchet script.
seed ts
git_ rm -q scripts/gate-ratchet.sh
git_ commit -q -m "base without ratchet script"
git_ update-ref refs/remotes/origin/main main
git_ checkout -q -B work main
cp "$RATCHET" "$R/scripts/gate-ratchet.sh"
git_ add -A
git_ commit -q -m "head brings its own judge"
OUT=$(cd "$R" && LABELS="" bash .claude/ci-gates.sh ratchet main 2>&1)
EC=$?
check 1 "$EC" "ci ratchet fails when the base has no ratchet script ($OUT)"
has "would judge itself" "$OUT" "ci ratchet names the missing base script"
OUT=$(cd "$R" && bash scripts/gate-ratchet.sh main 2>&1)
check 2 "$?" "ratchet fails when the base has no ratchet script ($OUT)"
has "would judge itself" "$OUT" "ratchet names the missing base script"

# Round 4: wl_norm skips the word after --reporter and friends only when it is a plain value.
seed ts
weakens package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --reporter --changed"' "reporter swallows --changed" "known-safe words" "test:ci"
weakens package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --outputFile --bail=1"' "outputFile swallows --bail=1" "known-safe words" "test:ci"
weakens package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --coverage.reporter --dir test/x"' "coverage.reporter swallows --dir" "known-safe words" "test:ci"
passes package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --reporter json"' "reporter with a value"
passes package.json '"test:ci": "vitest --run --coverage"' '"test:ci": "vitest --run --coverage --outputFile out.xml"' "outputFile with a value"

# Round 4: every key under test: is a fact unless it is on the neutral list.
for kv in 'changed: true,' "dir: 'test/nothing'," "testNamePattern: 'zzz'," "root: './test/x'," 'bail: 1,' "projects: ['a']," 'allowOnly: true,' "exclude: ['**/*.spec.ts']," ; do
  key=${kv%%:*}
  case "$key" in
    exclude) continue ;;
  esac
  weakens vitest.config.ts "globals: false," "globals: false,
    $kv" "vitest test.$key added" "new setting test.$key"
done
passes vitest.config.ts "globals: false," "globals: false,
    clearMocks: true," "vitest neutral test key"
passes vitest.config.ts "environment: 'node'," "environment: 'jsdom'," "vitest environment"

# Round 4: pytest collection hooks in conftest files.
seed py
mkdir -p "$R/test" "$R/src"
printf 'import pytest\n\n\n@pytest.fixture\ndef one():\n    return 1\n\n\ndef pytest_collection_modifyitems(config, items):\n    pass\n' > "$R/test/conftest.py"
git_ add -A
git_ commit -q -m "conftest at base"
git_ checkout -q -B work main
python3 - "$R/test/conftest.py" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("    pass\n", "    items.clear()\n", 1))
PY2
git_ commit -q -am "edit hook body"
expect 1 "existing conftest hook body edited" "test/conftest.py" "collection hook"
git_ checkout -q -B work main
printf '\n\n@pytest.fixture\ndef two():\n    return 2\n' >> "$R/test/conftest.py"
git_ commit -q -am "add fixture"
expect 0 "existing conftest gains a fixture"
git_ checkout -q -B work main
printf 'collect_ignore_glob = ["*"]\n' >> "$R/test/conftest.py"
git_ commit -q -am "ignore all"
expect 1 "existing conftest gains collect_ignore_glob" "test/conftest.py" "collection hook"
add_file conftest.py 'def pytest_collection_modifyitems(config, items):
    items[:] = []'
expect 1 "new root conftest with a hook" "conftest.py" "collection hook"
add_file test/unit/conftest.py 'collect_ignore_glob = ["*.py"]'
expect 1 "new nested conftest with collect_ignore_glob" "test/unit/conftest.py" "collection hook"
add_file test/unit/conftest.py 'collect_ignore = ["a.py"]'
expect 1 "new nested conftest with collect_ignore" "test/unit/conftest.py" "collection hook"
add_file test/unit/conftest.py 'def pytest_configure(config):
    config.option.keyword = "zzz"'
expect 1 "new conftest with pytest_configure" "test/unit/conftest.py" "collection hook"
add_file test/unit/conftest.py 'pytest_plugins = ["x"]'
expect 1 "new conftest with pytest_plugins" "test/unit/conftest.py" "collection hook"
add_file test/unit/conftest.py 'import pytest


@pytest.fixture
def three():
    return 3


def helper():
    return 4'
expect 0 "new fixture-only conftest"

# Round 4: a shadow config file at any depth.
seed py
add_file src/pytest.ini '[pytest]
addopts = --no-cov'
expect 1 "new src/pytest.ini beside pyproject settings" "src/pytest.ini" "may read it instead"
add_file tox.ini '[pytest]
addopts = -k none'
expect 1 "new tox.ini beside pyproject settings" "tox.ini" "may read it instead"
add_file pkg/.coveragerc '[report]
fail_under = 0'
expect 1 "new nested .coveragerc beside pyproject settings" "pkg/.coveragerc" "may read it instead"
seed ts
add_file src/pytest.ini '[pytest]
addopts = --no-cov'
expect 0 "pytest.ini with no pyproject settings at base"

# Round 4: install-time package.json scripts are guarded.
seed ts
weakens package.json '"prepare": "lefthook install || true"' '"prepare": "echo skip"' "prepare changed" "prepare"
weakens package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "postinstall": "echo skip",' "postinstall added" "postinstall"
weakens package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "install": "echo skip",' "install added" "install"

# Round 4: --config on a new script passes, on an existing one fails.
seed ts
passes package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "test:integration": "vitest --run --config vitest.config.integration.mts",' "new script with --config"
weakens package.json '"test:e2e": "vitest --run --config vitest.config.e2e.mts"' '"test:e2e": "vitest --run --config vitest.config.other.mts"' "--config changed on an existing script" "script-flag"
weakens package.json '"test:watch": "vitest"' '"test:watch": "vitest --config vitest.config.other.mts"' "--config added to an existing script" "script-flag"
weakens package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "test:cheat": "vitest --run --no-coverage",' "--no-coverage on a new script" "script-flag"

# Round 4: a new pyproject.toml needs [tool.ruff] only when the base has one.
seed py
add_file sub/pyproject.toml '[project]
name = "sub"'
expect 0 "new sub/pyproject.toml without [tool.ruff]"
edit pyproject.toml "[tool.ruff]" "[tool.rufff]"
edit_more pyproject.toml "[tool.ruff.lint]" "[tool.rufff.lint]"
expect 2 "existing pyproject.toml loses [tool.ruff]" "no [tool.ruff] section"

# Round 4: an empty coverage value is neutral in every awk, a filled one is a finding.
seed py
passes pyproject.toml "fail_under = 80" "fail_under = 80
plugins = ['']" "coverage setting with only quotes"
weakens pyproject.toml "fail_under = 80" "fail_under = 80
plugins = ['x']" "coverage setting with a value" "new setting"

# Round 4: --list-guarded rejects a bad ref and ci-gates fails when the list is empty.
seed ts
OUT=$(cd "$R" && bash scripts/gate-ratchet.sh --list-guarded no-such-ref 2>&1)
check 2 "$?" "list-guarded with a bad ref exits 2 ($OUT)"
has "is not a commit" "$OUT" "list-guarded bad ref names the cause"
OUT=$(cd "$R" && bash scripts/gate-ratchet.sh --list-guarded HEAD 2>&1)
check 0 "$?" "list-guarded with a good ref exits 0"
git_ checkout -q -B work main
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/gate-ratchet.sh"
git_ commit -q -am "ratchet that lists nothing"
git_ checkout -q -B main work
git_ checkout -q -B work main
printf 'x\n' >> "$R/scripts/check-docs.sh"
git_ commit -q -am "change"
ci_gate ""
check 1 "$EC" "ci ratchet fails when the guarded list is empty ($OUT)"
has "failed or listed nothing" "$OUT" "ci ratchet names the empty list"

# Round 4: the waiver and the ratchet read one derived set.
seed ts
printf '#!/usr/bin/env bash\necho gate\n' > "$R/scripts/check-extra.sh"
printf '# runs scripts/check-extra.sh\n' >> "$R/.claude/gates.txt"
git_ add -A
git_ commit -q -m "gate script named by gates.txt"
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/scripts/check-extra.sh"
git_ commit -q -am "sabotage"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not cover a derived gate script ($OUT)"
has "scripts/check-extra.sh" "$OUT" "waiver refusal names the derived script"
seed ts
git_ checkout -q -B work main
printf 'GHSA-dddd-eeee-ffff 2099-01-01 new\n' >> "$R/.claude/dep-audit-allow.txt"
git_ commit -q -am "allow-list line"
ci_gate "allow-gate-change"
check 0 "$EC" "waiver still covers a label-waivable file ($OUT)"

# Round 5: a base_edit helper puts an edit on main itself.
base_edit() {
  edit "$@"
  git_ checkout -q -B main work
}

# listed <path>: the list-guarded line for a path at HEAD of the current repo, or nothing.
listed() {
  (cd "$R" && bash scripts/gate-ratchet.sh --list-guarded HEAD 2>/dev/null) | awk -F'\t' -v p="$1" '$2 == p { print }'
}

# Round 5: a path named only in a project skill document is not a guard.
seed ts
printf '#!/usr/bin/env bash\necho helper\n' > "$R/scripts/helper.sh"
mkdir -p "$R/.claude/skills/demo"
printf '# demo\nRun scripts/helper.sh before you start.\n' > "$R/.claude/skills/demo/SKILL.md"
git_ add -A
git_ commit -q -m "script named by a skill document"
check "" "$(listed scripts/helper.sh)" "skill document mention does not list the script as guarded"
git_ checkout -q -B work main
printf 'echo more\n' >> "$R/scripts/helper.sh"
printf 'Also run it twice.\n' >> "$R/.claude/skills/demo/SKILL.md"
git_ commit -q -am "touch both"
expect 0 "change touching a script and the skill document that names it"
printf '#!/usr/bin/env bash\necho helper2\n' > "$R/scripts/helper2.sh"
printf '# runs scripts/helper2.sh\n' >> "$R/.claude/gates.txt"
git_ add -A
git_ commit -q -m "script named by the manifest"
git_ checkout -q -B main work
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/scripts/helper2.sh"
git_ commit -q -am "edit manifest script"
expect 1 "control: a script named by gates.txt stays guarded" "scripts/helper2.sh" "gate script, runner or manifest changed"

# Round 5: a runner named only by package.json, the Makefile or .husky is guarded.
seed ts
printf '#!/usr/bin/env bash\necho run\n' > "$R/scripts/run-tests.sh"
printf '#!/usr/bin/env bash\necho dev\n' > "$R/scripts/run-dev.sh"
printf '#!/usr/bin/env bash\necho mk\n' > "$R/scripts/mk-step.sh"
printf '#!/usr/bin/env bash\necho hk\n' > "$R/scripts/hk-step.sh"
printf 'check:\n\tbash scripts/mk-step.sh\n' > "$R/Makefile"
mkdir -p "$R/.husky"
printf '#!/usr/bin/env sh\nbash scripts/hk-step.sh\n' > "$R/.husky/pre-commit"
git_ add -A
git_ commit -q -m "runners"
base_edit package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "test:unit": "bash scripts/run-tests.sh",
    "dev": "bash scripts/run-dev.sh",'
for r in run-tests mk-step hk-step; do
  git_ checkout -q -B work main
  printf 'exit 0\n' >> "$R/scripts/$r.sh"
  git_ commit -q -am "gut $r"
  expect 1 "runner $r named only by its caller" "scripts/$r.sh" "gate script, runner or manifest changed"
done
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/scripts/run-dev.sh"
git_ commit -q -am "edit dev script"
expect 0 "control: a script named only by a dev script"
check "" "$(listed scripts/run-dev.sh)" "dev-only script is not listed as guarded"

# Round 5: conftest code that can hide tests is a finding, the rest is not.
conftest_cases() {
  local tag=$1
  seed py
  add_file test/unit/conftest.py 'import pytest


@pytest.fixture(autouse=True)
def _gate():
    pytest.skip("always")'
  expect 1 "$tag autouse fixture that skips" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import pytest


@pytest.fixture(autouse=True)
def _quiet():
    return 1'
  expect 1 "$tag autouse fixture with no skip" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import pytest

pytestmark = pytest.mark.skip'
  expect 1 "$tag pytestmark" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import pytest


def check():
    pytest.xfail("x")'
  expect 1 "$tag pytest.xfail" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import pytest

dep = pytest.importorskip("nothing_here")'
  expect 1 "$tag importorskip" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import pytest


def check():
    pytest.exit("stop")'
  expect 1 "$tag pytest.exit" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import sys

sys.exit(0)'
  expect 1 "$tag sys.exit" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'import os

os._exit(0)'
  expect 1 "$tag os._exit" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'pytest_plugins = ["pytest_asyncio", "evil_plugin"]'
  expect 1 "$tag pytest_plugins with a plugin outside the list" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py 'def pytest_configure(config):
    config.option.keyword = "zzz"'
  expect 1 "$tag pytest_configure that sets an option" "test/unit/conftest.py" "collection hook"
  add_file test/unit/conftest.py '"""Notes on pytest_collection_modifyitems and autouse fixtures."""
import pytest


@pytest.fixture
def one():
    # pytest_collection_modifyitems is not used here
    return 1'
  expect 0 "$tag hook name inside a docstring and a comment"
  add_file test/unit/conftest.py 'pytest_plugins = ["pytest_asyncio"]'
  expect 0 "$tag pytest_plugins with a neutral plugin"
  add_file test/unit/conftest.py 'def pytest_configure(config):
    config.addinivalue_line("markers", "slow: slow tests")'
  expect 0 "$tag pytest_configure that only registers a marker"
  add_file test/unit/conftest.py 'def pytest_addoption(parser):
    parser.addoption("--runslow", action="store_true", default=False)'
  expect 0 "$tag pytest_addoption that only adds an option"
  add_file test/unit/conftest.py 'import pytest


@pytest.fixture
def client():
    return object()


def build(n):
    return [n, n]'
  expect 0 "$tag plain fixtures and helpers"
}
conftest_cases "[awk]"
MAWK=$(command -v mawk || true)
if [[ -n "$MAWK" ]]; then
  mkdir -p "$T/mawkbin"
  ln -sf "$MAWK" "$T/mawkbin/awk"
  OLDPATH=$PATH
  PATH="$T/mawkbin:$PATH"
  conftest_cases "[mawk]"
  seed py
  passes pyproject.toml "fail_under = 80" "fail_under = 80
plugins = ['']" "[mawk] coverage setting with only quotes"
  weakens pyproject.toml "fail_under = 80" "fail_under = 80
plugins = ['x']" "[mawk] coverage setting with a value" "new setting"
  PATH=$OLDPATH
fi

# Round 5: the list carries an enforced column, one spaced guarded path, and the scan fails closed.
seed ts
check "1" "$(listed .claude/gates.txt | cut -f3)" "gates manifest is enforced"
check "1" "$(listed scripts/test-budget.sh | cut -f3)" "budget script is enforced"
check "1" "$(listed .github/workflows/ci.yml | cut -f3)" "ci workflow is enforced"
check "0" "$(listed eslint.config.mjs | cut -f3)" "eslint config is label-waivable"
check "0" "$(listed .claude/dep-audit-allow.txt | cut -f3)" "dependency allow-list is label-waivable"
printf '#!/usr/bin/env bash\necho a\n' > "$R/.claude/hooks/my hook.sh"
git_ add -A
git_ commit -q -m "hook with a space"
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/.claude/hooks/my hook.sh"
git_ commit -q -am "sabotage the spaced hook"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not cover a hook with a space in its path ($OUT)"
has "my hook.sh" "$OUT" "waiver refusal names the whole spaced path"
seed ts
printf '#!/usr/bin/env bash\necho a\n' > "$R/.claude/hooks/uniq.sh"
printf 'unique-content-%s\n' "$$" >> "$R/.claude/hooks/uniq.sh"
git_ add -A
git_ commit -q -m "unique hook"
BLOB=$(git_ rev-parse "HEAD:.claude/hooks/uniq.sh")
git_ checkout -q -B work main
git_ rm -q .claude/hooks/uniq.sh
printf 'x\n' >> "$R/scripts/check-docs.sh"
git_ commit -q -am "drop the hook"
rm -f "$R/.git/objects/${BLOB:0:2}/${BLOB:2}"
expect 2 "unreadable tracked file at the merge base" "cannot derive the guarded set"

# Round 5: classification runs in one pass, with a CPU bound on a large tree.
KOF=$(cat "$RATCHET")
check 0 "$(printf '%s\n' "$KOF" | grep -c 'list_kinds\|kind_full')" "no per-path helper survives in the ratchet"
check 0 "$(printf '%s\n' "$KOF" | awk '/^classify\(\)/,/^}/' | grep -c '[$][(]')" "classify has no command substitution per path"
seed ts
mkdir -p "$R/src/a" "$R/src/b" "$R/src/c"
for i in $(seq 1 1000); do
  printf 'x\n' > "$R/src/a/f$i.ts"
  printf 'x\n' > "$R/src/b/f$i.ts"
  printf 'x\n' > "$R/src/c/f$i.ts"
done
git_ add -A
git_ commit -q -m "3000 files"
CPU=$(cd "$R" && python3 - <<'PY'
import resource, subprocess
subprocess.run(["bash", "scripts/gate-ratchet.sh", "--list-guarded", "HEAD"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
r = resource.getrusage(resource.RUSAGE_CHILDREN)
print(int((r.ru_utime + r.ru_stime) * 100))
PY
)
if [[ "$CPU" -lt 100 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: list-guarded on 3000 files used ${CPU} centiseconds of CPU, limit 100"; fi

# Round 6: a base package.json that cannot be parsed fails the scan, it never shrinks the guarded set.
seed ts
printf '#!/usr/bin/env bash\necho run\n' > "$R/scripts/run-tests.sh"
git_ add -A
git_ commit -q -m "runner"
base_edit package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "x\\y": "1",
    "test:unit": "bash scripts/run-tests.sh",'
git_ checkout -q -B work main
python3 - "$R/package.json" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('    "x\\\\y": "1",\n', '', 1)
open(p, "w").write(s)
PY
printf 'exit 0\n' >> "$R/scripts/run-tests.sh"
git_ commit -q -am "fix package.json and gut the runner"
expect 2 "unparseable base package.json" "cannot derive the guarded set"
LISTRC=$(cd "$R" && git checkout -q main && bash scripts/gate-ratchet.sh --list-guarded HEAD >/dev/null 2>&1; echo $?)
check 2 "$LISTRC" "--list-guarded on an unparseable package.json exits 2"
seed ts
printf '#!/usr/bin/env bash\necho run\n' > "$R/scripts/run-tests.sh"
git_ add -A
git_ commit -q -m "runner"
base_edit package.json '"test:ci": "vitest --run --coverage",' '"test:ci": "vitest --run --coverage",
    "test:unit": "bash scripts/run-tests.sh",'
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/scripts/run-tests.sh"
git_ commit -q -am "gut the runner"
expect 1 "control: parseable package.json keeps the runner guarded" "scripts/run-tests.sh" "gate script, runner or manifest changed"

# Round 6: a grep that fails with a status above 1 fails the scan with exit 2.
seed ts
git_ checkout -q -B work main
printf 'x\n' >> "$R/scripts/check-docs.sh"
git_ commit -q -am "touch a script"
mkdir -p "$T/grepshim"
REALGREP=$(command -v grep)
printf '#!/bin/sh\ncase "$*" in *"[.]md$"*) exit 2 ;; esac\nexec %s "$@"\n' "$REALGREP" > "$T/grepshim/grep"
chmod +x "$T/grepshim/grep"
OLDPATH=$PATH
PATH="$T/grepshim:$PATH"
ratchet
PATH=$OLDPATH
check 2 "$EC" "a grep that fails with status 2 fails the scan ($OUT)"
has "cannot derive the guarded set" "$OUT" "grep failure message"
printf '#!/bin/sh\nexec %s "$@"\n' "$REALGREP" > "$T/grepshim/grep"
PATH="$T/grepshim:$PATH"
ratchet
PATH=$OLDPATH
check 1 "$EC" "control: a pass-through grep shim leaves the scan working ($OUT)"
has "scripts/check-docs.sh" "$OUT" "control: the touched gate script is still found"

# Round 6: gitleaks and comment-hygiene files are enforced, so the label never waives them.
seed ts
check "1" "$(listed .gitleaks.toml | cut -f3)" "gitleaks config is enforced"
check "1" "$(listed .claude/comment-hygiene-patterns.txt | cut -f3)" "comment-hygiene patterns are enforced"
git_ checkout -q -B work main
python3 - "$R/.gitleaks.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("useDefault = true", "useDefault = false", 1))
PY
git_ commit -q -am "gitleaks default rules off"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not clear a gitleaks finding ($OUT)"
has "cannot waive a change to the files that enforce the gates" "$OUT" "gitleaks waiver refusal"
git_ checkout -q -B work main
: > "$R/.claude/comment-hygiene-patterns.txt"
git_ commit -q -am "patterns emptied"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not clear a comment-hygiene finding ($OUT)"
has "cannot waive a change to the files that enforce the gates" "$OUT" "patterns waiver refusal"

# Round 6: a listing row with fewer than three fields fails closed.
seed ts
git_ checkout -q -B work main
printf '#!/usr/bin/env bash\nif [ "${1:-}" = --list-guarded ]; then printf "guard\\t.claude/gates.txt\\n"; exit 0; fi\necho "WEAKENED .claude/gates.txt: x"\nexit 1\n' > "$R/scripts/gate-ratchet.sh"
git_ commit -q -am "two column runner"
git_ checkout -q -B main work
git_ checkout -q -B work main
printf '# note\n' >> "$R/.claude/gates.txt"
git_ commit -q -am "touch manifest"
ci_gate "allow-gate-change"
check 1 "$EC" "a two-column listing fails closed ($OUT)"
has "fewer than three fields" "$OUT" "short row message"

# Round 6: a guarded path that holds a colon and a space is matched whole.
seed ts
printf '#!/usr/bin/env bash\necho a\n' > "$R/.claude/hooks/a: b.sh"
git_ add -A
git_ commit -q -m "hook with a colon and a space"
git_ checkout -q -B work main
printf 'exit 0\n' >> "$R/.claude/hooks/a: b.sh"
git_ commit -q -am "sabotage the hook"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not cover a hook with a colon and a space ($OUT)"
has "cannot waive a change to the files that enforce the gates" "$OUT" "colon path waiver refusal"

# Round 6: a Node hook-manager file is guarded content, so rewriting it is a finding.
seed ts
mkdir -p "$R/.husky"
printf '#!/usr/bin/env sh\nbash scripts/check-docs.sh\n' > "$R/.husky/pre-commit"
git_ add -A
git_ commit -q -m "hook manager file"
check "1" "$(listed .husky/pre-commit | cut -f3)" "hook-manager file is enforced"
check "guard" "$(listed .husky/pre-commit | cut -f1)" "hook-manager file is kind guard"
git_ checkout -q -B work main
printf 'exit 0\n' > "$R/.husky/pre-commit"
git_ commit -q -am "gut the hook"
expect 1 "hook-manager file rewritten" ".husky/pre-commit" "gate script, runner or manifest changed"
ci_gate "allow-gate-change"
check 1 "$EC" "waiver does not cover the hook-manager file ($OUT)"
seed ts
check "" "$(listed .husky/pre-commit)" "a project without the folder lists nothing"
git_ checkout -q -B work main
printf 'x\n' >> "$R/scripts/check-docs.sh"
git_ commit -q -am "touch"
expect 1 "control: a project without the folder still guards its scripts" "scripts/check-docs.sh"

echo "gate-ratchet.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
