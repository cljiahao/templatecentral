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
# A file is deleted only when it is byte for byte the scaffold's example file in this plugin
# (skills/scaffold/<stack>/template/<path>). A file that differs, or that the scaffold never had, is a blocker unless its path
# (or the manifest's directory row) is named with --force <path>.
# All checks run before the first write, and any blocker makes the whole run refuse: no file is deleted or edited.
# Re-running after a removal is a no-op: a file whose expected lines are all absent counts as done only when every delete
# path is already gone; otherwise it is reported as a mismatch.
# Exit codes: 0 done, dry run clean, or nothing to remove; 1 refused (a blocker was printed); 2 usage error.
# Caught: no AGENTS.md marker; a manifest row that is malformed; a path outside the project, absolute, with . or .. segments,
#   or with a symlink component; a symlink or special file inside a deleted directory; an expected line that is missing, matches
#   twice, or sits in a file with no final newline; overlapping edits; a --force path that matches nothing.
# Not caught: a file whose content changed but still equals the scaffold's current example (nothing is lost then);
#   example code a user copied elsewhere; imports of the example from files the manifest does not name (the build and
#   typecheck show these); a write that fails halfway after every check passed.
# Needs bash 3.2+, awk, cmp, find, sort, mktemp.
set -u

NL='
'
TAB=$(printf '\t')
die() { echo "remove-example: $1" >&2; exit 1; }
usage() { echo "usage: remove-example.sh <project-dir> [--apply] [--force <path>]..." >&2; exit 2; }

PROJ=
APPLY=0
FORCE=
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --force) shift; [ $# -gt 0 ] || usage; FORCE=$FORCE$1$NL ;;
    -*) usage ;;
    *) [ -z "$PROJ" ] || usage; PROJ=$1 ;;
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
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '<!-- templateCentral: '*'@'*' -->')
      STACK=${line#'<!-- templateCentral: '}
      STACK=${STACK%%@*}
      break ;;
  esac
done <"$AGENTS"
case "$STACK" in nestjs | nextjs | vite-react | fastapi) ;; *) die "AGENTS.md has no templateCentral marker naming a stack: run templatecentral:migrate first" ;; esac

MANIFEST=$SH/$STACK.manifest
TPL=$SH/../../scaffold/$STACK/template
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "manifest $MANIFEST is missing or a symlink"
TPL=$(cd -P -- "$TPL" 2>/dev/null && pwd -P) || die "the scaffold template for $STACK is not beside this script"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/remove-example.XXXXXX") || die "cannot create a temp directory"
trap 'rm -rf "$STAGE"' EXIT

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
    [ ! -L "$acc" ] || return 1
  done
  return 0
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
block() { echo "BLOCK  $1"; blockers=$((blockers + 1)); }

FORCE_USED=
is_forced() {
  case "$NL$FORCE" in *"$NL$1$NL"*) FORCE_USED=$FORCE_USED$1$NL; return 0 ;; esac
  return 1
}

OLDIFS=$IFS
IFS=$NL
for f in $FORCE; do
  safe_rel "$f" || die "--force path '$f' is outside the project, unclean or has a symlink"
done
IFS=$OLDIFS

: >"$STAGE/deletes"
: >"$STAGE/editfiles"
ALL_GONE=1

