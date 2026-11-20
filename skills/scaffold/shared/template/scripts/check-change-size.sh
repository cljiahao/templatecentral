#!/usr/bin/env bash
# Change-size guard: fails when the branch changes more lines or files than the budget, so reviews stay small.
# Compares the working tree with the merge base of <base-ref> (argument, BASE_REF, else origin/main). Local git only, no network.
# Counts committed and uncommitted changes to tracked files, plus untracked files that are not ignored.
# Budgets (env overrides): CHANGE_SIZE_MAX_LINES lines added plus deleted, CHANGE_SIZE_MAX_FILES files changed.
# Not counted: paths matching .claude/change-size-exclude.txt (lockfiles), and files marked linguist-generated in .gitattributes. A rename counts as a delete plus an add.
# A binary file weighs one line per 4 KB, rounded up, so a large binary is not free.
# Exit: 0 within budget, 1 over budget, 2 it could not measure (no git, no base ref, bad budget, no exclude file).
# In GitHub Actions and Azure Pipelines the budget and exclude-file overrides are refused.
# Usage: bash scripts/check-change-size.sh [base-ref]        Env: CHANGE_SIZE_EXCLUDE_FILE overrides the exclude file path.
set -uo pipefail

MAX_CHANGED_LINES=${CHANGE_SIZE_MAX_LINES:-800}
MAX_CHANGED_FILES=${CHANGE_SIZE_MAX_FILES:-40}
base=${1:-${BASE_REF:-origin/main}}

die() {
  printf 'check-change-size: %s\n' "$1" >&2
  exit 2
}

# Refuses an environment override that could widen the gate when the run is in CI.
refuse_in_ci() {
  case "${GITHUB_ACTIONS:-}" in
    [Tt][Rr][Uu][Ee]) die "$1 is set, which can widen the gate. It is not allowed in CI: change the file in .claude/ and review the change." ;;
  esac
  case "${TF_BUILD:-}" in
    [Tt][Rr][Uu][Ee]) die "$1 is set, which can widen the gate. It is not allowed in CI: change the file in .claude/ and review the change." ;;
  esac
}
for v in CHANGE_SIZE_MAX_LINES CHANGE_SIZE_MAX_FILES CHANGE_SIZE_EXCLUDE_FILE; do
  if [ -n "${!v:-}" ]; then refuse_in_ci "$v"; fi
done

# True for a path that matches a pattern in the exclude file.
excluded() {
  local pat
  for pat in ${patterns[@]+"${patterns[@]}"}; do
    # The pattern is a glob on purpose.
    # shellcheck disable=SC2254
    case "$1" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Prints the weight of a binary file of $1 bytes: one line per 4 KB, rounded up.
binary_weight() {
  echo $((($1 + 4095) / 4096))
}

for v in "$MAX_CHANGED_LINES" "$MAX_CHANGED_FILES"; do
  case "$v" in
    '' | *[!0-9]*) die "budgets must be whole numbers (got '$v' from CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES)" ;;
  esac
done
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"
git rev-parse --verify --quiet "${base}^{commit}" > /dev/null || die "base ref '$base' not found, so the change size cannot be measured. Fetch it (git fetch origin main), or pass another base ref as the first argument."
mb=$(git merge-base "$base" HEAD 2> /dev/null) || die "no merge base between '$base' and HEAD (shallow clone?). Fetch full history (git fetch --unshallow), or pass another base ref."

exclude_file=${CHANGE_SIZE_EXCLUDE_FILE:-.claude/change-size-exclude.txt}
if [ ! -f "$exclude_file" ]; then die "$exclude_file is missing. Restore it from the scaffold: it lists the lockfiles that do not count."; fi
patterns=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  if [ -n "$line" ]; then patterns+=("$line"); fi
done < "$exclude_file"

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
  if [ "$added" = - ]; then
    if [ -f "$path" ]; then
      bytes=$(wc -c < "$path" | tr -d ' ')
    else
      bytes=$(git cat-file -s "$mb:$path" 2> "$tmp/err.txt") || die "cannot size binary file $path: $(head -n 1 "$tmp/err.txt")"
    fi
    printf '%s\t%s\n' "$(binary_weight "$bytes")" "$path" >> "$tmp/counted.txt"
    continue
  fi
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
    case "$n" in '' | *[!0-9]*) n=0 ;; esac
    bytes=$(wc -c < "$path" | tr -d ' ')
    if [ "$n" -eq 0 ] && [ "$bytes" -gt 0 ]; then n=$(binary_weight "$bytes"); fi
  fi
  printf '%s\t%s\n' "$n" "$path" >> "$tmp/counted.txt"
done < "$tmp/untracked.z"

cut -f2- "$tmp/counted.txt" | tr '\n' '\0' > "$tmp/paths.z"
: > "$tmp/generated.txt"
if [ -s "$tmp/paths.z" ]; then
  git -c core.quotepath=false check-attr -z linguist-generated --stdin < "$tmp/paths.z" > "$tmp/attr.z" 2> "$tmp/err.txt" || die "git check-attr failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
  while IFS= read -r -d '' apath && IFS= read -r -d '' _attr && IFS= read -r -d '' aval; do
    case "$aval" in
      set | true) printf '%s\n' "$apath" >> "$tmp/generated.txt" ;;
    esac
  done < "$tmp/attr.z"
fi
if [ -s "$tmp/generated.txt" ]; then
  awk -F '\t' 'NR == FNR { g[$0] = 1; next } { p = $0; sub(/^[^\t]*\t/, "", p); if (!(p in g)) print }' "$tmp/generated.txt" "$tmp/counted.txt" > "$tmp/kept.txt" || die "cannot drop generated files"
  mv "$tmp/kept.txt" "$tmp/counted.txt" || die "cannot update the counted list"
fi

files=$(wc -l < "$tmp/counted.txt" | tr -d ' ')
lines=$(awk -F '\t' '{ s += $1 } END { print s + 0 }' "$tmp/counted.txt") || die "cannot add up the changed lines"

if [ "$lines" -gt "$MAX_CHANGED_LINES" ] || [ "$files" -gt "$MAX_CHANGED_FILES" ]; then
  printf 'check-change-size: %s changed lines (budget %s) in %s files (budget %s) against %s. Lockfiles and files marked linguist-generated are not counted; untracked files and binaries (one line per 4 KB) are.\n' "$lines" "$MAX_CHANGED_LINES" "$files" "$MAX_CHANGED_FILES" "$base" >&2
  printf 'check-change-size: largest changes:\n' >&2
  sort -rn "$tmp/counted.txt" | head -n 5 | while IFS="$tab" read -r n p; do printf 'check-change-size:   %s lines  %s\n' "$n" "$p" >&2; done
  printf 'check-change-size: split the change into smaller pull requests that each do one thing. Raise CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES only for a reviewed exception.\n' >&2
  exit 1
fi
echo "check-change-size: ok ($lines lines in $files files, budget $MAX_CHANGED_LINES lines and $MAX_CHANGED_FILES files)"
