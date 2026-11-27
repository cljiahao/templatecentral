#!/usr/bin/env bash
# scripts/day-one.test.sh — scaffold each stack and CI host with tc-copy.sh into a temp repo and run every seeded gate that needs no network or install; each must pass on day one.
# Regression test for gates that contradict the files the scaffold itself writes (for example the nosonar gate against the lint rule that lists the marker).
# Usage: bash scripts/day-one.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/dayone.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

clean() { env -u CI -u GITHUB_ACTIONS -u TF_BUILD "$@"; }

# gate <label> <command...>: run in $P; a pass needs exit 0.
gate() {
  local label=$1 out rc
  shift
  out=$(cd "$P" && clean "$@" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then ok; else bad "$ST/$HOST $label exited $rc"; printf '%s\n' "$out" | tail -8 | sed 's/^/    /'; fi
}

# obtain_ruff: sets RUFF_CMD to ruff from PATH, else uvx, else a pip install of the spec the seeded project pins in
# requirements-dev.txt into the temp dir (no sudo, no account, no key). Returns 1 when none works. Tried once per run.
RUFF_STATE=""
RUFF_CMD=()
obtain_ruff() {
  if [ -n "$RUFF_STATE" ]; then [ "$RUFF_STATE" = ok ]; return; fi
  RUFF_STATE=no
  local spec
  spec=$(sed -n 's/^\(ruff[<>=!~][^[:space:]#]*\).*$/\1/p' "$REPO_ROOT/skills/scaffold/fastapi/template/requirements-dev.txt" | head -1)
  if command -v ruff > /dev/null 2>&1; then
    RUFF_CMD=(ruff); RUFF_STATE=ok
  elif [ -n "$spec" ] && command -v uvx > /dev/null 2>&1; then
    RUFF_CMD=(uvx --from "$spec" ruff); RUFF_STATE=ok
  elif [ -n "$spec" ] && command -v python3 > /dev/null 2>&1; then
    if python3 -m pip install -q --disable-pip-version-check --target "$T/ruffpkg" "$spec" > /dev/null 2>&1 && [ -x "$T/ruffpkg/bin/ruff" ]; then
      RUFF_CMD=("$T/ruffpkg/bin/ruff"); RUFF_STATE=ok
    fi
  fi
  [ "$RUFF_STATE" = ok ]
}

# ruff_gate: ruff format --check and ruff check on the seeded FastAPI src and test; with no ruff the case is skipped locally and fails closed in CI.
ruff_gate() {
  if ! obtain_ruff; then
    if [ -n "${CI:-}${GITHUB_ACTIONS:-}${TF_BUILD:-}" ]; then bad "$ST/$HOST ruff is not available in CI, so the seeded tests were not format-checked"
    else echo "SKIPPED: ruff could not be found or installed, so the seeded FastAPI src and test were NOT format-checked."; fi
    return 0
  fi
  local -a r=("${RUFF_CMD[@]}")
  gate ruff-format "${r[@]}" format --check src/ test/
  gate ruff-check "${r[@]}" check src/ test/
  local f
  for f in "$P"/scripts/*.py; do
    gate "ruff check skips ${f##*/}" "${r[@]}" check "scripts/${f##*/}"
    gate "ruff format skips ${f##*/}" "${r[@]}" format --check "scripts/${f##*/}"
  done
}

# gate_default FILE KEY: the first default value written as KEY...} in FILE.
gate_default() {
  awk -v key="$2" 'index($0, key) { v = substr($0, index($0, key) + length(key)); sub(/\}.*/, "", v); print v; exit }' "$1"
}

# gate_outputs_ignored: every path a seeded gate writes is ignored and the tree stays clean; rows are <path> <writer>.
# SBOM needs a lockfile (network) and a review record needs a verdict, so those files are made by hand.
gate_outputs_ignored() {
  local sbom dc rows row p dirty
  sbom=$(gate_default "$P/scripts/generate-sbom.sh" 'SBOM_OUT:-')
  dc=$(gate_default "$P/.claude/ci-gates.sh" 'DIFF_COVER_OUTPUT:-')
  if [ -z "$sbom" ] || [ -z "$dc" ]; then bad "$ST/$HOST cannot read the SBOM or diff-cover output path from the gates"; return; fi
  rows="$sbom sbom-gate
$dc diffcover-gate
dist/x bundle-gate-build-and-sbom
.claude/gate-times.tsv gate-budget-record
.claude/gate-times.AbC123 gate-budget-temp-file
.claude/review/current.diff record-review-prepare"
  case $ST in
    fastapi) rows="$rows
coverage.xml verify-gate-pytest-cov
.coverage verify-gate-pytest-cov
htmlcov/x verify-gate-pytest-cov
.pytest_cache/x verify-gate-pytest
.ruff_cache/x verify-gate-ruff" ;;
    *) rows="$rows
coverage/x verify-gate-vitest-coverage
tsconfig.tsbuildinfo verify-gate-tsc" ;;
  esac
  if [ "$ST" = nextjs ]; then rows="$rows
