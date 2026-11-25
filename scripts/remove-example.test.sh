#!/usr/bin/env bash
# Behavioural test for skills/cleanup/remove-example/remove-example.sh and its four manifests.
# Seeds each stack with tc-copy.sh into a temp dir. A refusal case has a clean control that passes, and a mutant of the script
# (one check removed) that lets the bad input through, so the test proves that check is what stops it. A refusal that a second check also
# backs up (an unreadable file, a special file, a newline name) has a mutant that shows its own message gone. No timing, no network.
# The manifest check asserts every path and line a manifest names exists in that stack's template tree.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RX=$ROOT/skills/cleanup/remove-example
COPY=$ROOT/skills/scaffold/shared/tc-copy.sh
T=$(mktemp -d "${TMPDIR:-/tmp}/rxtest.XXXXXX") || exit 1
cleanup() { if [ -d "$T" ]; then chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; fi; }
trap cleanup EXIT
fail=0
NL='
'
TAB=$(printf '\t')
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]"; fail=1 ;; esac; }
absent() { case "$3" in *"$2"*) echo "FAIL $1: [$2] found in [$3]"; fail=1 ;; *) echo "ok   $1" ;; esac; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi 2>/dev/null | cut -d' ' -f1; }
# listing <dir>: sorted "hash path" of every file and "L path target" of every symlink
listing() { (cd "$1" && find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf 'L %s %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$(sha "$f")" "$f"; fi; done); }
treehash() { listing "$1" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }
exists01() { if [ -e "$1" ] || [ -L "$1" ]; then echo 1; else echo 0; fi; }
changed01() { if [ "$1" != "$2" ]; then echo 1; else echo 0; fi; }
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
      delete) check "$s manifest: $p exists in the template" "1" "$(exists01 "$TPL/$p")" ;;
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
  check "$s manifest has rows" "1" "$(changed01 0 "$n")"
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
  for d in $(dels_of "$s"); do check "$s apply: $d is gone" "0" "$(exists01 "$D/$d")"; done
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
  check "$s --force: the modified file is gone" "0" "$(exists01 "$D/$f")"
  check "$s --force: no example directory entry is left" "" "$(find "$D/src" -type d -empty 2>/dev/null | grep -i example)"
done
D=$T/mod-dir
seed "$D" nextjs
printf 'x\n' >"$D/src/features/example/extra-user-file.ts"
h=$(treehash "$D")
contains "extra file in the example directory is a blocker" "BLOCK  src/features/example/extra-user-file.ts" "$(out "$D")"
r=$(out "$D" --apply --force src/features/example)
contains "--force on the directory row removes it with the extra file" "remove-example: applied" "$r"
check "--force on the directory row: directory gone" "0" "$(exists01 "$D/src/features/example")"
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
check "a symlinked example directory: the target outside is intact" "1" "$(exists01 "$T/elsewhere/example/index.ts")"
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

# --- probes for the user-file traps: each refuses, writes nothing and names the reason; a clean control applies
PN=0
mode_of() { if stat --version >/dev/null 2>&1; then stat -c %a -- "$1"; else stat -f %Lp -- "$1"; fi; }
NOTROOT=1
if [ "$(id -u)" -eq 0 ]; then NOTROOT=0; fi
outcwd() { local d=$1; shift; (cd "$d" && out . "$@"); }
PAGE='src/app/dashboard/(overview)/page.tsx'
# probe <name> <stack> <setup-fn> <expected text> <control-fn or empty> [script args...]
probe() {
  local name=$1 s=$2 setup=$3 expect=$4 control=$5 D C h r
  shift 5
  D=$T/pr-$PN; PN=$((PN + 1))
  seed "$D" "$s" || return 0
  "$setup" "$D"
  h=$(treehash "$D")
  r=$(outcwd "$D" --apply "$@")
  contains "$name: refused, rc 1" "rc=1" "$r"
  contains "$name: says why" "$expect" "$r"
  check "$name: nothing written" "$h" "$(treehash "$D")"
  if [ -n "$control" ]; then
    C=$T/pr-$PN; PN=$((PN + 1))
    seed "$C" "$s" || return 0
    "$control" "$C"
    contains "$name, control: the clean variant applies" "remove-example: applied" "$(outcwd "$C" --apply "$@")"
  fi
}
s_crlf_all() { local f="$1/$PAGE"; awk '{ printf "%s\r\n", $0 }' "$f" >"$f.new"; mv "$f.new" "$f"; }
s_cr_one() { printf '// note\r\n' >>"$1/$PAGE"; }
s_lf_one() { printf '// note\n' >>"$1/$PAGE"; }
s_link_edit() { mv "$1/$PAGE" "$T/lnk-page.tsx"; ln -s "$T/lnk-page.tsx" "$1/$PAGE"; }
s_link_del() { mv "$1/src/api/services/example.py" "$T/lnk-svc.py"; ln -s "$T/lnk-svc.py" "$1/src/api/services/example.py"; }
s_nl_name() { : >"$1/src/features/example/a${NL}AGENTS.md"; }
s_sp_name() { : >"$1/src/features/example/a AGENTS.md"; }
s_unread_ex() { chmod 000 "$1/src/features/example/index.ts"; }
s_unread_edit() { chmod 000 "$1/$PAGE"; }
s_nothing() { :; }
s_fifo() { mkfifo "$1/src/features/example/pipe"; }
probe "a CRLF user file" nextjs s_crlf_all "CR line endings" s_lf_one
probe "one CR line in an edited file" nextjs s_cr_one "CR line endings" s_lf_one
probe "an edit file that is a symlink" nextjs s_link_edit "symlink" s_nothing
probe "a single-file delete row that is a symlink" fastapi s_link_del "symlink" s_nothing
check "a symlinked single file: the link target is intact" "1" "$(exists01 "$T/lnk-svc.py")"
probe "a file name with a newline inside a forced directory" nextjs s_nl_name "newline" s_sp_name --force src/features/example
probe "a special file inside the example directory" nextjs s_fifo "special file" s_nothing
if [ "$NOTROOT" -eq 1 ]; then
  probe "an unreadable example file" nextjs s_unread_ex "is not readable" s_nothing
  probe "an unreadable edit file" nextjs s_unread_edit "is not readable" s_nothing
else
  echo "skip unreadable-file probes: running as root"
fi

# glob characters in --force are literal; the decoy index.ts is what an expanded [i]ndex.ts would name
D=$T/glob
seed "$D" nextjs
: >"$D/src/features/example/[i]ndex.ts"
r=$(outcwd "$D" --apply --force 'src/features/example/[i]ndex.ts')
contains "a --force path with glob characters: applied, taken literally" "remove-example: applied" "$r"
check "a --force path with glob characters: the example directory is gone" "0" "$(exists01 "$D/src/features/example")"

# a same-length edit of a middle line of a removed block is a blocker (3-line and 31-line blocks)
mid_probe() { # name stack file count
  local name=$1 s=$2 file=$3 cnt=$4 D C key at mid
  D=$T/mid-$PN; PN=$((PN + 1))
  seed "$D" "$s" || return 0
  key=$(awk -F'\t' -v f="$file" -v c="$cnt" '$1 == "rmblock" && $2 == f && $3 == c { print $4; exit }' "$RX/$s.manifest")
  at=$(awk -v k="$key" '$0 == k { print NR; exit }' "$D/$file")
  mid=$((at + cnt / 2))
  awk -v n="$mid" 'NR == n { $0 = substr($0, 1, length($0) - 1) "#" } { print }' "$D/$file" >"$D/$file.new"
  mv "$D/$file.new" "$D/$file"
  MID_SIZE=$(wc -c <"$D/$file" | tr -d ' ')
  check "$name: the middle line really changed, same length" "$(wc -c <"$ROOT/skills/scaffold/$s/template/$file" | tr -d ' ')" "$MID_SIZE"
  local h; h=$(treehash "$D")
  local r; r=$(out "$D" --apply)
  contains "$name: refused, rc 1" "rc=1" "$r"
  contains "$name: names the block line" "of the block differs from the scaffold text" "$r"
  check "$name: nothing written" "$h" "$(treehash "$D")"
  C=$T/mid-$PN; PN=$((PN + 1))
  seed "$C" "$s" || return 0
  contains "$name, control: the unedited block applies" "remove-example: applied" "$(out "$C" --apply)"
}
mid_probe "a 3-line block with a changed middle line" vite-react src/pages/dashboard.tsx 3
mid_probe "the 31-line e2e block with a changed middle line" nestjs test/app.e2e-spec.ts 31

# a failed write leaves every file as it was (needs a non-root user: a read-only directory)
if [ "$NOTROOT" -eq 1 ]; then
  D=$T/wf-del
  seed "$D" fastapi
  h=$(treehash "$D")
  chmod a-w "$D/src/api/services"
  r=$(out "$D" --apply)
  chmod u+w "$D/src/api/services"
  contains "a delete that fails midway: rc 1" "rc=1" "$r"
  contains "a delete that fails midway: says it restored everything" "every file was restored" "$r"
  check "a delete that fails midway: every file is byte for byte as before (edits rolled back, deleted files back)" "$h" "$(treehash "$D")"
  contains "control: the same project applies once the directory is writable again" "remove-example: applied" "$(out "$D" --apply)"
  D=$T/wf-stage
  seed "$D" nextjs
  h=$(treehash "$D")
  chmod a-w "$D/test/components"
  r=$(out "$D" --apply)
  chmod u+w "$D/test/components"
  contains "a temp file that cannot be created next to the second edit: rc 1" "rc=1" "$r"
  check "a temp file that cannot be created: nothing was written, not even the first edit" "$h" "$(treehash "$D")"
else
  echo "skip failed-write probes: running as root"
fi

# the mode of an edited file is kept
D=$T/mode
seed "$D" fastapi
chmod 755 "$D/src/api/routes.py"
chmod 600 "$D/src/api/tags.py"
out "$D" --apply >/dev/null
check "mode kept: routes.py 755" "755" "$(mode_of "$D/src/api/routes.py")"
check "mode kept: tags.py 600" "600" "$(mode_of "$D/src/api/tags.py")"

# missing manifest, symlinked manifest, missing template: refused, nothing written
plugcase() { # name expected-text setup-function
  local D=$T/pg4 h r
  rm -rf "$T/plug4" "$D"
  mkplug "$T/plug4"
  "$3"
  seed "$D" nextjs
  h=$(treehash "$D")
  r=$(bash "$T/plug4/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
  contains "$1: refused" "rc=1" "$r"
  contains "$1: says why" "$2" "$r"
  check "$1: nothing written" "$h" "$(treehash "$D")"
}
PM=$T/plug4/skills/cleanup/remove-example/nextjs.manifest
pc_missing() { rm "$PM"; }
pc_link() { cp "$PM" "$T/real.manifest"; rm "$PM"; ln -s "$T/real.manifest" "$PM"; }
pc_notpl() { rm "$T/plug4/skills/scaffold/nextjs/template"; }
plugcase "a missing manifest" "missing or a symlink" pc_missing
plugcase "a symlinked manifest" "missing or a symlink" pc_link
plugcase "a missing scaffold template" "scaffold template for nextjs is not beside this script" pc_notpl

# overlapping edits, and a subline row on its own
D=$T/ov
seed "$D" fastapi
rm -rf "$T/plug2"; mkplug "$T/plug2"
PM2=$T/plug2/skills/cleanup/remove-example/fastapi.manifest
awk -F'\t' '$1 == "rmline" && $2 == "src/api/tags.py"' "$RX/fastapi.manifest" >>"$PM2"
h=$(treehash "$D")
r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
contains "overlapping edits: refused" "rc=1" "$r"
contains "overlapping edits: says so" "overlapping edits" "$r"
check "overlapping edits: nothing written" "$h" "$(treehash "$D")"
D=$T/subonly
seed "$D" nestjs
rm -rf "$T/plug2"; mkplug "$T/plug2"
PM2=$T/plug2/skills/cleanup/remove-example/nestjs.manifest
awk -F'\t' '$1 == "subline"' "$RX/nestjs.manifest" >"$PM2"
old=$(awk -F'\t' '{ print $3 }' "$PM2")
new=$(awk -F'\t' '{ print $4 }' "$PM2")
sfile=$(awk -F'\t' '{ print $2 }' "$PM2")
r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
contains "a subline row alone: applied" "remove-example: applied" "$r"
check "a subline row alone: the old line is gone" "0" "$(grep -c -x -F -e "$old" "$D/$sfile")"
check "a subline row alone: the new line is there once" "1" "$(grep -c -x -F -e "$new" "$D/$sfile")"
r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply 2>&1; echo "rc=$?")
contains "a subline row alone: the second run is a no-op" "nothing to remove" "$r"

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
  check "mutant without the byte compare deletes the modified file" "0" "$(exists01 "$D/src/features/example/index.ts")"
fi
D=$T/mut2
seed "$D" nextjs
pg="$D/src/app/dashboard/(overview)/page.tsx"
sed 's/ExampleList } from/ExampleList  } from/' "$pg" >"$pg.new" && mv "$pg.new" "$pg"
if mutate "blockers ignored" 's|if \[ "[$]blockers" -gt 0 \]; then|if false; then|'; then
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant that ignores blockers deletes the example although the edit failed (half-done)" "0" "$(exists01 "$D/src/features/example")"
fi
D=$T/mut3
seed "$D" nextjs
mkdir -p "$T/mut3-outside"
if mutate "no symlink component check" 's|if \[ -L "[$]acc" \]; then return 1; fi|:|'; then
  mv "$D/src/features" "$T/mut3-outside/features"
  ln -s "$T/mut3-outside/features" "$D/src/features"
  bash "$MUT" "$D" --apply >/dev/null 2>&1
  check "mutant without the symlink check deletes through the link" "0" "$(exists01 "$T/mut3-outside/features/example/index.ts")"
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

# --- mutants for the other refusals: with the check removed, the bad input gets through
mutate_awk() { # name awk-program: like mutate, with an awk program
  local name=$1 prog=$2
  rm -rf "$T/plug3"; mkplug "$T/plug3"
  local m=$T/plug3/skills/cleanup/remove-example/remove-example.sh
  awk "$prog" "$RX/remove-example.sh" >"$m"
  if cmp -s "$m" "$RX/remove-example.sh"; then echo "FAIL mutant $name: awk program matched nothing"; fail=1; return 1; fi
  MUT=$m
}
mrun() { local d=$1; shift; (cd "$d" && bash "$MUT" . "$@" 2>&1; echo "rc=$?"); }

D=$T/mut-dup
seed "$D" nextjs
printf "import DashboardPage from '@/app/dashboard/(overview)/page';\n" >>"$D/test/components/render.test.tsx"
if mutate "dup-line check" 's|if (cnt > 1) {|if (0) {|'; then
  contains "mutant without the match-once check lets a duplicated line through" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-nonl
seed "$D" fastapi
printf '%s' "$(cat "$D/src/api/tags.py")" >"$D/src/api/tags.py"
if mutate "final newline check" '/has no final newline/s/^  if .*; then block/  if false; then block/'; then
  contains "mutant without the final-newline check lets the file through" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-partial
seed "$D" fastapi
sed '/^from api.routers import example$/d' "$D/src/api/routes.py" >"$D/src/api/routes.new"; mv "$D/src/api/routes.new" "$D/src/api/routes.py"
if mutate "partial-present check" 's|if (absent > 0) { print "some expected lines are present and some are missing"; exit 3 }|absent = 0|'; then
  contains "mutant that accepts some-present-some-missing lets the file through" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-nontpl
seed "$D" nextjs
printf 'mine\n' >"$D/src/mine.ts"
if mutate "non-template-file check" 's|^  if \[ ! -e "[$]TPL/[$]p" \]; then block .*|  :|'; then
  printf 'delete\tsrc/mine.ts\n' >"$T/plug3/skills/cleanup/remove-example/nextjs.manifest"
  mrun "$D" --apply --force src/mine.ts >/dev/null
  check "mutant without the template check deletes a forced user file the scaffold never had" "0" "$(exists01 "$D/src/mine.ts")"
fi
D=$T/nontpl
seed "$D" nextjs
printf 'mine\n' >"$D/src/mine.ts"
rm -rf "$T/plug2"; mkplug "$T/plug2"
printf 'delete\tsrc/mine.ts\n' >"$T/plug2/skills/cleanup/remove-example/nextjs.manifest"
r=$(bash "$T/plug2/skills/cleanup/remove-example/remove-example.sh" "$D" --apply --force src/mine.ts 2>&1; echo "rc=$?")
contains "control: the real script refuses a forced manifest root the scaffold never had" "is not in the scaffold template" "$r"
check "control: the user file is intact" "1" "$(exists01 "$D/src/mine.ts")"
D=$T/mut-special
seed "$D" nextjs
mkfifo "$D/src/features/example/pipe"
if mutate "special-file check" 's|^    if \[ -s "[$]STAGE/odd" \]; then block .*|    :|'; then
  absent "mutant without the special-file check no longer reports it" "special file" "$(mrun "$D" --apply)"
fi
D=$T/mut-abs
seed "$D" nextjs
if mutate "absolute-path check" "s#case \"\$p\" in '' | /\* | #case \"\$p\" in '' | #; s#\*/\./\* | \*//\*) return 1#*/./*) return 1#"; then
  printf 'delete\t/etc\n' >"$T/plug3/skills/cleanup/remove-example/nextjs.manifest"
  contains "mutant without the absolute-path check lets an absolute manifest path through" "rc=0" "$(mrun "$D")"
fi
D=$T/mut-cr
seed "$D" nextjs
s_cr_one "$D"
if mutate "CR check" 's|^  if LC_ALL=C grep -q "[$]CR" .*|  :|'; then
  contains "mutant without the CR check lets a CR line through" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-mid
seed "$D" vite-react
awk -v k="$(awk -F'\t' '$1 == "rmblock" && $3 == 3 { print $4; exit }' "$RX/vite-react.manifest")" '$0 == k { m = NR + 1 } { L[NR] = $0 } END { for (i = 1; i <= NR; i++) { x = L[i]; if (i == m) x = substr(x, 1, length(x) - 1) "#"; print x } }' "$D/src/pages/dashboard.tsx" >"$D/src/pages/dashboard.new"
mv "$D/src/pages/dashboard.new" "$D/src/pages/dashboard.tsx"
if mutate "every-line block compare" 's|if (L\[at + k\] "" != T\[ts + k\] "") {|if (0) {|'; then
  contains "mutant that compares only the first and last lines applies a block with an edited middle line" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-ov
seed "$D" fastapi
if mutate "overlap check" 's|^    function mark.*|    function mark(i, what) { gone[i] = what }|'; then
  awk -F'\t' '$1 == "rmline" && $2 == "src/api/tags.py"' "$RX/fastapi.manifest" >>"$T/plug3/skills/cleanup/remove-example/fastapi.manifest"
  contains "mutant without the overlap check applies overlapping edits" "rc=0" "$(mrun "$D" --apply)"
fi
D=$T/mut-nlname
seed "$D" nextjs
s_nl_name "$D"
if mutate "newline-name check" 's|^    if \[ -s "[$]STAGE/nlnames" \]; then block .*|    :|'; then
  absent "mutant without the newline-name check no longer reports it" "newline" "$(mrun "$D" --apply --force src/features/example)"
fi
D=$T/mut-glob
seed "$D" nextjs
: >"$D/src/features/example/[i]ndex.ts"
if mutate_awk "unquoted force list" '/^while IFS= read -r f; do$/ { a++; if (a == 2) { print "for f in $FORCE; do"; next } } /^done <<<"\$FORCE"$/ { b++; if (b == 2) { print "done"; next } } { print }'; then
  contains "mutant with an unquoted force list expands the glob and refuses the literal path" "matches no file this run would delete" "$(mrun "$D" --apply --force 'src/features/example/[i]ndex.ts')"
fi
D=$T/mut-link-edit
seed "$D" nextjs
s_link_edit "$D"
if mutate "symlink check (edit file)" 's|if \[ -L "[$]acc" \]; then return 1; fi|:|'; then
  mrun "$D" --apply >/dev/null
  check "mutant without the symlink check replaces the symlink with a file" "0" "$(if [ -L "$D/$PAGE" ]; then echo 1; else echo 0; fi)"
fi
D=$T/mut-link-del
seed "$D" fastapi
s_link_del "$D"
if mutate "symlink check (delete file)" 's|if \[ -L "[$]acc" \]; then return 1; fi|:|'; then
  mrun "$D" --apply >/dev/null
  check "mutant without the symlink check deletes the user's link" "0" "$(exists01 "$D/src/api/services/example.py")"
fi
if [ "$NOTROOT" -eq 1 ]; then
  D=$T/mut-rb
  seed "$D" fastapi
  h=$(treehash "$D")
  chmod a-w "$D/src/api/services"
  if mutate "rollback" 's|^  rollback$|  :|'; then
    mrun "$D" --apply >/dev/null
    chmod u+w "$D/src/api/services"
    check "mutant without the rollback leaves the project half-done" "1" "$(changed01 "$h" "$(treehash "$D")")"
  fi
  chmod -R u+rwx "$D" 2>/dev/null
fi
D=$T/mut-mode
seed "$D" fastapi
chmod 755 "$D/src/api/routes.py"
if mutate "mode kept" 's|^  chmod "[$]m" "[$]tmp" .*|  :|'; then
  mrun "$D" --apply >/dev/null
  check "mutant that skips the chmod changes the mode of the edited file" "1" "$(changed01 755 "$(mode_of "$D/src/api/routes.py")")"
fi

if [ "$fail" -ne 0 ]; then echo "remove-example tests FAILED"; exit 1; fi
echo "remove-example tests passed"
