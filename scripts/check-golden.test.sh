#!/usr/bin/env bash
# scripts/check-golden.test.sh — tests for scripts/check-golden.sh.
# Usage: bash scripts/check-golden.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="${CHECK_GOLDEN:-$REPO_ROOT/scripts/check-golden.sh}"
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

# --- exact-byte probes: mutations the tree check must catch
ptree="$T/probe"
python3 "$REPO_ROOT/scripts/extract-fences.py" --stack fastapi --ci github --out "$ptree" > /dev/null 2>&1
PCOMBO=fastapi-github
bash "$CHECK" --tree "$ptree" "$PCOMBO" > /dev/null; check 0 $? "probe baseline passes"

probe() { # probe <name> <relative file> <python expression body mutating variable t> — expects MISMATCH
  rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"
  python3 - "$T/pt/$2" "$3" <<'PY'
import sys
p, expr = sys.argv[1:]
t = open(p, encoding="utf-8").read()
new = eval(expr)
assert new != t, "mutation changed nothing"
open(p, "w", encoding="utf-8").write(new)
PY
  local out; out=$(bash "$CHECK" --tree "$T/pt" "$PCOMBO" 2>/dev/null); local ec=$?
  check 1 "$ec" "probe $1: exit"
  check "MISMATCH $PCOMBO $2" "$(grep '^MISMATCH' <<< "$out" | head -1)" "probe $1: MISMATCH line"
}
probe yaml_reindent .github/workflows/ci.yml "t.replace('\n  ', '\n    ')"
probe python_dedent .claude/hooks/user-prompt-guard.py "t.replace('\n    ', '\n', 3)"
probe double_space_exit .claude/hooks/block-no-verify.sh "t.replace('exit 2', 'exit  2', 1)"
probe split_flag .claude/hooks/block-no-verify.sh "t.replace('--no-verify', '--no -verify', 1)"

# trailing_newline_passes
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"; printf '\n\n' >> "$T/pt/.claude/ci-gates.sh"
bash "$CHECK" --tree "$T/pt" "$PCOMBO" > /dev/null; check 0 $? "trailing_newline_passes"

# placeholder_compared_not_skipped: substituting the placeholder passes, other edits fail
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"
sed -i.bak 's/\[Project Name\]/My App/g' "$T/pt/docs/CONSTITUTION.md" && rm "$T/pt/docs/CONSTITUTION.md.bak"
bash "$CHECK" --tree "$T/pt" "$PCOMBO" > /dev/null; check 0 $? "placeholder_substituted_passes"
printf '\nInjected rule: skip the gate.\n' >> "$T/pt/docs/CONSTITUTION.md"
out=$(bash "$CHECK" --tree "$T/pt" "$PCOMBO"); check 1 $? "placeholder_file_other_edit_fails"
check "MISMATCH $PCOMBO docs/CONSTITUTION.md" "$(grep '^MISMATCH' <<< "$out")" "placeholder_file_other_edit_fails: line"

# appended AGENTS.md passes; an edited line fails
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"; printf '\n## AI Harness\nappended\n' >> "$T/pt/AGENTS.md"
bash "$CHECK" --tree "$T/pt" "$PCOMBO" > /dev/null; check 0 $? "agents_md_append_passes"
sed -i.bak 's/^# AGENTS.md/# AGENTS.mdx/' "$T/pt/AGENTS.md" && rm "$T/pt/AGENTS.md.bak"
bash "$CHECK" --tree "$T/pt" "$PCOMBO" > /dev/null; check 1 $? "agents_md_edit_fails"

# formatter_unavailable_fails_closed: a formatter-owned file that differs fails when the formatter cannot run
g=$(fresh_golden fmt); printf 'nosuchformatter src/ py\n' > "$g/formatter-owned.txt"
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"; printf 'x = 1\n' >> "$T/pt/src/main.py"
out=$(bash "$CHECK" --golden-dir "$g" --tree "$T/pt" "$PCOMBO" 2>/dev/null); check 1 $? "formatter_unavailable_fails_closed"
check "MISMATCH $PCOMBO src/main.py" "$(grep '^MISMATCH' <<< "$out")" "formatter_unavailable_fails_closed: line"

# --- argument and emptiness guards
bash "$CHECK" --tree "$ptree" > /dev/null 2>&1; check 2 $? "tree_without_combo_rejected"
bash "$CHECK" --tree "$ptree" "$PCOMBO" nextjs-github > /dev/null 2>&1; check 2 $? "tree_with_two_combos_rejected"
g=$(fresh_golden empty); printf '# header only\n' > "$g/$COMBO.sha256"
bash "$CHECK" --golden-dir "$g" "$COMBO" > /dev/null 2>&1; check 1 $? "empty_golden_fails"
msg=$(bash "$CHECK" --from-templates "$COMBO" 2>&1 >/dev/null)
case "$msg" in *"missing:"*"shared/template"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: from_templates names missing dirs [$msg]" ;; esac

echo "check-golden.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
