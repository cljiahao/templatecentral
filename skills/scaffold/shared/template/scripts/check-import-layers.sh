#!/usr/bin/env bash
# Import-layer gate: runs import-linter (lint-imports) on every fastapi app, so a layer that imports one it must not fails before it merges. The TypeScript stacks enforce the same rule with ESLint no-restricted-imports.
# An app is found by its files, in any folder (backend/, apps/api/): a requirements*.txt, requirements.in or pyproject.toml that names fastapi, or a pyproject.toml with [tool.importlinter]. Each app needs [tool.importlinter] and at least one [[tool.importlinter.contracts]] in its pyproject.toml.
# lint-imports comes from the app's .venv/bin, else the PATH. It runs inside the app folder with the app's src/ on PYTHONPATH, and the gate fails when it exits non-zero or reports no contract kept.
# Fails closed: a fastapi app with no contract, a missing lint-imports (one line, never a skip), a lint-imports that analysed zero contracts.
# Nothing checked (exit 0, own line): no fastapi app and no [tool.importlinter] anywhere in the tracked files.
# Exit: 0 every contract kept or nothing checked, 1 a broken contract or a missing rule, 2 it could not run (no git, unreadable input).
# Not caught: a developer who edits files outside git and the hooks on their own machine and never opens a PR; git commit --no-verify locally (CI still runs the gate); a host with no CI; an import hidden from lint-imports (a runtime importlib call; ruff and review cover it); a contract that was weak from the start.
# Usage: bash scripts/check-import-layers.sh
set -uo pipefail
export LC_ALL=C
export GIT_LITERAL_PATHSPECS=1

die() {
  printf 'check-import-layers: %s\n' "$1" >&2
  exit 2
}

failed=0
checked=0
# Prints a failure line and marks the run failed, so every broken app shows in one run.
fail() {
  printf 'check-import-layers: FAIL: %s\n' "$1" >&2
  failed=1
}

command -v git > /dev/null 2>&1 || die "git is not installed"
top=$(git rev-parse --show-toplevel 2> /dev/null) || die "not a git repository"
cd "$top" || die "cannot enter $top"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-import-layers.XXXXXX") || die "cannot create a temporary folder in ${TMPDIR:-/tmp}"
trap 'rm -rf "$tmp"' EXIT

git -c core.quotepath=false ls-files -z --cached --others --exclude-standard > "$tmp/all.z" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"

# Counts matches of extended pattern $2 in file $1; stops the run when the file cannot be read.
count_in() {
  local n
  n=$(grep -a -i -E -c -e "$2" -- "$1" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then die "cannot read $1: $(head -n 1 "$tmp/err.txt")"; fi
  echo "$n"
}

: > "$tmp/dirs.txt"
while IFS= read -r -d '' p; do
  case "$p" in *$'\n'*) die "a file name holds a line break: refusing to read it" ;; esac
  [ -f "$p" ] || continue
  case "${p##*/}" in
    requirements*.txt | requirements.in)
      if [ "$(count_in "$p" '(^|[^A-Za-z0-9_-])fastapi([^A-Za-z0-9_-]|$)')" -gt 0 ]; then dirname "$p" >> "$tmp/dirs.txt"; fi
      ;;
    pyproject.toml)
      if [ "$(count_in "$p" '^[[:space:]]*\[tool\.importlinter\]|(^|[^A-Za-z0-9_-])fastapi([^A-Za-z0-9_-]|$)')" -gt 0 ]; then dirname "$p" >> "$tmp/dirs.txt"; fi
      ;;
  esac
done < "$tmp/all.z"
sort -u "$tmp/dirs.txt" > "$tmp/dirs.sorted" || die "cannot sort the app folders"

# Checks the app folder $1.
check_app() {
  local dir=$1 label=$1 pp lint out rc
  [ "$dir" = . ] && label='the repository root'
  pp=$dir/pyproject.toml
  if [ ! -f "$pp" ] || [ -L "$pp" ]; then
    fail "$label: fastapi app with no pyproject.toml (or a symlink), so [tool.importlinter] cannot be read. Add it: the layer contract is in the scaffold's pyproject.toml."
    return
  fi
  if [ "$(count_in "$pp" '^[[:space:]]*\[tool\.importlinter\]')" -eq 0 ] || [ "$(count_in "$pp" '^[[:space:]]*\[\[tool\.importlinter\.contracts\]\]')" -eq 0 ]; then
    fail "$label: $pp has no [tool.importlinter] with a [[tool.importlinter.contracts]], so no layer rule is enforced. Restore it from git (git checkout <merge-base> -- $pp)."
    return
  fi
  lint=
  if [ -x "$dir/.venv/bin/lint-imports" ]; then
    lint=$top/$dir/.venv/bin/lint-imports
  elif command -v lint-imports > /dev/null 2>&1; then
    lint=lint-imports
  fi
  if [ -z "$lint" ]; then
    fail "$label: lint-imports is not installed, so the layer rule cannot run. Install it: pip install -r requirements-dev.txt"
    return
  fi
  out=$tmp/out.txt
  (cd "$dir" && PYTHONPATH="$top/${dir#./}/src${PYTHONPATH:+:$PYTHONPATH}" "$lint") > "$out" 2>&1
  rc=$?
  checked=$((checked + 1))
  if [ "$rc" -ne 0 ]; then
    fail "$label: lint-imports exited $rc. Output:"
    sed 's/^/check-import-layers:   | /' "$out" >&2
    return
  fi
  if ! grep -q -E 'Contracts: [1-9][0-9]* kept, 0 broken' "$out"; then
    fail "$label: lint-imports exited 0 and reported no kept contract, so nothing was analysed. Output: $(tail -n 3 "$out" | tr '\n' ' ')"
  fi
}

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  check_app "$dir"
done < "$tmp/dirs.sorted"

if [ "$failed" -eq 1 ]; then
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  echo "check-import-layers: nothing checked: no fastapi app and no [tool.importlinter] found (the TypeScript stacks use ESLint no-restricted-imports)."
  exit 0
fi
echo "check-import-layers: ok ($checked app(s), every contract kept)"
