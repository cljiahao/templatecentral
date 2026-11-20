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
    git -C "$P" add -A
    git -C "$P" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "chore: scaffold" || bad "$ST/$HOST base commit failed"
    git -C "$P" checkout -q -b work

    gate harness bash .claude/verify-harness.sh
    gate docs bash scripts/check-docs.sh
    if [ "$ST" = nextjs ]; then
      : # shadcn primitives are generated at scaffold time and count as source; without them the ratio is skewed, and they cannot be generated offline.
    else
      gate testbudget bash scripts/test-budget.sh
    fi
    gate nosonar bash .claude/ci-gates.sh nosonar
    gate workarounds bash scripts/check-workarounds.sh main
    gate ratchet bash scripts/gate-ratchet.sh auto
    gate envexample bash scripts/check-env-example.sh
    gate workflows bash scripts/check-workflows.sh
    gate supplychain bash scripts/check-supply-chain.sh
    gate dockerfile bash scripts/check-dockerfile.sh
  done
done

echo "day-one: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
