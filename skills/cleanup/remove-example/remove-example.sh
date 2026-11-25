#!/usr/bin/env bash
# remove-example.sh: remove the example code of a templateCentral project, driven by a per-stack manifest.
# Usage: remove-example.sh <project-dir> [--apply] [--force <path>]...
# Dry run by default: prints what it would delete and edit, writes nothing. --apply does it.
# The stack comes from the "<!-- templateCentral: <stack>@<version> -->" marker in <project-dir>/AGENTS.md. The manifest
# <stack>.manifest beside this script lists tab-separated rows (# starts a comment):
#   delete   <path>                                            a file or a directory
#   rmline   <file> <line> <blank>                             remove the one line that equals <line>
#   rmblock  <file> <count> <first> <last> <blank>             remove <count> lines from <first> to <last>
#   subline  <file> <old> <new>                                replace the one line that equals <old>
# <blank> is - (none), before or after: also remove the single blank line before or after the removal. A line must match
# exactly once, whole and byte for byte.
# Nothing is removed unless it is proved to be scaffold text. This script needs the scaffold beside it
# (skills/scaffold/<stack>/template, in the same plugin) and fails closed when that is not there:
#   a deleted file must be byte for byte the scaffold's example file; a removed block must equal, line for line, the same
#   lines in the scaffold's copy of the file. A deleted file that differs, or that the scaffold never had, is a blocker unless
#   its path (or the manifest's directory row) is named with --force <path>. A manifest path that the scaffold itself lacks is
#   always a blocker (the plugin is damaged), and an edit row cannot be forced: change those lines by hand.
# All checks run before the first write, and any blocker makes the whole run refuse: no file is deleted or edited.
# Apply order: re-check every file against the copy taken during the checks, write each edited file as a temp file in its own
#   directory (same mode) and rename it over the original, then delete the files, then the empty directories. On any failure
#   everything already done is restored from the copies and the exit code is 1; if even the restore fails the copies are kept
#   and their directory is printed.
# Re-running after a removal is a no-op: a file whose expected lines are all absent counts as done only when every delete
# path is already gone; otherwise it is reported as a mismatch.
# Exit codes: 0 done, dry run clean, or nothing to remove; 1 refused or failed (a blocker or the failure was printed); 2 usage error.
# Caught: no AGENTS.md marker; a manifest row that is malformed; a path outside the project, absolute, with . or .. segments, or
#   with a symlink component; a symlink, special file, unreadable file or file name with a newline inside a deleted directory; an
#   unreadable directory (find fails); a CR in an edited file; an expected line that is missing, matches twice, or sits in a file
#   with no final newline; a block that differs from the scaffold's in any line; overlapping edits; a --force path that matches
#   nothing; a file changed between the checks and the write; a write or delete that fails (rolled back).
# Not caught: a file whose content changed but still equals the scaffold's current example (nothing is lost then); example code a
#   user copied elsewhere; imports of the example from files the manifest does not name (the build and typecheck show these); a
#   change made in the instant between the final re-check and the write; deleted directories come back with default modes after
#   a rollback; a project seeded by an older plugin version: its example files can differ from today's scaffold (the BLOCK output
#   names both versions; do not --force a whole directory to get past it, compare each file first).
# Needs bash 3.2+, awk, chmod, cmp, cp, find, grep, mktemp, mv, rm, rmdir, sed, sort, stat, tail.
set -u

NL='
'
TAB=$(printf '\t')
CR=$(printf '\r')
die() { echo "remove-example: $1" >&2; exit 1; }
usage() { echo "usage: remove-example.sh <project-dir> [--apply] [--force <path>]..." >&2; exit 2; }

PROJ=
APPLY=0
FORCE=
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --force)
      shift
      [ $# -gt 0 ] || usage
      case "$1" in '' | *"$NL"*) usage ;; esac
      FORCE=$FORCE$1$NL ;;
    -*) usage ;;
    *)
      if [ -n "$PROJ" ]; then usage; fi
      PROJ=$1 ;;
  esac
  shift
done
[ -n "$PROJ" ] || usage
[ -d "$PROJ" ] || die "$PROJ is not a directory"
ROOT=$(cd -P -- "$PROJ" 2>/dev/null && pwd -P) || die "cannot enter $PROJ"
case "$ROOT" in *"$NL"*) die "the project path holds a newline" ;; esac

src=${BASH_SOURCE[0]:-$0}
SH=$(cd -P -- "$(dirname -- "$src")" 2>/dev/null && pwd -P) || die "cannot locate the script directory"

