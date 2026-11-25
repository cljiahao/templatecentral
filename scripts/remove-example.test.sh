#!/usr/bin/env bash
# Behavioural test for skills/cleanup/remove-example/remove-example.sh and its four manifests.
# Seeds each stack with tc-copy.sh into a temp dir. A refusal case has a clean control that passes, and a mutant of the script
# (one check removed) that lets the bad input through, so the test proves that check is what stops it. No timing, no network.
# The manifest check asserts every path and line a manifest names exists in that stack's template tree.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RX=$ROOT/skills/cleanup/remove-example
COPY=$ROOT/skills/scaffold/shared/tc-copy.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/rxtest.XXXXXX") || exit 1
trap '[ -d "$T" ] && chmod -R u+rwx "$T" 2>/dev/null; [ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
NL='
'
TAB=$(printf '\t')
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]"; fail=1 ;; esac; }
absent() { case "$3" in *"$2"*) echo "FAIL $1: [$2] found in [$3]"; fail=1 ;; *) echo "ok   $1" ;; esac; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }
# listing <dir>: sorted "hash path" of every file and "L path target" of every symlink
listing() { (cd "$1" && find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf 'L %s %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$(sha "$f")" "$f"; fi; done); }
treehash() { listing "$1" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }
fld() { printf '%s' "$1" | awk -F'\t' -v n="$2" '{ print $n }'; }

# mkplug <dir> [stack...]: a plugin copy: the script, the manifests, and the real template trees linked in
mkplug() {
  local d=$1 s
  mkdir -p "$d/skills/cleanup/remove-example"
  cp "$RX"/remove-example.sh "$RX"/*.manifest "$d/skills/cleanup/remove-example/"
  for s in nextjs vite-react fastapi nestjs; do
    mkdir -p "$d/skills/scaffold/$s"
    ln -s "$ROOT/skills/scaffold/$s/template" "$d/skills/scaffold/$s/template"
  done
}
PLUG=$T/plugin
mkplug "$PLUG"
SCRIPT=$PLUG/skills/cleanup/remove-example/remove-example.sh
run() { bash "$SCRIPT" "$@" 2>&1; }
out() { local o rc; o=$(run "$@"); rc=$?; if [ -n "$o" ]; then printf '%s\nrc=%s' "$o" "$rc"; else printf 'rc=%s' "$rc"; fi; }
rcof() { run "$@" >/dev/null; echo "$?"; }

seed() { # seed <dir> <stack>
  local d=$1 s=$2 p
  mkdir -p "$d"
  for p in base stack agents; do
    TC_STACK=$s TC_PART=$p bash "$COPY" "$d" >/dev/null 2>&1 || { echo "FAIL seed $s $p"; fail=1; return 1; }
  done
}

# per stack: example delete paths (files or directories), edited files with their line delta, a leftover pattern
dels_of() { case "$1" in
  nextjs | vite-react) echo "src/features/example" ;;
  fastapi) echo "src/api/routers/example.py src/api/schemas/request/example.py src/api/schemas/response/example.py src/api/services/example.py test/test_api/test_example.py" ;;
  nestjs) echo "src/modules/example" ;; esac; }
edits_of() { case "$1" in
  nextjs) echo "src/app/dashboard/(overview)/page.tsx:-8 test/components/render.test.tsx:-35" ;;
  vite-react) echo "src/pages/dashboard.tsx:-9" ;;
  fastapi) echo "src/api/routes.py:-3 src/api/tags.py:-1" ;;
  nestjs) echo "test/app.e2e-spec.ts:-34 src/modules/index.ts:-1 src/app.module.ts:-1" ;; esac; }
left_of() { case "$1" in
  nextjs | vite-react) echo 'features/example|ExampleList' ;;
  fastapi) echo 'routers import example|APITags\.EXAMPLE|services\.example|schemas\.(request|response)\.example|example\.router' ;;
  nestjs) echo 'ExampleModule|example\.module|/examples|CreateExampleDto' ;; esac; }
a_file_of() { case "$1" in
  nextjs | vite-react) echo "src/features/example/index.ts" ;;
  fastapi) echo "src/api/services/example.py" ;;
  nestjs) echo "src/modules/example/example.service.ts" ;; esac; }

is_deleted() { local d; for d in $(dels_of "$1"); do
  if [ "$2" = "./$d" ]; then return 0; fi
  case "$2" in "./$d"/*) return 0 ;; esac
done; return 1; }
is_edited() { local e; for e in $(edits_of "$1"); do if [ "$2" = "./${e%:*}" ]; then return 0; fi; done; return 1; }
# filter_untouched <stack> <drop-deleted>: stdin lines "hash ./path" without edited files (and deleted ones when asked)
filter_untouched() {
  local line path
  while IFS= read -r line; do
    path=${line#* }
    if is_edited "$1" "$path"; then continue; fi
    if [ "$2" = 1 ] && is_deleted "$1" "$path"; then continue; fi
    printf '%s\n' "$line"
  done
}

# --- manifest rows against the template trees
for s in nextjs vite-react fastapi nestjs; do
  M=$RX/$s.manifest
  TPL=$ROOT/skills/scaffold/$s/template
  n=0
  while IFS= read -r row || [ -n "$row" ]; do
    case "$row" in '#'* | '') continue ;; esac
    n=$((n + 1))
    t=$(fld "$row" 1)
    p=$(fld "$row" 2)
    case "$t" in
      delete) check "$s manifest: $p exists in the template" "1" "$([ -e "$TPL/$p" ] && echo 1 || echo 0)" ;;
      rmline | subline | rmblock)
        key=$(fld "$row" 3)
        if [ "$t" = rmblock ]; then key=$(fld "$row" 4); fi
        if [ ! -f "$TPL/$p" ]; then echo "FAIL $s manifest: $p missing from the template"; fail=1; continue; fi
        c=$(grep -c -x -F -e "$key" "$TPL/$p")
        check "$s manifest: line in $p appears exactly once" "1" "$c"
        if [ "$t" = rmblock ]; then
          at=$(grep -n -x -F -e "$key" "$TPL/$p" | head -n 1 | cut -d: -f1)
          cnt=$(fld "$row" 3)
          last=$(fld "$row" 5)
          check "$s manifest: block in $p ends with its last line" "$last" "$(sed -n "$((at + cnt - 1))p" "$TPL/$p")"
        fi ;;
      *) echo "FAIL $s manifest: unknown row type $t"; fail=1 ;;
    esac
  done <"$M"
  check "$s manifest has rows" "1" "$([ "$n" -gt 0 ] && echo 1 || echo 0)"
done

# --- lifecycle per stack, in a directory whose name holds a space
for s in nextjs vite-react fastapi nestjs; do
  D="$T/my proj $s"
  seed "$D" "$s" || continue
  before=$(listing "$D")
  bh=$(treehash "$D")
  r=$(out "$D")
  contains "$s dry run: rc 0" "rc=0" "$r"
  contains "$s dry run: says nothing changed" "dry run: nothing was changed" "$r"
  contains "$s dry run: lists a DELETE" "DELETE " "$r"
  contains "$s dry run: lists an EDIT" "EDIT   " "$r"
  check "$s dry run wrote nothing" "$bh" "$(treehash "$D")"
  r=$(out "$D" --apply)
  contains "$s apply: rc 0" "rc=0" "$r"
  # expected after-tree: before minus deleted paths, edited files compared by delta and content
  exp=$(printf '%s\n' "$before" | filter_untouched "$s" 1)
  got=$(listing "$D" | filter_untouched "$s" 0)
  check "$s apply: the tree is the scaffold minus the example (every other file byte for byte)" "$exp" "$got"
  for e in $(edits_of "$s"); do
    f=${e%:*}; delta=${e#*:}
    old=$(wc -l <"$ROOT/skills/scaffold/$s/template/$f" | tr -d ' ')
    new=$(wc -l <"$D/$f" | tr -d ' ')
    check "$s apply: $f line count changed by $delta" "$((old + delta))" "$new"
  done
  for d in $(dels_of "$s"); do check "$s apply: $d is gone" "0" "$([ -e "$D/$d" ] && echo 1 || echo 0)"; done
  check "$s apply: no reference to the example is left in src or test" "" "$(cd "$D" && grep -rIlE "$(left_of "$s")" src test 2>/dev/null)"
  check "$s apply: no empty example directory is left" "" "$(find "$D/src" "$D/test" -type d -empty 2>/dev/null | grep -i example)"
  ah=$(treehash "$D")
  r=$(out "$D" --apply)
  contains "$s second run: a no-op, rc 0" "nothing to remove" "$r"
  contains "$s second run: rc" "rc=0" "$r"
  check "$s second run changed nothing" "$ah" "$(treehash "$D")"
  r=$(out "$D")
  contains "$s second dry run: nothing to remove" "nothing to remove" "$r"
done

# --- a modified example file is kept without --force
for s in nextjs fastapi; do
  D=$T/mod-$s
  seed "$D" "$s"
  f=$(a_file_of "$s")
  printf '\n// local change\n' >>"$D/$f"
  h=$(treehash "$D")
  r=$(out "$D" --apply)
  contains "$s modified example file: refused, rc 1" "rc=1" "$r"
  contains "$s modified example file: named as a blocker" "BLOCK  $f differs" "$r"
  check "$s modified example file: nothing was deleted or edited" "$h" "$(treehash "$D")"
  r=$(out "$D" --apply --force "$f")
  contains "$s --force on the file: applied" "remove-example: applied" "$r"
  check "$s --force: the modified file is gone" "0" "$([ -e "$D/$f" ] && echo 1 || echo 0)"
  check "$s --force: no example directory entry is left" "" "$(find "$D/src" -type d -empty 2>/dev/null | grep -i example)"
done
D=$T/mod-dir
seed "$D" nextjs
printf 'x\n' >"$D/src/features/example/extra-user-file.ts"
h=$(treehash "$D")
contains "extra file in the example directory is a blocker" "BLOCK  src/features/example/extra-user-file.ts" "$(out "$D")"
r=$(out "$D" --apply --force src/features/example)
contains "--force on the directory row removes it with the extra file" "remove-example: applied" "$r"
check "--force on the directory row: directory gone" "0" "$([ -e "$D/src/features/example" ] && echo 1 || echo 0)"
D=$T/force-typo
seed "$D" nextjs
h=$(treehash "$D")
contains "--force naming no deletable file is refused" "matches no file this run would delete" "$(out "$D" --apply --force src/nothing.ts)"
check "--force typo: nothing written" "$h" "$(treehash "$D")"
contains "--force outside the project is refused" "rc=1" "$(out "$D" --apply --force ../x)"
contains "--force absolute is refused" "rc=1" "$(out "$D" --apply --force /etc/passwd)"

# --- an expected line that is not found exactly: reported, rc 1, nothing half-edited
D=$T/drift
seed "$D" nextjs
pg="$D/src/app/dashboard/(overview)/page.tsx"
sed 's/ExampleList } from/ExampleList  } from/' "$pg" >"$pg.new" && mv "$pg.new" "$pg"
h=$(treehash "$D")
r=$(out "$D" --apply)
contains "drifted line: refused, rc 1" "rc=1" "$r"
contains "drifted line: the file is named" "page.tsx" "$r"
check "drifted line: the example directory is still there (nothing half-done)" "$h" "$(treehash "$D")"
D=$T/dup
seed "$D" nextjs
pg="$D/src/app/dashboard/(overview)/page.tsx"
printf "import { ExampleList } from '@/features/example';\n" >>"$pg"
h=$(treehash "$D")
contains "a line matching twice: refused" "matches 2 lines" "$(out "$D" --apply)"
check "a line matching twice: nothing written" "$h" "$(treehash "$D")"
D=$T/partial
seed "$D" fastapi
sed '/^from api.routers import example$/d' "$D/src/api/routes.py" >"$D/src/api/routes.new" && mv "$D/src/api/routes.new" "$D/src/api/routes.py"
h=$(treehash "$D")
contains "some expected lines present and some missing: refused" "rc=1" "$(out "$D" --apply)"
check "some expected lines missing: nothing written" "$h" "$(treehash "$D")"
D=$T/nonl
seed "$D" fastapi
printf '%s' "$(cat "$D/src/api/tags.py")" >"$D/src/api/tags.py"
contains "a file with no final newline: refused" "no final newline" "$(out "$D" --apply)"
D=$T/gone-edit
seed "$D" fastapi
rm "$D/src/api/tags.py"
contains "an edited file that is missing while example files remain: refused" "tags.py to edit does not exist" "$(out "$D")"
D=$T/hand-removed
seed "$D" fastapi
rm -rf "$D/src/api/routers/example.py" "$D/src/api/schemas/request/example.py" "$D/src/api/schemas/response/example.py" "$D/src/api/services/example.py" "$D/test/test_api/test_example.py"
r=$(out "$D" --apply)
contains "files deleted by hand: the edits still apply" "remove-example: applied" "$r"
check "files deleted by hand: routes.py edited" "0" "$(grep -c 'example' "$D/src/api/routes.py")"
D=$T/lines-gone-files-here
seed "$D" fastapi
sed '/EXAMPLE/d' "$D/src/api/tags.py" >"$D/src/api/tags.new" && mv "$D/src/api/tags.new" "$D/src/api/tags.py"
sed '/example/d' "$D/src/api/routes.py" >"$D/src/api/routes.new" && mv "$D/src/api/routes.new" "$D/src/api/routes.py"
h=$(treehash "$D")
contains "edits made by hand while the example files remain: refused, not a silent no-op" "rc=1" "$(out "$D" --apply)"
check "edits made by hand while files remain: nothing written" "$h" "$(treehash "$D")"

# --- marker and project checks
D=$T/nomarker
seed "$D" nextjs
sed '1d' "$D/AGENTS.md" >"$D/AGENTS.new" && mv "$D/AGENTS.new" "$D/AGENTS.md"
contains "no AGENTS.md marker: refused" "no templateCentral marker" "$(out "$D")"
mkdir -p "$T/noagents"
contains "no AGENTS.md: refused" "no AGENTS.md" "$(out "$T/noagents")"
D=$T/agentslink
seed "$D" nextjs
mv "$D/AGENTS.md" "$T/real-agents.md"; ln -s "$T/real-agents.md" "$D/AGENTS.md"
contains "AGENTS.md a symlink: refused" "AGENTS.md is a symlink" "$(out "$D")"
check "usage: no project" "2" "$(rcof)"
check "usage: unknown flag" "2" "$(rcof "$D" --bogus)"
check "usage: --force needs a value" "2" "$(rcof "$D" --force)"
contains "not a directory: refused" "rc=1" "$(out "$T/missing-dir")"

# --- crafted manifests: each bad row refuses, nothing is written
badman() { # name row
  local name=$1 row=$2 D=$T/bm
  rm -rf "$D" "$T/plug2"
  seed "$D" nextjs
  mkplug "$T/plug2"
  printf '%s\n' "$row" >"$T/plug2/skills/cleanup/remove-example/nextjs.manifest"
  local h; h=$(treehash "$D")
  local r; r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
  contains "$name: refused" "rc=1" "$r"
  check "$name: nothing written" "$h" "$(treehash "$D")"
}
badman "manifest: unknown row type" "frobnicate${TAB}src/x"
badman "manifest: delete with a missing path" "delete"
badman "manifest: rmline with a missing field" "rmline${TAB}src/a.ts${TAB}line"
badman "manifest: bad blank flag" "rmline${TAB}src/a.ts${TAB}line${TAB}sideways"
badman "manifest: rmblock with a zero count" "rmblock${TAB}src/a.ts${TAB}0${TAB}a${TAB}b${TAB}-"
badman "manifest: subline with identical old and new" "subline${TAB}src/a.ts${TAB}same${TAB}same"
badman "manifest: delete path outside the project" "delete${TAB}../outside"
badman "manifest: absolute delete path" "delete${TAB}/etc"
badman "manifest: dot segment" "delete${TAB}src/./features"
badman "manifest: edit path outside the project" "rmline${TAB}../x.ts${TAB}line${TAB}-"
# a path in the manifest that is a symlink inside the project
D=$T/bm
rm -rf "$D" "$T/plug2"
seed "$D" nextjs
mkplug "$T/plug2"
mkdir -p "$T/elsewhere/example"
cp "$D/src/features/example/index.ts" "$T/elsewhere/example/index.ts"
mv "$D/src/features/example" "$T/example-orig"
ln -s "$T/elsewhere/example" "$D/src/features/example"
h=$(treehash "$D")
r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
contains "a symlinked example directory: refused" "rc=1" "$r"
contains "a symlinked example directory: named" "symlink" "$r"
check "a symlinked example directory: nothing written" "$h" "$(treehash "$D")"
check "a symlinked example directory: the target outside is intact" "1" "$([ -f "$T/elsewhere/example/index.ts" ] && echo 1 || echo 0)"
rm "$D/src/features/example"; mv "$T/example-orig" "$D/src/features/example"
ln -s "$T/elsewhere/example/index.ts" "$D/src/features/example/linked.ts"
h=$(treehash "$D")
r=$(out "$D" --apply)
contains "a symlink inside the example directory: refused" "holds a symlink" "$r"
check "a symlink inside the example directory: nothing written" "$h" "$(treehash "$D")"
rm "$D/src/features/example/linked.ts"
mv "$D/src/app" "$T/app-real"; ln -s "$T/app-real" "$D/src/app"
r=$(out "$D" --apply)
contains "an edited file under a symlinked directory: refused" "rc=1" "$r"
rm "$D/src/app"; mv "$T/app-real" "$D/src/app"
contains "control: the same project applies once the symlinks are gone" "remove-example: applied" "$(out "$D" --apply)"

# --- mutants: with one check removed the bad input gets through (dangerous outcome observed)
mutate() { # name sed-expr
  local name=$1 expr=$2
  rm -rf "$T/plug3"; mkplug "$T/plug3"
  local m=$T/plug3/skills/cleanup/remove-example/remove-example.sh
  sed "$expr" "$RX/remove-example.sh" >"$m"
  if cmp -s "$m" "$RX/remove-example.sh"; then echo "FAIL mutant $name: sed expression matched nothing"; fail=1; return 1; fi
  MUT=$m
}
D=$T/mut1
seed "$D" nextjs
printf '\n// local\n' >>"$D/src/features/example/index.ts"
if mutate "no byte compare" 's|if \[ -f "[$]TPL/[$]rel" \] \&\& cmp -s -- "[$]abs" "[$]TPL/[$]rel"; then|if true; then|'; then
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant without the byte compare deletes the modified file" "0" "$([ -e "$D/src/features/example/index.ts" ] && echo 1 || echo 0)"
fi
D=$T/mut2
seed "$D" nextjs
pg="$D/src/app/dashboard/(overview)/page.tsx"
sed 's/ExampleList } from/ExampleList  } from/' "$pg" >"$pg.new" && mv "$pg.new" "$pg"
if mutate "blockers ignored" 's|if \[ "[$]blockers" -gt 0 \]; then|if false; then|'; then
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant that ignores blockers deletes the example although the edit failed (half-done)" "0" "$([ -e "$D/src/features/example" ] && echo 1 || echo 0)"
fi
D=$T/mut3
seed "$D" nextjs
mkdir -p "$T/mut3-outside"
if mutate "no symlink component check" 's|\[ ! -L "[$]acc" \] \|\| return 1|true|'; then
  mv "$D/src/features" "$T/mut3-outside/features"
  ln -s "$T/mut3-outside/features" "$D/src/features"
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant without the symlink check deletes through the link" "0" "$([ -e "$T/mut3-outside/features/example/index.ts" ] && echo 1 || echo 0)"
fi
D=$T/mut4
seed "$D" fastapi
sed '/EXAMPLE/d' "$D/src/api/tags.py" >"$D/src/api/tags.new" && mv "$D/src/api/tags.new" "$D/src/api/tags.py"
sed '/example/d' "$D/src/api/routes.py" >"$D/src/api/routes.new" && mv "$D/src/api/routes.new" "$D/src/api/routes.py"
if mutate "all-gone rule ignored" 's|if \[ "[$]ALL_GONE" -eq 1 \]; then echo "DONE   [$]file (already edited)"; else block|if true; then echo "DONE   [$]file (already edited)"; else block|'; then
  r=$(bash "$MUT" "$D" --apply 2>&1; echo "rc=$?")
  contains "mutant that treats absent lines as done lets the half-removed project through" "rc=0" "$r"
fi
D=$T/mm
seed "$D" nextjs
printf 'hello\nkeep\n' >"$T/x.ts"
if mutate "no path check" 's|case "/[$]p/" in \*/\.\./\* \| \*/\./\* \| \*//\*) return 1 ;; esac|:|'; then
  printf 'rmline\t../x.ts\thello\t-\n' >"$T/plug3/skills/cleanup/remove-example/nextjs.manifest"
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant without the .. check edits a file outside the project" "keep" "$(cat "$T/x.ts")"
fi
printf 'hello\nkeep\n' >"$T/x.ts"
rm -rf "$T/plug2"; mkplug "$T/plug2"
printf 'rmline\t../x.ts\thello\t-\n' >"$T/plug2/skills/cleanup/remove-example/nextjs.manifest"
bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply >/dev/null 2>&1
check "control: the real script leaves the outside file alone" "hello${NL}keep" "$(cat "$T/x.ts")"
if mutate "no manifest check" 's|\[ -z "[$]bad" \] \|\| die|true \|\| die|'; then
  printf 'frobnicate\tsrc/x\n' >"$T/plug3/skills/cleanup/remove-example/nextjs.manifest"
  contains "mutant without the manifest check accepts a malformed row" "rc=0" "$(bash "$MUT" "$D" 2>&1; echo "rc=$?")"
fi

if [ "$fail" -ne 0 ]; then echo "remove-example tests FAILED"; exit 1; fi
echo "remove-example tests passed"