# delete rows
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in "delete$TAB"*) ;; *) continue ;; esac
  p=${row#delete"$TAB"}
  safe_rel "$p" || { block "delete path '$p' is outside the project, unclean or has a symlink"; continue; }
  if [ ! -e "$ROOT/$p" ]; then echo "GONE   $p"; continue; fi
  ALL_GONE=0
  [ -e "$TPL/$p" ] || { block "$p is not in the scaffold template; nothing to compare it with"; continue; }
  if [ -d "$ROOT/$p" ]; then
    find "$ROOT/$p" ! -type d ! -type f >"$STAGE/odd"
    if [ -s "$STAGE/odd" ]; then block "$p holds a symlink or special file"; continue; fi
    find "$ROOT/$p" -type f -print >"$STAGE/files"
    LC_ALL=C sort "$STAGE/files" >"$STAGE/files.sorted"
  elif [ -f "$ROOT/$p" ]; then
    printf '%s\n' "$ROOT/$p" >"$STAGE/files.sorted"
  else
    block "$p is not a regular file or directory"; continue
  fi
  while IFS= read -r abs; do
    rel=${abs#"$ROOT"/}
    if [ -f "$TPL/$rel" ] && cmp -s -- "$abs" "$TPL/$rel"; then
      printf '%s\n' "$rel" >>"$STAGE/deletes"
      echo "DELETE $rel"
    elif is_forced "$rel" || is_forced "$p"; then
      printf '%s\n' "$rel" >>"$STAGE/deletes"
      echo "FORCE  $rel (differs from the scaffold example)"
    else
      block "$rel differs from the scaffold example or is not part of it; keep it, or name it with --force $rel"
    fi
  done <"$STAGE/files.sorted"
  printf '%s\n' "$p" >>"$STAGE/delroots"
done <"$MANIFEST"
[ -f "$STAGE/delroots" ] || : >"$STAGE/delroots"

IFS=$NL
for f in $FORCE; do
  case "$NL$FORCE_USED" in *"$NL$f$NL"*) ;; *) block "--force $f matches no file this run would delete" ;; esac
done
IFS=$OLDIFS

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
  if [ -s "$ROOT/$file" ] && [ -n "$(tail -c1 "$ROOT/$file")" ]; then block "$file has no final newline"; continue; fi
  awk -F'\t' -v f="$file" '/^#/ || /^$/ { next } $1 != "delete" && $2 == f { print }' "$MANIFEST" >"$STAGE/rows.$n"
  OUT=$STAGE/out.$n
  export OUT
  res=$(awk '
    BEGIN { FS = "\t" }
    FNR == NR { nr++; t[nr] = $1; a[nr] = $3; b[nr] = $4; c[nr] = $5; d[nr] = $6; next }
    { L[FNR] = $0; nl = FNR }
    function mark(i, what) { if (i in gone || i in subs) { print "overlapping edits at line " i; bad = 1 } else gone[i] = what }
    END {
      absent = 0; present = 0
      for (r = 1; r <= nr; r++) {
        key = (t[r] == "rmblock") ? b[r] : (t[r] == "rmline" ? a[r] : a[r])
        cnt = 0; at = 0
        for (i = 1; i <= nl; i++) if (L[i] == key) { cnt++; at = i }
        if (cnt == 0) { absent++; continue }
        if (cnt > 1) { print "expected line matches " cnt " lines: " key; bad = 1; continue }
        present++
        if (t[r] == "subline") { if (at in gone || at in subs) { print "overlapping edits at line " at; bad = 1 } else subs[at] = b[r]; print "  replace line " at; continue }
        s = at; e = at; blk = d[r]
        if (t[r] == "rmline") blk = b[r]
        if (t[r] == "rmblock") {
          e = at + a[r] - 1
          if (e > nl || L[e] != c[r]) { print "block of " a[r] " lines from line " at " does not end with the expected last line"; bad = 1; continue }
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
  ' "$STAGE/rows.$n" "$ROOT/$file")
  rc=$?
  case "$rc" in
    0) echo "EDIT   $file"; printf '%s\n' "$res"; printf '%s\t%s\n' "$file" "$OUT" >>"$STAGE/editfiles" ;;
    4) if [ "$ALL_GONE" -eq 1 ]; then echo "DONE   $file (already edited)"; else block "$file: none of the expected lines were found, but example files still exist"; fi ;;
    *) block "$file: $(printf '%s' "$res" | tr '\n' ';')" ;;
  esac
done <"$STAGE/names"

if [ "$blockers" -gt 0 ]; then
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

while IFS="$TAB" read -r file staged; do
  [ -n "$file" ] || continue
  cat -- "$staged" >"$ROOT/$file" || die "cannot write $file"
done <"$STAGE/editfiles"
while IFS= read -r rel; do
  rm -f -- "$ROOT/$rel" || die "cannot delete $rel"
done <"$STAGE/deletes"
while IFS= read -r p; do
  if [ -d "$ROOT/$p" ]; then find "$ROOT/$p" -depth -type d -exec rmdir {} \; || die "cannot remove directory $p"; fi
done <"$STAGE/delroots"
echo "remove-example: applied"
