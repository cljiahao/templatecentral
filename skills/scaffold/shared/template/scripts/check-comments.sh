#!/usr/bin/env bash
# Comment gate for project source: check-comments.sh [--root DIR] [--ts-from DIR] [--full] [base-ref | --all path...]
# Judges only lines added or changed since the base ref (--all treats every line of the listed paths as new); a reindented line counts as changed. Offline.
# Judged extensions: ts tsx js jsx mjs cjs mts cts py pyi. Paths are relative to the project root, which may sit in a git subfolder; files outside it are never judged.
# Rules: a comment sits on its own line at the top of the file or directly above a statement, declaration, member or object property, and never inside a function body.
# A block is at most MAX_COMMENT_LINES lines, a line at most MAX_LINE_CHARS characters, with no parenthetical aside and no comment wholly in brackets.
# A code reference such as call foo() first is not an aside. JSDoc blocks do not count @tag lines, Python docstrings do not count blank lines or section entries such as Args.
# A tool directive is exempt only when it matches that directive's own grammar from its start, and a directive that suppresses a check must carry a reason:
# eslint-disable*, istanbul/c8/v8 ignore, NOSONAR, gitleaks:allow, pragma: no cover and noqa take " -- reason" (noqa also needs a rule code); @ts-ignore, @ts-expect-error and @ts-nocheck take the reason as text after them;
# biome-ignore takes ": reason"; type: ignore[code] and pyright: ignore[rule] take "  # reason". A reason is one line of at least three different words, each with a letter and two or more characters, that is not only TODO, at most MAX_REASON_CHARS characters, and is checked for asides.
# Formatting directives (prettier-ignore, fmt, isort, __PURE__, webpack magic comments) need no reason. Known JSDoc @tag lines (@param, @returns and the like) are capped at MAX_TAG_LINES over all the comments above one declaration, and a tag line with more than 8 words after its name, type and parameter name, like the text of @remarks, @example and @see, counts as prose.
# Comments before the first line of code total at most MAX_COMMENT_LINES lines. Only the top-of-file block is exempt: at most 3 Copyright lines (a required year, then a holder of at most 8 plain tokens: letters, digits and . , & ' - only, 100 characters) and 1 SPDX line (ids from the closed lists in check-comments.licences.txt joined by AND, OR, WITH) and a comment that quotes one text in check-comments.licences.txt from its start (at most 40 lines, exempt from the line cap); a line with no letter or digit counts.
# Symlinked source files are never followed; --all lists them in a note.
# Shebangs are never judged. Tokenizers: the project's own node_modules/typescript for TypeScript and JavaScript, python3 tokenize and ast for Python.
# Base ref: the argument, else BASE_REF, else the merge base with the default branch; in CI (CI, GITHUB_ACTIONS or TF_BUILD) the default branch is never guessed,
# so CI needs the argument or the pipeline target variable; the pipeline passes the base argument on every trigger, since a push run has no target variable and exits 2. In CI a BASE_REF from the environment is accepted only when it names the pipeline's own target branch variable; the report says which.
# In CI on a push to the target branch HEAD is the base, so there is nothing to compare: the gate says so, exits 0 and judges pull requests only.
# When a change touches no judged file the gate prints "nothing checked" and the reason instead of ok and exits 0. --all with no source file under its paths, or a missing path, exits 2.
# Exit 0 clean, 1 findings, 2 cannot run (missing runtime or package, no base, unreadable file), always with one line naming the cause.
set -uo pipefail

MAX_COMMENT_LINES=3
MAX_LINE_CHARS=120
MAX_REASON_CHARS=60
MAX_TAG_LINES=10
MAX_REPORT_LINES=30
SOURCE_EXT='ts tsx js jsx mjs cjs mts cts py pyi'

