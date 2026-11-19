#!/usr/bin/env bash
# Harness refresh: bring the seeded harness files of a project up to the current templateCentral templates without losing local edits.
# Usage: harness-refresh.sh <project-dir> [--apply [--baseline <scratch-dir>]] [--allow-dirty] [--stack <nestjs|nextjs|vite-react|fastapi>]
# Default is a dry run: one line per file, nothing written. Classes:
#   SAME     identical to the current template
#   REPLACE  not identical, and proven unmodified since it was seeded (replaced on --apply)
#   MODIFIED a local edit, or no proof either way; --apply writes <path>.templatecentral-new beside it and never touches it
#   ADD      missing (added on --apply)
#   GONE     recorded as seeded in .claude/harness.json but no longer in the templates (report only, never deleted)
# Proof of "unmodified": the file's hash equals its origin_hash in .claude/harness.json and the file is byte-equal to its
# copy under .claude/.harness-base/. Without both records the file counts as MODIFIED; the script never guesses.
# A file whose template carries a __TC_<NAME>__ placeholder is never replaced: it is SAME or MODIFIED.
# --apply refuses a dirty git tree (or no git) unless --allow-dirty, so the change is one reviewable diff. It also refreshes the
# records of the files it wrote, runs harness-live.sh, and with --baseline runs quality-baseline.sh before and after and compares.
# --baseline runs the project's lint, typecheck and tests and installs pinned scratch tools (network): use it only after the user's yes.
# Exit 0 when nothing needs the user, 1 when a file is MODIFIED or a check failed, 2 on a usage error or refusal. No secret or .env file is read.
# Needs bash 3.2+, cmp, awk; git for the dirty-tree check; python3 or node to update .claude/harness.json.
set -u

NEWSUF=.templatecentral-new
NL='
'
TAB=$(printf '\t')
die() { echo "harness-refresh: $1" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
sha() { if have shasum; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }

PROJ=
APPLY=0
DIRTY_OK=0
STACK=
BASEDIR=
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --allow-dirty) DIRTY_OK=1 ;;
    --stack) shift; [ $# -gt 0 ] || die "--stack needs a value"; STACK=$1 ;;
    --baseline) shift; [ $# -gt 0 ] || die "--baseline needs a directory"; BASEDIR=$1 ;;
    -*) die "unknown option $1" ;;
    *) [ -z "$PROJ" ] || die "one project directory only"; PROJ=$1 ;;
  esac
  shift
done
[ -n "$PROJ" ] && [ -d "$PROJ" ] || die "usage: harness-refresh.sh <project-dir> [--apply [--baseline <scratch-dir>]] [--allow-dirty] [--stack <stack>]"
[ -z "$BASEDIR" ] || [ "$APPLY" -eq 1 ] || die "--baseline needs --apply"
case "$STACK" in ''|nestjs|nextjs|vite-react|fastapi) ;; *) die "unknown stack '$STACK'" ;; esac

