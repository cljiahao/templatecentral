#!/usr/bin/env bash
# Review gate: passes only when .claude/review/<HEAD sha>.record holds a pass verdict for this exact diff.
# Offline: reads git and one local file, calls no model and no network. Exit 0 pass, 1 gate failure, 2 environment error.
# Fails closed: no merge base, empty diff, base equal to HEAD, dirty tree, or any bad record is a failure.
# Skips only on GITHUB_ACTIONS=true or TF_BUILD=True, because records are local and gitignored and CI cannot hold one.
# A bare CI=1 or GITHUB_ACTIONS=false does not skip. Anyone can set these by hand: the skip is not a security boundary.
# Limit: only the record for HEAD is checked, so a push of another branch or ref is not covered (a pre-push hook gets the pushed refs on stdin).
# Also used by record-review.sh: --emit [base] prints base, HEAD sha and diff hash; --print-diff <base> prints the diff.
# The record is an honesty aid inside one session, not a security boundary.
set -uo pipefail

dir=.claude/review
cr=$(printf '\r')

fail() {
  printf 'check-review-record: %s\n' "$1" >&2
  printf 'check-review-record: fix: run "bash scripts/record-review.sh --prepare", ask Claude to use the code-reviewer agent on .claude/review/current.diff, fix its findings and commit, repeat until it ends with "VERDICT: pass", then save the agent'"'"'s reply verbatim to a file and run "bash scripts/record-review.sh <file>".\n' >&2
  exit 1
}

die() {
  printf 'check-review-record: %s\n' "$1" >&2
  exit 2
}

# Prints the SHA-256 of a file.
hash_file() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    die "need shasum or sha256sum"
  fi
}

safe_ref() {
  case "$1" in
    '' | -* | *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

# Prints the base ref: the explicit argument must exist; otherwise origin/main, then origin/master.
resolve_base() {
  local c
  if [ -n "$1" ]; then
    safe_ref "$1" || fail "base ref '$1' is not a plain branch name."
    git rev-parse --verify --quiet "$1^{commit}" > /dev/null 2>&1 || fail "base ref '$1' does not exist here: set TC_REVIEW_BASE to a branch such as origin/main."
    printf '%s\n' "$1"
    return 0
  fi
  for c in origin/main origin/master; do
    if git rev-parse --verify --quiet "$c^{commit}" > /dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  fail "no base ref found (looked for origin/main and origin/master): fetch it, or set TC_REVIEW_BASE to a branch."
}

mb_out=""

# Writes the committed diff of this project from the merge base of $1 to HEAD into file $2; fails closed on every problem.
write_diff() {
  local bsha hsha mb gerr
  hsha=$(git rev-parse HEAD 2> /dev/null) || fail "no commit yet: commit first, then review."
  bsha=$(git rev-parse --verify --quiet "$1^{commit}" 2> /dev/null) || fail "base ref '$1' does not exist here."
  [ "$bsha" != "$hsha" ] || fail "base ref '$1' is HEAD itself: there is nothing to review."
  mb=$(git merge-base "$1" HEAD 2> /dev/null) || fail "no merge base between '$1' and HEAD (shallow clone or unrelated history): fetch more history, for example git fetch --unshallow, or set TC_REVIEW_BASE."
  [ "$mb" != "$hsha" ] || fail "HEAD has no commit beyond '$1': there is nothing to review."
  mb_out=$mb
  if ! gerr=$(git -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false diff \
    --no-ext-diff --no-textconv --text --no-color --no-renames --full-index \
    --src-prefix=a/ --dst-prefix=b/ -U3 --diff-algorithm=myers "$mb" HEAD -- . 2>&1 > "$2"); then
    fail "git diff failed against '$1': ${gerr%%$'\n'*}"
  fi
  [ -s "$2" ] || fail "the diff against '$1' is empty: there is nothing to review."
}

require_clean() {
  local st
  st=$(git status --porcelain -- . 2> /dev/null) || fail "cannot read the git status."
  [ -z "$st" ] || fail "the working tree has uncommitted or untracked changes: commit the changes, then review again."
}

root=$(cd "$(dirname "$0")/.." && pwd) || die "cannot find the project root"
cd "$root" || die "cannot enter $root"
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"
tmpf=$(mktemp "${TMPDIR:-/tmp}/review-record.XXXXXX") || die "cannot create a temporary file"
trap 'rm -f "$tmpf"' EXIT

mode=${1:-}
case "$mode" in
  --emit)
    require_clean
    base=$(resolve_base "${2:-${TC_REVIEW_BASE:-}}") || exit 1
    write_diff "$base" "$tmpf"
    head_sha=$(git rev-parse HEAD 2> /dev/null) || die "cannot read HEAD"
    h=$(hash_file "$tmpf") || exit 2
    [ -n "$h" ] || die "could not compute the diff hash"
    printf '%s\n%s\n%s\n%s\n' "$base" "$head_sha" "$h" "$mb_out"
    exit 0
    ;;
  --print-diff)
    safe_ref "${2:-}" || die "usage: --print-diff <base-ref>"
    write_diff "$2" "$tmpf"
    cat "$tmpf"
    exit 0
    ;;
  '') ;;
  *) die "usage: check-review-record.sh" ;;
