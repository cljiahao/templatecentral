#!/usr/bin/env bash
# scripts/post-edit-lint.test.sh — tests for scripts/post-edit-lint.sh (stubbed lint script).
# Usage: bash scripts/post-edit-lint.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/post-edit-lint.sh"
command -v jq >/dev/null 2>&1 || { echo "post-edit-lint.test: jq missing, skipped"; exit 0; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/post-edit-lint.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
check() { # check <want-nonempty|empty> <got> <description>
  if { [[ "$1" == empty && -z "$2" ]] || [[ "$1" == output && -n "$2" ]]; }; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected $1, got [$2]"; fi
}

mkdir -p "$TMP/scripts" "$TMP/skills"
printf '#!/bin/bash\necho "ran" >> "%s/ran"\necho "── X ──"\necho "skills/a.md:1: bad"\necho "FAIL: broken"\nexit 1\n' "$TMP" > "$TMP/scripts/lint-skills.sh"

run() { rm -f "$TMP/ran"; printf '{"tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK"; }

out=$(run "$TMP/skills/a.md"); check output "$out" "skills edit reports lint failure"
case "$out" in *'"hookEventName":"PostToolUse"'*"skills/a.md:1: bad"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: additionalContext carries the hit lines"; esac
for f in README.md CHANGELOG.md AGENTS.md .claude-plugin/plugin.json scripts/other.sh src/x.ts; do
  out=$(run "$TMP/$f"); check empty "$out" "$f skips lint"
  if [[ -e "$TMP/ran" ]]; then FAIL=$((FAIL + 1)); echo "FAIL: lint ran for $f"; else PASS=$((PASS + 1)); fi
done
out=$(run "$TMP/scripts/lint-skills.sh"); check output "$out" "lint script edit runs lint"

echo "post-edit-lint.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
