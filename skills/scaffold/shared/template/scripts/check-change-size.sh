#!/usr/bin/env bash
# Change-size guard: fails when the branch changes more lines or files than the budget, so reviews stay small.
# Compares the working tree with the merge base of <base-ref> (argument, BASE_REF, else origin/main). Local git only, no network.
# Counts committed and uncommitted changes to tracked files, plus untracked files that are not ignored.
# Budgets (env overrides): CHANGE_SIZE_MAX_LINES lines added plus deleted, CHANGE_SIZE_MAX_FILES files changed.
# Not counted: lockfiles, generated files and snapshots, listed once in excluded() below. A rename counts as a delete plus an add.
# Exit: 0 within budget, 1 over budget, 2 it could not measure (no git, no base ref, bad budget).
# Usage: bash scripts/check-change-size.sh [base-ref]
set -uo pipefail

MAX_CHANGED_LINES=${CHANGE_SIZE_MAX_LINES:-800}
MAX_CHANGED_FILES=${CHANGE_SIZE_MAX_FILES:-40}
base=${1:-${BASE_REF:-origin/main}}

die() {
  printf 'check-change-size: %s\n' "$1" >&2
  exit 2
}

# True for a path that does not count toward the budget.
excluded() {
  case "$1" in
    pnpm-lock.yaml | */pnpm-lock.yaml | package-lock.json | */package-lock.json | yarn.lock | */yarn.lock) return 0 ;;
    bun.lock | */bun.lock | bun.lockb | */bun.lockb) return 0 ;;
    uv.lock | */uv.lock | poetry.lock | */poetry.lock | requirements.txt | */requirements.txt) return 0 ;;
    *.snap | */__snapshots__/* | *.min.js | *.min.css | *.map | *.generated.* | */generated/* | generated/*) return 0 ;;
  esac
  return 1
}

for v in "$MAX_CHANGED_LINES" "$MAX_CHANGED_FILES"; do
  case "$v" in
    '' | *[!0-9]*) die "budgets must be whole numbers (got '$v' from CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES)" ;;
  esac
done
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"
git rev-parse --verify --quiet "${base}^{commit}" > /dev/null || die "base ref '$base' not found, so the change size cannot be measured. Fetch it (git fetch origin main), or pass another base ref as the first argument."
mb=$(git merge-base "$base" HEAD 2> /dev/null) || die "no merge base between '$base' and HEAD (shallow clone?). Fetch full history (git fetch --unshallow), or pass another base ref."

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-change-size.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
: > "$tmp/counted.txt"

git -c core.quotepath=false diff --numstat -z --no-renames "$mb" > "$tmp/numstat.z" 2> "$tmp/err.txt" || die "git diff failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' rec; do
  added=${rec%%"$tab"*}
  rest=${rec#*"$tab"}
  deleted=${rest%%"$tab"*}
  path=${rest#*"$tab"}
  if [ -z "$path" ] || excluded "$path"; then continue; fi
  case "$added" in *[!0-9]*) added=0 ;; esac
  case "$deleted" in *[!0-9]*) deleted=0 ;; esac
  printf '%s\t%s\n' "$((added + deleted))" "$path" >> "$tmp/counted.txt"
done < "$tmp/numstat.z"

git -c core.quotepath=false ls-files -z --others --exclude-standard > "$tmp/untracked.z" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' path; do
  if excluded "$path"; then continue; fi
  n=0
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    n=$(LC_ALL=C grep -I -c '' "$path" 2> "$tmp/err.txt")
    rc=$?
    if [ "$rc" -gt 1 ]; then die "cannot read untracked file $path: $(head -n 1 "$tmp/err.txt")"; fi
  fi
  printf '%s\t%s\n' "$n" "$path" >> "$tmp/counted.txt"
done < "$tmp/untracked.z"

files=$(wc -l < "$tmp/counted.txt" | tr -d ' ')
lines=$(awk -F '\t' '{ s += $1 } END { print s + 0 }' "$tmp/counted.txt") || die "cannot add up the changed lines"

if [ "$lines" -gt "$MAX_CHANGED_LINES" ] || [ "$files" -gt "$MAX_CHANGED_FILES" ]; then
  printf 'check-change-size: %s changed lines (budget %s) in %s files (budget %s) against %s. Lockfiles, generated files and snapshots are not counted; untracked files are.\n' "$lines" "$MAX_CHANGED_LINES" "$files" "$MAX_CHANGED_FILES" "$base" >&2
  printf 'check-change-size: largest changes:\n' >&2
  sort -rn "$tmp/counted.txt" | head -n 5 | while IFS="$tab" read -r n p; do printf 'check-change-size:   %s lines  %s\n' "$n" "$p" >&2; done
  printf 'check-change-size: split the change into smaller pull requests that each do one thing. Raise CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES only for a reviewed exception.\n' >&2
  exit 1
fi
echo "check-change-size: ok ($lines lines in $files files, budget $MAX_CHANGED_LINES lines and $MAX_CHANGED_FILES files)"