src=${BASH_SOURCE[0]:-$0}
hops=0
while [ -L "$src" ] && [ "$hops" -lt 40 ]; do
  link=$(readlink -- "$src") || break
  case "$link" in /*) src=$link ;; *) src=$(dirname -- "$src")/$link ;; esac
  hops=$((hops + 1))
done
GEN=$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd -P) || die "cannot locate the script directory"
SHARED=$GEN/../../scaffold/shared
MANIFEST=$SHARED/template.manifest
[ -s "$MANIFEST" ] || die "template.manifest not found at $MANIFEST"
P=$(cd -P -- "$PROJ" 2>/dev/null && pwd -P) || die "cannot enter $PROJ"
case "$P$GEN" in *"$NL"*) die "a path contains a newline" ;; esac
[ "$P" != / ] || die "the project directory is the filesystem root"
if [ -L "$P/.claude" ]; then die ".claude is a symlink; refusing to touch it"; fi

HJ=$P/.claude/harness.json
BASE=.claude/.harness-base

# Stack from the signals in AGENTS.md; both a frontend and a backend signal means a monorepo root.
detect_stack() {
  local found="" f
  for f in "$P"/next.config.*; do [ -e "$f" ] && { found="$found nextjs"; break; }; done
  if [ -z "$found" ]; then
    for f in "$P"/vite.config.*; do [ -e "$f" ] && { found="$found vite-react"; break; }; done
  fi
  if [ -f "$P/nest-cli.json" ] || { [ -f "$P/package.json" ] && grep -q '"@nestjs/core"' "$P/package.json"; }; then found="$found nestjs"; fi
  if [ -f "$P/requirements.txt" ] && grep -qi 'fastapi' "$P/requirements.txt"; then found="$found fastapi"; fi
  echo "${found# }"
}
if [ -z "$STACK" ]; then
  det=$(detect_stack)
  case "$det" in
    nextjs|vite-react|nestjs|fastapi) STACK=$det ;;
    '') die "no stack detected; run in a project directory or pass --stack" ;;
    *) die "several stacks detected ($det); run in the project subdirectory or pass --stack" ;;
  esac
fi
case "$STACK" in fastapi) V=py ;; *) V=ts ;; esac

if [ -f "$HJ" ]; then
  rec_stack=$(tr -d '\n' <"$HJ" | sed -n 's/.*"stack"[[:space:]]*:[[:space:]]*"\([a-z-]*\)".*/\1/p')
  if [ -n "$rec_stack" ] && [ "$rec_stack" != "$STACK" ]; then die "detected stack $STACK but .claude/harness.json records $rec_stack; pass --stack to choose"; fi
fi

# CI host from what the project already has; none means CI files are not managed.
CI=none
[ -e "$P/.github/workflows/ci.yml" ] && CI=github
if [ -e "$P/azure-pipelines.yml" ] || [ -d "$P/azure-pipelines" ]; then
  if [ "$CI" = github ]; then CI=github+azure; else CI=azure; fi
fi
SEL="template template-$V template-settings-$V template-late"
case "$CI" in
  github) SEL="$SEL template-ci/github-$V" ;;
  azure) SEL="$SEL template-ci/azure template-ci/azure-$V" ;;
  github+azure) SEL="$SEL template-ci/github-$V template-ci/azure template-ci/azure-$V" ;;
esac

