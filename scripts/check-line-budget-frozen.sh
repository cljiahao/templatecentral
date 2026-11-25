#!/usr/bin/env bash
# scripts/check-line-budget-frozen.sh — fail when a change raises a line-budget allowance.
#
# Usage: bash scripts/check-line-budget-frozen.sh BASE_REF
#   Compares tests/golden/line-budget.txt at HEAD with its merge base against BASE_REF. A row may only
#   shrink or go: a larger max_lines or max_prose fails, and so does a max_prose that turns from - to a
#   number or back. A new row passes only for a file that did not exist under skills/ at the merge base,
#   with max_lines of at most 150 and max_prose of at most 50 (or -). A file that existed at the base
#   without a row had to fit its class cap: cut it, do not add a row. It passes when BASE_REF holds no
#   line-budget.txt yet (the initial capture). No BASE_REF, an unknown ref or an unreadable file fails
#   (exit 2), so CI without a base never passes silently. Row syntax and stale rows are the lint's job.
# Not caught: a row that stays above what its file now needs (the lint only sees a file over its row).
# Exit 0 ok, 1 an allowance was raised, 2 usage error or no base.
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
if ! git cat-file -e "$mb:$F" 2> /dev/null; then
  echo "check-line-budget-frozen: $base holds no $F; initial capture"
  exit 0
fi
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
if ! git show "$mb:$F" > "$T/base" || ! git show "HEAD:$F" > "$T/head"; then
  echo "check-line-budget-frozen: cannot read $F at $mb or at HEAD" >&2
  exit 2
fi
if ! git ls-tree -r --name-only "$mb" -- skills > "$T/tree"; then
  echo "check-line-budget-frozen: cannot list skills/ at $mb" >&2
  exit 2
fi

out=$(awk -v bf="$T/base" -v hf="$T/head" -v tf="$T/tree" '
  function load(file, lim, prs,   s, n, f, ln) {
    while ((getline s < file) > 0) {
      ln++
      if (s ~ /^#/) continue
      n = split(s, f, "\t")
      if (n != 3 || f[2] !~ "^[1-9][0-9]*$" || f[3] !~ "^([1-9][0-9]*|-)$" || (f[1] in lim)) {
        print file ":" ln ": unparseable or duplicate row [" s "] — fix the row"
        continue
      }
      lim[f[1]] = f[2] + 0; prs[f[1]] = f[3]
    }
    close(file)
  }
  BEGIN {
    load(bf, bl, bp); load(hf, hl, hp)
    while ((getline s < tf) > 0) existed[substr(s, 8)] = 1
    close(tf)
    for (p in hl) {
      if (p in bl) {
        if (hl[p] > bl[p]) print p ": max_lines raised from " bl[p] " to " hl[p] " — cut the file, never raise its row"
        if ((hp[p] == "-") != (bp[p] == "-")) print p ": max_prose changed from " bp[p] " to " hp[p] " — cut the file, never change the kind of its row"
        else if (hp[p] != "-" && hp[p] + 0 > bp[p] + 0) print p ": max_prose raised from " bp[p] " to " hp[p] " — cut the file, never raise its row"
      } else if (p in existed) {
        print p ": new row for a file that existed at the base without one — cut the file to its class cap, do not add a row"
      } else {
        if (hl[p] > 150) print p ": new row has max_lines " hl[p] ", above the hard cap 150 — write a shorter file"
        if (hp[p] != "-" && hp[p] + 0 > 50) print p ": new row has max_prose " hp[p] ", above the hard cap 50 — write a shorter file"
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
