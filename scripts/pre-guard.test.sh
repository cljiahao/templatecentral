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
run_guard '{"tool_name":"Grep","tool_input":{"path":"secrets"}}'
expect_exit "Grep secrets/ dir blocked" 2 "$code"
run_guard '{"tool_name":"Read","tool_input":{"file_path":"docs/secrets.md"}}'
expect_exit "Read docs/secrets.md (name contains secrets) allowed" 0 "$code"
run_guard '{"tool_name":"Read","tool_input":{"file_path":"AGENTS.md"}}'
expect_exit "Read AGENTS.md allowed without ask" 0 "$code"
if [[ -z "$out" ]]; then
  pass=$((pass + 1)); echo "  OK   Read AGENTS.md emits no ask"
else
  fail=$((fail + 1)); echo "  FAIL Read AGENTS.md emitted: $out"
fi
run_guard "{\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}"
expect_contains "absolute ~/.claude/settings.json asks" "\"permissionDecision\":\"ask\"" "$out"

echo "== (h2) scratch dirs skip Tier 2 only =="
SCRATCH=$(mktemp -d /tmp/pre-guard-scratch.XXXXXX)
TMPD=$(mktemp -d)
LINKDIR=$(mktemp -d /tmp/pre-guard-link.XXXXXX)
ln -s "$REPO_ROOT" "$LINKDIR/repo"
ask_json() { printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; }
expect_allowed() {
  if [[ "$code" == 0 && -z "$out" ]]; then pass=$((pass + 1)); echo "  OK   $1 allowed"
  else fail=$((fail + 1)); echo "  FAIL $1 — expected silent allow, got exit $code: $out"; fi
}
expect_asks() {
  if [[ "$code" == 0 ]] && ask_json; then pass=$((pass + 1)); echo "  OK   $1 asks"
  else fail=$((fail + 1)); echo "  FAIL $1 — expected ask, got exit $code: $out"; fi
}
run_guard '{"tool_input":{"file_path":"/tmp/scaffold-e2e/Dockerfile"}}'
expect_allowed "/tmp/scaffold-e2e/Dockerfile"
run_guard "{\"tool_input\":{\"file_path\":\"$SCRATCH/app/Dockerfile\"}}"
expect_allowed "existing /tmp subdir Dockerfile"
out=$(printf '%s' "{\"tool_input\":{\"file_path\":\"$TMPD/a/b/Dockerfile\"}}" | TMPDIR="$TMPD" bash "$GUARD" 2>&1); code=$?
expect_allowed "\$TMPDIR/.../Dockerfile"
run_guard "{\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}"
expect_asks "\$HOME/.claude/settings.json"
run_guard "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/Dockerfile\"}}"
expect_asks "in-repo Dockerfile"
run_guard '{"tool_input":{"file_path":"Dockerfile"}}'
expect_asks "relative in-repo Dockerfile"
run_guard "{\"tool_input\":{\"file_path\":\"/tmp/../${REPO_ROOT#/}/Dockerfile\"}}"
expect_asks "/tmp/.. path into repo"
run_guard "{\"tool_input\":{\"file_path\":\"$LINKDIR/repo/Dockerfile\"}}"
expect_asks "/tmp symlink into repo"
run_guard '{"tool_input":{"file_path":"/tmp/nonexistent-dir/../Dockerfile"}}'
expect_asks "/tmp unresolvable .. tail"
run_guard '{"tool_input":{"file_path":"/tmp/x/.env"}}'
expect_exit "/tmp/x/.env still blocked" 2 "$code"
run_guard '{"tool_input":{"file_path":"/tmp/x/server.pem"}}'
expect_exit "/tmp/x/server.pem still blocked" 2 "$code"

# run_env INPUT_JSON VAR=value... — runs the guard with an explicit environment.
run_env() {
  local input="$1"; shift
  out=$(printf '%s' "$input" | env "$@" bash "$GUARD" 2>&1)
  code=$?
}
fj() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "${2:-Write}" "$1"; }
RT=$(mktemp -d /tmp/pg-repo.XXXXXX)
SIB=$(mktemp -d /tmp/pg-sib.XXXXXX)
HOMEDIR="$HOME/pre-guard-nonexistent-scratch"

# $TMPDIR outside a system temp tree, or covering $HOME / the repo, is ignored.
run_env "$(fj "$HOME/.claude/settings.json")" "TMPDIR=$HOME"
expect_asks "TMPDIR=\$HOME: ~/.claude/settings.json"
run_env "$(fj "$HOMEDIR/Dockerfile")" "TMPDIR=$HOME"
expect_asks "TMPDIR=\$HOME: Dockerfile under home"
run_env "$(fj "$HOME/.claude/settings.json")" "TMPDIR=$(dirname "$HOME")"
expect_asks "TMPDIR=parent of home"
run_env "$(fj "$HOMEDIR/Dockerfile")" "TMPDIR=$(dirname "$REPO_ROOT")"
expect_asks "TMPDIR=ancestor of repo"
run_env "$(fj "$HOMEDIR/Dockerfile")" "TMPDIR=/"
expect_asks "TMPDIR=/"
run_env "$(fj "$REPO_ROOT/scripts/Dockerfile")" "TMPDIR=$REPO_ROOT/scripts"
expect_asks "TMPDIR inside the repo"
run_env "$(fj "$HOMEDIR/Dockerfile")" -u TMPDIR
expect_asks "TMPDIR unset: non-/tmp target"
run_env "$(fj "$HOMEDIR/Dockerfile")" "TMPDIR=$TMPD"
expect_asks "TMPDIR set elsewhere: unrelated target"
run_env "$(fj "$SIB/Dockerfile")" "TMPDIR=$HOME"
expect_allowed "/tmp target allowed while TMPDIR=\$HOME"