plan=$(awk -v sel="$SEL" '
  BEGIN { n = split(sel, s, " ") }
  /^#/ || NF == 0 { next }
  { for (i = 1; i <= n; i++) if (index($1, s[i] "/") == 1) { print s[i] "\t" substr($1, length(s[i]) + 2) "\t" $2 "\t" $3; next } }
' "$MANIFEST" | LC_ALL=C sort -t "$TAB" -k2,2)
[ -n "$plan" ] || die "no manifest entries selected for $STACK"

records=
if [ -f "$HJ" ]; then
  records=$(tr -d '\n' <"$HJ" | grep -o '"origin_hash"[[:space:]]*:[[:space:]]*"[0-9a-f]*"[[:space:]]*,[[:space:]]*"path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"origin_hash"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1 \2/')
fi
origin_of() { printf '%s\n' "$records" | awk -v p="$1" '{ h = $1; $1 = ""; sub(/^ /, ""); if ($0 == p) { print h; exit } }'; }

# unsafe_path <rel>: succeeds when the file or any parent below the project is a symlink or not a directory.
unsafe_path() {
  local d=$1
  [ -L "$P/$d" ] && return 0
  while [ "${d%/*}" != "$d" ]; do
    d=${d%/*}
    if [ -L "$P/$d" ]; then return 0; fi
    if [ -e "$P/$d" ] && [ ! -d "$P/$d" ]; then return 0; fi
  done
  return 1
}

# masked_same <template> <file>: equal once the template's placeholder lines are dropped from both.
masked_same() {
  local ls
  ls=$(grep -n '__TC_' "$1" | cut -d: -f1 | tr '\n' ' ')
  [ "$(wc -l <"$1")" -eq "$(wc -l <"$2")" ] || return 1
  cmp -s <(awk -v ls="$ls" 'BEGIN { n = split(ls, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 } !(NR in d)' "$1") \
         <(awk -v ls="$ls" 'BEGIN { n = split(ls, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 } !(NR in d)' "$2")
}

mode_of() { if stat -f %Lp -- "$1" >/dev/null 2>&1; then stat -f %Lp -- "$1"; else stat -c %a -- "$1"; fi; }

# Result lines: class, path, source file, mode, note.
RES=$(mktemp "${TMPDIR:-/tmp}/hrefresh.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$RES"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
add() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >>"$RES"; }

managed=
while IFS="$TAB" read -r tree rel mode ph; do
  dest=${rel%.tmpl}
  srcf=$SHARED/$tree/$rel
  managed="$managed$NL$dest"
  [ -r "$srcf" ] || die "template file $srcf is unreadable"
  if unsafe_path "$dest"; then add MODIFIED "$dest" "$srcf" "$mode" "path is or sits under a symlink; left alone"; continue; fi
  if [ ! -e "$P/$dest" ]; then
    if [ "$dest" = .claude/ci-gates.sh ] && [ "$CI" = none ]; then continue; fi
    add ADD "$dest" "$srcf" "$mode" ""; continue
  fi
  if [ ! -f "$P/$dest" ]; then add MODIFIED "$dest" "$srcf" "$mode" "not a regular file"; continue; fi
  if [ "$ph" != "-" ]; then
    if masked_same "$srcf" "$P/$dest"; then add SAME "$dest" "$srcf" "$mode" "placeholder file"
    else add MODIFIED "$dest" "$srcf" "$mode" "placeholder file; project text differs"; fi
    continue
  fi
  if cmp -s -- "$srcf" "$P/$dest"; then
    if [ "$(mode_of "$P/$dest")" = "$mode" ]; then add SAME "$dest" "$srcf" "$mode" ""
    else add REPLACE "$dest" "$srcf" "$mode" "content identical; mode set to $mode"; fi
    continue
  fi
  oh=$(origin_of "$dest")
  if [ -z "$oh" ]; then add MODIFIED "$dest" "$srcf" "$mode" "no origin hash recorded; cannot prove it unmodified"; continue; fi
  if [ "$(sha "$P/$dest")" != "$oh" ]; then add MODIFIED "$dest" "$srcf" "$mode" "differs from its recorded origin hash"; continue; fi
  if [ ! -f "$P/$BASE/$dest" ]; then add MODIFIED "$dest" "$srcf" "$mode" "no seeded copy under $BASE; cannot prove it unmodified"; continue; fi
  if ! cmp -s -- "$P/$BASE/$dest" "$P/$dest"; then add MODIFIED "$dest" "$srcf" "$mode" "differs from its seeded copy under $BASE"; continue; fi
  add REPLACE "$dest" "$srcf" "$mode" "unmodified since seeded"
done <<TC_PLAN
$plan
TC_PLAN

# GONE: recorded as seeded, no longer in the templates. The files the stack guides and the kit write are not in the manifest.
printf '%s\n' "$records" | while IFS= read -r line; do
  [ -n "$line" ] || continue
  p=${line#* }
  case "$p" in AGENTS.md|CLAUDE.md|.claude/skills/*-verify/SKILL.md|.claude/skills/next-migrate/SKILL.md) continue ;; esac
  case "$managed$NL" in *"$NL$p$NL"*) continue ;; esac
  if [ -e "$P/$p" ]; then add GONE "$p" - - "no longer seeded; still on disk, left alone"; else add GONE "$p" - - "no longer seeded; already absent"; fi
done

count() { awk -F "$TAB" -v c="$1" '$1 == c { n++ } END { print n + 0 }' "$RES"; }
N_SAME=$(count SAME); N_REP=$(count REPLACE); N_MOD=$(count MODIFIED); N_ADD=$(count ADD); N_GONE=$(count GONE)

TREE=clean
if have git && git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git -C "$P" status --porcelain -- . 2>/dev/null)" ] || TREE=dirty
else
  TREE="no git"
fi

echo "harness refresh: $P"
echo "stack $STACK, ci $CI, git tree $TREE, $([ "$APPLY" -eq 1 ] && echo apply || echo 'dry run, nothing is changed')"
awk -F "$TAB" '{ printf "%-9s %s%s\n", $1, $2, ($5 != "" ? "  (" $5 ")" : "") }' "$RES"
echo "summary: $N_SAME same, $N_REP to replace, $N_ADD to add, $N_MOD modified (need you), $N_GONE no longer seeded (report only)"

if [ "$APPLY" -eq 0 ]; then
  [ "$TREE" = clean ] || echo "note: the tree is $TREE; --apply refuses it unless --allow-dirty is given."
  if [ "$N_MOD" -gt 0 ]; then
    echo "NEEDS YOU: --apply writes each MODIFIED file's new version beside it as <path>$NEWSUF; merge by hand."
    exit 1
  fi
  exit 0
fi

if [ "$TREE" != clean ] && [ "$DIRTY_OK" -eq 0 ]; then
  echo "refusing to apply: git tree is $TREE. Commit or stash first so the refresh is one reviewable diff, or pass --allow-dirty." >&2
  exit 2
fi
if [ -n "$BASEDIR" ]; then
  [ -d "$BASEDIR" ] || die "--baseline directory $BASEDIR does not exist"
  BD=$(cd -P -- "$BASEDIR" && pwd -P)
  case "$BD/" in "$P"/*) die "--baseline directory must be outside the project" ;; esac
  QB=$GEN/quality-baseline.sh
  echo "baseline before the refresh (runs project code, uses the network for scratch tools)"
  bash "$QB" "$P" --full --label before --keep-coverage "$BD/cov-before" >"$BD/before.md" || die "baseline before failed"
  cat "$BD/before.md"
  if tail -n 1 "$BD/before.md" | grep -q 'CHANGED'; then die "the baseline run changed project files; stop and look at the last row of $BD/before.md"; fi
fi

TMPF=
trap 'rm -f "$RES" "$TMPF"' EXIT
write_file() {
  local srcf=$1 out=$2 mode=$3 d
  d=$(dirname -- "$out")
  mkdir -p -- "$d" || return 1
  TMPF=$(mktemp "$d/.tc-refresh.XXXXXX") || return 1
  if ! { cp -- "$srcf" "$TMPF" && chmod -- "$mode" "$TMPF" && mv -f -- "$TMPF" "$out"; }; then rm -f -- "$TMPF"; return 1; fi
  TMPF=
}

WROTE=$(mktemp "${TMPDIR:-/tmp}/hrefresh-wrote.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$RES" "$TMPF" "$WROTE"' EXIT
NEWFILES=
FAILED=0
while IFS="$TAB" read -r cls path srcf mode note; do
  case "$cls" in
    ADD|REPLACE)
      if [ "$cls" = ADD ] && { [ -e "$P/$path" ] || [ -L "$P/$path" ]; }; then echo "skipped $path: it appeared after the plan"; FAILED=1; continue; fi
      if write_file "$srcf" "$P/$path" "$mode"; then echo "wrote    $path"; echo "$path" >>"$WROTE"
      else echo "FAILED   $path"; FAILED=1; fi ;;
    MODIFIED)
      if unsafe_path "$path" || { [ -e "$P/$path" ] && [ ! -f "$P/$path" ]; }; then echo "left     $path (no new version written: $note)"; continue; fi
      if [ -e "$P/$path$NEWSUF" ] || [ -L "$P/$path$NEWSUF" ]; then
        if [ -L "$P/$path$NEWSUF" ]; then echo "left     $path (its $NEWSUF is a symlink)"; FAILED=1; continue; fi
      fi
      if write_file "$srcf" "$P/$path$NEWSUF" 644; then echo "wrote    $path$NEWSUF"; NEWFILES="$NEWFILES$NL$path$NEWSUF"
      else echo "FAILED   $path$NEWSUF"; FAILED=1; fi ;;
  esac
done <"$RES"

# Refresh the records of the files written, so verify-harness.sh and the next run see them as seeded.
if [ -s "$WROTE" ] && [ -f "$HJ" ]; then
  VER=
  pj=$GEN/../../../.claude-plugin/plugin.json
  [ -f "$pj" ] && VER=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$pj" | head -n 1)
  [ "$N_MOD" -eq 0 ] || VER=
  while IFS= read -r p; do
    mkdir -p -- "$P/$BASE/$(dirname -- "$p")" && cp -- "$P/$p" "$P/$BASE/$p"
  done <"$WROTE"
  if have python3; then
    (cd "$P" && python3 - "$WROTE" "$VER" <<'PY'
import hashlib, json, sys
f = ".claude/harness.json"
j = json.load(open(f))
for p in open(sys.argv[1]).read().split("\n"):
    if p:
        j["seeded_files"][p] = {"origin_hash": hashlib.sha256(open(p, "rb").read()).hexdigest(), "path": p}
if sys.argv[2]:
    j["templatecentral_version"] = sys.argv[2]
open(f, "w").write(json.dumps(j, indent=2) + "\n")
PY
    ) || { echo "could not update .claude/harness.json"; FAILED=1; }
  elif have node; then
    (cd "$P" && node - "$WROTE" "$VER" <<'JS'
const fs = require("fs"), cr = require("crypto");
const f = ".claude/harness.json", j = JSON.parse(fs.readFileSync(f, "utf8"));
for (const p of fs.readFileSync(process.argv[2], "utf8").split("\n"))
  if (p) j.seeded_files[p] = { origin_hash: cr.createHash("sha256").update(fs.readFileSync(p)).digest("hex"), path: p };
if (process.argv[3]) j.templatecentral_version = process.argv[3];
fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n");
JS
    ) || { echo "could not update .claude/harness.json"; FAILED=1; }
  else
    echo "neither python3 nor node found: .claude/harness.json not updated; verify-harness.sh will flag the written files."
    FAILED=1
  fi
elif [ -s "$WROTE" ]; then
  echo "no .claude/harness.json: files written, no records updated (kit Step E writes it)."
fi

echo "live check:"
bash "$GEN/harness-live.sh" "$P"
LIVE=$?

CMP=0
if [ -n "$BASEDIR" ]; then
  bash "$QB" "$P" --full --label after >"$BD/after.md" || die "baseline after failed"
  echo "baseline compare (before vs after the refresh):"
  bash "$QB" --compare "$BD/before.md" "$BD/after.md"
  CMP=$?
fi

echo "---"
if [ -s "$WROTE" ] && grep -q '\.md$' "$WROTE"; then echo "Run the project's formatter over the written Markdown files: the templates are unformatted."; fi
if [ -n "$NEWFILES" ]; then
  echo "NEEDS YOU: merge each new version into your file, then delete the $NEWSUF file:${NEWFILES}"
fi
[ "$N_GONE" -eq 0 ] || echo "Report only: $N_GONE recorded file(s) are no longer seeded; nothing was deleted."
echo "Review with git diff, then commit the refresh as one change."
if [ "$N_MOD" -gt 0 ] || [ "$FAILED" -ne 0 ] || [ "$LIVE" -ne 0 ] || [ "$CMP" -ne 0 ]; then exit 1; fi
exit 0
