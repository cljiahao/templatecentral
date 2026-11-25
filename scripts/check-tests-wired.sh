#!/usr/bin/env bash
# scripts/check-tests-wired.sh — fail when a scripts/*.test.sh file is not run by any workflow step.
# Usage: bash scripts/check-tests-wired.sh [scripts dir] [workflow dir]   (defaults: this repo's)
# A test counts as run when a workflow line that is not a comment holds "bash scripts/<name>" as a whole word.
# It also fails when it finds no test file or no workflow file, so it cannot pass on nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${1:-$ROOT/scripts}"
WORKFLOWS="${2:-$ROOT/.github/workflows}"

shopt -s nullglob
tests=("$SCRIPTS"/*.test.sh)
workflows=("$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml)
shopt -u nullglob

[[ ${#tests[@]} -gt 0 ]] || { echo "FAIL: no *.test.sh file in $SCRIPTS"; exit 1; }
[[ ${#workflows[@]} -gt 0 ]] || { echo "FAIL: no workflow file in $WORKFLOWS"; exit 1; }

lines=$(awk '!/^[[:space:]]*#/' "${workflows[@]}") || { echo "FAIL: cannot read the workflow files in $WORKFLOWS"; exit 1; }

missing=0
for t in "${tests[@]}"; do
  name=${t##*/}
  pattern="bash scripts/${name//./\\.}([^A-Za-z0-9._-]|\$)"
  if ! grep -qE "$pattern" <<<"$lines"; then
    echo "FAIL: scripts/$name is not run by any workflow step"
    missing=$((missing + 1))
  fi
done

[[ $missing -eq 0 ]] || exit 1
echo "OK: all ${#tests[@]} scripts/*.test.sh files are run by a workflow step"