# Repo root under /tmp: /tmp contains the repo, so it is no scratch base and everything asks.
run_env "$(fj "$RT/Dockerfile")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "repo under /tmp: in-repo Dockerfile"
run_env "$(fj "$SIB/Dockerfile")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "repo under /tmp: sibling dir Dockerfile"
run_env "$(fj "../$(basename "$SIB")/Dockerfile")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "repo under /tmp: relative .. into sibling dir"
run_env "$(fj "../../../../../../../../tmp/$(basename "$SIB")/Dockerfile")"
expect_allowed "relative .. out of the repo into /tmp"
run_env "$(fj "../$(basename "$RT")/Dockerfile")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "relative .. back into the repo"
run_env "$(fj "$SIB/Dockerfile/")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "trailing slash"
ln -s "$RT/Dockerfile" "$SIB/Dockerfile"
run_env "$(fj "$SIB/Dockerfile")" "CLAUDE_PROJECT_DIR=$RT"
expect_asks "symlink leaf in /tmp"
rm -f "$SIB/Dockerfile"

# Case: folded only where the filesystem folds it. Detection also probes the target ancestor and
# scratch base, which needs a casefold mount to exercise; a case-sensitive /tmp must not fold.
if [[ "$(uname -s)" == "Darwin" ]]; then
  run_guard '{"tool_input":{"file_path":"/TMP/scaffold-e2e/Dockerfile"}}'
  expect_allowed "case-insensitive fs: /TMP"
else
  run_guard '{"tool_input":{"file_path":"/TMP/scaffold-e2e/Dockerfile"}}'
  expect_asks "case-sensitive fs: /TMP"
fi

# A /tmp symlink into the repo matches the anchored Tier 2 patterns on the resolved path.
run_guard "{\"tool_input\":{\"file_path\":\"$LINKDIR/repo/scripts/pre-guard.sh\"}}"
expect_asks "symlink into repo: scripts/pre-guard.sh"
run_guard "{\"tool_input\":{\"file_path\":\"$LINKDIR/repo/.claude/settings.json\"}}"
expect_asks "symlink into repo: .claude/settings.json"
run_guard "{\"tool_input\":{\"file_path\":\"$LINKDIR/repo/skills/add/SKILL.md\"}}"
expect_allowed "symlink into repo: unprotected file"

# Every writing tool name takes the same decision.
for t in Write Edit MultiEdit NotebookEdit; do
  run_guard "$(fj /tmp/scaffold-e2e/Dockerfile "$t")"
  expect_allowed "$t /tmp/scaffold-e2e/Dockerfile"
  run_guard "$(fj "$REPO_ROOT/Dockerfile" "$t")"
  expect_asks "$t in-repo Dockerfile"
done

# Symlink leaves are followed, never judged by their own name.
ln -s "$REPO_ROOT/scripts/pre-guard.sh" "$SIB/notes.txt"
run_guard "$(fj "$SIB/notes.txt")"
expect_asks "leaf symlink in /tmp into the repo"
ln -s "$REPO_ROOT/scripts/Dockerfile" "$SIB/dangle.txt"
run_guard "$(fj "$SIB/dangle.txt")"
expect_asks "dangling leaf symlink into the repo"
ln -s "$SIB/loop-b" "$SIB/loop-a"; ln -s "$SIB/loop-a" "$SIB/loop-b"
run_guard "$(fj "$SIB/loop-a")"
expect_asks "symlink hop loop"
ln -s .claude/settings.json "$REPO_ROOT/pg-leaf-link.txt"
run_guard "$(fj pg-leaf-link.txt)"
expect_asks "in-repo leaf symlink to .claude/settings.json"
rm -f "$REPO_ROOT/pg-leaf-link.txt"
ln -s "$REPO_ROOT/.secrets" "$SIB/secretlink"
run_guard "$(fj "$SIB/secretlink/foo.txt")"
expect_exit "Tier 1 through a /tmp directory symlink" 2 "$code"
ln -s "$REPO_ROOT/.env" "$SIB/.env.example"
run_guard "$(fj "$SIB/.env.example")"
expect_exit "Tier 1: .env.example link to .env" 2 "$code"
run_guard "$(fj "$SIB/secretlink/foo.txt" Read)"
expect_exit "Tier 1 on Read through a symlink" 2 "$code"

