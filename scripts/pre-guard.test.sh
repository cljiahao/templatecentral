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

echo "== (f) path normalisation and case =="
run_guard '{"tool_input":{"file_path":".ENV"}}'
expect_exit "Tier1 upper-case .ENV" 2 "$code"
run_guard '{"tool_input":{"file_path":"./src/../.env.local"}}'
expect_exit "Tier1 ./ and .. folded" 2 "$code"
run_guard "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/.env\"}}"
expect_exit "Tier1 absolute path" 2 "$code"
run_guard '{"tool_input":{"file_path":"docs/.Env.Example"}}'
expect_exit "Tier1 exemption is case-insensitive" 0 "$code"

echo "== (g) Tier 2 instruction files =="
for f in CONSTITUTION.md docs/constitution.md Claude.md GEMINI.md .claude/rules/nextjs.md .claude/skills/tc-audit/SKILL.md .claude-plugin/plugin.json scripts/bash-guard.sh; do
  run_guard "{\"tool_input\":{\"file_path\":\"$f\"}}"
  expect_contains "Tier2 $f ask" "\"permissionDecision\":\"ask\"" "$out"
done
run_guard '{"tool_input":{"notebook_path":"AGENTS.md"}}'
expect_contains "Tier2 NotebookEdit path" "\"permissionDecision\":\"ask\"" "$out"
run_guard '{"tool_input":{"file_path":"x/\"q\"/AGENTS.md"}}'
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
  pass=$((pass + 1)); echo "  OK   ask JSON stays valid with quotes in path"
else
  fail=$((fail + 1)); echo "  FAIL ask JSON invalid: $out"
fi
run_guard '{"tool_input":{"file_path":"skills/add/SKILL.md"}}'
expect_exit "Tier3 skills/ allowed" 0 "$code"

echo "== (h) Read/Grep: secrets blocked, instruction files readable =="
run_guard '{"tool_name":"Read","tool_input":{"file_path":".env.uat"}}'
expect_exit "Read .env.uat blocked" 2 "$code"
run_guard '{"tool_name":"Grep","tool_input":{"path":"config/credentials.json"}}'
expect_exit "Grep credentials.json blocked" 2 "$code"
run_guard '{"tool_name":"Read","tool_input":{"file_path":"AGENTS.md"}}'
expect_exit "Read AGENTS.md allowed without ask" 0 "$code"
if [[ -z "$out" ]]; then
  pass=$((pass + 1)); echo "  OK   Read AGENTS.md emits no ask"
else
  fail=$((fail + 1)); echo "  FAIL Read AGENTS.md emitted: $out"
fi
run_guard "{\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}"
expect_contains "absolute ~/.claude/settings.json asks" "\"permissionDecision\":\"ask\"" "$out"

echo "== (i) bash-guard.sh =="
BG="$REPO_ROOT/scripts/bash-guard.sh"
E=.env
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/backend" "$SANDBOX/secrets"
touch "$SANDBOX/$E" "$SANDBOX/$E.example" "$SANDBOX/secrets/a"
NESTED=$(mktemp -d)
mkdir -p "$NESTED/backend"
touch "$NESTED/backend/$E"
# run_bash WANT_EXIT PROJECT_DIR CWD COMMAND
run_bash() {
  out=$(jq -cn --arg c "$4" --arg w "$3" '{tool_input:{command:$c},cwd:$w}' | CLAUDE_PROJECT_DIR="$2" bash "$BG" 2>&1)
  expect_exit "bash: $4" "$1" "$?"
}
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .env'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat ./.ENV'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .en?'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .[e]nv'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat secrets/*'
run_bash 2 "$SANDBOX" "$SANDBOX" 'python3 -c "print(open(\".env\").read())"'
# shellcheck disable=SC2016  # literal $PWD: the guard must expand it itself.
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat "$PWD/.env"'
run_bash 2 "$SANDBOX" "$SANDBOX" 'source .env && x'
run_bash 2 "$NESTED" "$NESTED/backend" 'cat .env'
run_bash 2 "$NESTED" "$NESTED" 'echo A > .env.local'
run_bash 2 "$NESTED" "$NESTED" 'cp .env.example .env'
run_bash 2 "$NESTED" "$NESTED" 'echo x | tee .env.prod'
run_bash 2 "$NESTED" "$NESTED" "cat > .env <<'EOF'
A=1
EOF"
run_bash 0 "$NESTED" "$NESTED" 'grep -rn ".env" skills 2>&1'
run_bash 0 "$SANDBOX" "$SANDBOX" 'cat .env.example'
run_bash 0 "$SANDBOX" "$SANDBOX" 'ls *.md'
run_bash 0 "$NESTED" "$NESTED" 'echo ".env" > notes.txt'
run_bash 0 "$NESTED" "$NESTED" 'git status'
run_bash 0 "$NESTED" "$NESTED" 'sed -n 1p .env.example > out.txt'
run_bash 0 "$NESTED" "$NESTED" "cat > t.sh <<'EOF'
cp .env.example .env
EOF"
rm -rf "$SANDBOX" "$NESTED"

echo ""
echo "pre-guard.sh matrix: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
