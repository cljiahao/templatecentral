#!/usr/bin/env bash
# Writes .claude/review/<HEAD sha>.record from the code-reviewer verdict. Offline: no model, no network.
# Usage: record-review.sh --prepare          writes .claude/review/current.diff for the reviewer to read
#        record-review.sh [file]             records the reviewer's reply from a file or stdin
# This record is an honesty aid inside one session, not a security boundary: the same session can write it.
# It stops a push without a review and a record reused for other content; it does not prove a review happened.
# Reply format: finding lines "<where> | <blocker|major|minor|nit> | <problem> | <fix>" (any prefix, any case), then
# "FINDINGS: none" when there are no finding lines, and as the last non-empty line "VERDICT: pass" or "VERDICT: fail".
# A pass needs no blocker or major line, and either a finding line or "FINDINGS: none". The diff the reviewer read
# (.claude/review/current.diff) must equal the diff of HEAD now.
set -uo pipefail

dir=.claude/review
sev='\|[[:space:]]*(blocker|major|minor|nit)[[:space:]]*\|'

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
  reply=$(tr -d '\r' < "$1")
else
  reply=$(tr -d '\r')
fi
[ -n "$reply" ] || die "empty reviewer reply: pass the code-reviewer output as a file or on stdin."

last=$(printf '%s\n' "$reply" | awk 'NF { l = $0 } END { print l }' | sed 's/[[:space:]]*$//')
case "$last" in
  "VERDICT: pass") verdict=pass ;;
  "VERDICT: fail") verdict=fail ;;
  *) die "the last non-empty line of the reply must be 'VERDICT: pass' or 'VERDICT: fail'." ;;
esac
verdict_lines=$(printf '%s\n' "$reply" | grep -cE '^[[:space:]]*VERDICT:')
[ "$verdict_lines" -eq 1 ] || die "the reply needs exactly one VERDICT line (found $verdict_lines)."

findings=$(printf '%s\n' "$reply" | grep -ciE "$sev")
blocking=$(printf '%s\n' "$reply" | grep -ciE '\|[[:space:]]*(blocker|major)[[:space:]]*\|')
none_lines=$(printf '%s\n' "$reply" | grep -cE '^FINDINGS: none[[:space:]]*$')
if [ "$none_lines" -gt 0 ] && [ "$findings" -gt 0 ]; then
  die "refused: the reply says 'FINDINGS: none' but also lists $findings finding line(s)."
fi
if [ "$verdict" = pass ] && [ "$blocking" -gt 0 ]; then
  die "refused: the verdict is pass but $blocking blocker or major finding(s) are listed. Fix them and review again, or record the reviewer's fail verdict."
fi
if [ "$verdict" = pass ] && [ "$findings" -eq 0 ] && [ "$none_lines" -eq 0 ]; then
  die "refused: a pass with no finding lines needs the line 'FINDINGS: none'. Ask the reviewer to state it."
fi

[ -f "$dir/current.diff" ] || die "no $dir/current.diff: run 'bash scripts/record-review.sh --prepare', then the reviewer."
fresh=$(mktemp "${TMPDIR:-/tmp}/record-review.XXXXXX") || die "cannot create a temporary file"
trap 'rm -f "$fresh"' EXIT
bash "$gate" --print-diff "$base" > "$fresh" || die "cannot compute the diff of HEAD."
cmp -s "$fresh" "$dir/current.diff" || die "current.diff is stale: run 'bash scripts/record-review.sh --prepare' again, then the reviewer."

printf 'sha=%s\nbase=%s\ndiff_hash=%s\nverdict=%s\n' "$sha" "$base" "$diff_hash" "$verdict" > "$dir/$sha.record" || die "cannot write the record."
printf 'record-review: wrote %s/%s.record (verdict %s, %s blocking finding(s)).\n' "$dir" "$sha" "$verdict" "$blocking"