AGENTS=$ROOT/AGENTS.md
[ ! -L "$AGENTS" ] || die "AGENTS.md is a symlink"
[ -f "$AGENTS" ] || die "no AGENTS.md: run templatecentral:migrate first"
STACK=
MARK_VER=
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '<!-- templateCentral: '*'@'*' -->')
      STACK=${line#'<!-- templateCentral: '}
      STACK=${STACK%%@*}
      MARK_VER=${line#*@}
      MARK_VER=${MARK_VER%' -->'}
      break ;;
  esac
done <"$AGENTS"
case "$STACK" in nestjs | nextjs | vite-react | fastapi) ;; *) die "AGENTS.md has no templateCentral marker naming a stack: run templatecentral:migrate first" ;; esac

MANIFEST=$SH/$STACK.manifest
TPL=$SH/../../scaffold/$STACK/template
if [ ! -f "$MANIFEST" ] || [ -L "$MANIFEST" ]; then die "manifest $MANIFEST is missing or a symlink"; fi
TPL=$(cd -P -- "$TPL" 2>/dev/null && pwd -P) || die "the scaffold template for $STACK is not beside this script"

PLUGIN_VER=unknown
if [ -f "$SH/../../../.claude-plugin/plugin.json" ]; then
  v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SH/../../../.claude-plugin/plugin.json")
  v=${v%%"$NL"*}
  if [ -n "$v" ]; then PLUGIN_VER=$v; fi
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/remove-example.XXXXXX") || die "cannot create a temp directory"
KEEP_STAGE=0
: >"$STAGE/temps"
cleanup() {
  local t
  while IFS= read -r t; do
    if [ -n "$t" ]; then rm -f -- "$t"; fi
  done <"$STAGE/temps"
  if [ "$KEEP_STAGE" -eq 0 ]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT

# safe_rel <path>: succeeds when the path is relative, clean and has no symlink component under the project.
safe_rel() {
  local p=$1 acc=$ROOT d part
  case "$p" in '' | /* | *"$NL"*) return 1 ;; esac
  case "/$p/" in */../* | */./* | *//*) return 1 ;; esac
  d=$p
  while [ -n "$d" ]; do
    part=${d%%/*}
    case "$d" in */*) d=${d#*/} ;; *) d= ;; esac
    acc=$acc/$part
    if [ -L "$acc" ]; then return 1; fi
  done
  return 0
}

# file_mode <file>: prints the octal permission bits.
file_mode() {
  if stat --version >/dev/null 2>&1; then stat -c %a -- "$1"; else stat -f %Lp -- "$1"; fi
}

# Manifest check: every row well formed. Prints one line per problem.
bad=$(awk -F'\t' '
  /^#/ || /^$/ { next }
  /\r/ { print "line " NR ": carriage return"; next }
  { t = $1; ok = 1 }
  t == "delete"  { if (NF != 2 || $2 == "") ok = 0 }
  t == "rmline"  { if (NF != 4 || $2 == "" || $3 == "" || $4 !~ /^(-|before|after)$/) ok = 0 }
  t == "rmblock" { if (NF != 6 || $2 == "" || $3 !~ /^[1-9][0-9]*$/ || $4 == "" || $5 == "" || $6 !~ /^(-|before|after)$/) ok = 0 }
  t == "subline" { if (NF != 4 || $2 == "" || $3 == "" || $4 == "" || $3 == $4) ok = 0 }
  t != "delete" && t != "rmline" && t != "rmblock" && t != "subline" { ok = 0 }
  !ok { print "line " NR ": malformed row" }
' "$MANIFEST") || die "cannot read the manifest"
[ -z "$bad" ] || die "manifest $MANIFEST is malformed:$NL$bad"

blockers=0
VERSION_NOTE=0
block() { echo "BLOCK  $1"; blockers=$((blockers + 1)); }
block_differs() { VERSION_NOTE=1; block "$1"; }

FORCE_USED=
is_forced() {
  case "$NL$FORCE" in *"$NL$1$NL"*) FORCE_USED=$FORCE_USED$1$NL; return 0 ;; esac
  return 1
}

while IFS= read -r f; do
  if [ -z "$f" ]; then continue; fi
  safe_rel "$f" || die "--force path '$f' is outside the project, unclean or has a symlink"
done <<<"$FORCE"

: >"$STAGE/deletes"
: >"$STAGE/editfiles"
: >"$STAGE/delroots"
: >"$STAGE/dirs"
ALL_GONE=1

# delete rows
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in "delete$TAB"*) ;; *) continue ;; esac
  p=${row#delete"$TAB"}
  safe_rel "$p" || { block "delete path '$p' is outside the project, unclean or has a symlink"; continue; }
  if [ ! -e "$ROOT/$p" ]; then echo "GONE   $p"; continue; fi
  ALL_GONE=0
  if [ ! -e "$TPL/$p" ]; then block "$p is not in the scaffold template; nothing to compare it with"; continue; fi
  if [ -d "$ROOT/$p" ]; then
    if ! find "$ROOT/$p" ! -type d ! -type f >"$STAGE/odd" 2>/dev/null; then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi
    if [ -s "$STAGE/odd" ]; then block "$p holds a symlink or special file"; continue; fi
    if ! find "$ROOT/$p" -name "*$NL*" >"$STAGE/nlnames" 2>/dev/null; then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi
    if [ -s "$STAGE/nlnames" ]; then block "$p holds a file name with a newline"; continue; fi
    if ! find "$ROOT/$p" -type f >"$STAGE/files" 2>/dev/null; then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi
    LC_ALL=C sort "$STAGE/files" >"$STAGE/files.sorted"
    if ! find "$ROOT/$p" -depth -type d >>"$STAGE/dirs" 2>/dev/null; then block "$p cannot be listed (an unreadable directory inside it)"; continue; fi
  elif [ -f "$ROOT/$p" ]; then
    printf '%s\n' "$ROOT/$p" >"$STAGE/files.sorted"
  else
    block "$p is not a regular file or directory"; continue
  fi
  while IFS= read -r abs; do
    rel=${abs#"$ROOT"/}
    if [ ! -r "$abs" ]; then block "$rel is not readable"; continue; fi
    if [ -f "$TPL/$rel" ] && cmp -s -- "$abs" "$TPL/$rel"; then
      printf '%s\n' "$rel" >>"$STAGE/deletes"
      echo "DELETE $rel"
    elif is_forced "$rel" || is_forced "$p"; then
      printf '%s\n' "$rel" >>"$STAGE/deletes"
      echo "FORCE  $rel (differs from the scaffold example)"
    else
      block_differs "$rel differs from the scaffold example or is not part of it; keep it, or name it with --force $rel"
    fi
  done <"$STAGE/files.sorted"
  printf '%s\n' "$p" >>"$STAGE/delroots"
done <"$MANIFEST"

while IFS= read -r f; do
  if [ -z "$f" ]; then continue; fi
  case "$NL$FORCE_USED" in *"$NL$f$NL"*) ;; *) block "--force $f matches no file this run would delete" ;; esac
