#!/usr/bin/env bash
# scripts/check-fences.test.sh — tests for scripts/check-fences.sh.
# Usage: bash scripts/check-fences.test.sh
# Each case builds a small skills/ tree in a temp dir, snapshots it, breaks it on purpose and expects the failure.
# Fixture text holds backticks inside single quotes on purpose.
# shellcheck disable=SC2016
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-fences.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

# fixture <name> — a tree with three skills, snapshotted; prints its root.
fixture() {
  local r="$T/$1"
  mkdir -p "$r/skills/add" "$r/skills/migrate" "$r/skills/standards" "$r/tests/golden/fences"
  cat > "$r/skills/add/a.md" <<'MD'
# Title

## Step 1

```ts
const a = 1;
```

```bash
echo hi
```

```python
# not a heading
x = 1
```

## Step 2

```ts
const b = 2;
```

```ts
const c = 3;
```
MD
  printf '## Only\n\n```json\n{"k": 1}\n```\n' > "$r/skills/migrate/m.md"
  printf '## Only\n\n- item\n\n  ```yaml\n  a: 1\n  ```\n' > "$r/skills/standards/s.md"
  mkdir -p "$r/tests/golden/fences/moved.d"
  python3 "$REPO_ROOT/scripts/check-fences.py" --root "$r" --snapshot > /dev/null
  echo "$r"
}

run() { # run <root> [args] — sets OUT and RC
  local r="$1"; shift
  OUT=$(bash "$CHECK" --root "$r" "$@" 2>&1); RC=$?
}
expect_fail() { # expect_fail <root> <pattern> <description> [args]
  local r="$1" pat="$2" desc="$3"; shift 3
  run "$r" "$@"
  check 1 "$RC" "$desc: exit code"
  case "$OUT" in *"$pat"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: $desc: wanted [$pat] in [$OUT]" ;; esac
}
expect_ok() { # expect_ok <root> <description> [args]
  local r="$1" desc="$2"; shift 2
  run "$r" "$@"
  check 0 "$RC" "$desc: exit code ($OUT)"
}

# the snapshot holds the right fences: shell fences and fenced comments are not keys
r=$(fixture clean)
expect_ok "$r" "clean tree passes"
check 4 "$(grep -vc '^#' "$r/tests/golden/fences/add.tsv" | tr -d ' ')" "add snapshot holds 4 fences, the bash one skipped"
check 0 "$(grep -c 'not a heading' "$r/tests/golden/fences/add.tsv")" "a comment line inside a fence is not a heading key"
check 2 "$(grep -c "$(printf '\tStep 1\t')" "$r/tests/golden/fences/add.tsv")" "two fences key under Step 1 (ts, python)"

# a shell fence may change freely; a copy-verbatim fence may not
r=$(fixture shell)
sed -i.bak 's/echo hi/echo bye/' "$r/skills/add/a.md" && rm "$r/skills/add/a.md.bak"
expect_ok "$r" "bash fence change is not tracked"

# a one-character difference in one fence, and in the second fence under a heading
r=$(fixture changed)
sed -i.bak 's/const a = 1;/const a = 2;/' "$r/skills/add/a.md" && rm "$r/skills/add/a.md.bak"
expect_fail "$r" "MISMATCH skills/add/a.md :: Step 1 :: 0" "changed_byte"
r=$(fixture changed2)
sed -i.bak 's/const c = 3;/const c = 4;/' "$r/skills/add/a.md" && rm "$r/skills/add/a.md.bak"
expect_fail "$r" "MISMATCH skills/add/a.md :: Step 2 :: 1" "changed_byte_second_fence"
r=$(fixture trailing)
printf '\n' >> "$r/skills/migrate/m.md"
expect_ok "$r" "text after a fence is not part of it"
r=$(fixture indent)
sed -i.bak 's/^  a: 1/ a: 1/' "$r/skills/standards/s.md" && rm "$r/skills/standards/s.md.bak"
expect_fail "$r" "MISMATCH skills/standards/s.md" "changed_indentation"

