#!/usr/bin/env bash
# scripts/check-golden.test.sh — tests for scripts/check-golden.sh.
# Usage: bash scripts/check-golden.test.sh
set -uo pipefail
export TC_TEST=1

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

# scaffold_tree <stack> <ci> <out> — a project as the scaffold writes it: the fences plus the template trees.
scaffold_tree() {
  local ts=py ci_dir=azure
  case "$1" in nextjs | vite-react | nestjs) ts=ts ;; esac
  [[ "$2" == github ]] && ci_dir="github-$ts"
  python3 "$REPO_ROOT/scripts/extract-fences.py" --stack "$1" --ci "$2" --out "$3" > /dev/null 2>&1
  local d
  for d in "$REPO_ROOT/skills/scaffold/shared/template" "$REPO_ROOT/skills/scaffold/shared/template-$ts" \
    "$REPO_ROOT/skills/scaffold/shared/template-settings-$ts" "$REPO_ROOT/skills/scaffold/shared/template-late" \
    "$REPO_ROOT/skills/scaffold/shared/template-ci/$ci_dir" "$REPO_ROOT/skills/scaffold/$1/template" \
    "$REPO_ROOT/skills/scaffold/$1/template-agents"; do
    [[ -d "$d" ]] && cp -Rp "$d/." "$3/"
  done
  # a generated project carries a real name where the template holds a placeholder
  python3 - "$3" "$REPO_ROOT/tests/golden/placeholders.env" <<'PY'
import os, sys
root, env = sys.argv[1:]
values = dict(l.rstrip("\n").split("=", 1) for l in open(env, encoding="utf-8") if l.strip() and not l.startswith("#"))
for dp, _, fs in os.walk(root):
    for f in fs:
        full = os.path.join(dp, f)
        data = open(full, "rb").read()
        new = data
        for k, v in values.items():
            new = new.replace(("__TC_%s__" % k).encode(), v.encode())
        if new != data:
            open(full, "wb").write(new)
PY
}