done <<<"$FORCE"

# edit rows, grouped by file in manifest order
awk -F'\t' '/^#/ || /^$/ { next } $1 != "delete" { print $2 }' "$MANIFEST" >"$STAGE/names"
n=0
seen=$NL
while IFS= read -r file; do
  case "$seen" in *"$NL$file$NL"*) continue ;; esac
  seen=$seen$file$NL
  n=$((n + 1))
  safe_rel "$file" || { block "edit path '$file' is outside the project, unclean or has a symlink"; continue; }
  if [ ! -f "$ROOT/$file" ]; then
    if [ "$ALL_GONE" -eq 1 ]; then echo "GONE   $file"; else block "$file to edit does not exist"; fi
    continue
  fi
  if [ ! -r "$ROOT/$file" ]; then block "$file is not readable"; continue; fi
  if LC_ALL=C grep -q "$CR" "$ROOT/$file"; then block "$file has CR line endings; the scaffold text uses LF, so nothing can be proved: edit it by hand"; continue; fi
  if [ -s "$ROOT/$file" ] && [ -n "$(tail -c1 "$ROOT/$file")" ]; then block "$file has no final newline"; continue; fi
  awk -F'\t' -v f="$file" '/^#/ || /^$/ { next } $1 != "delete" && $2 == f { print }' "$MANIFEST" >"$STAGE/rows.$n"
  tplfile=/dev/null
  if [ -f "$TPL/$file" ]; then tplfile=$TPL/$file; fi
  OUT=$STAGE/out.$n
  export OUT
  res=$(awk '
    BEGIN { FS = "\t" }
    FILENAME == ARGV[1] { nr++; t[nr] = $1; a[nr] = $3; b[nr] = $4; c[nr] = $5; d[nr] = $6; next }
    FILENAME == ARGV[2] { nt++; T[nt] = $0; next }
    { L[FNR] = $0; nl = FNR }
    function mark(i, what) { if (i in gone || i in subs) { print "overlapping edits at line " i; bad = 1 } else gone[i] = what }
    END {
      absent = 0; present = 0
      for (r = 1; r <= nr; r++) {
        key = (t[r] == "rmblock") ? b[r] : a[r]
        cnt = 0; at = 0
        for (i = 1; i <= nl; i++) if (L[i] "" == key "") { cnt++; at = i }
        if (cnt == 0) { absent++; continue }
        if (cnt > 1) { print "expected line matches " cnt " lines: " key; bad = 1; continue }
        present++
        if (t[r] == "subline") { if (at in gone || at in subs) { print "overlapping edits at line " at; bad = 1 } else subs[at] = b[r]; print "  replace line " at; continue }
        s = at; e = at; blk = d[r]
        if (t[r] == "rmline") blk = b[r]
        if (t[r] == "rmblock") {
          cb = a[r] + 0
          e = at + cb - 1
          if (e > nl || L[e] "" != c[r] "") { print "block of " cb " lines from line " at " does not end with the expected last line"; bad = 1; continue }
          if (nt == 0) { print "the scaffold has no copy of this file to compare the block with"; bad = 1; continue }
          tc = 0; ts = 0
          for (i = 1; i <= nt; i++) if (T[i] "" == key "") { tc++; ts = i }
          if (tc != 1 || ts + cb - 1 > nt || T[ts + cb - 1] "" != c[r] "") { print "the scaffold copy does not hold this block exactly once"; bad = 1; continue }
          differs = 0
          for (k = 0; k < cb; k++) if (L[at + k] "" != T[ts + k] "") { print "line " (at + k) " of the block differs from the scaffold text: edit it by hand"; differs = 1; break }
          if (differs) { bad = 1; continue }
        }
        if (blk == "before") { if (s > 1 && L[s - 1] == "") s--; else { print "no blank line before line " at; bad = 1; continue } }
        if (blk == "after") { if (e < nl && L[e + 1] == "") e++; else { print "no blank line after line " e; bad = 1; continue } }
        for (i = s; i <= e; i++) mark(i, 1)
        print "  remove lines " s "-" e
      }
      if (bad) exit 3
      if (present == 0) exit 4
      if (absent > 0) { print "some expected lines are present and some are missing"; exit 3 }
      out = ENVIRON["OUT"]
      printf "" > out
      for (i = 1; i <= nl; i++) { if (i in gone) continue; if (i in subs) print subs[i] >> out; else print L[i] >> out }
      close(out)
    }
  ' "$STAGE/rows.$n" "$tplfile" "$ROOT/$file")
  rc=$?
  case "$rc" in
    0)
      if [ "$APPLY" -eq 1 ]; then
        if ! cp -p -- "$ROOT/$file" "$STAGE/snapedit.$n"; then block "$file cannot be copied for the rollback"; continue; fi
      fi
      echo "EDIT   $file"; printf '%s\n' "$res"; printf '%s\t%s\t%s\n' "$file" "$OUT" "$STAGE/snapedit.$n" >>"$STAGE/editfiles" ;;
    4) if [ "$ALL_GONE" -eq 1 ]; then echo "DONE   $file (already edited)"; else block "$file: none of the expected lines were found, but example files still exist"; fi ;;
    *) block "$file: $(printf '%s' "$res" | tr '\n' ';')" ;;
  esac
