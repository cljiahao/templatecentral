#!/usr/bin/env bash
# review-scope.sh: print the files a review covers, or record the new review baseline.
# Usage: review-scope.sh <project-dir> [--session <path>]...
#        review-scope.sh <project-dir> --record-baseline --stack <nestjs|nextjs|vite-react|fastapi>
# Scope mode (default, writes nothing): prints one project-relative path per line, sorted, without duplicates: the files
#   committed since the baseline commit (git diff <sha>..HEAD --name-only) plus every --session path (the files the agent
#   wrote or edited this session, uncommitted ones included). No baseline file: the --session paths only. Empty output means an
#   empty scope: report "No changes since last review — nothing to check." and stop without recording.
# Record mode: writes <project-dir>/.claude/review-baseline.md (last-reviewed-commit, stack, reviewed-at). A project with no
#   commit yet gets no baseline and exit 0 with a note on stderr.
# Exit codes: 0 done, 1 refused (the project or the baseline is not safe to use; nothing written), 2 usage error.
# The baseline is written as a temp file inside .claude and renamed over the old one, so a failed write leaves the old baseline.
# A --session path is relative to the project, or absolute or prefixed with <project-dir> (any trailing / on it is ignored);
#   glob characters in it are literal.
# Caught: not a git repo; baseline file unreadable, a symlink, not a regular file, or with a missing, repeated or malformed
#   last-reviewed-commit line (a CR counts as malformed); baseline commit absent from the repo or not an ancestor of HEAD (a
#   shallow clone gets its own message); .claude a symlink; a --session path that is absolute outside the project, holds .., is
#   empty, holds a newline, has a symlink component, or names a file that is neither in the project nor a deletion in HEAD; a
#   changed file whose name holds a newline; a write or rename that fails (the old baseline stays).
# Not caught: a baseline file that is not the one the previous review wrote (any 40 or 64 hex commit in history is accepted);
#   a deleted file (git diff lists it, as before); two reviews recording at the same moment (each rename is whole, the last wins).
# Needs bash 3.2+, git, sort, date, mktemp, mv, chmod, stat.
set -u

die() { echo "review-scope: $1" >&2; exit 1; }
usage() { echo "usage: review-scope.sh <project-dir> [--session <path>]... | <project-dir> --record-baseline --stack <stack>" >&2; exit 2; }

PROJ=
RECORD=0
STACK=
SESSION=
NL='
'
while [ $# -gt 0 ]; do
  case "$1" in
    --record-baseline) RECORD=1 ;;
    --stack) shift; [ $# -gt 0 ] || usage; STACK=$1 ;;
    --session)
      shift
      [ $# -gt 0 ] || usage
      [ -n "$1" ] || die "empty --session path"
      case "$1" in *"$NL"*) die "a --session path holds a newline" ;; esac
      SESSION=$SESSION$1$NL ;;
    -*) usage ;;
    *) [ -z "$PROJ" ] || usage; PROJ=$1 ;;
  esac
  shift
done
[ -n "$PROJ" ] || usage
while [ "${#PROJ}" -gt 1 ]; do
  case "$PROJ" in */) PROJ=${PROJ%/} ;; *) break ;; esac
done
if [ "$RECORD" -eq 1 ]; then
  [ -z "$SESSION" ] || usage
  case "$STACK" in nestjs | nextjs | vite-react | fastapi) ;; *) usage ;; esac
else
  [ -z "$STACK" ] || usage
fi

[ -d "$PROJ" ] || die "$PROJ is not a directory"
ROOT=$(cd -P -- "$PROJ" 2>/dev/null && pwd -P) || die "cannot enter $PROJ"
case "$ROOT" in *"$NL"*) die "the project path holds a newline" ;; esac
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not inside a git repository"

SHALLOW=$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)
HAS_COMMIT=1
git -C "$ROOT" rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null 2>&1 || HAS_COMMIT=0
HEAD_SHA=
if [ "$HAS_COMMIT" -eq 1 ]; then HEAD_SHA=$(git -C "$ROOT" rev-parse 'HEAD^{commit}') || die "cannot resolve HEAD"; fi

BASE_DIR=$ROOT/.claude
BASE=$BASE_DIR/review-baseline.md
[ ! -L "$BASE_DIR" ] || die "$BASE_DIR is a symlink"

