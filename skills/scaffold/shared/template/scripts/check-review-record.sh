#!/usr/bin/env bash
# Review gate: passes only when .claude/review/<HEAD sha>.record holds a pass verdict for this exact diff.
# Offline: reads git and one local file, calls no model and no network. Exit 0 pass, 1 gate failure, 2 environment error.
# Also used by record-review.sh: --emit [base] prints base, HEAD sha and diff hash; --print-diff <base> prints the diff.
# The record is an honesty aid inside one session, not a security boundary. CI skips this gate: records are local and gitignored.
set -uo pipefail

dir=.claude/review

fail() {
  printf 'check-review-record: %s\n' "$1" >&2
  printf 'check-review-record: fix: run "bash scripts/record-review.sh --prepare", ask Claude to use the code-reviewer agent on .claude/review/current.diff, fix its findings and commit, repeat until it ends with "VERDICT: pass", then save its reply to a file and run "bash scripts/record-review.sh <file>".\n' >&2
  exit 1
}

die() {
  printf 'check-review-record: %s\n' "$1" >&2
  exit 2
}

# Prints the SHA-256 of stdin.
hash_stdin() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum > /dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    die "need shasum or sha256sum"
  fi
}

# Prints the first usable base ref: the argument, then the upstream, then the usual default branches.
resolve_base() {
  local c
  for c in "$1" "$(git rev-parse --abbrev-ref '@{upstream}' 2> /dev/null)" origin/main origin/master main master; do
    if [ -n "$c" ] && git rev-parse --verify --quiet "$c^{commit}" > /dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

# Prints the committed diff of this project from the merge base of $1 to HEAD.
print_diff() {
  local mb
  mb=$(git merge-base "$1" HEAD 2> /dev/null) || return 1
  git diff --no-ext-diff --no-color --no-renames "$mb" HEAD -- .
}

safe_ref() {
  case "$1" in
    '' | -* | *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

root=$(cd "$(dirname "$0")/.." && pwd) || die "cannot find the project root"
cd "$root" || die "cannot enter $root"
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"

mode=${1:-}
case "$mode" in
  --emit)
    base=$(resolve_base "${2:-${TC_REVIEW_BASE:-}}") || die "no base ref found: set TC_REVIEW_BASE to a branch such as origin/main"
    diff_hash=$(print_diff "$base" | hash_stdin)
    printf '%s\n%s\n%s\n' "$base" "$(git rev-parse HEAD)" "$diff_hash"
    exit 0
    ;;
  --print-diff)
    safe_ref "${2:-}" || die "usage: --print-diff <base-ref>"
    print_diff "$2" || die "no merge base between $2 and HEAD"
    exit 0
    ;;
  '') ;;
  *) die "usage: check-review-record.sh" ;;
esac

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${TF_BUILD:-}" ]; then
  echo "check-review-record: SKIP in CI: review records are local and gitignored."
  exit 0
fi

sha=$(git rev-parse HEAD 2> /dev/null) || die "no commit yet: commit first, then review"
rec="$dir/$sha.record"
[ -f "$rec" ] || fail "no review record for commit $sha."

r_sha=""
r_base=""
r_hash=""
r_verdict=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    sha=*) r_sha=${line#sha=} ;;
    base=*) r_base=${line#base=} ;;
    diff_hash=*) r_hash=${line#diff_hash=} ;;
    verdict=*) r_verdict=${line#verdict=} ;;
    '') ;;
    *) fail "review record $rec is malformed (unknown line)." ;;
  esac
done < "$rec"

[ "$r_sha" = "$sha" ] || fail "review record $rec is for a different commit."
safe_ref "$r_base" || fail "review record $rec is malformed (bad base)."
case "$r_hash" in
  *[!0-9a-f]* | '') fail "review record $rec is malformed (bad diff_hash)." ;;
esac
[ "${#r_hash}" -eq 64 ] || fail "review record $rec is malformed (bad diff_hash)."
case "$r_verdict" in
  pass | fail) ;;
  *) fail "review record $rec is malformed (verdict must be pass or fail)." ;;
esac

git rev-parse --verify --quiet "$r_base^{commit}" > /dev/null 2>&1 || fail "base ref $r_base from the record does not exist here."
now_hash=$(print_diff "$r_base" | hash_stdin)
[ "$now_hash" = "$r_hash" ] || fail "review record is stale: the diff against $r_base changed since it was reviewed."
[ "$r_verdict" = pass ] || fail "the recorded review verdict is fail."
echo "check-review-record: ok, commit $sha reviewed against $r_base."