done <"$STAGE/names"

if [ "$blockers" -gt 0 ]; then
  if [ "$VERSION_NOTE" -eq 1 ] && [ "$MARK_VER" != "$PLUGIN_VER" ]; then
    echo "NOTE   the project marker says templateCentral $MARK_VER, this plugin is $PLUGIN_VER: example files seeded by an older plugin can differ from today's scaffold. Do not --force a whole directory to get past this; compare each file first."
  fi
  echo "remove-example: $blockers blocker(s); nothing was changed" >&2
  exit 1
fi
if [ ! -s "$STAGE/deletes" ] && [ ! -s "$STAGE/editfiles" ]; then
  echo "No example code found — nothing to remove. The example may have already been removed."
  exit 0
fi
if [ "$APPLY" -eq 0 ]; then
  echo "dry run: nothing was changed; run again with --apply after the user confirms"
  exit 0
fi

# --- apply
: >"$STAGE/replaced"
: >"$STAGE/removed"

# restore_file <copy> <target>: put the copy back over target (temp file in the same directory, then rename).
restore_file() {
  local snap=$1 target=$2 t m
  t=$(mktemp "${target%/*}/.remove-example.XXXXXX") || return 1
  printf '%s\n' "$t" >>"$STAGE/temps"
  m=$(file_mode "$snap") || return 1
  cat -- "$snap" >"$t" || return 1
  chmod "$m" "$t" || return 1
  mv -f -- "$t" "$target"
}

