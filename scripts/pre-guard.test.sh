#!/usr/bin/env bash
# scripts/pre-guard.test.sh — behavioral test for scripts/pre-guard.sh's tiering + fail-closed logic.
# Complements the existing shellcheck/bash -n syntax checks with real invocations.
#
# Usage: bash scripts/pre-guard.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/pre-guard.sh"

pass=0
fail=0

# run_guard INPUT_JSON  [FAKE_PATH]
# Runs pre-guard.sh with INPUT_JSON on stdin, optionally with PATH overridden to FAKE_PATH
# (used to simulate jq being missing). Sets $out and $code.
run_guard() {
  local input="$1"
  local fakepath="${2:-}"
  if [[ -n "$fakepath" ]]; then
    out=$(printf '%s' "$input" | PATH="$fakepath" bash "$GUARD" 2>&1)
  else
    out=$(printf '%s' "$input" | bash "$GUARD" 2>&1)
  fi
  code=$?
}

expect_exit() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    pass=$((pass + 1))
    echo "  OK   $name (exit $got)"
  else
    fail=$((fail + 1))
    echo "  FAIL $name — expected exit $want, got $got"
  fi
}

expect_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass + 1))
    echo "  OK   $name (contains \"$needle\")"
  else
    fail=$((fail + 1))
    echo "  FAIL $name — expected output to contain \"$needle\", got: $haystack"
  fi
}

echo "== (a) jq missing -> fail-closed =="
FAKEBIN=$(mktemp -d)
# Minimal PATH: only 'bash' + 'cat' (and bash builtins) available, no jq.
ln -s "$(command -v bash)" "$FAKEBIN/bash"
ln -s "$(command -v cat)" "$FAKEBIN/cat"
run_guard '{"tool_input":{"file_path":"src/app.ts"}}' "$FAKEBIN"
expect_exit "jq missing" 2 "$code"
expect_contains "jq missing message" "jq required" "$out"
rm -rf "$FAKEBIN"

echo "== (b) malformed JSON -> fail-closed =="
run_guard 'not json at all {{{'
expect_exit "malformed JSON" 2 "$code"
expect_contains "malformed JSON message" "failed to parse" "$out"

echo "== (c) Tier 1 hard-block =="
run_guard '{"tool_input":{"file_path":".env"}}'
expect_exit "Tier1 .env" 2 "$code"
expect_contains "Tier1 .env message" "BLOCKED (secret/credential)" "$out"

run_guard '{"tool_input":{"file_path":"src/certs/server.pem"}}'
expect_exit "Tier1 .pem" 2 "$code"

run_guard '{"tool_input":{"file_path":".env.example"}}'
expect_exit "Tier1 exemption: .env.example allowed" 0 "$code"

echo "== (d) Tier 2 ask =="
run_guard '{"tool_input":{"file_path":".claude/settings.local.json"}}'
expect_exit "Tier2 settings.local.json exit" 0 "$code"
expect_contains "Tier2 settings.local.json ask" "\"permissionDecision\":\"ask\"" "$out"

run_guard '{"tool_input":{"file_path":".claude/agents/reviewer.md"}}'
expect_exit "Tier2 .claude/agents/* exit" 0 "$code"
expect_contains "Tier2 .claude/agents/* ask" "\"permissionDecision\":\"ask\"" "$out"

run_guard '{"tool_input":{"file_path":".mcp.json"}}'
expect_exit "Tier2 .mcp.json exit" 0 "$code"
expect_contains "Tier2 .mcp.json ask" "\"permissionDecision\":\"ask\"" "$out"

run_guard '{"tool_input":{"file_path":"AGENTS.md"}}'
expect_exit "Tier2 AGENTS.md exit" 0 "$code"
expect_contains "Tier2 AGENTS.md ask" "\"permissionDecision\":\"ask\"" "$out"

echo "== (e) Tier 3 normal allow =="
run_guard '{"tool_input":{"file_path":"src/app.ts"}}'
expect_exit "Tier3 allow exit" 0 "$code"
if [[ -z "$out" ]]; then
  pass=$((pass + 1))
  echo "  OK   Tier3 allow (no ask JSON emitted)"
else
  fail=$((fail + 1))
  echo "  FAIL Tier3 allow — expected empty output, got: $out"
fi

echo ""
echo "pre-guard.sh matrix: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
