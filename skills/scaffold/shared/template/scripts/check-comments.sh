#!/usr/bin/env bash
# Comment gate for project source: check-comments.sh [--root DIR] [--ts-from DIR] [--full] [base-ref | --all path...]
# Judges only lines added or changed since the base ref (--all treats every line of the listed paths as new). Offline.
# Rules: no trailing comment, no comment inside a function body, at most MAX_COMMENT_LINES per block,
# no parenthetical aside, no comment wholly in brackets. Tool directives, shebangs and licence headers are never judged.
# Tokenizers: the project's own typescript package for ts/tsx/js/jsx, python3 tokenize and ast for py.
# Base ref: the argument, else BASE_REF, else the merge base with the default branch. In CI (CI, GITHUB_ACTIONS or TF_BUILD)
# a BASE_REF from the environment is accepted only when it names the pipeline's own target branch variable; the report says which.
# Exit 0 clean, 1 findings, 2 cannot run (missing runtime or package, no base, unreadable file), always with one line naming the cause.
set -uo pipefail

MAX_COMMENT_LINES=3
MAX_REPORT_LINES=30
SOURCE_EXT='ts tsx js jsx mjs cjs mts cts py'

# Generated and vendored paths nobody edits by hand; one place to extend.
is_skipped() {
  case "/$1" in
    */node_modules/* | */dist/* | */build/* | */coverage/* | */.next/* | */.turbo/* | */storybook-static/*) return 0 ;;
    */.venv/* | */venv/* | */__pycache__/* | */.git/* | */.claude/*) return 0 ;;
    */migrations/* | */alembic/versions/* | */src/components/ui/*) return 0 ;;
    */next-env.d.ts | *.min.js | *.lock | */package-lock.json | */pnpm-lock.yaml) return 0 ;;
  esac
  return 1
}

die() {
  printf 'check-comments: %s\n' "$1" >&2
  exit 2
}

here=$(cd "$(dirname "$0")" && pwd) || die "cannot locate the script folder"
root=$here/..
ts_from=
full=0
all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die "--root needs a folder"; root=$2; shift 2 ;;
    --ts-from) [ $# -ge 2 ] || die "--ts-from needs a folder"; ts_from=$2; shift 2 ;;
    --full) full=1; shift ;;
    --all) all=1; shift; break ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
cd "$root" || die "cannot enter the project folder ($root)"
root=$PWD
[ -z "$ts_from" ] || ts_from=$(cd "$ts_from" 2> /dev/null && pwd) || die "--ts-from folder does not exist"

for tool in awk sort mktemp rm find; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done
wd=$(mktemp -d "${TMPDIR:-/tmp}/check-comments.XXXXXX") || die "cannot create a temp folder"
trap 'rm -rf "$wd"' EXIT
specs=$wd/specs
: > "$specs"
decision=

has_source_ext() {
  local e
  for e in $SOURCE_EXT; do
    case "$1" in *."$e") return 0 ;; esac
  done
  return 1
}

# Adds one "path<TAB>ranges" line unless the path is skipped or not source.
add_spec() {
  has_source_ext "$1" || return 0
  is_skipped "$1" && return 0
  case "$1" in *$'\t'* | *$'\n'*) die "path holds a tab or newline, rename it: $1" ;; esac
  printf '%s\t%s\n' "$1" "$2" >> "$specs"
}

in_ci=0
[ -z "${GITHUB_ACTIONS:-}" ] || in_ci=1
[ -z "${TF_BUILD:-}" ] || in_ci=1
case "${CI:-}" in '' | false | False | FALSE | 0) ;; *) in_ci=1 ;; esac

