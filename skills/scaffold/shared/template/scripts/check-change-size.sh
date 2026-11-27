#!/usr/bin/env bash
# Change-size guard: fails when the branch changes more lines or files than the budget, so reviews stay small.
# Compares the working tree with the merge base of <base-ref> (argument, BASE_REF, else origin/main). Local git only, no network.
# Counts committed and uncommitted changes to tracked files, plus untracked files that are not ignored.
# Budgets (env overrides): CHANGE_SIZE_MAX_LINES lines added plus deleted, CHANGE_SIZE_MAX_FILES files changed.
# Not counted: paths matching .claude/change-size-exclude.txt (lockfiles), and files marked linguist-generated in .gitattributes. Both are read at the merge base, so a change cannot exclude itself; this needs git 2.40 or newer. A rename counts as a delete plus an add.
# A file that git does not diff as text (binary, a NUL byte, an attribute) and every untracked file weighs max(its newline count, one line per 4 KB rounded up), so no content trick or attribute can make a file weigh less than its lines: a text file with one NUL byte, or a -diff line in .gitattributes or .git/info/attributes, still weighs every line. A changed binary adds the newline count of its old content. A tracked text file weighs max(the lines git reports as added plus deleted, one line per 4 KB rounded up of the bytes on those added and deleted lines), so one huge line, a file with only CR line ends, a huge deleted file and a huge line added to an existing file all weigh their size. The size term counts the changed lines only, never the whole file: a one-line edit to a large existing file weighs what git reports. Replacing a huge line with another huge line counts both (old plus new bytes), because a reviewer must read both.
# Limits: bytes weigh 1 line per 4 KB, so a diff of many short lines and no huge line weighs its git line count; a change that git reports as zero lines and zero bytes (a mode change) weighs 0.
# linguist-generated is read at the merge base from a scratch git directory that shares the object store but has no info/attributes, with core.attributesFile off, so neither a changed .gitattributes nor a local .git/info/attributes line can drop a file from the count.
# Every git call reads a changed file's name literally (GIT_LITERAL_PATHSPECS=1), so a name that looks like pathspec magic is a plain file name; a changed path whose own diff has no hunk although git counted lines is an exit 2.
# Exit: 0 within budget, 1 over budget, 2 it could not measure (no git, no base ref, bad budget).
# In GitHub Actions and Azure Pipelines the budget and exclude-file overrides are refused.
# Usage: bash scripts/check-change-size.sh [base-ref]        Env: CHANGE_SIZE_EXCLUDE_FILE overrides the exclude file path.
set -uo pipefail
# A changed file's name is data: every git call reads a path literally, so a name such as :(glob)x, :(top)y or :(attr:foo)z cannot act as a pathspec that matches nothing, or another file, or makes git fail.
export GIT_LITERAL_PATHSPECS=1

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

# Prints the weight of a file of $1 bytes and $2 newline-counted lines: the larger of the line count and one line per 4 KB, rounded up.
file_weight() {
  local w=$((($1 + 4095) / 4096))
  if [ "$2" -gt "$w" ]; then w=$2; fi
  echo "$w"
}

# Prints the number of lines in file $1, counting a last line with no newline, whatever bytes it holds (NUL included). Returns 1 when the file cannot be read, so a caller stops instead of counting 0.
count_lines() {
  local n
  n=$(LC_ALL=C grep -a -c -e '' -- "$1" 2> "$tmp/err.txt")
  if [ $? -gt 1 ]; then
    return 1
  fi
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  echo "$n"
}

for v in "$MAX_CHANGED_LINES" "$MAX_CHANGED_FILES"; do
  case "$v" in
    '' | *[!0-9]*) die "budgets must be whole numbers (got '$v' from CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES)" ;;
  esac
