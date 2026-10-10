#!/bin/bash
# PostToolUse feedback: runs the skill lint only when the edited file can affect it, and
# returns failures as additionalContext (plain stdout on exit 0 never reaches Claude).
# Always exits 0 — feedback, not a gate; CI enforces.

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
file="${file#"$PWD"/}"
case "$file" in
  skills/*|scripts/*|.claude-plugin/*|.claude/harness.json|AGENTS.md|README.md|CHANGELOG.md) ;;
  *) exit 0 ;;
esac

out=$(bash scripts/lint-skills.sh skills/ 2>&1) && exit 0
# Keep each failing section whole (header, file:line hits, FAIL line) so Claude sees locations.
failures=$(printf '%s\n' "$out" | awk '/^── /{buf=""} {buf=buf $0 "\n"} /^FAIL/{printf "%s", buf; buf=""}' | head -60)
jq -cn --arg c "lint-skills.sh failed after editing $file:
${failures:-$(printf '%s\n' "$out" | tail -20)}" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