# Generated and vendored paths nobody edits by hand, relative to the project root; one place to extend.
is_skipped() {
  case "/$1" in
    */node_modules/* | */__pycache__/* | */.git/*) return 0 ;;
  esac
  case "$1" in
    dist/* | build/* | coverage/* | .next/* | .turbo/* | storybook-static/* | .venv/* | venv/* | .claude/*) return 0 ;;
    migrations/* | alembic/versions/* | src/components/ui/*) return 0 ;;
    next-env.d.ts | *.min.js | *.lock | package-lock.json | pnpm-lock.yaml) return 0 ;;
  esac
  return 1
}

die() {
  printf 'check-comments: %s\n' "$1" >&2
  exit 2
}

abs_dir() {
  if [ -d "$1" ]; then (cd "$1" && pwd); else return 1; fi
}

here=$(abs_dir "$(dirname "$0")") || die "cannot locate the script folder"
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
if [ -n "$ts_from" ]; then ts_from=$(abs_dir "$ts_from") || die "--ts-from folder does not exist"; fi

for tool in awk sort mktemp rm find; do
  command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done
wd=$(mktemp -d "${TMPDIR:-/tmp}/check-comments.XXXXXX") || die "cannot create a temp folder"
trap 'rm -rf "$wd"' EXIT
specs=$wd/specs
: > "$specs"
decision=
src_seen=0
: > "$wd/skipped"
: > "$wd/links"

# Joins the lines of a file with commas, at most 20 of them.
list_lines() {
  awk 'NR <= 20 { printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { if (NR > 20) printf ", and %d more", NR - 20 }' "$1"
}

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
  src_seen=1
  if is_skipped "$1"; then
    printf '%s\n' "$1" >> "$wd/skipped"
    return 0
  fi
  case "$1" in *$'\t'* | *$'\n'*) die "path holds a tab or newline, rename it: $1" ;; esac
  printf '%s\t%s\n' "$1" "$2" >> "$specs"
}

in_ci=0
[ -z "${GITHUB_ACTIONS:-}" ] || in_ci=1
[ -z "${TF_BUILD:-}" ] || in_ci=1
case "${CI:-}" in '' | false | False | FALSE | 0) ;; *) in_ci=1 ;; esac

if [ "$all" = 1 ]; then
  [ $# -gt 0 ] || die "--all needs at least one path"
  for p in "$@"; do
    [ -e "$p" ] || die "path does not exist: $p. Fix: check the path, it is relative to the project root."
  done
  while IFS= read -r -d '' f; do
    add_spec "${f#./}" all
  done < <(find "$@" -type f -print0 2> /dev/null)
  while IFS= read -r -d '' f; do
    if has_source_ext "$f"; then printf '%s\n' "${f#./}" >> "$wd/links"; fi
  done < <(find "$@" -type l -print0 2> /dev/null)
else
  command -v git > /dev/null 2>&1 || die "missing tool: git"
  git rev-parse --git-dir > /dev/null 2>&1 || die "not a git work tree, so there is no base to diff against. Fix: run inside the repository, or use --all"
  [ $# -le 1 ] || die "unexpected extra argument after the base ref: $2"
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
  elif [ "$in_ci" = 1 ]; then
    die "in CI the base ref is never guessed and no pull-request target variable is set (GITHUB_BASE_REF or SYSTEM_PULLREQUEST_TARGETBRANCH). Fix: pass the base ref as an argument in the pipeline step."
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
  head_sha=$(git rev-parse HEAD 2> /dev/null) || die "cannot read HEAD"
  git -c core.quotePath=false diff --relative --src-prefix=a/ --dst-prefix=b/ --no-color --no-ext-diff -U0 -M --diff-filter=AMR "$mb" -- . > "$wd/diff" 2> "$wd/diff.err" || die "git diff failed: $(head -n 1 "$wd/diff.err")"
  awk '
    /^diff --git / { hdr = 1; f = ""; next }
    hdr && /^\+\+\+ / {
      f = substr($0, 5)
      sub(/\t.*$/, "", f)
      if (f ~ /^"/) { r[f] = "!quoted"; f = ""; next }
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
    END { for (k in r) printf "%s\t%s\n", k, r[k] }
  ' "$wd/diff" > "$wd/ranges" || die "cannot read the git diff"
  while IFS="$(printf '\t')" read -r f r; do
    [ "$r" != '!quoted' ] || die "a changed path needs quoting, rename it: $f"
    add_spec "$f" "$r"
  done < "$wd/ranges"
  while IFS= read -r -d '' f; do
    add_spec "$f" all
  done < <(git ls-files -o --exclude-standard -z)
  if [ "$in_ci" = 1 ] && [ "$mb" = "$head_sha" ] && [ ! -s "$specs" ]; then
    printf 'check-comments: diff base: %s\n' "$decision"
    printf 'check-comments: nothing to compare: HEAD is the base (%s), as on a push to the target branch. The gate judges pull requests, so no comment was checked.\n' "$ref"
    printf 'check-comments: nothing checked\n'
    exit 0
  fi
fi

: > "$wd/spec.ts"
: > "$wd/spec.py"
while IFS= read -r line; do
  case "${line%%$'\t'*}" in
    *.py | *.pyi) printf '%s\n' "$line" >> "$wd/spec.py" ;;
    *) printf '%s\n' "$line" >> "$wd/spec.ts" ;;
  esac
done < "$specs"

adr=
if [ -d docs/adr ] || [ -d docs/decisions ]; then adr=--adr; fi
: > "$wd/out"

if [ -s "$wd/spec.ts" ]; then
  command -v node > /dev/null 2>&1 || die "node is missing, so TypeScript and JavaScript comments cannot be read. Fix: install Node.js and re-run."
  set -- --max "$MAX_COMMENT_LINES" --max-line "$MAX_LINE_CHARS" --max-reason "$MAX_REASON_CHARS" --max-tags "$MAX_TAG_LINES" --root "$root"
  [ -z "$adr" ] || set -- "$@" "$adr"
  [ -z "$ts_from" ] || set -- "$@" --ts-from "$ts_from"
  node "$here/check-comments.mjs" "$@" < "$wd/spec.ts" > "$wd/out.ts" 2> "$wd/err.ts"
  rc=$?
  msg=$(tail -n 1 "$wd/err.ts")
  [ "$rc" -le 1 ] || die "${msg#check-comments: }"
  if [ "$rc" = 1 ] && [ ! -s "$wd/out.ts" ]; then die "the TypeScript reader failed: ${msg#check-comments: }"; fi
  cat "$wd/out.ts" >> "$wd/out"
fi
if [ -s "$wd/spec.py" ]; then
  py=python3
  if [ -x "$root/.venv/bin/python3" ]; then py=$root/.venv/bin/python3; fi
  command -v "$py" > /dev/null 2>&1 || die "python3 is missing, so Python comments cannot be read. Fix: install Python 3 and re-run."
  set -- --max "$MAX_COMMENT_LINES" --max-line "$MAX_LINE_CHARS" --max-reason "$MAX_REASON_CHARS"
  [ -z "$adr" ] || set -- "$@" "$adr"
  "$py" -I "$here/check-comments.py" "$@" < "$wd/spec.py" > "$wd/out.py" 2> "$wd/err.py"
  rc=$?
  msg=$(tail -n 1 "$wd/err.py")
  [ "$rc" -le 1 ] || die "${msg#check-comments: }"
  if [ "$rc" = 1 ] && [ ! -s "$wd/out.py" ]; then die "the Python reader failed: ${msg#check-comments: }"; fi
  cat "$wd/out.py" >> "$wd/out"
fi

nfiles=$(wc -l < "$specs" | tr -d ' ')
[ -z "$decision" ] || printf 'check-comments: diff base: %s\n' "$decision"
if [ "$nfiles" = 0 ]; then
  if [ "$all" = 1 ] && [ "$src_seen" = 0 ]; then
    if [ -s "$wd/links" ]; then
      die "no regular source file under the given paths ($*). The only source files are symlinks ($(list_lines "$wd/links")), which the gate does not follow out of the project. Fix: name the real file."
    fi
    die "no source file under the given paths ($*). Fix: name a folder or file with one of these extensions: $SOURCE_EXT."
  fi
  if [ "$all" = 1 ]; then why="every source file under the given paths is a skipped generated or vendored path ($(list_lines "$wd/skipped"))"
  elif [ -s "$wd/skipped" ]; then why="every changed source file is on a skipped generated or vendored path ($(list_lines "$wd/skipped"))"
  elif [ "$mb" = "$head_sha" ]; then why="HEAD is the base ($ref) and the work tree has no changed source file"
  else why="no source file was added, changed or renamed since the base ($ref)"
  fi
  printf 'check-comments: nothing checked: %s. This is not a pass.\n' "$why"
  exit 0
fi
if [ -s "$wd/links" ]; then
  printf 'check-comments: note: symlinked source files were not followed and not judged: %s\n' "$(list_lines "$wd/links")"
fi
total=$(wc -l < "$wd/out" | tr -d ' ')
if [ "$total" -gt 0 ]; then
  if [ "$full" = 1 ]; then
    sort -t: -k1,1 -k2,2n "$wd/out"
  else
    sort -t: -k1,1 -k2,2n "$wd/out" | awk -v n="$MAX_REPORT_LINES" 'NR <= n'
    [ "$total" -le "$MAX_REPORT_LINES" ] || printf '... and %d more (run with --full to list all)\n' $((total - MAX_REPORT_LINES))
  fi
  printf 'check-comments: FAIL (%d finding(s) in %d file(s) checked)\n' "$total" "$nfiles"
  exit 1
fi
printf 'check-comments: ok (%d file(s) checked)\n' "$nfiles"