.next/x bundle-gate-build"; fi
  while IFS= read -r row; do
    p=${row%% *}
    if ! git -C "$P" check-ignore -q "$p"; then bad "$ST/$HOST ${row#* } writes $p but .gitignore does not ignore it"; fi
  done <<< "$rows"
  # dist/ is the root build and SBOM output only; developer source under src/ must stay visible to the git gates.
  if git -C "$P" check-ignore -q src/dist/x; then bad "$ST/$HOST ignores src/dist/x, which hides developer source from the git gates"; fi
  mkdir -p "$P/$(dirname "$sbom")" "$P/.claude/review" && : > "$P/$sbom" && : > "$P/$dc" && : > "$P/.claude/review/current.diff"
  dirty=$(git -C "$P" status --porcelain)
  if [ -z "$dirty" ]; then ok; else bad "$ST/$HOST tree is dirty after the gates: $dirty"; fi
}

# ts_helpers_skipped: every hash-guarded seeded scripts/*.mjs is named in the eslint ignores and in .prettierignore, so the first commit's format-lint cannot parse-fail or rewrite it.
ts_helpers_skipped() {
  local list f stem
  list=$(grep -o '"scripts/[^"]*\.mjs"' "$P/.claude/harness.json" | tr -d '"')
  if [ -z "$list" ]; then bad "$ST/$HOST harness.json lists no seeded scripts/*.mjs"; return 0; fi
  for f in $list; do
    stem=${f#scripts/}
    stem=${stem%.mjs}
    gate "eslint ignores $f" grep -Eq "'scripts/(\{([a-z-]+,)*$stem(,[a-z-]+)*\}|$stem)\.mjs'" eslint.config.mjs
    gate "prettier ignores $f" grep -qx "$f" .prettierignore
  done
}

for ST in nestjs nextjs vite-react fastapi; do
  for HOST in github azure; do
    P="$T/$ST-$HOST"
    mkdir -p "$P"
    for part in stack base agents settings late; do
      TC_STACK=$ST TC_PART=$part bash "$SHARED/tc-copy.sh" "$P" > /dev/null 2>&1 || bad "$ST/$HOST tc-copy part $part failed"
    done
    TC_STACK=$ST TC_PART=ci TC_CI=$HOST bash "$SHARED/tc-copy.sh" "$P" > /dev/null 2>&1 || bad "$ST/$HOST tc-copy part ci failed"
    TC_STACK=$ST TC_PART=manifest bash "$SHARED/tc-copy.sh" "$P" > /dev/null 2>&1 || bad "$ST/$HOST tc-copy part manifest failed"
    printf '# %s\n\nA scaffolded project.\n' "$ST" > "$P/README.md"
    git -C "$P" init -q -b main
    git -C "$P" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m "chore: root"
    ROOT=$(git -C "$P" rev-parse HEAD)
    git -C "$P" add -A
    git -C "$P" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "chore: scaffold" || bad "$ST/$HOST base commit failed"
    git -C "$P" checkout -q -b work

    gate harness bash .claude/verify-harness.sh
    gate docs bash scripts/check-docs.sh
    gate testbudget bash scripts/test-budget.sh
    gate nosonar bash .claude/ci-gates.sh nosonar
    gate workarounds bash scripts/check-workarounds.sh main
    gate workarounds-whole-scaffold bash scripts/check-workarounds.sh "$ROOT"
    gate ratchet bash scripts/gate-ratchet.sh auto
    gate ratchet-whole-scaffold bash scripts/gate-ratchet.sh "$ROOT"
    gate envexample bash scripts/check-env-example.sh
    gate workflows bash scripts/check-workflows.sh
    gate supplychain bash scripts/check-supply-chain.sh
    gate dockerfile bash scripts/check-dockerfile.sh
    gate_outputs_ignored
    gate changelog-seeded bash -c 'head -n 1 CHANGELOG.md | grep -qx "# Changelog" && grep -qx "## \[Unreleased\]" CHANGELOG.md'
    case $ST in
      fastapi)
        gate ignores bash -c 'git check-ignore -q coverage.xml && git check-ignore -q .coverage'
        gate coverage-floor grep -q 'fail_under = 80' pyproject.toml
        ruff_gate
        gate exclusions bash scripts/check-exclude-reasons.sh
        ;;
      nestjs)
        gate ignores bash -c 'git check-ignore -q coverage/x && git check-ignore -q blob/x'
        ts_helpers_skipped
        gate test-budget-headroom env TEST_BUDGET_MAX_RATIO=32 bash scripts/test-budget.sh
        gate coverage-floor grep -Eq 'thresholds: [{] lines: 80' vitest.config.mts
        ;;
      nextjs)
        gate ignores bash -c 'git check-ignore -q coverage/x'
        ts_helpers_skipped
        gate test-budget-headroom env TEST_BUDGET_MAX_RATIO=34.5 bash scripts/test-budget.sh
        gate coverage-floor grep -Eq 'thresholds: [{] lines: 80' vitest.config.ts
        ;;
      vite-react)
        gate ignores bash -c 'git check-ignore -q coverage/x'
        ts_helpers_skipped
        gate coverage-floor grep -Eq 'thresholds: [{] lines: 80' vite.config.ts
        ;;
    esac
  done
done

echo "day-one: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
