#!/usr/bin/env bash
# scripts/check-golden.test.sh — tests for scripts/check-golden.sh.
# Usage: bash scripts/check-golden.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-golden.sh"
COMBO=fastapi-azure
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

fresh_golden() { # fresh_golden <name> — a writable copy of the real goldens
  mkdir -p "$T/$1"
  cp "$REPO_ROOT"/tests/golden/*.sha256 "$REPO_ROOT"/tests/golden/exceptions.txt "$T/$1/"
  echo "$T/$1"
}

# clean_tree_passes
g=$(fresh_golden clean)
out=$(bash "$CHECK" --golden-dir "$g" "$COMBO"); ec=$?
check 0 "$ec" "clean_tree_passes: exit"
check "OK $COMBO" "$(grep '^OK' <<< "$out")" "clean_tree_passes: OK line"

# changed_byte_fails
g=$(fresh_golden changed)
target=$(grep -v '^#' "$g/$COMBO.sha256" | sed -n 2p | sed 's/^[^ ]*  //')
python3 - "$g/$COMBO.sha256" "$target" <<'PY'
import sys
p, target = sys.argv[1:]
out = []
for line in open(p).read().split("\n"):
    if line.endswith("  " + target):
        line = ("0" if line[0] != "0" else "f") + line[1:]
    out.append(line)
open(p, "w").write("\n".join(out))
PY
out=$(bash "$CHECK" --golden-dir "$g" "$COMBO"); ec=$?
check 1 "$ec" "changed_byte_fails: exit"
check "MISMATCH $COMBO $target" "$(grep '^MISMATCH' <<< "$out" | head -1)" "changed_byte_fails: MISMATCH line"

# exception_suppresses
printf '%s %s # test\n' "$COMBO" "$target" >> "$g/exceptions.txt"
out=$(bash "$CHECK" --golden-dir "$g" "$COMBO"); ec=$?
check 0 "$ec" "exception_suppresses: exit"
printf '* %s # test\n' "$target" > "$g/exceptions.txt"
bash "$CHECK" --golden-dir "$g" "$COMBO" > /dev/null; check 0 $? "exception_suppresses: wildcard combo"

# missing_file_fails (golden lists a path the tree does not produce)
g=$(fresh_golden missing)
printf '%s  no/such/file.txt\n' "$(printf x | shasum -a 256 | cut -d' ' -f1)" >> "$g/$COMBO.sha256"
out=$(bash "$CHECK" --golden-dir "$g" "$COMBO"); ec=$?
check 1 "$ec" "missing_file_fails: exit"
check "MISSING $COMBO no/such/file.txt" "$(grep '^MISSING' <<< "$out")" "missing_file_fails: MISSING line"

# extra_file_fails (tree produces a path the golden lacks)
g=$(fresh_golden extra)
grep -v -F -- "  $target" "$g/$COMBO.sha256" > "$g/new" && mv "$g/new" "$g/$COMBO.sha256"
out=$(bash "$CHECK" --golden-dir "$g" "$COMBO"); ec=$?
check 1 "$ec" "extra_file_fails: exit"
check "EXTRA $COMBO $target" "$(grep '^EXTRA' <<< "$out")" "extra_file_fails: EXTRA line"

# all 8 combos pass on the real goldens
out=$(bash "$CHECK"); ec=$?
check 0 "$ec" "all_combos: exit"
check "check-golden: 8/8 combos OK" "$(tail -1 <<< "$out")" "all_combos: summary"

# --from-templates fails loudly while a combo has no template trees
bash "$CHECK" --from-templates "$COMBO" > /dev/null 2>&1; ec=$?
if [[ $ec -ne 0 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: from_templates_without_trees should fail"; fi

# --tree: a generated project is compared against the expected tree
tree="$T/project"
python3 "$REPO_ROOT/scripts/extract-fences.py" --stack fastapi --ci azure --out "$tree" > /dev/null 2>&1
mkdir -p "$tree/node_modules/x" && echo junk > "$tree/node_modules/x/y" && echo more > "$tree/extra.txt"
bash "$CHECK" --tree "$tree" "$COMBO" > /dev/null; check 0 $? "tree_clean_passes (extra files and node_modules ignored)"
printf '\n\n' >> "$tree/pyproject.toml"
bash "$CHECK" --tree "$tree" "$COMBO" > /dev/null; check 0 $? "tree_whitespace_only_passes"
echo "tampered = true" >> "$tree/pyproject.toml"
out=$(bash "$CHECK" --tree "$tree" "$COMBO"); check 1 $? "tree_changed_fails"
check "MISMATCH $COMBO pyproject.toml" "$(grep '^MISMATCH' <<< "$out")" "tree_changed_fails: MISMATCH line"
rm "$tree/pyproject.toml"
out=$(bash "$CHECK" --tree "$tree" "$COMBO"); check 1 $? "tree_missing_fails"
check "MISSING $COMBO pyproject.toml" "$(grep '^MISSING' <<< "$out")" "tree_missing_fails: MISSING line"

echo "check-golden.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
