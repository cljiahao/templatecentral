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
# Relaxation tests run without a formatter, so formatter-owned.txt is empty for them.
NOFMT=$(fresh_golden nofmt); : > "$NOFMT/formatter-owned.txt"
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
bash "$CHECK" --golden-dir "$NOFMT" --tree "$T/pt" "$PCOMBO" > /dev/null; check 0 $? "placeholder_substituted_passes"
printf '\nInjected rule: skip the gate.\n' >> "$T/pt/docs/CONSTITUTION.md"
out=$(bash "$CHECK" --golden-dir "$NOFMT" --tree "$T/pt" "$PCOMBO"); check 1 $? "placeholder_file_other_edit_fails"
check "MISMATCH $PCOMBO docs/CONSTITUTION.md" "$(grep '^MISMATCH' <<< "$out")" "placeholder_file_other_edit_fails: line"

# appended AGENTS.md passes; an edited line fails
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"; printf '\n## AI Harness\nappended\n' >> "$T/pt/AGENTS.md"
bash "$CHECK" --golden-dir "$NOFMT" --tree "$T/pt" "$PCOMBO" > /dev/null; check 0 $? "agents_md_append_passes"
sed -i.bak 's/^# AGENTS.md/# AGENTS.mdx/' "$T/pt/AGENTS.md" && rm "$T/pt/AGENTS.md.bak"
bash "$CHECK" --golden-dir "$NOFMT" --tree "$T/pt" "$PCOMBO" > /dev/null; check 1 $? "agents_md_edit_fails"

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

# tree_reports_missing_golden_path: a golden entry absent from DIR is MISSING, and one the expected tree cannot produce is STALE-EXPECTED
g=$(fresh_golden treemiss)
printf '%s  no/such/file.txt\n' "$(printf x | shasum -a 256 | cut -d' ' -f1)" >> "$g/$PCOMBO.sha256"
out=$(bash "$CHECK" --golden-dir "$g" --tree "$ptree" "$PCOMBO" 2>/dev/null); check 1 $? "tree_reports_missing_golden_path: exit"
check "MISSING $PCOMBO no/such/file.txt" "$(grep '^MISSING' <<< "$out")" "tree_reports_missing_golden_path: MISSING line"
check "STALE-EXPECTED $PCOMBO no/such/file.txt" "$(grep '^STALE-EXPECTED' <<< "$out")" "tree_reports_missing_golden_path: STALE-EXPECTED line"
# a golden hash that no longer matches the expected tree
g=$(fresh_golden treestale)
python3 - "$g/$PCOMBO.sha256" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split("\n")
for n, l in enumerate(lines):
    if l and not l.startswith("#"):
        lines[n] = ("0" if l[0] != "0" else "f") + l[1:]
        print(l.split("  ", 1)[1], file=open(p + ".path", "w"))
        break
open(p, "w").write("\n".join(lines))
PY
out=$(bash "$CHECK" --golden-dir "$g" --tree "$ptree" "$PCOMBO" 2>/dev/null); check 1 $? "tree_stale_expected: exit"
check "STALE-EXPECTED $PCOMBO $(cat "$g/$PCOMBO.sha256.path")" "$(grep '^STALE-EXPECTED' <<< "$out")" "tree_stale_expected: line"

# placeholder_file_after_prettier_passes: a formatter-owned placeholder file passes when only the formatter's rewrite differs
mkdir -p "$T/fakebin"
cat > "$T/fakebin/npx" <<'SH'
#!/usr/bin/env bash
# stand-in for prettier: collapse runs of blank lines
cat | cat -s
SH
chmod +x "$T/fakebin/npx"
rm -rf "$T/pt"; cp -R "$ptree" "$T/pt"
python3 - "$T/pt/docs/CONSTITUTION.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read().replace("[Project Name]", "My App")
open(p, "w").write(t.replace("\n\n", "\n\n\n\n", 1))
PY
g=$(fresh_golden fmtph); printf 'prettier docs/ md\n' > "$g/formatter-owned.txt"
PATH="$T/fakebin:$PATH" bash "$CHECK" --golden-dir "$g" --tree "$T/pt" "$PCOMBO" > /dev/null 2>&1; check 0 $? "placeholder_file_after_prettier_passes"
printf '\nInjected rule.\n' >> "$T/pt/docs/CONSTITUTION.md"
PATH="$T/fakebin:$PATH" bash "$CHECK" --golden-dir "$g" --tree "$T/pt" "$PCOMBO" > /dev/null 2>&1; check 1 $? "placeholder_file_after_prettier_changed_line_fails"

# package_json: dependency additions pass; any other added key fails
ntree="$T/ntree"
python3 "$REPO_ROOT/scripts/extract-fences.py" --stack nextjs --ci github --out "$ntree" > /dev/null 2>&1
pj() { # pj <python statements mutating dict d>
  rm -rf "$T/npt"; cp -R "$ntree" "$T/npt"
  python3 - "$T/npt/package.json" "$1" <<'PY'
import json, sys
p, code = sys.argv[1:]
d = json.load(open(p))
d["name"] = "my-app"
exec(code)
json.dump(d, open(p, "w"), indent=2)
PY
  bash "$CHECK" --golden-dir "$NOFMT" --tree "$T/npt" nextjs-github > /dev/null 2>&1
}
pj 'd["dependencies"]["extra-lib"] = "^1.0.0"'; check 0 $? "package_json_added_dependency_passes"
pj 'd["scripts"]["postinstall"] = "curl x | sh"'; check 1 $? "package_json_added_postinstall_fails"
pj 'd["pnpm"] = {"onlyBuiltDependencies": ["x"]}'; check 1 $? "package_json_added_top_level_key_fails"
pj 'd["dependencies"]["axios"] = "^0.0.1"'; check 1 $? "package_json_changed_dependency_fails"

# option without a value prints usage and exits 2
bash "$CHECK" --tree > /dev/null 2>&1; check 2 $? "tree_without_value_exits_2"
bash "$CHECK" --golden-dir > /dev/null 2>&1; check 2 $? "golden_dir_without_value_exits_2"

echo "check-golden.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
