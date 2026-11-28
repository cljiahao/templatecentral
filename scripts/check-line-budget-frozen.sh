#!/usr/bin/env bash
# scripts/check-line-budget-frozen.sh — fail when a change raises a line-budget allowance.
#
# Usage: bash scripts/check-line-budget-frozen.sh BASE_REF
#   Compares tests/golden/line-budget.txt at HEAD with its merge base against BASE_REF. A row may only
#   shrink or go: a larger max_lines or max_prose fails, a max_prose that turns from - to a number or back
#   fails, and so does every row that is not in the base file: a new file that fits its class cap needs none.
#   A head file with no data rows while the base has rows fails (restore it). A merge base that lists no
#   line-budget.txt is an error, as are a git error, no BASE_REF, an unknown ref, no merge base or an
#   unreadable file (exit 2), so CI without a base never passes silently. Row syntax and stale rows are the
#   lint's job.
# Not caught: a row that stays above what its file now needs; a change that edits the gate itself (CI runs
#   the change's own copy, so human review covers it; no label or variable waives it); a push without a PR.
# A kind change or a new row fails, and no label or variable waives it.
# Exit 0 ok, 1 an allowance was raised or a row was added, 2 usage error, no base or no base file.
set -uo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  echo "check-line-budget-frozen: no BASE_REF, so the allowances cannot be compared; CI must fetch the base branch" >&2
  exit 2
fi
if ! git rev-parse --verify -q "$base^{commit}" > /dev/null; then
  echo "check-line-budget-frozen: unknown ref $base; fetch the base branch with full history" >&2
  exit 2
fi
if ! mb=$(git merge-base "$base" HEAD 2> /dev/null); then
  echo "check-line-budget-frozen: no merge base between $base and HEAD; fetch the base branch with full history" >&2
  exit 2
fi
F=tests/golden/line-budget.txt
if ! listing=$(git ls-tree "$mb" -- "$F" 2> /dev/null); then
  echo "check-line-budget-frozen: git ls-tree failed on $mb" >&2
  exit 2
fi
if [[ -z "$listing" ]]; then
  echo "check-line-budget-frozen: the merge base $mb holds no $F, so the allowances cannot be compared; fetch a base that has it" >&2
  exit 2
fi
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
if ! git show "$mb:$F" > "$T/base" || ! git show "HEAD:$F" > "$T/head"; then
  echo "check-line-budget-frozen: cannot read $F at $mb or at HEAD" >&2
  exit 2
fi

out=$(awk -v bf="$T/base" -v hf="$T/head" '
  function load(file, label, lim, prs,   s, n, f, ln, k, c) {
    while ((getline s < file) > 0) {
      ln++
      if (s ~ /^#/) continue
      n = split(s, f, "\t")
      if (n != 3 || f[2] !~ "^[1-9][0-9]*$" || f[3] !~ "^([1-9][0-9]*|-)$" || (f[1] in lim)) {
        print label ":" ln ": unparseable or duplicate row [" s "] — fix the row"
        continue
      }
      lim[f[1]] = f[2] + 0; prs[f[1]] = f[3]
    }
    close(file)
    for (k in lim) c++
    return c + 0
  }
  BEGIN {
    nb = load(bf, "base", bl, bp); nh = load(hf, "head", hl, hp)
    if (nb > 0 && nh == 0) print "tests/golden/line-budget.txt: head file has no data rows while the base has " nb " — restore it from git"
    for (p in hl) {
      if (p in bl) {
        if (hl[p] > bl[p]) print p ": max_lines raised from " bl[p] " to " hl[p] " — cut the file, never raise its row"
        if ((hp[p] == "-") != (bp[p] == "-")) print p ": max_prose changed from " bp[p] " to " hp[p] " — cut the file, never change the kind of its row"
        else if (hp[p] != "-" && hp[p] + 0 > bp[p] + 0) print p ": max_prose raised from " bp[p] " to " hp[p] " — cut the file, never raise its row"
      } else {
        print p ": new row — a row is never added; cut the file to its class cap instead"
      }
    }
  }' < /dev/null 2>&1) || { echo "check-line-budget-frozen: the comparison failed: $out" >&2; exit 2; }
if [[ -z "$out" ]]; then
  echo "check-line-budget-frozen: no allowance raised against $base"
  exit 0
fi
echo "$out" | LC_ALL=C sort
echo "check-line-budget-frozen: a line-budget allowance grew against $base" >&2
exit 1