# deleted fence
r=$(fixture deleted)
printf '## Only\n\nno fence here\n' > "$r/skills/migrate/m.md"
expect_fail "$r" "MISSING skills/migrate/m.md :: Only :: 0" "deleted_fence"
r=$(fixture deleted-file)
rm "$r/skills/migrate/m.md"
expect_fail "$r" "MISSING skills/migrate/m.md" "deleted_file"

# unmapped file: a markdown file or a fence with no snapshot row
r=$(fixture unmapped)
printf '## New\n\n```ts\nx\n```\n' > "$r/skills/standards/new.md"
expect_fail "$r" "EXTRA skills/standards/new.md :: New :: 0" "unmapped_file"
r=$(fixture unmapped-fence)
printf '\n## Step 3\n\n```ts\nd\n```\n' >> "$r/skills/add/a.md"
expect_fail "$r" "EXTRA skills/add/a.md :: Step 3 :: 0" "unmapped_fence"

# empty match: no fence anywhere, no snapshot, nothing mapped
r=$(fixture empty-md)
for f in "$r"/skills/*/*.md; do printf '# no fences\n' > "$f"; done
expect_fail "$r" "EMPTY no fence was found" "empty_markdown_matches_nothing"
r=$(fixture empty-snapshot)
rm "$r"/tests/golden/fences/{add,migrate,standards}.tsv
expect_fail "$r" "EMPTY the snapshot has no rows" "empty_snapshot"
r="$T/empty-root"; mkdir -p "$r"
expect_fail "$r" "EMPTY" "empty_root"
code=$(python3 "$REPO_ROOT/scripts/check-fences.py" --root "$r" --snapshot > /dev/null 2>&1; echo $?)
check 1 "$code" "snapshot of a tree with no fences fails"
r=$(fixture empty-templates)
expect_fail "$r" "EMPTY no fence is mapped" "from_templates_with_no_mapping" --from-templates
run "$r" --has-mappings
check 1 "$RC" "has_mappings is 1 with no row"

# a fence held in a template file: the file has the fence bytes, the markdown has a pointer
move() { # move <root> — moves the Step 2 fence 1 (const c = 3;) into a template file and maps it
  local r="$1" f="$1/skills/add/a.md"
  mkdir -p "$r/skills/add/template"
  printf 'const c = 3;\n' > "$r/skills/add/template/c.ts"
  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("```ts\nconst c = 3;\n```\n", "File: `template/c.ts`.\n")
open(p, "w").write(s)
PY
  printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/c.ts\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
}
r=$(fixture moved)
move "$r"
expect_ok "$r" "moved fence with the same bytes passes"
expect_ok "$r" "moved fence with the same bytes passes from templates" --from-templates
run "$r" --has-mappings
check 0 "$RC" "has_mappings is 0 with a row"
printf 'const c = 3;' > "$r/skills/add/template/c.ts"
expect_fail "$r" "MISMATCH skills/add/a.md :: Step 2 :: 1 -> skills/add/template/c.ts" "moved_missing_newline"
expect_fail "$r" "MISMATCH" "moved_missing_newline_from_templates" --from-templates
r=$(fixture moved-byte)
move "$r"
printf 'const c = 4;\n' > "$r/skills/add/template/c.ts"
expect_fail "$r" "MISMATCH" "moved_changed_byte"
expect_fail "$r" "MISMATCH" "moved_changed_byte_from_templates" --from-templates
r=$(fixture moved-dup)
move "$r"
printf '\n## Step 2\n\n```ts\nconst c = 3;\n```\n' >> "$r/skills/add/a.md"
python3 - "$r/skills/add/a.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("File: `template/c.ts`.\n\n## Step 2\n\n", "File: `template/c.ts`.\n", 1)
open(p, "w").write(s)
PY
expect_fail "$r" "DUPLICATE" "moved_fence_still_in_markdown"
r=$(fixture moved-deleted-file)
move "$r"
rm "$r/skills/add/template/c.ts"
expect_fail "$r" "BADMAP" "mapped_file_deleted"
expect_fail "$r" "BADMAP" "mapped_file_deleted_from_templates" --from-templates

# mapping rows that are wrong
r=$(fixture badmap-dir)
mkdir -p "$r/skills/add/notes"; printf 'const c = 3;\n' > "$r/skills/add/notes/c.ts"
printf 'skills/add/a.md\tStep 2\t1\tskills/add/notes/c.ts\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
expect_fail "$r" "not under a template* directory" "mapping_outside_template_dir"
r=$(fixture badmap-escape)
printf 'x\n' > "$r/skills/add/template.ts"
printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/../template.ts\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
expect_fail "$r" "BADMAP" "mapping_with_dotdot"
r=$(fixture badmap-key)
mkdir -p "$r/skills/add/template"; printf 'q\n' > "$r/skills/add/template/q.ts"
printf 'skills/add/a.md\tStep 9\t0\tskills/add/template/q.ts\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
expect_fail "$r" "is not in the snapshot" "mapping_unknown_key"
r=$(fixture badmap-twice)
move "$r"
printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/c.ts\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
expect_fail "$r" "is mapped twice" "mapping_repeated"
r=$(fixture badmap-columns)
printf 'skills/add/a.md\tStep 2\n' >> "$r/tests/golden/fences/moved.d/slice-a.tsv"
run "$r"
check 2 "$RC" "mapping_row_with_wrong_columns exits 2"
r=$(fixture badmap-link)
move "$r"
rm "$r/skills/add/template/c.ts"; printf 'const c = 3;\n' > "$r/real.ts"; ln -s ../../../real.ts "$r/skills/add/template/c.ts"
expect_fail "$r" "BADMAP" "mapping_to_symlink"

# the snapshot is not rewritten over moved fences
r=$(fixture snap-refuse)
move "$r"
code=$(python3 "$REPO_ROOT/scripts/check-fences.py" --root "$r" --snapshot > /dev/null 2>&1; echo $?)
check 2 "$code" "snapshot_refuses_with_mappings"

# an unterminated fence is a parse error, not a pass
r=$(fixture unterminated)
printf '\n```ts\nopen\n' >> "$r/skills/add/a.md"
run "$r"
check 2 "$RC" "unterminated_fence exits 2"

# --- fence recognition ---------------------------------------------------------------------------
# mkroot <name> — an empty tree: a one-fence anchor file per skill so a case needs only its own file.
mkroot() {
  local r="$T/$1"
  mkdir -p "$r/skills/add" "$r/skills/migrate" "$r/skills/standards" "$r/tests/golden/fences/moved.d"
  printf '## A\n\n```ts\na\n```\n' > "$r/skills/migrate/anchor.md"
  printf '## A\n\n```ts\na\n```\n' > "$r/skills/standards/anchor.md"
  echo "$r"
}
snapshot() { python3 "$REPO_ROOT/scripts/check-fences.py" --root "$1" --snapshot > /dev/null; }
rows_of() { grep -F "$2" "$1/tests/golden/fences/add.tsv" 2>/dev/null | grep -vc '^#' || true; }

r=$(mkroot tilde)
printf '## T\n\n~~~markdown\n```ts\ninner\n```\n~~~\n' > "$r/skills/add/t.md"
snapshot "$r"
check 1 "$(rows_of "$r" skills/add/t.md)" "a tilde fence holding backtick fences is one fence"
check 1 "$(grep -c "$(printf '\tmarkdown$')" "$r/tests/golden/fences/add.tsv")" "tilde fence keeps its lang"
printf '## T\n\n~~~markdown\n```ts\ninnerX\n```\n~~~\n' > "$r/skills/add/t.md"
expect_fail "$r" "MISMATCH skills/add/t.md :: T :: 0" "tilde_fence_changed"

r=$(mkroot four)
printf '## F\n\n````md\n```ts\ninner\n```\n````\n\n## G\n\n```ts\nafter\n```\n' > "$r/skills/add/f.md"
snapshot "$r"
check 2 "$(rows_of "$r" skills/add/f.md)" "a 4-backtick fence holding a 3-backtick fence is one fence, and the next heading is seen"
check 1 "$(grep -c "$(printf 'G\t0\tts')" "$r/tests/golden/fences/add.tsv")" "the fence after a nested fence keys under its own heading"

r=$(mkroot crlf)
printf '## C\r\n\r\n```ts\r\nline\r\n```\r\n' > "$r/skills/add/c.md"
snapshot "$r"
expect_ok "$r" "crlf fence passes unchanged"
printf '## C\n\n```ts\nline\n```\n' > "$r/skills/add/c.md"
expect_fail "$r" "MISMATCH skills/add/c.md :: C :: 0" "crlf_to_lf"
r=$(mkroot crlf2)
printf '## C\n\n```ts\nline\n```\n' > "$r/skills/add/c.md"
snapshot "$r"
printf '## C\r\n\r\n```ts\r\nline\r\n```\r\n' > "$r/skills/add/c.md"
expect_fail "$r" "MISMATCH skills/add/c.md :: C :: 0" "lf_to_crlf"

r=$(mkroot tags)
printf '## T\n\n```\nuntagged\n```\n\n```ts{1}\nbraced\n```\n\n```sh\na\n```\n\n```shell\na\n```\n\n```console\na\n```\n\n```zsh\na\n```\n\n```BASH\n# hash\n```\n\n```bash{2}\na\n```\n' > "$r/skills/add/t.md"
snapshot "$r"
check 2 "$(rows_of "$r" skills/add/t.md)" "only the untagged and the ts{1} fence are tracked (sh, shell, console, zsh, BASH, bash{2} are not)"
check 1 "$(grep -c "$(printf '\t0\t-$')" "$r/tests/golden/fences/add.tsv")" "an untagged fence has lang -"
check 1 "$(grep -c "$(printf '\t1\tts{1}$')" "$r/tests/golden/fences/add.tsv")" "a ts{1} fence keeps its full tag"
printf '## T\n\n```\nuntagged\n```\n\n```ts{1}\nbraced\n```\n\n```sh\nCHANGED\n```\n\n```shell\nCHANGED\n```\n\n```console\nCHANGED\n```\n\n```zsh\nCHANGED\n```\n\n```BASH\nCHANGED\n```\n\n```bash{2}\nCHANGED\n```\n' > "$r/skills/add/t.md"
expect_ok "$r" "shell-tagged fences change freely"
printf '## T\n\n```\nuntaggedX\n```\n\n```ts{1}\nbraced\n```\n' > "$r/skills/add/t.md"
expect_fail "$r" "MISMATCH skills/add/t.md :: T :: 0" "untagged_fence_changed"

r=$(mkroot repeat)
printf '## Same\n\n```ts\none\n```\n\n## Other\n\n## Same\n\n```ts\ntwo\n```\n' > "$r/skills/add/r.md"
snapshot "$r"
check 1 "$(grep -c "$(printf 'Same\t1\tts')" "$r/tests/golden/fences/add.tsv")" "a repeated heading shares one counter"

r=$(mkroot opener)
printf 'text\n\n```a``` x\n\n    ```ts\n    indented code, not a fence\n    ```\n\n## H\n\n```ts\nreal\n```\n' > "$r/skills/add/o.md"
snapshot "$r"
check 1 "$(rows_of "$r" skills/add/o.md)" "an inline triple-backtick line and a 4-space code block are not fences"
check 1 "$(grep -c "$(printf '\tH\t0\tts')" "$r/tests/golden/fences/add.tsv")" "the heading after them is seen"
r=$(mkroot listopen)
printf '1. step\n\n    ```ts\n    inside: 1\n    ```\n\n2. step\n\n   ```ts\n   inside: 2\n   ```\n' > "$r/skills/add/l.md"
snapshot "$r"
check 2 "$(rows_of "$r" skills/add/l.md)" "fences indented to a list item's content column are fences"

# --- fences held in files: sibling indexes, slices, indentation --------------------------------------
three() { # three <name> — one heading with three fences A, B, C; snapshotted; prints the root
  local r; r=$(mkroot "$1")
  printf '## S\n\n```ts\nA\n```\n\n```ts\nB\n```\n\n```ts\nC\n```\n' > "$r/skills/add/s.md"
  snapshot "$r"
  echo "$r"
}
# mv_fence <root> <letter> <index> <slice file> — the fence's file, a pointer in its place, one row
mv_fence() {
  local r="$1" letter="$2" idx="$3" slice="$4"
  mkdir -p "$r/skills/add/template"
  printf '%s\n' "$letter" > "$r/skills/add/template/$letter.ts"
  python3 - "$r/skills/add/s.md" "$letter" <<'PY'
import sys
p, letter = sys.argv[1:]
s = open(p).read().replace("```ts\n" + letter + "\n```\n", "File: `template/" + letter + ".ts`.\n")
open(p, "w").write(s)
PY
  printf 'skills/add/s.md\tS\t%s\tskills/add/template/%s.ts\n' "$idx" "$letter" >> "$r/tests/golden/fences/moved.d/$slice.tsv"
}
for which in "A 0" "B 1" "C 2"; do
  read -r -a pair <<< "$which"
  set -- "${pair[@]}"
  r=$(three "move-$1")
  before=$(cat "$r"/tests/golden/fences/{add,migrate,standards}.tsv | cksum)
  mv_fence "$r" "$1" "$2" slice-a
  expect_ok "$r" "moving fence $2 of three passes"
  expect_ok "$r" "moving fence $2 of three passes from templates" --from-templates
  check "$before" "$(cat "$r"/tests/golden/fences/{add,migrate,standards}.tsv | cksum)" "moving fence $2 leaves the snapshot alone"
done
r=$(three move-first-edit-last)
mv_fence "$r" A 0 slice-a
sed -i.bak 's/^C$/C2/' "$r/skills/add/s.md" && rm "$r/skills/add/s.md.bak"
expect_fail "$r" "MISMATCH skills/add/s.md :: S :: 2" "later_sibling_byte_change_after_a_move"
r=$(three move-middle-edit-last)
mv_fence "$r" B 1 slice-a
sed -i.bak 's/^C$/C2/' "$r/skills/add/s.md" && rm "$r/skills/add/s.md.bak"
expect_fail "$r" "MISMATCH skills/add/s.md :: S :: 2" "last_sibling_byte_change_after_a_middle_move"
r=$(three move-then-delete)
mv_fence "$r" A 0 slice-a
python3 - "$r/skills/add/s.md" <<'PY'
import sys
p = sys.argv[1]
open(p, "w").write(open(p).read().replace("```ts\nC\n```\n", ""))
PY
expect_fail "$r" "MISSING skills/add/s.md :: S :: 1" "later_sibling_deleted_after_a_move"
r=$(three move-keep-fence)
mv_fence "$r" A 0 slice-a
printf '\n```ts\nA\n```\n' >> "$r/skills/add/s.md"
expect_fail "$r" "DUPLICATE skills/add/s.md :: S :: 0" "moved_first_fence_still_in_markdown"
r=$(three slices)
mv_fence "$r" A 0 slice-a
mv_fence "$r" B 1 slice-b
expect_ok "$r" "two slices each moving a fence of one heading pass"
expect_ok "$r" "two slices pass from templates" --from-templates
r=$(three slices-clash)
mv_fence "$r" A 0 slice-a
printf 'skills/add/s.md\tS\t0\tskills/add/template/A.ts\n' > "$r/tests/golden/fences/moved.d/slice-b.tsv"
expect_fail "$r" "is mapped twice (slice-b.tsv and slice-a.tsv)" "same_fence_in_two_slices"
r=$(three legacy)
mv_fence "$r" A 0 slice-a
printf 'x\n' > "$r/tests/golden/fences/moved.d/notes.txt"
expect_ok "$r" "only moved.d/*.tsv are read"

# a fence indented in a list item: the file holds it without the indentation
indented() { # indented <name> — a list item with a 2-space-indented fence; snapshotted
  local r; r=$(mkroot "$1")
  printf -- '- item\n\n  ```ts\n  x: 1\n\n  y: 2\n  ```\n' > "$r/skills/add/s.md"
  snapshot "$r"
  mkdir -p "$r/skills/add/template"
  printf 'x: 1\n\ny: 2\n' > "$r/skills/add/template/x.ts"
  printf -- '- item\n\nFile.\n' > "$r/skills/add/s.md"
  echo "$r"
}
r=$(indented indent-ok)
printf 'skills/add/s.md\t(top)\t0\tskills/add/template/x.ts\tindent=2\n' > "$r/tests/golden/fences/moved.d/a.tsv"
expect_ok "$r" "an indent=2 mapping matches the indented fence"
expect_ok "$r" "an indent=2 mapping matches from templates" --from-templates
printf 'skills/add/s.md\t(top)\t0\tskills/add/template/x.ts\n' > "$r/tests/golden/fences/moved.d/a.tsv"
expect_fail "$r" "MISMATCH" "indented_fence_mapped_without_indent"
printf 'skills/add/s.md\t(top)\t0\tskills/add/template/x.ts\tindent=4\n' > "$r/tests/golden/fences/moved.d/a.tsv"
expect_fail "$r" "MISMATCH" "indented_fence_mapped_with_wrong_indent"
printf 'skills/add/s.md\t(top)\t0\tskills/add/template/x.ts\tindent=two\n' > "$r/tests/golden/fences/moved.d/a.tsv"
run "$r"
check 2 "$RC" "a malformed indent column exits 2"

# CRLF in a moved fence: the file must carry the carriage returns
r=$(mkroot crlf-move)
printf '## C\r\n\r\n```ts\r\nline\r\n```\r\n' > "$r/skills/add/c.md"
snapshot "$r"
mkdir -p "$r/skills/add/template"
printf '## C\r\n\r\nFile.\r\n' > "$r/skills/add/c.md"
printf 'skills/add/c.md\tC\t0\tskills/add/template/c.ts\n' > "$r/tests/golden/fences/moved.d/a.tsv"
printf 'line\n' > "$r/skills/add/template/c.ts"
expect_fail "$r" "MISMATCH" "moved_crlf_fence_with_an_lf_file"
printf 'line\r\n' > "$r/skills/add/template/c.ts"
expect_ok "$r" "moved crlf fence with a crlf file passes"

# a symlinked directory above the template file
r=$(three symlink-dir)
mv_fence "$r" A 0 slice-a
mkdir -p "$r/real"; mv "$r/skills/add/template/A.ts" "$r/real/A.ts"; rmdir "$r/skills/add/template"
ln -s ../../real "$r/skills/add/template"
expect_fail "$r" "goes through a symlink" "symlinked_template_directory"
expect_fail "$r" "goes through a symlink" "symlinked_template_directory_from_templates" --from-templates

# --has-mappings: 0 with a row, 1 with none, 2 on a parse error
r=$(three has-map)
run "$r" --has-mappings; check 1 "$RC" "has_mappings is 1 with no slice file"
mv_fence "$r" A 0 slice-a
run "$r" --has-mappings; check 0 "$RC" "has_mappings is 0 with a row"
printf 'only\ttwo\n' > "$r/tests/golden/fences/moved.d/slice-b.tsv"
run "$r" --has-mappings; check 2 "$RC" "has_mappings is 2 on a malformed row"

# the real tree matches its snapshot
expect_ok "$REPO_ROOT" "repo snapshot matches skills/"
case "$OUT" in *"fences OK"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: repo check reports fences OK [$OUT]" ;; esac
nrows=$(cat "$REPO_ROOT"/tests/golden/fences/{add,migrate,standards}.tsv | grep -vc '^#')
nfences=$(grep -rhcE '^[[:space:]]*(```|~~~)' "$REPO_ROOT"/skills/add "$REPO_ROOT"/skills/migrate "$REPO_ROOT"/skills/standards | awk '{ n += $1 } END { print n + 0 }')
if [[ "$nrows" -gt 100 && "$nrows" -lt $((nfences / 2)) ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: snapshot row count $nrows looks wrong against $nfences fence lines"; fi

echo "check-fences.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
