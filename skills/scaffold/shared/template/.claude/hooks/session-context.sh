#!/usr/bin/env bash
# SessionStart(startup|resume|clear|compact): AGENTS.md is already loaded, so print only what it cannot know.
# Every source: a line when the checkout sits on a protected branch. Compact: three invariant lines.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
input=$(cat)
branch=$(git symbolic-ref --short -q HEAD 2>/dev/null)
case "$branch" in
  main|uat|develop) echo "On protected branch $branch: commits here are blocked; branch off a fresh main before editing." ;;
esac
if printf '%s' "$input" | grep -Eq '"source"[[:space:]]*:[[:space:]]*"compact"'; then
  echo "Never read or write secrets (.env*, secrets/); never commit to main/uat/develop."
  echo "Run the quality gate before declaring a task done."
  echo "Binding invariants and the protected-file list: docs/CONSTITUTION.md."
fi
exit 0
