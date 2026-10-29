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
  printf '## Only\n\n    ```yaml\n    a: 1\n    ```\n' > "$r/skills/standards/s.md"
  printf '# file\theading\tindex\ttemplate-path\n' > "$r/tests/golden/fences/moved.tsv"
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
sed -i.bak 's/    a: 1/  a: 1/' "$r/skills/standards/s.md" && rm "$r/skills/standards/s.md.bak"
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
  printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/c.ts\n' >> "$r/tests/golden/fences/moved.tsv"
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
printf 'skills/add/a.md\tStep 2\t1\tskills/add/notes/c.ts\n' >> "$r/tests/golden/fences/moved.tsv"
expect_fail "$r" "not under a template* directory" "mapping_outside_template_dir"
r=$(fixture badmap-escape)
printf 'x\n' > "$r/skills/add/template.ts"
printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/../template.ts\n' >> "$r/tests/golden/fences/moved.tsv"
expect_fail "$r" "BADMAP" "mapping_with_dotdot"
r=$(fixture badmap-key)
mkdir -p "$r/skills/add/template"; printf 'q\n' > "$r/skills/add/template/q.ts"
printf 'skills/add/a.md\tStep 9\t0\tskills/add/template/q.ts\n' >> "$r/tests/golden/fences/moved.tsv"
expect_fail "$r" "is not in the snapshot" "mapping_unknown_key"
r=$(fixture badmap-twice)
move "$r"
printf 'skills/add/a.md\tStep 2\t1\tskills/add/template/c.ts\n' >> "$r/tests/golden/fences/moved.tsv"
expect_fail "$r" "is mapped twice" "mapping_repeated"
r=$(fixture badmap-columns)
printf 'skills/add/a.md\tStep 2\n' >> "$r/tests/golden/fences/moved.tsv"
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

# the real tree matches its snapshot
expect_ok "$REPO_ROOT" "repo snapshot matches skills/"
case "$OUT" in *"fences OK"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: repo check reports fences OK [$OUT]" ;; esac
nrows=$(cat "$REPO_ROOT"/tests/golden/fences/{add,migrate,standards}.tsv | grep -vc '^#')
nfences=$(grep -rhcE '^[[:space:]]*(```|~~~)' "$REPO_ROOT"/skills/add "$REPO_ROOT"/skills/migrate "$REPO_ROOT"/skills/standards | awk '{ n += $1 } END { print n + 0 }')
if [[ "$nrows" -gt 100 && "$nrows" -lt $((nfences / 2)) ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: snapshot row count $nrows looks wrong against $nfences fence lines"; fi

echo "check-fences.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