# read_baseline: sets BSHA from the baseline file; BSHA stays empty when there is no baseline file.
BSHA=
read_baseline() {
  [ -e "$BASE" ] || [ -L "$BASE" ] || return 0
  [ ! -L "$BASE" ] || die "$BASE is a symlink"
  [ -f "$BASE" ] || die "$BASE is not a regular file"
  [ -r "$BASE" ] || die "$BASE is not readable"
  local count=0 line val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      last-reviewed-commit:*)
        count=$((count + 1))
        val=${line#last-reviewed-commit:}
        val=${val# }
        BSHA=$val ;;
    esac
  done <"$BASE"
  [ "$count" -eq 1 ] || die "$BASE needs exactly one last-reviewed-commit line (found $count)"
  case "$BSHA" in
    *[!0-9a-f]* | '') die "$BASE: last-reviewed-commit is not a lowercase hex commit id" ;;
  esac
  case "${#BSHA}" in 40 | 64) ;; *) die "$BASE: last-reviewed-commit must be a full 40 or 64 digit commit id" ;; esac
  [ "$HAS_COMMIT" -eq 1 ] || die "$BASE names a commit but the repository has none"
  if ! git -C "$ROOT" cat-file -e "${BSHA}^{commit}" 2>/dev/null; then
    if [ "$SHALLOW" = true ]; then die "baseline commit $BSHA is not in this shallow clone: fetch more history (git fetch --unshallow) and run again; $BASE was not touched"; fi
    die "baseline commit $BSHA is not in this repository's history"
  fi
  if ! git -C "$ROOT" merge-base --is-ancestor "$BSHA" "$HEAD_SHA" 2>/dev/null; then
    if [ "$SHALLOW" = true ]; then die "this is a shallow clone, so the history between baseline commit $BSHA and HEAD cannot be checked: fetch more history (git fetch --unshallow) and run again; $BASE was not touched"; fi
    die "baseline commit $BSHA is not an ancestor of HEAD (history was rewritten); delete $BASE to start a new baseline"
  fi
}

# session_path <path>: prints the project-relative form of a session path, or exits 1.
session_path() {
  local p=$1 rel part acc d
  [ -n "$p" ] || die "empty --session path"
  case "$p" in
    "$ROOT"/*) rel=${p#"$ROOT"/} ;;
    "$PROJ"/*) rel=${p#"$PROJ"/} ;;
    /*) die "session path $p is outside the project" ;;
    *) rel=${p#./} ;;
  esac
  case "/$rel/" in
    */../* | */./* | *//*) die "session path $p holds an empty, . or .. segment" ;;
  esac
  [ -n "$rel" ] || die "empty --session path"
  acc=$ROOT
  d=$rel
  while [ -n "$d" ]; do
    part=${d%%/*}
    case "$d" in */*) d=${d#*/} ;; *) d= ;; esac
    acc=$acc/$part
    [ ! -L "$acc" ] || die "session path $p has a symlink component ($part)"
  done
  if [ ! -e "$ROOT/$rel" ]; then
    if [ "$HAS_COMMIT" -eq 1 ] && [ -n "$(git -C "$ROOT" ls-tree --name-only HEAD -- ":(literal)$rel" 2>/dev/null)" ]; then
      :
    else
      die "session path $p is not in the project and is not a file deleted since HEAD"
    fi
  fi
  printf '%s\n' "$rel"
}

if [ "$RECORD" -eq 1 ]; then
  if [ "$HAS_COMMIT" -eq 0 ]; then
    echo "review-scope: no commit yet, baseline not written" >&2
    exit 0
  fi
  read_baseline
  mkdir -p -- "$BASE_DIR" || die "cannot create $BASE_DIR"
  [ -d "$BASE_DIR" ] || die "$BASE_DIR is not a directory"
  TMP=$(mktemp "$BASE_DIR/.review-baseline.XXXXXX") || die "cannot create a temp file in $BASE_DIR; the old baseline stays"
  trap 'rm -f "$TMP"' EXIT
  {
    printf 'last-reviewed-commit: %s\n' "$HEAD_SHA"
    printf 'stack: %s\n' "$STACK"
    printf 'reviewed-at: %s\n' "$(date +%Y-%m-%d)"
  } >"$TMP" || die "cannot write the baseline; the old baseline stays"
  MODE=644
  if [ -f "$BASE" ]; then
    if stat --version >/dev/null 2>&1; then MODE=$(stat -c %a -- "$BASE"); else MODE=$(stat -f %Lp -- "$BASE"); fi
  fi
  chmod "$MODE" "$TMP" || die "cannot set the mode of the new baseline; the old baseline stays"
  mv -f -- "$TMP" "$BASE" || die "cannot replace $BASE; the old baseline stays"
  echo "review-scope: baseline written to $BASE"
  exit 0
fi

read_baseline
TMP=$(mktemp "${TMPDIR:-/tmp}/review-scope.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$TMP" "$TMP.diff"' EXIT
: >"$TMP"
if [ -n "$BSHA" ]; then
  git -C "$ROOT" diff --name-only --relative -z "$BSHA..HEAD" >"$TMP.diff" || die "git diff failed"
  while IFS= read -r -d '' f; do
    case "$f" in *"$NL"*) die "a changed file name holds a newline: refusing" ;; esac
    printf '%s\n' "$f" >>"$TMP"
  done <"$TMP.diff"
fi
while IFS= read -r s; do
  if [ -z "$s" ]; then continue; fi
  rel=$(session_path "$s") || exit 1
  printf '%s\n' "$rel" >>"$TMP"
done <<<"$SESSION"
LC_ALL=C sort -u "$TMP"