if [ "$all" = 1 ]; then
  [ $# -gt 0 ] || die "--all needs at least one path"
  while IFS= read -r -d '' f; do
    add_spec "${f#./}" all
  done < <(find "$@" -type f -print0 2> /dev/null)
else
  command -v git > /dev/null 2>&1 || die "missing tool: git"
  git rev-parse --git-dir > /dev/null 2>&1 || die "not a git work tree, so there is no base to diff against. Fix: run inside the repository, or use --all"
  arg_base=${1:-}
  env_base=${BASE_REF:-}
  target=
  [ -z "${GITHUB_BASE_REF:-}" ] || target=$GITHUB_BASE_REF
  if [ -z "$target" ]; then
    target=${SYSTEM_PULLREQUEST_TARGETBRANCHNAME:-}
  fi
  if [ -z "$target" ] && [ -n "${SYSTEM_PULLREQUEST_TARGETBRANCH:-}" ]; then
    target=${SYSTEM_PULLREQUEST_TARGETBRANCH#refs/heads/}
  fi
  ref=
  if [ -n "$arg_base" ]; then
    ref=$arg_base
    decision="base ref taken from the command-line argument"
  elif [ -n "$env_base" ]; then
    if [ "$in_ci" = 1 ]; then
      [ -n "$target" ] || die "BASE_REF from the environment is refused in CI: no pipeline target branch variable is set. Fix: pass the base ref as an argument in the pipeline step."
      case "$env_base" in
        "$target" | "origin/$target" | "refs/heads/$target" | "refs/remotes/origin/$target") ;;
        *) die "BASE_REF=$env_base is refused in CI: it is not the pipeline target branch ($target). Fix: unset BASE_REF, or pass the base ref as an argument in the pipeline step." ;;
      esac
      decision="BASE_REF from the environment, accepted because it names the pipeline target branch ($target)"
    else
      decision="BASE_REF from the environment (not CI)"
    fi
    ref=$env_base
  elif [ "$in_ci" = 1 ] && [ -n "$target" ]; then
    ref=origin/$target
    decision="pipeline target branch ($target)"
  else
    head_ref=$(git symbolic-ref -q refs/remotes/origin/HEAD 2> /dev/null || true)
    head_ref=${head_ref#refs/remotes/}
    for cand in "$head_ref" origin/main origin/master main master; do
      [ -n "$cand" ] || continue
      if git rev-parse --verify -q "$cand^{commit}" > /dev/null 2>&1; then ref=$cand; break; fi
    done
    [ -n "$ref" ] || die "no default branch found to diff against. Fix: fetch it (git fetch origin) or pass the base ref as an argument."
    decision="merge base with the default branch ($ref)"
  fi
  git rev-parse --verify -q "$ref^{commit}" > /dev/null 2>&1 || die "base ref not found: $ref. Fix: fetch it (CI needs fetch-depth: 0)."
  mb=$(git merge-base "$ref" HEAD 2> /dev/null) || die "no merge base between $ref and HEAD. Fix: fetch full history (CI needs fetch-depth: 0)."
  git -c core.quotePath=false diff --no-color --no-ext-diff -U0 -M --diff-filter=AMR "$mb" -- . > "$wd/diff" 2> "$wd/diff.err" || die "git diff failed: $(head -n 1 "$wd/diff.err")"
  awk -F'\t' '
    /^diff --git / { hdr = 1; f = ""; next }
    hdr && /^\+\+\+ / {
      f = substr($0, 5)
      if (f ~ /^"/) { print "QUOTED" > "/dev/stderr"; bad = 1; next }
      sub(/^b\//, "", f)
      next
    }
    /^@@ / {
      hdr = 0
      if (!match($0, /\+[0-9]+(,[0-9]+)?/)) next
      s = substr($0, RSTART + 1, RLENGTH - 1)
      split(s, a, ",")
      n = (a[2] == "") ? 1 : a[2]
      if (n > 0 && f != "") r[f] = (r[f] == "" ? "" : r[f] ",") a[1] "-" (a[1] + n - 1)
    }
    END { for (k in r) printf "%s\t%s\n", k, r[k]; exit bad }
  ' "$wd/diff" > "$wd/ranges" 2> "$wd/awk.err" || die "a changed path needs quoting, rename it ($(head -n 1 "$wd/awk.err"))"
  while IFS="$(printf '\t')" read -r f r; do
    add_spec "$f" "$r"
  done < "$wd/ranges"
  while IFS= read -r -d '' f; do
    add_spec "$f" all
  done < <(git ls-files -o --exclude-standard -z)
fi

: > "$wd/spec.ts"
: > "$wd/spec.py"
while IFS= read -r line; do
  case "${line%%$'\t'*}" in
    *.py) printf '%s\n' "$line" >> "$wd/spec.py" ;;
    *) printf '%s\n' "$line" >> "$wd/spec.ts" ;;
  esac
done < "$specs"

adr=
if [ -d docs/adr ] || [ -d docs/decisions ]; then adr=--adr; fi
: > "$wd/out"

if [ -s "$wd/spec.ts" ]; then
  command -v node > /dev/null 2>&1 || die "node is missing, so TypeScript and JavaScript comments cannot be read. Fix: install Node.js and re-run."
  set -- --max "$MAX_COMMENT_LINES" --root "$root"
  [ -z "$adr" ] || set -- "$@" "$adr"
  [ -z "$ts_from" ] || set -- "$@" --ts-from "$ts_from"
  node "$here/check-comments.mjs" "$@" < "$wd/spec.ts" > "$wd/out.ts" 2> "$wd/err.ts"
  rc=$?
  [ "$rc" -le 1 ] || die "$(head -n 1 "$wd/err.ts")"
  if [ "$rc" = 1 ] && [ ! -s "$wd/out.ts" ]; then die "the TypeScript reader failed: $(head -n 1 "$wd/err.ts")"; fi
  cat "$wd/out.ts" >> "$wd/out"
fi
if [ -s "$wd/spec.py" ]; then
  command -v python3 > /dev/null 2>&1 || die "python3 is missing, so Python comments cannot be read. Fix: install Python 3 and re-run."
  set -- --max "$MAX_COMMENT_LINES"
  [ -z "$adr" ] || set -- "$@" "$adr"
  python3 -I "$here/check-comments.py" "$@" < "$wd/spec.py" > "$wd/out.py" 2> "$wd/err.py"
  rc=$?
  [ "$rc" -le 1 ] || die "$(head -n 1 "$wd/err.py")"
  if [ "$rc" = 1 ] && [ ! -s "$wd/out.py" ]; then die "the Python reader failed: $(head -n 1 "$wd/err.py")"; fi
  cat "$wd/out.py" >> "$wd/out"
fi

nfiles=$(wc -l < "$specs" | tr -d ' ')
[ -z "$decision" ] || printf 'check-comments: diff base: %s\n' "$decision"
total=$(wc -l < "$wd/out" | tr -d ' ')
if [ "$total" -gt 0 ]; then
  if [ "$full" = 1 ]; then
    sort -t: -k1,1 -k2,2n "$wd/out"
  else
    sort -t: -k1,1 -k2,2n "$wd/out" | head -n "$MAX_REPORT_LINES"
    [ "$total" -le "$MAX_REPORT_LINES" ] || printf '... and %d more (run with --full to list all)\n' $((total - MAX_REPORT_LINES))
  fi
  printf 'check-comments: FAIL (%d finding(s) in %d file(s) checked)\n' "$total" "$nfiles"
  exit 1
fi
printf 'check-comments: ok (%d file(s) checked)\n' "$nfiles"