esac

if [ "${GITHUB_ACTIONS:-}" = true ] || [ "${TF_BUILD:-}" = True ]; then
  echo "check-review-record: SKIP in CI: review records are local and gitignored."
  exit 0
fi

sha=$(git rev-parse HEAD 2> /dev/null) || fail "no commit yet: commit first, then review."
require_clean
rec="$dir/$sha.record"
[ -f "$rec" ] || fail "no review record for commit $sha."

r_sha=""
r_base=""
r_hash=""
r_mb=""
r_verdict=""
seen=" "
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *"$cr"*) fail "review record $rec is malformed (carriage return)." ;;
    '') continue ;;
    sha=* | base=* | diff_hash=* | merge_base=* | verdict=*) ;;
    *) fail "review record $rec is malformed (unknown line)." ;;
  esac
  key=${line%%=*}
  case "$seen" in
    *" $key "*) fail "review record $rec is malformed (duplicate $key)." ;;
  esac
  seen="$seen$key "
  case "$key" in
    sha) r_sha=${line#*=} ;;
    base) r_base=${line#*=} ;;
    diff_hash) r_hash=${line#*=} ;;
    merge_base) r_mb=${line#*=} ;;
    verdict) r_verdict=${line#*=} ;;
  esac
done < "$rec"

[ "$r_sha" = "$sha" ] || fail "review record $rec is for a different commit."
safe_ref "$r_base" || fail "review record $rec is malformed (bad base)."
case "$r_hash" in
  *[!0-9a-f]* | '') fail "review record $rec is malformed (bad diff_hash)." ;;
esac
[ "${#r_hash}" -eq 64 ] || fail "review record $rec is malformed (bad diff_hash)."
case "$r_mb" in
  *[!0-9a-f]* | '') fail "review record $rec is malformed (bad merge_base)." ;;
esac
case "$r_verdict" in
  pass | fail) ;;
  *) fail "review record $rec is malformed (verdict must be pass or fail)." ;;
esac

want_base=$(resolve_base "${TC_REVIEW_BASE:-}") || exit 1
[ "$r_base" = "$want_base" ] || fail "review record is for base '$r_base' but the base now is '$want_base': review again against '$want_base'."
write_diff "$r_base" "$tmpf"
[ "$mb_out" = "$r_mb" ] || fail "review record is stale: the merge base of '$r_base' moved from $r_mb to $mb_out since it was reviewed."
now_hash=$(hash_file "$tmpf") || exit 2
[ -n "$now_hash" ] || die "could not compute the diff hash"
[ "$now_hash" = "$r_hash" ] || fail "review record is stale: the diff against $r_base changed since it was reviewed."
[ "$r_verdict" = pass ] || fail "the recorded review verdict is fail."
echo "check-review-record: ok, commit $sha reviewed against $r_base."
