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
  cp "$SH/template/.claude/ci-gates.sh" "$SH/template/.claude/verify-harness.sh" "$R/.claude/"
  cp "$SH/template-$1/lefthook.yml" "$R/lefthook.yml"
  if [[ "$1" == ts ]]; then
    cp "$SH/../nestjs/template/eslint.config.mjs" "$SH/../nestjs/template/vitest.config.ts" "$R/"
    cp "$SH/template-ts/.jscpd.json" "$R/.jscpd.json"
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
weakens .claude/gates.txt "ratchet|-|ci-gates.sh ratchet" "ratchet|-|ratchet" "gate needle rewritten" "gate script, runner or manifest changed"
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
passes vitest.config.ts "include: ['src/**/*.ts']," "include: ['src/**/*.ts'],
      reporter: ['text']," "vitest coverage reporter edit"
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
R=$R_TS

R="$T/adopt"
rm -rf "$R"
mkdir -p "$R/src"
echo 'export const a = 1;' > "$R/src/a.ts"
cp "$SH/../nestjs/template/eslint.config.mjs" "$SH/../nestjs/template/vitest.config.ts" "$R/"
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
passes pyproject.toml "[tool.coverage.report]" "[tool.pytest.ini_options]
addopts = \"-q\"
[tool.coverage.report]" "pytest options edit"
git_ checkout -q -B work main
sed -i.bak 's/tool[.]ruff/tool.rff/g' "$R/pyproject.toml" && rm -f "$R/pyproject.toml.bak"
git_ commit -q -am rename
ratchet
check 2 "$EC" "pyproject without [tool.ruff]: exits 2 ($OUT)"

echo "gate-ratchet.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