# /tmp is no scratch base when it is or contains $HOME; an unset HOME disables the exemption.
mkdir -p "$SIB/h"
run_env "$(fj "$SIB/h/.claude/settings.json")" "HOME=$SIB/h"
expect_asks "HOME=/tmp/h: \$HOME/.claude/settings.json"
run_env "$(fj /tmp/scaffold-e2e/Dockerfile)" "HOME=/tmp"
expect_asks "HOME=/tmp: /tmp Dockerfile"
run_env "$(fj /tmp/scaffold-e2e/Dockerfile)" -u HOME
expect_asks "HOME unset"

# Symlinks to protected files outside the repo are matched on the resolved absolute path.
ln -s "$HOME/.claude/settings.json" "$SIB/home-settings.txt"
run_guard "$(fj "$SIB/home-settings.txt")"
expect_asks "/tmp link to a .claude/settings.json"
ln -s "$HOME/.claude/settings.json" "$REPO_ROOT/pg-foreign-link.txt"
run_guard "$(fj pg-foreign-link.txt)"
expect_asks "in-repo link to a foreign .claude/settings.json"
rm -f "$REPO_ROOT/pg-foreign-link.txt"
ln -s "$HOME/.claude" "$SIB/claude-dir"
run_guard "$(fj "$SIB/claude-dir/settings.json")"
expect_asks "/tmp dir link to a .claude dir"

# Absolute ~/.claude coverage; session memory stays unprompted.
for f in rules/x.md skills/x/SKILL.md commands/x.md keybindings.json settings.json; do
  run_guard "$(fj "$HOME/.claude/$f")"
  expect_asks "\$HOME/.claude/$f"
done
run_guard "$(fj "$HOME/.claude/projects/p/memory/m.md")"
expect_allowed "\$HOME/.claude/projects/p/memory/m.md"

# An ancestor named secrets / .secrets does not make in-repo targets secret.
for d in secrets .secrets; do
  SR="$SIB/$d/repo"; mkdir -p "$SR/src"
  run_env "$(fj src/a.ts)" "CLAUDE_PROJECT_DIR=$SR"
  expect_allowed "repo under $d/: src/a.ts"
  run_env "$(fj "$SR/src/a.ts")" "CLAUDE_PROJECT_DIR=$SR"
  expect_allowed "repo under $d/: absolute src/a.ts"
  run_env "$(fj .env)" "CLAUDE_PROJECT_DIR=$SR"
  expect_exit "repo under $d/: .env blocked" 2 "$code"
done
rm -rf "$RT" "$SIB"
rm -rf "$SCRATCH" "$TMPD" "$LINKDIR"

echo "== (i) bash-guard.sh =="
BG="$REPO_ROOT/scripts/bash-guard.sh"
E=.env
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/backend" "$SANDBOX/secrets" "$SANDBOX/upper"
# Separate dir: on case-insensitive filesystems .ENV and .env are the same file.
touch "$SANDBOX/$E" "$SANDBOX/$E.example" "$SANDBOX/secrets/a" "$SANDBOX/upper/.ENV"
NESTED=$(mktemp -d)
mkdir -p "$NESTED/backend"
touch "$NESTED/backend/$E"
# run_bash WANT_EXIT PROJECT_DIR CWD COMMAND
run_bash() {
  out=$(jq -cn --arg c "$4" --arg w "$3" '{tool_input:{command:$c},cwd:$w}' | CLAUDE_PROJECT_DIR="$2" bash "$BG" 2>&1)
  expect_exit "bash: $4" "$1" "$?"
}
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .env'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat ./upper/.ENV'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .en?'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat .[e]nv'
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat secrets/*'
run_bash 2 "$SANDBOX" "$SANDBOX" 'python3 -c "print(open(\".env\").read())"'
# shellcheck disable=SC2016  # literal $PWD: the guard must expand it itself.
run_bash 2 "$SANDBOX" "$SANDBOX" 'cat "$PWD/.env"'
run_bash 2 "$SANDBOX" "$SANDBOX" 'source .env && x'
run_bash 2 "$NESTED" "$NESTED/backend" 'cat .env'
run_bash 2 "$NESTED" "$NESTED" 'cd backend && cat .env'
run_bash 2 "$SANDBOX" "$SANDBOX" 'tar czf x.tgz secrets'
run_bash 2 "$NESTED" "$NESTED" 'cd "backend" && cat .env'
run_bash 2 "$NESTED" "$NESTED/backend" 'cd .. && cd backend; cat .env'
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
run_bash 0 "$NESTED" "$NESTED" 'grep -rn secrets docs'
run_bash 0 "$NESTED" "$NESTED" 'cd backend && cat .env.example'
run_bash 0 "$NESTED" "$NESTED" 'cd nowhere && cat .env'
run_bash 0 "$NESTED" "$NESTED" 'sed -n 1p .env.example > out.txt'
run_bash 0 "$NESTED" "$NESTED" "cat > t.sh <<'EOF'
cp .env.example .env
EOF"
rm -rf "$SANDBOX" "$NESTED"

echo ""
echo "pre-guard.sh matrix: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