# rollback: undo what the apply did so far.
rollback() {
  local bad=0 t s rel d
  while IFS="$TAB" read -r t s; do
    if [ -z "$t" ]; then continue; fi
    if ! restore_file "$s" "$t"; then echo "remove-example: could not restore $t" >&2; bad=1; fi
  done <"$STAGE/replaced"
  while IFS= read -r d; do
    if [ -z "$d" ]; then continue; fi
    if ! mkdir -p -- "$d"; then echo "remove-example: could not recreate $d" >&2; bad=1; fi
  done <"$STAGE/dirs"
  while IFS= read -r rel; do
    if [ -z "$rel" ]; then continue; fi
    if [ -e "$ROOT/$rel" ]; then continue; fi
    if ! cp -p -- "$STAGE/snapdel/$rel" "$ROOT/$rel"; then echo "remove-example: could not restore $rel" >&2; bad=1; fi
  done <"$STAGE/removed"
  if [ "$bad" -eq 1 ]; then
    KEEP_STAGE=1
    echo "remove-example: ROLLBACK INCOMPLETE. Copies of the original files are kept in $STAGE" >&2
  else
    echo "remove-example: every file was restored; the project is as it was" >&2
  fi
}

# fail_apply <message>: report, roll back, exit 1.
fail_apply() {
  echo "remove-example: $1" >&2
  rollback
  exit 1
}

# copies of every file to delete, taken now; they are also what the rollback restores
while IFS= read -r rel; do
  if [ -z "$rel" ]; then continue; fi
  case "$rel" in */*) mkdir -p -- "$STAGE/snapdel/${rel%/*}" || die "cannot create a temp directory" ;; *) mkdir -p -- "$STAGE/snapdel" || die "cannot create a temp directory" ;; esac
  cp -p -- "$ROOT/$rel" "$STAGE/snapdel/$rel" || die "cannot copy $rel; nothing was changed"
done <"$STAGE/deletes"

# re-check: nothing changed since the checks
while IFS="$TAB" read -r file staged snap; do
  if [ -z "$file" ]; then continue; fi
  if ! cmp -s -- "$snap" "$ROOT/$file"; then die "$file changed while the script ran; nothing was changed"; fi
done <"$STAGE/editfiles"

# stage every edited file as a temp file next to its target, with the target's mode
: >"$STAGE/plan"
while IFS="$TAB" read -r file staged snap; do
  if [ -z "$file" ]; then continue; fi
  target=$ROOT/$file
  tmp=$(mktemp "${target%/*}/.remove-example.XXXXXX") || die "cannot create a temp file next to $file; nothing was changed"
  printf '%s\n' "$tmp" >>"$STAGE/temps"
  m=$(file_mode "$target") || die "cannot read the mode of $file; nothing was changed"
  cat -- "$staged" >"$tmp" || die "cannot write the new $file; nothing was changed"
  chmod "$m" "$tmp" || die "cannot set the mode of the new $file; nothing was changed"
  printf '%s\t%s\t%s\n' "$target" "$tmp" "$snap" >>"$STAGE/plan"
done <"$STAGE/editfiles"

# all edits before any delete
while IFS="$TAB" read -r target tmp snap; do
  if [ -z "$target" ]; then continue; fi
  if ! mv -f -- "$tmp" "$target"; then fail_apply "cannot replace ${target#"$ROOT"/}"; fi
  printf '%s\t%s\n' "$target" "$snap" >>"$STAGE/replaced"
done <"$STAGE/plan"

while IFS= read -r rel; do
  if [ -z "$rel" ]; then continue; fi
  printf '%s\n' "$rel" >>"$STAGE/removed"
  if ! rm -f -- "$ROOT/$rel"; then fail_apply "cannot delete $rel"; fi
  if [ -e "$ROOT/$rel" ]; then fail_apply "$rel is still there after the delete"; fi
done <"$STAGE/deletes"

while IFS= read -r d; do
  if [ -z "$d" ]; then continue; fi
  if ! rmdir -- "$d"; then fail_apply "cannot remove the directory ${d#"$ROOT"/}"; fi
done <"$STAGE/dirs"
while IFS= read -r p; do
  if [ -z "$p" ]; then continue; fi
  if [ -e "$ROOT/$p" ]; then fail_apply "$p is still there after the removal"; fi
done <"$STAGE/delroots"
echo "remove-example: applied"
