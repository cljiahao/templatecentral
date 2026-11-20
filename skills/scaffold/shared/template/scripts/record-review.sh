#!/usr/bin/env bash
# Writes .claude/review/<HEAD sha>.record from the code-reviewer verdict. Offline: no model, no network.
# Usage: record-review.sh --prepare          writes .claude/review/current.diff for the reviewer to read
#        record-review.sh [file]             records the reviewer's reply from a file or stdin
# This record is an honesty aid inside one session, not a security boundary: the same session can write it.
# It stops a push without a review and a record reused for other content; it does not prove a review happened.
# Finding lines read: <file>:<line> | <blocker|major|minor|nit> | <problem> | <fix>. Last line: VERDICT: pass|fail.
set -uo pipefail

dir=.claude/review

die() {
  printf 'record-review: %s\n' "$1" >&2
  exit 1
}

root=$(cd "$(dirname "$0")/.." && pwd) || die "cannot find the project root"
cd "$root" || die "cannot enter $root"
gate=scripts/check-review-record.sh
[ -f "$gate" ] || die "$gate is missing: restore it from the scaffold."

if ! git check-ignore -q "$dir/x"; then
  die "$dir is not gitignored. Add the line '.claude/review/' to .gitignore first, so records are never committed."
fi

emit=$(bash "$gate" --emit "${TC_REVIEW_BASE:-}") || die "cannot compute the diff hash (see the message above)."
base=$(printf '%s\n' "$emit" | sed -n 1p)
sha=$(printf '%s\n' "$emit" | sed -n 2p)
diff_hash=$(printf '%s\n' "$emit" | sed -n 3p)

if [ "${1:-}" = "--prepare" ]; then
  mkdir -p "$dir" || die "cannot create $dir"
  bash "$gate" --print-diff "$base" > "$dir/current.diff" || die "cannot write the diff."
  printf 'record-review: wrote %s/current.diff (base %s, commit %s). Ask Claude to run the code-reviewer agent on it.\n' "$dir" "$base" "$sha"
  exit 0
fi

if [ -n "${1:-}" ]; then
  [ -f "$1" ] || die "no such file: $1"
  reply=$(cat "$1")
else
  reply=$(cat)
fi
[ -n "$reply" ] || die "empty reviewer reply: pass the code-reviewer output as a file or on stdin."

verdict_lines=$(printf '%s\n' "$reply" | grep -cE '^VERDICT: (pass|fail)[[:space:]]*$')
[ "$verdict_lines" -eq 1 ] || die "the reply needs exactly one line 'VERDICT: pass' or 'VERDICT: fail' (found $verdict_lines)."
verdict=$(printf '%s\n' "$reply" | sed -n 's/^VERDICT: \([a-z]*\)[[:space:]]*$/\1/p')

blocking=$(printf '%s\n' "$reply" | grep -cE '^[^[:space:]|]+:[0-9]+ \| (blocker|major) \|')
if [ "$verdict" = pass ] && [ "$blocking" -gt 0 ]; then
  die "refused: the verdict is pass but $blocking blocker or major finding(s) are listed. Fix them and review again, or record the reviewer's fail verdict."
fi

mkdir -p "$dir" || die "cannot create $dir"
printf 'sha=%s\nbase=%s\ndiff_hash=%s\nverdict=%s\n' "$sha" "$base" "$diff_hash" "$verdict" > "$dir/$sha.record" || die "cannot write the record."
printf 'record-review: wrote %s/%s.record (verdict %s, %s blocking finding(s)).\n' "$dir" "$sha" "$verdict" "$blocking"