done
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"
# Every path below is relative to the top of the repository, so work from there whatever folder the run started in; an exclude-file override is made absolute first.
case "${CHANGE_SIZE_EXCLUDE_FILE:-}" in '' | /*) ;; *) CHANGE_SIZE_EXCLUDE_FILE=$PWD/$CHANGE_SIZE_EXCLUDE_FILE ;; esac
top=$(git rev-parse --show-toplevel 2> /dev/null) || die "cannot find the top of the repository (a bare repository has none)"
cd "$top" || die "cannot enter the top of the repository $top"
git rev-parse --verify --quiet "${base}^{commit}" > /dev/null || die "base ref '$base' not found, so the change size cannot be measured. Fetch it (git fetch origin main), or pass another base ref as the first argument."
mb=$(git merge-base "$base" HEAD 2> /dev/null) || die "no merge base between '$base' and HEAD (shallow clone?). Fetch full history (git fetch --unshallow), or pass another base ref."

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-change-size.XXXXXX") || die "cannot create a temporary folder"
trap 'rm -rf "$tmp"' EXIT

# The exclude list and the linguist-generated attributes are read as they were at the merge base, so a change cannot switch off its own gate.
# The working-tree list is never read: with no list at the merge base nothing is excluded, so every changed line counts. CHANGE_SIZE_EXCLUDE_FILE names another list (refused in CI).
exclude_path=.claude/change-size-exclude.txt
if [ -n "${CHANGE_SIZE_EXCLUDE_FILE:-}" ]; then
  if [ ! -f "$CHANGE_SIZE_EXCLUDE_FILE" ]; then die "$CHANGE_SIZE_EXCLUDE_FILE is missing."; fi
  cp "$CHANGE_SIZE_EXCLUDE_FILE" "$tmp/exclude.txt" || die "cannot read $CHANGE_SIZE_EXCLUDE_FILE"
elif git cat-file -e "$mb:./$exclude_path" 2> /dev/null; then
  git show "$mb:./$exclude_path" > "$tmp/exclude.txt" 2> "$tmp/err.txt" || die "cannot read $exclude_path at the merge base: $(head -n 1 "$tmp/err.txt")"
else
  : > "$tmp/exclude.txt"
  printf 'check-change-size: %s is not on %s yet, so nothing is excluded and every changed line counts. Exclusions apply once the file is on the base branch.\n' "$exclude_path" "$base" >&2
fi
git -c core.attributesFile=/dev/null check-attr --source="$mb" linguist-generated -- "$exclude_path" > /dev/null 2> "$tmp/err.txt" || die "git check-attr --source needs git 2.40 or newer to read the attributes at the merge base ($(git --version)): $(head -n 1 "$tmp/err.txt")"
git --attr-source="$mb" -c core.attributesFile=/dev/null check-attr diff -- "$exclude_path" > /dev/null 2> "$tmp/err.txt" || die "git --attr-source needs git 2.40 or newer, so the diff and binary attributes cannot be read at the merge base ($(git --version)): $(head -n 1 "$tmp/err.txt")"

tab=$(printf '\t')
: > "$tmp/counted.txt"

git --attr-source="$mb" -c core.attributesFile=/dev/null -c core.quotepath=false diff --no-textconv --numstat -z --no-renames "$mb" > "$tmp/numstat.z" 2> "$tmp/err.txt" || die "git diff failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' rec; do
  added=${rec%%"$tab"*}
  rest=${rec#*"$tab"}
  deleted=${rest%%"$tab"*}
  path=${rest#*"$tab"}
  if [ -z "$path" ]; then continue; fi
  if [ "$added" = - ]; then
    nl=0
    bytes=0
    if [ -f "$path" ]; then
      bytes=$(wc -c < "$path" | tr -d ' ')
      nl=$(count_lines "$path") || die "cannot read $path"
    fi
    if git cat-file -e "$mb:$path" 2> /dev/null; then
      git cat-file blob "$mb:$path" > "$tmp/base.bin" 2> "$tmp/err.txt" || die "cannot read $path at the merge base: $(head -n 1 "$tmp/err.txt")"
      obytes=$(wc -c < "$tmp/base.bin" | tr -d ' ')
      if [ "$obytes" -gt "$bytes" ]; then bytes=$obytes; fi
      onl=$(count_lines "$tmp/base.bin") || die "cannot read $path at the merge base"
      nl=$((nl + onl))
    fi
    printf '%s\t%s\n' "$(file_weight "$bytes" "$nl")" "$path" >> "$tmp/counted.txt"
    continue
  fi
  case "$added" in *[!0-9]*) added=0 ;; esac
  case "$deleted" in *[!0-9]*) deleted=0 ;; esac
  w=$((added + deleted))
  git --attr-source="$mb" -c core.attributesFile=/dev/null -c core.quotepath=false diff --no-textconv --no-renames -U0 "$mb" -- "$path" > "$tmp/one.diff" 2> "$tmp/err.txt" || die "git diff failed for $path: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
  # Fail closed: git reported changed lines for this path, so its own diff must hold a hunk. A diff with none means the path was not read as this file.
  if [ "$w" -gt 0 ] && ! grep -a -q -e '^@@' -- "$tmp/one.diff"; then die "git reported $w changed lines in $path but its diff has no hunk, so the file cannot be weighed"; fi
  cbytes=$(LC_ALL=C awk 'hdr == 0 && /^@@/ { hdr = 1 } hdr == 1 && /^[-+]/ { n += length($0) + 1 } END { print n + 0 }' "$tmp/one.diff") || die "cannot measure the changed bytes of $path"
  sw=$(((cbytes + 4095) / 4096))
  if [ "$sw" -gt "$w" ]; then w=$sw; fi
  printf '%s\t%s\n' "$w" "$path" >> "$tmp/counted.txt"
done < "$tmp/numstat.z"

git -c core.quotepath=false ls-files -z --others --exclude-standard > "$tmp/untracked.z" 2> "$tmp/err.txt" || die "git ls-files failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
while IFS= read -r -d '' path; do
  n=0
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    bytes=$(wc -c < "$path" | tr -d ' ')
    nl=$(count_lines "$path") || die "cannot read untracked file $path"
    n=$(file_weight "$bytes" "$nl")
  fi
  printf '%s\t%s\n' "$n" "$path" >> "$tmp/counted.txt"
done < "$tmp/untracked.z"

# A scratch git directory that shares the object store but has no info/attributes, so a local attributes line cannot mark a file generated.
git init -q --bare "$tmp/attr.git" > /dev/null 2> "$tmp/err.txt" || die "cannot create a scratch git directory: $(head -n 1 "$tmp/err.txt")"
objdir=$(git rev-parse --path-format=absolute --git-path objects 2> "$tmp/err.txt") || die "cannot find the object store: $(head -n 1 "$tmp/err.txt")"
printf '%s\n' "$objdir" > "$tmp/attr.git/objects/info/alternates" || die "cannot link the object store"
rm -f "$tmp/attr.git/info/attributes"

cut -f2- "$tmp/counted.txt" | tr '\n' '\0' > "$tmp/paths.z"
: > "$tmp/generated.txt"
if [ -s "$tmp/paths.z" ]; then
  git --git-dir="$tmp/attr.git" -c core.attributesFile=/dev/null -c core.quotepath=false check-attr --source="$mb" -z linguist-generated --stdin < "$tmp/paths.z" > "$tmp/attr.z" 2> "$tmp/err.txt" || die "git check-attr failed: $(head -n 2 "$tmp/err.txt" | tr '\n' ' ')"
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

awk -F '\t' -v pattern_file="$tmp/exclude.txt" '
  function glob2re(g,   i, c, r) {
    r = "^"
    for (i = 1; i <= length(g); i++) {
      c = substr(g, i, 1)
      if (c == "*") r = r ".*"
      else if (index("\\.^$()[]{}|+?/", c) > 0) r = r "\\" c
      else r = r c
    }
    return r "$"
  }
  BEGIN {
    while ((getline line < pattern_file) > 0) {
      sub(/#.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") re[++n] = glob2re(line)
    }
  }
  { p = $0; sub(/^[^\t]*\t/, "", p); for (i = 1; i <= n; i++) if (p ~ re[i]) next; print }
' "$tmp/counted.txt" > "$tmp/kept.txt" || die "cannot apply the exclude list"
mv "$tmp/kept.txt" "$tmp/counted.txt" || die "cannot update the counted list"

files=$(wc -l < "$tmp/counted.txt" | tr -d ' ')
lines=$(awk -F '\t' '{ s += $1 } END { print s + 0 }' "$tmp/counted.txt") || die "cannot add up the changed lines"

if [ "$lines" -gt "$MAX_CHANGED_LINES" ] || [ "$files" -gt "$MAX_CHANGED_FILES" ]; then
  printf 'check-change-size: %s changed lines (budget %s) in %s files (budget %s) against %s. Lockfiles and files marked linguist-generated are not counted; untracked files and binaries (one line per 4 KB) are.\n' "$lines" "$MAX_CHANGED_LINES" "$files" "$MAX_CHANGED_FILES" "$base" >&2
  printf 'check-change-size: largest changes:\n' >&2
  sort -rn "$tmp/counted.txt" > "$tmp/counted-sorted.txt"
  head -n 5 "$tmp/counted-sorted.txt" | while IFS="$tab" read -r n p; do printf 'check-change-size:   %s lines  %s\n' "$n" "$p" >&2; done
  printf 'check-change-size: split the change into smaller pull requests that each do one thing. Raise CHANGE_SIZE_MAX_LINES or CHANGE_SIZE_MAX_FILES only for a reviewed exception.\n' >&2
  exit 1
fi
echo "check-change-size: ok ($lines lines in $files files, budget $MAX_CHANGED_LINES lines and $MAX_CHANGED_FILES files)"