fresh_golden() { # fresh_golden <name> — a writable copy of the real goldens
  mkdir -p "$T/$1"
  cp "$REPO_ROOT"/tests/golden/*.sha256 "$REPO_ROOT"/tests/golden/exceptions.txt "$REPO_ROOT"/tests/golden/placeholders.env "$T/$1/"
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
mkdir -p "$T/emptysk"
TC_SCAFFOLD_DIR="$T/emptysk" bash "$CHECK" --from-templates "$COMBO" > /dev/null 2>&1; ec=$?
if [[ $ec -ne 0 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: from_templates_without_trees should fail"; fi

# --from-templates passes for every path the template trees hold, and says how many that is
out=$(bash "$CHECK" --from-templates); ec=$?
check 0 "$ec" "from_templates_passes_for_moved_paths: exit"
check "check-golden: 8/8 combos OK" "$(tail -1 <<< "$out")" "from_templates_passes_for_moved_paths: summary"
case "$(grep "^OK $COMBO" <<< "$out")" in *"golden paths templated"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: from_templates_reports_coverage [$out]" ;; esac

# deleting a template file fails --from-templates on its own (COUNT), and so does an emptied manifest
rm -rf "$T/sk-del"; mkdir -p "$T/sk-del"; cp -R "$REPO_ROOT/skills/scaffold/shared" "$T/sk-del/shared"
rm "$T/sk-del/shared/template/.claude/regen-harness.sh"
out=$(TC_SCAFFOLD_DIR="$T/sk-del" bash "$CHECK" --from-templates "$COMBO"); ec=$?
check 1 "$ec" "from_templates_deleted_template_fails: exit"
case "$out" in *"COUNT $COMBO templated "*" expected "*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: from_templates_deleted_template_fails: no COUNT line [$out]" ;; esac
rm -rf "$T/sk-del/shared/template.manifest"
TC_SCAFFOLD_DIR="$T/sk-del" bash "$CHECK" --from-templates "$COMBO" > /dev/null 2>&1; check 1 $? "from_templates_missing_manifest_fails"

# a templated path that exceptions.txt lists still counts as templated (no false COUNT failure)
g=$(fresh_golden excount); printf '* .gitleaks.toml # test\n' >> "$g/exceptions.txt"
bash "$CHECK" --golden-dir "$g" --from-templates "$COMBO" > /dev/null 2>&1; check 0 $? "from_templates_excepted_templated_path_counts"

# placeholders.env: the last line counts even without a trailing newline
rm -rf "$T/sk-ph"; mkdir -p "$T/sk-ph"; cp -R "$REPO_ROOT/skills/scaffold/shared" "$T/sk-ph/shared"
python3 - "$T/sk-ph/shared/template/.gitleaks.toml" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
assert "useDefault" in t
open(p, "w").write(t.replace("useDefault", "__TC_FOO__", 1))
PY
g=$(fresh_golden ph); printf 'PROJECT_TITLE=[Project Name]\nFOO=useDefault' > "$g/placeholders.env"
TC_SCAFFOLD_DIR="$T/sk-ph" bash "$CHECK" --golden-dir "$g" --from-templates "$COMBO" > /dev/null 2>&1; check 0 $? "placeholders_env_last_line_without_newline_is_read"

# extractor failure: its stderr is shown when it fails
printf '#!/usr/bin/env bash\necho "extractor exploded" >&2\nexit 2\n' > "$T/stub-extract.sh"
out=$(TC_EXTRACT="bash $T/stub-extract.sh" bash "$CHECK" "$COMBO" 2>&1); ec=$?
check 1 "$ec" "extractor_failure_exits_1"
case "$out" in *"extractor exploded"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: extractor_stderr_is_printed [$out]" ;; esac

# compare crash: a compare_tree crash is a failure even when the lines printed before it are all excepted
mkdir -p "$T/fakepy"
cat > "$T/fakepy/python3" <<SH
#!/usr/bin/env bash
if [[ "\$1" == "-" ]]; then
  src=\$(cat)
  if grep -q 'def golden_paths' <<<"\$src"; then printf 'MISSING fastapi-github .gitleaks.toml\n'; echo Traceback >&2; exit 3; fi
  exec $(command -v python3) - "\${@:2}" <<<"\$src"
fi
exec $(command -v python3) "\$@"
SH
chmod +x "$T/fakepy/python3"
g=$(fresh_golden crash); printf '* .gitleaks.toml # test\n' >> "$g/exceptions.txt"
scaffold_tree fastapi github "$T/ctree"
PATH="$T/fakepy:$PATH" bash "$CHECK" --golden-dir "$g" --tree "$T/ctree" fastapi-github > /dev/null 2>&1; check 1 $? "tree_crash_with_excepted_report_fails"

# empty option values: an empty --tree or --golden-dir value is a usage error, not a silent fall back to fence mode
bash "$CHECK" --tree "" "$COMBO" > /dev/null 2>&1; check 2 $? "empty_tree_value_exits_2"
bash "$CHECK" --golden-dir "" "$COMBO" > /dev/null 2>&1; check 2 $? "empty_golden_dir_value_exits_2"

# real exception: a real exception inside compare_tree, after an excepted MISSING line, must not end in OK
scaffold_tree fastapi github "$T/xtree"
rm "$T/xtree/.claude/ci-gates.sh"; chmod 000 "$T/xtree/.gitleaks.toml"
g=$(fresh_golden realcrash); printf 'fastapi-github .claude/ci-gates.sh # test\n' >> "$g/exceptions.txt"
out=$(bash "$CHECK" --golden-dir "$g" --tree "$T/xtree" fastapi-github 2>&1); ec=$?
chmod 644 "$T/xtree/.gitleaks.toml"
check 1 "$([[ $ec -ne 0 && "$out" != *"OK fastapi-github"* ]] && echo 1 || echo 0)" "tree_real_exception_after_excepted_line_fails ($ec)"
case "$out" in *"crashed (exit 3)"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: tree_real_exception_is_reported_as_a_crash [$out]" ;; esac

# a compare that exits 1 with no report is a failure, not an OK
mkdir -p "$T/fakepy2"
cat > "$T/fakepy2/python3" <<SH
#!/usr/bin/env bash
if [[ "\$1" == "-" ]]; then
  src=\$(cat)
  if grep -q 'def golden_paths' <<<"\$src"; then exit 1; fi
  exec $(command -v python3) - "\${@:2}" <<<"\$src"
fi
exec $(command -v python3) "\$@"
SH
chmod +x "$T/fakepy2/python3"
PATH="$T/fakepy2:$PATH" bash "$CHECK" --tree "$T/ctree" fastapi-github > /dev/null 2>&1; check 1 $? "tree_exit_1_without_a_report_fails"

# a golden whose entries are all skipped compares nothing and must not be OK
g=$(fresh_golden skipall); printf '# t\n%s  pnpm-lock.yaml\n' "$(printf x | shasum -a 256 | cut -d' ' -f1)" > "$g/fastapi-github.sha256"
out=$(bash "$CHECK" --golden-dir "$g" --tree "$T/ctree" fastapi-github 2>&1); ec=$?
check 1 "$ec" "tree_golden_with_nothing_to_compare_fails: exit"
case "$out" in *"EMPTY fastapi-github"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: tree_golden_with_nothing_to_compare_fails: no EMPTY line [$out]" ;; esac

# a symlink in place of a golden file is rejected, and an extra file among the hooks is reported
scaffold_tree fastapi github "$T/ltree"
mv "$T/ltree/.gitleaks.toml" "$T/real-gitleaks.toml"; ln -s "$T/real-gitleaks.toml" "$T/ltree/.gitleaks.toml"
out=$(bash "$CHECK" --tree "$T/ltree" fastapi-github 2>&1); ec=$?
check 1 "$ec" "tree_symlink_in_place_of_a_file_fails: exit"
check "SYMLINK fastapi-github .gitleaks.toml" "$(grep '^SYMLINK' <<< "$out")" "tree_symlink_in_place_of_a_file_fails: SYMLINK line"
scaffold_tree fastapi github "$T/etree"
printf 'x\n' > "$T/etree/.claude/hooks/extra-hook.sh"; mkdir -p "$T/etree/.claude/hooks/local"; printf 'x\n' > "$T/etree/.claude/hooks/local/mine.sh"; printf 'x\n' > "$T/etree/.lefthook/extra.sh"
out=$(bash "$CHECK" --tree "$T/etree" fastapi-github 2>&1); ec=$?
check 1 "$ec" "tree_extra_hook_fails: exit"
check "EXTRA fastapi-github .claude/hooks/extra-hook.sh
EXTRA fastapi-github .lefthook/extra.sh" "$(grep '^EXTRA' <<< "$out")" "tree_extra_hook_fails: EXTRA lines (hooks/local is the project's own and is not reported)"

# a symlinked directory is as bad as a symlinked file
scaffold_tree fastapi github "$T/dtree1"; mkdir -p "$T/outside"; ln -s "$T/outside" "$T/dtree1/.claude/hooks/evil"
out=$(bash "$CHECK" --tree "$T/dtree1" fastapi-github 2>&1); ec=$?
check 1 "$ec" "tree_symlinked_dir_inside_hooks_fails: exit"
check "SYMLINK fastapi-github .claude/hooks/evil" "$(grep '^SYMLINK' <<< "$out")" "tree_symlinked_dir_inside_hooks_fails: SYMLINK line"
scaffold_tree fastapi github "$T/dtree2"; cp -R "$T/dtree2/.claude/hooks" "$T/real-hooks"; rm -rf "$T/dtree2/.claude/hooks"; ln -s "$T/real-hooks" "$T/dtree2/.claude/hooks"
out=$(bash "$CHECK" --tree "$T/dtree2" fastapi-github 2>&1); ec=$?
check 1 "$ec" "tree_hooks_dir_replaced_by_symlink_fails: exit"
check "SYMLINK fastapi-github .claude/hooks" "$(grep '^SYMLINK' <<< "$out" | sort -u)" "tree_hooks_dir_replaced_by_symlink_fails: SYMLINK .claude/hooks reported once"

# placeholders.env format and test overrides: a placeholders.env line without = fails, and the test overrides only work with TC_TEST=1
g=$(fresh_golden badph); printf 'NOEQUALS\n' > "$g/placeholders.env"
bash "$CHECK" --golden-dir "$g" --from-templates "$COMBO" > /dev/null 2>&1; check 1 $? "placeholders_env_line_without_equals_fails"
out=$(TC_TEST="" TC_SCAFFOLD_DIR="$T/emptysk" bash "$CHECK" --from-templates "$COMBO" 2>&1); ec=$?
check 0 "$ec" "tc_scaffold_dir_is_ignored_without_tc_test ($out)"

# path and usage handling: backslashes in a path are not interpreted, an unknown combo exits 2, -h prints usage
rm -rf "$T/sk-bs"; mkdir -p "$T/sk-bs"; cp -R "$REPO_ROOT/skills/scaffold/shared" "$T/sk-bs/shared"
printf 'x\n' > "$T/sk-bs/shared/template/a\tb"; printf 'template/a\\tb 644 - -\n' >> "$T/sk-bs/shared/template.manifest"
g=$(fresh_golden bs); printf '%s  a\\tb\n' "$(printf 'x\n' | shasum -a 256 | cut -d' ' -f1)" >> "$g/$COMBO.sha256"
TC_SCAFFOLD_DIR="$T/sk-bs" bash "$CHECK" --golden-dir "$g" --from-templates "$COMBO" > /dev/null 2>&1; check 0 $? "backslash_in_path_is_literal"
# GNU sha256sum prefixes the hash with a backslash and escapes the name when the path has a backslash;
# a stand-in that does the same must not change the result, because the check hashes stdin, not a name
mkdir -p "$T/gnusum"
cat > "$T/gnusum/sha256sum" <<SH
#!/usr/bin/env bash
if [[ \$# -eq 0 ]]; then printf '%s  -\n' "\$(shasum -a 256 | cut -d' ' -f1)"; exit 0; fi
h=\$(shasum -a 256 "\$1" | cut -d' ' -f1)
case "\$1" in *\\\\*) printf '\\\\%s  %s\n' "\$h" "\${1//\\\\/\\\\\\\\}" ;; *) printf '%s  %s\n' "\$h" "\$1" ;; esac
SH
chmod +x "$T/gnusum/sha256sum"
PATH="$T/gnusum:$PATH" TC_SCAFFOLD_DIR="$T/sk-bs" bash "$CHECK" --golden-dir "$g" --from-templates "$COMBO" > /dev/null 2>&1; check 0 $? "backslash_in_path_with_gnu_style_sha256sum"
bash "$CHECK" nosuch-combo > /dev/null 2>&1; check 2 $? "unknown_combo_exits_2"
out=$(bash "$CHECK" -h 2>&1); ec=$?
check 0 "$ec" "help_exits_0"
case "$out" in *Usage:*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: help_prints_usage [$out]" ;; esac

# a changed template byte is MISMATCH, an unexpected template file is EXTRA, a path both fenced and templated is DUPLICATE
mkdir -p "$T/sk-bad"; cp -R "$REPO_ROOT/skills/scaffold/shared" "$T/sk-bad/shared"
printf 'x\n' >> "$T/sk-bad/shared/template/.gitleaks.toml"
out=$(TC_SCAFFOLD_DIR="$T/sk-bad" bash "$CHECK" --from-templates "$COMBO"); ec=$?
check 1 "$ec" "from_templates_changed_byte_fails: exit"
check "MISMATCH $COMBO .gitleaks.toml" "$(grep '^MISMATCH' <<< "$out")" "from_templates_changed_byte_fails: MISMATCH line"
printf 'x\n' > "$T/sk-bad/shared/template/stray.txt"
out=$(TC_SCAFFOLD_DIR="$T/sk-bad" bash "$CHECK" --from-templates "$COMBO"); check "EXTRA $COMBO stray.txt" "$(grep '^EXTRA' <<< "$out")" "from_templates_extra_file_fails"
rm -rf "$T/sk-bad"; mkdir -p "$T/sk-bad/shared/template"
printf 'x\n' > "$T/sk-bad/shared/template/pyproject.toml"
out=$(TC_SCAFFOLD_DIR="$T/sk-bad" bash "$CHECK" "$COMBO"); ec=$?
check 1 "$ec" "duplicate_fence_and_template_fails: exit"
check "DUPLICATE $COMBO pyproject.toml" "$(grep '^DUPLICATE' <<< "$out")" "duplicate_fence_and_template_fails: DUPLICATE line"

# --tree: a generated project is compared against the expected tree
tree="$T/project"
scaffold_tree fastapi azure "$tree"
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
scaffold_tree fastapi github "$ptree"
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
msg=$(TC_SCAFFOLD_DIR="$T/emptysk" bash "$CHECK" --from-templates "$COMBO" 2>&1 >/dev/null)
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
scaffold_tree nextjs github "$ntree"
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

bash "$CHECK" --tree --from-templates "$PCOMBO" > /dev/null 2>&1; check 2 $? "tree_value_starting_with_dashes_exits_2"
bash "$CHECK" --golden-dir --tree "$ptree" "$PCOMBO" > /dev/null 2>&1; check 2 $? "golden_dir_value_starting_with_dashes_exits_2"

# an exceptions.txt path suppresses STALE-EXPECTED, MISSING and MISMATCH alike
g=$(fresh_golden excall)
printf '%s  no/such/file.txt\n' "$(printf x | shasum -a 256 | cut -d' ' -f1)" >> "$g/$PCOMBO.sha256"
printf '%s no/such/file.txt # test\n' "$PCOMBO" > "$g/exceptions.txt"
bash "$CHECK" --golden-dir "$g" --tree "$ptree" "$PCOMBO" > /dev/null 2>&1; check 0 $? "exception_suppresses_stale_and_missing_in_tree"

echo "check-golden.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
