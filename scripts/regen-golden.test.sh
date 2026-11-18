#!/usr/bin/env bash
# scripts/regen-golden.test.sh — tests for scripts/regen-golden.sh, run on a scratch copy of the repo.
# Usage: bash scripts/regen-golden.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/regen-golden-test.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

S="$T/repo"
mkdir -p "$S/skills" "$S/tests"
cp -R "$REPO_ROOT/scripts" "$S/scripts"
cp -R "$REPO_ROOT/tests/golden" "$S/tests/golden"
for d in scaffold add migrate standards; do cp -R "$REPO_ROOT/skills/$d" "$S/skills/$d"; done

# snap <dir> — one checksum line per file under the folder
snap() { (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "$f")" "$f"; done); }

regen() { OUT=$(cd "$S" && bash scripts/regen-golden.sh "$@" 2>&1); EC=$?; }

golden_before=$(snap "$S/tests/golden")
fences_before=$(snap "$S/tests/golden/fences")

# a changed template file makes the check fail
printf '# changed\n' >> "$S/skills/scaffold/shared/template/scripts/check-docs.sh"
(cd "$S" && bash scripts/check-golden.sh nextjs-github > /dev/null 2>&1)
check 1 "$?" "precondition: check-golden fails on a changed template file"

# default mode names the files and changes nothing
regen
check 0 "$EC" "dry_run: exits 0 ($OUT)"
check 8 "$(printf '%s\n' "$OUT" | grep -c '^would change tests/golden/[a-z-]*\.sha256$')" "dry_run: names all 8 goldens ($OUT)"
check "$golden_before" "$(snap "$S/tests/golden")" "dry_run: nothing changes"

# --write fixes the goldens, and only the one changed hash moves; the fence snapshots stay as they were
regen --write
check 0 "$EC" "write: exits 0 ($OUT)"
check 8 "$(printf '%s\n' "$OUT" | grep -c '^wrote tests/golden/[a-z-]*\.sha256$')" "write: names all 8 goldens ($OUT)"
(cd "$S" && bash scripts/check-golden.sh > /dev/null 2>&1)
check 0 "$?" "write: check-golden passes afterwards"
check "$fences_before" "$(snap "$S/tests/golden/fences")" "write: fence snapshots unchanged without --fences"
check 0 "$(cd "$S" && grep -c 'scripts/check-docs\.sh$' tests/golden/*.sha256 | grep -vc ':1$')" "write: the entry is still one line per golden"
check 4 "$(grep -c '^#' "$S/tests/golden/nextjs-github.sha256")" "write: the header comments are kept"
regen nextjs-github
check 1 "$(printf '%s\n' "$OUT" | grep -c '^regen-golden: no golden file would change$')" "second_run: nothing left to change ($OUT)"

# a stale snapshot is left alone without --fences and refused while moved.d holds a row
fence=$(printf '\140\140\140')
printf '# t\n\n## Heading\n\n%sts\nconst a = 1;\n%s\n' "$fence" "$fence" > "$S/skills/add/zz-regen-test.md"
regen --write nextjs-github
check "$fences_before" "$(snap "$S/tests/golden/fences")" "stale_fences_without_flag: snapshots unchanged"
regen --fences nextjs-github
check 2 "$EC" "fences_with_moved_rows: refused with exit 2 ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c 'moved.d has rows')" "fences_with_moved_rows: the refusal is passed on ($OUT)"
check "$fences_before" "$(snap "$S/tests/golden/fences")" "fences_with_moved_rows: snapshots unchanged"

# with moved.d empty, --fences lists the snapshot change in a dry run and writes it with --write
rm -f "$S"/tests/golden/fences/moved.d/*.tsv
fences_before=$(snap "$S/tests/golden/fences")
regen --fences nextjs-github
check 0 "$EC" "fences_dry_run: exits 0 ($OUT)"
check 1 "$(printf '%s\n' "$OUT" | grep -c '^would change tests/golden/fences/add\.tsv$')" "fences_dry_run: names the snapshot ($OUT)"
check "$fences_before" "$(snap "$S/tests/golden/fences")" "fences_dry_run: nothing changes"
regen --fences --write nextjs-github
check 0 "$EC" "fences_write: exits 0 ($OUT)"
check 1 "$(grep -c 'zz-regen-test\.md' "$S/tests/golden/fences/add.tsv")" "fences_write: the new fence is in the snapshot"

echo "regen-golden.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
