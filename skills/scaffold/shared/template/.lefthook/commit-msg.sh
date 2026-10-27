#!/usr/bin/env bash
# Conventional Commits gate. Invoked by lefthook commit-msg with the message file as $1.
set -euo pipefail
msg=$(head -1 "$1")

# Allow git-generated subjects (merge, revert, autosquash) and release commits.
if printf '%s' "$msg" | grep -qE '^(Merge |Revert |fixup! |squash! |amend! )' || [[ "$msg" == "chore(release):"* ]]; then
  exit 0
fi

pattern='^(feat|fix|chore|docs|style|refactor|test|ci|perf|build|revert)(\([a-z0-9/._-]+\))?!?: .{1,100}$'
if ! printf '%s' "$msg" | grep -qE "$pattern"; then
  {
    echo "❌ Commit message must follow Conventional Commits:"
    echo "   <type>(<scope>)!: <description>   e.g.  feat(auth): add OAuth2 sign-in   (! marks a breaking change)"
    echo "   types: feat fix chore docs style refactor test ci perf build revert"
    echo "   your message: $msg"
  } >&2
  exit 1
fi
