#!/usr/bin/env bash
# Harness refresh: bring the seeded harness files of a project up to the current templateCentral templates without losing local edits.
# Usage: harness-refresh.sh <project-dir> [--apply [--baseline <scratch-dir>]] [--allow-dirty] [--stack <nestjs|nextjs|vite-react|fastapi>]
# Default is a dry run: one line per file, nothing written. Classes:
#   SAME     identical to the current template
#   REPLACE  not identical, and proven unmodified since it was seeded (replaced on --apply)
#   MODIFIED a local edit, or no proof either way; --apply writes <path>.templatecentral-new beside it and never touches it
#   ADD      missing (added on --apply)
#   GONE     recorded as seeded in .claude/harness.json but no longer in the templates (report only, never deleted)
# Proof of "unmodified": the file's sha256 is on pristine-hashes.txt (beside this script) for that path, the hashes of the files
# every released version shipped (made by gen-pristine-hashes.sh). The project's own records (origin_hash in .claude/harness.json,
# the copies under .claude/.harness-base/) prove nothing: regen-harness.sh and the re-baseline step rewrite them from the current
# file. A file with no hash match, or no list, is MODIFIED; the script never guesses.
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
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then die "usage: harness-refresh.sh <project-dir> [--apply [--baseline <scratch-dir>]] [--allow-dirty] [--stack <stack>]"; fi
[ -z "$BASEDIR" ] || [ "$APPLY" -eq 1 ] || die "--baseline needs --apply"
case "$STACK" in ''|nestjs|nextjs|vite-react|fastapi) ;; *) die "unknown stack '$STACK'" ;; esac

src=${BASH_SOURCE[0]:-$0}
hops=0
while [ -L "$src" ] && [ "$hops" -lt 40 ]; do
  link=$(readlink -- "$src") || break
  case "$link" in /*) src=$link ;; *) src=$(dirname -- "$src")/$link ;; esac
  hops=$((hops + 1))
done
if ! GEN=$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd -P); then die "cannot locate the script directory"; fi
SHARED=$GEN/../../scaffold/shared
MANIFEST=$SHARED/template.manifest
[ -s "$MANIFEST" ] || die "template.manifest not found at $MANIFEST"
if ! P=$(cd -P -- "$PROJ" 2>/dev/null && pwd -P); then die "cannot enter $PROJ"; fi
case "$P$GEN" in *"$NL"*) die "a path contains a newline" ;; esac
[ "$P" != / ] || die "the project directory is the filesystem root"
if [ -L "$P/.claude" ]; then die ".claude is a symlink; refusing to touch it"; fi

HJ=$P/.claude/harness.json
BASE=.claude/.harness-base
PRISTINE=$GEN/pristine-hashes.txt

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

# pristine_version <rel> <hash>: the released version that shipped this exact file at this path; fails when none did or the list is missing.
pristine_version() {
  [ -s "$PRISTINE" ] || return 1
  awk -F "$TAB" -v h="$2" -v p="$1" '$1 == h && $3 == p { print $2; found = 1; exit } END { exit !found }' "$PRISTINE"
}

# unsafe_path <rel>: the one check for every write site (targets, sidecars, base copies). Succeeds when the file or any
# parent below the project is a symlink or not a directory, the path escapes the project, or the nearest existing
# ancestor resolves outside the project root.
unsafe_path() {
  local d=$1 a r
  case "$d" in /*|..|../*|*/..|*/../*) return 0 ;; esac
  [ -L "$P/$d" ] && return 0
  while [ "${d%/*}" != "$d" ]; do
    d=${d%/*}
    if [ -L "$P/$d" ]; then return 0; fi
    if [ -e "$P/$d" ] && [ ! -d "$P/$d" ]; then return 0; fi
  done
  a=$1
  while [ "${a%/*}" != "$a" ] && [ ! -d "$P/${a%/*}" ]; do a=${a%/*}; done
  if [ "${a%/*}" != "$a" ]; then
    if ! r=$(cd -P -- "$P/${a%/*}" 2>/dev/null && pwd -P); then return 0; fi
  else
    r=$P
  fi
  case "$r/" in "$P"/*) return 1 ;; esac
  return 0
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
  if pv=$(pristine_version "$dest" "$(sha "$P/$dest")"); then add REPLACE "$dest" "$srcf" "$mode" "unmodified since seeded: identical to the file released in $pv"; continue; fi
  if [ ! -s "$PRISTINE" ]; then add MODIFIED "$dest" "$srcf" "$mode" "pristine-hashes.txt is missing; cannot prove it unmodified"; continue; fi
  add MODIFIED "$dest" "$srcf" "$mode" "not identical to any released template; treated as edited"
done <<TC_PLAN
$plan
TC_PLAN

# GONE: recorded as seeded, no longer in the templates. The files the stack guides and the kit write are not in the manifest.
printf '%s\n' "$records" | while IFS= read -r line; do
  [ -n "$line" ] || continue
  p=${line#* }
  case "$p" in AGENTS.md|CLAUDE.md|.claude/skills/*-verify/SKILL.md|.claude/skills/next-migrate/SKILL.md) continue ;; esac
  case "$managed$NL" in *"$NL$p$NL"*) continue ;; esac
  if unsafe_path "$p"; then add GONE "$p" - - "record path is outside the project or under a symlink; ignored"; continue; fi
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
if [ "$APPLY" -eq 1 ]; then MODE_TXT=apply; else MODE_TXT='dry run, nothing is changed'; fi
echo "stack $STACK, ci $CI, git tree $TREE, $MODE_TXT"
awk -F "$TAB" '{ printf "%-9s %s%s\n", $1, $2, ($5 != "" ? "  (" $5 ")" : "") }' "$RES"
echo "summary: $N_SAME same, $N_REP to replace, $N_ADD to add, $N_MOD modified (need you), $N_GONE no longer seeded (report only)"

# Plan notes: seeded files that land next to the project's own CI or git-hook manager, for the owner to review.
OWNCI=
for f in "$P"/.github/workflows/* "$P"/azure-pipelines*; do
  [ -e "$f" ] || continue
  case "$f" in "$P/.github/workflows/ci.yml") continue ;; esac
  OWNCI="$OWNCI ${f#"$P"/}"
done
OTHERHK=
[ -d "$P/.githooks" ] && OTHERHK="$OTHERHK .githooks"
[ -f "$P/.pre-commit-config.yaml" ] && OTHERHK="$OTHERHK .pre-commit-config.yaml"
[ -f "$P/package.json" ] && grep -q '"simple-git-hooks"' "$P/package.json" && OTHERHK="$OTHERHK package.json(simple-git-hooks)"
while IFS="$TAB" read -r cls path _; do
  [ "$cls" = ADD ] || continue
  case "$path" in
    .github/*|azure-pipelines*)
      [ -z "$OWNCI" ] || echo "note: $path will be added next to the project's own CI (${OWNCI# }); review it before you commit." ;;
    lefthook.yml)
      [ -z "$OTHERHK" ] || echo "note: lefthook.yml will be added but the project already uses another git-hook manager (${OTHERHK# }); two managers can fight over .git/hooks, so choose one." ;;
    sonar-project.properties)
      echo "note: sonar-project.properties is seeded as a file only; it runs no scanner. Review the project key and sources, or delete it if the project does not use it." ;;
  esac
done <"$RES"

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

# Every path the run will write is checked here, before the first write, so a refusal leaves the tree untouched.
if [ -L "$HJ" ] || { [ -e "$HJ" ] && [ ! -f "$HJ" ]; }; then die "refusing: .claude/harness.json is a symlink or not a regular file"; fi
unsafe_path .claude/harness.json && die "refusing: .claude/harness.json resolves outside the project"
if [ "$N_REP$N_ADD" != 00 ]; then
  unsafe_path "$BASE/x" && die "refusing: $BASE is a symlink or resolves outside the project"
  while IFS="$TAB" read -r cls path _; do
    case "$cls" in
      ADD|REPLACE)
        unsafe_path "$path" && die "refusing: $path is a symlink, sits under one, or resolves outside the project"
        unsafe_path "$BASE/$path" && die "refusing: the base copy of $path ($BASE/$path) is a symlink, sits under one, or resolves outside the project" ;;
    esac
  done <"$RES"
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
  if unsafe_path "${out#"$P"/}"; then return 1; fi
  mkdir -p -- "$d" || return 1
  TMPF=$(mktemp "$d/.tc-refresh.XXXXXX") || return 1
  if ! { cp -- "$srcf" "$TMPF" && chmod -- "$mode" "$TMPF" && mv -f -- "$TMPF" "$out"; }; then rm -f -- "$TMPF"; return 1; fi
  TMPF=
}

WROTE=$(mktemp "${TMPDIR:-/tmp}/hrefresh-wrote.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$RES" "$TMPF" "$WROTE"' EXIT
NEWFILES=
FAILED=0
WLIST=
NWLIST=
# still_proven <path> <note>: the REPLACE proof holds right now, re-checked just before the write.
still_proven() {
  local path=$1 note=$2
  if [ ! -f "$P/$path" ] || [ -L "$P/$path" ]; then return 1; fi
  case "$note" in
    "content identical"*) cmp -s -- "$srcf" "$P/$path" ;;
    *) pristine_version "$path" "$(sha "$P/$path")" >/dev/null ;;
  esac
}
# write_sidecar <path> <srcf>: the new version beside a modified file; never replaces anything that is already there.
# An identical sidecar is a merge still pending, not a failure; a different one is kept and reported.
write_sidecar() {
  local path=$1 srcf=$2 sc=$P/$1$NEWSUF
  if [ -L "$sc" ]; then echo "FAILED   $path$NEWSUF (it is a symlink)"; FAILED=1; NWLIST="$NWLIST $path$NEWSUF"; return; fi
  if [ -e "$sc" ] && [ ! -f "$sc" ]; then echo "FAILED   $path$NEWSUF (it exists and is not a regular file)"; FAILED=1; NWLIST="$NWLIST $path$NEWSUF"; return; fi
  if [ -f "$sc" ] && cmp -s -- "$srcf" "$sc"; then
    echo "pending  $path$NEWSUF (already written, identical to the new version; merge it into your file, then delete it)"
    NEWFILES="$NEWFILES$NL$path$NEWSUF"; return
  fi
  if [ -f "$sc" ]; then
    echo "kept     $path$NEWSUF (an older or edited sidecar differs from the new version and is not overwritten; compare it with $srcf, merge, delete it, then run the refresh again)"
    NEWFILES="$NEWFILES$NL$path$NEWSUF"; return
  fi
  if write_file "$srcf" "$sc" 644; then echo "wrote    $path$NEWSUF"; NEWFILES="$NEWFILES$NL$path$NEWSUF"; WLIST="$WLIST $path$NEWSUF"
  else echo "FAILED   $path$NEWSUF"; FAILED=1; NWLIST="$NWLIST $path$NEWSUF"; fi
}
while IFS="$TAB" read -r cls path srcf mode note; do
  case "$cls" in
    ADD|REPLACE)
      if [ "$cls" = ADD ]; then
        if [ -e "$P/$path" ] || [ -L "$P/$path" ]; then echo "FAILED   $path (it appeared after the plan)"; FAILED=1; NWLIST="$NWLIST $path"; continue; fi
      fi
      if [ "$cls" = REPLACE ] && ! still_proven "$path" "$note"; then
        echo "changed  $path since the plan; treated as MODIFIED"
        N_MOD=$((N_MOD + 1)); write_sidecar "$path" "$srcf"; continue
      fi
      if write_file "$srcf" "$P/$path" "$mode"; then echo "wrote    $path"; echo "$path" >>"$WROTE"; WLIST="$WLIST $path"
      else echo "FAILED   $path"; FAILED=1; NWLIST="$NWLIST $path"; fi ;;
    MODIFIED)
      if unsafe_path "$path" || { [ -e "$P/$path" ] && [ ! -f "$P/$path" ]; }; then echo "left     $path (no new version written: $note)"; continue; fi
      write_sidecar "$path" "$srcf" ;;
  esac
done <"$RES"

if [ "$N_MOD" -gt 0 ] && [ -f "$HJ" ]; then echo "version not bumped: $N_MOD file(s) wait for merge (templatecentral_version in .claude/harness.json stays as it is)"; fi

# Refresh the records of the files written, so verify-harness.sh and the next run see them as seeded.
if [ -s "$WROTE" ] && [ -f "$HJ" ]; then
  VER=
  pj=$GEN/../../../.claude-plugin/plugin.json
  [ -f "$pj" ] && VER=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$pj" | head -n 1)
  [ "$N_MOD" -eq 0 ] || VER=
  while IFS= read -r p; do
    if ! write_file "$P/$p" "$P/$BASE/$p" 644; then echo "FAILED   $BASE/$p"; FAILED=1; NWLIST="$NWLIST $BASE/$p"; fi
  done <"$WROTE"
  if have python3; then
    (cd "$P" && python3 - "$WROTE" "$VER" <<'PY'
import hashlib, json, os, sys
f = ".claude/harness.json"
j = json.load(open(f))
for p in open(sys.argv[1]).read().split("\n"):
    if p:
        j["seeded_files"][p] = {"origin_hash": hashlib.sha256(open(p, "rb").read()).hexdigest(), "path": p}
if sys.argv[2]:
    j["templatecentral_version"] = sys.argv[2]
tmp = f + ".tc-refresh.%d" % os.getpid()
try:
    with open(tmp, "w") as o:
        o.write(json.dumps(j, indent=2) + "\n")
    os.chmod(tmp, os.stat(f).st_mode & 0o777)
    os.replace(tmp, f)
except BaseException:
    if os.path.exists(tmp):
        os.remove(tmp)
    raise
PY
    ) || { echo "could not update .claude/harness.json"; FAILED=1; NWLIST="$NWLIST .claude/harness.json"; }
  elif have node; then
    (cd "$P" && node - "$WROTE" "$VER" <<'JS'
const fs = require("fs"), cr = require("crypto");
const f = ".claude/harness.json", j = JSON.parse(fs.readFileSync(f, "utf8"));
for (const p of fs.readFileSync(process.argv[2], "utf8").split("\n"))
  if (p) j.seeded_files[p] = { origin_hash: cr.createHash("sha256").update(fs.readFileSync(p)).digest("hex"), path: p };
if (process.argv[3]) j.templatecentral_version = process.argv[3];
const tmp = f + ".tc-refresh." + process.pid;
try {
  fs.writeFileSync(tmp, JSON.stringify(j, null, 2) + "\n");
  fs.chmodSync(tmp, fs.statSync(f).mode & 0o777);
  fs.renameSync(tmp, f);
} catch (e) {
  try { fs.unlinkSync(tmp); } catch (_) { /* nothing to remove */ }
  throw e;
}
JS
    ) || { echo "could not update .claude/harness.json"; FAILED=1; NWLIST="$NWLIST .claude/harness.json"; }
  else
    echo "neither python3 nor node found: .claude/harness.json not updated; verify-harness.sh will flag the written files."
    FAILED=1; NWLIST="$NWLIST .claude/harness.json"
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
  echo "The refresh does not edit AGENTS.md: its line-1 marker and the version line are yours; see harness-refresh.md."
fi
if awk -F "$TAB" '$1 == "MODIFIED" && $2 == ".claude/settings.json" { f = 1 } END { exit !f }' "$RES" && [ -s "$WROTE" ]; then
  GATEW=$(grep -E '^\.claude/(hooks/|verify-harness\.sh$)' "$WROTE" | tr '\n' ' ')
  if [ -n "$GATEW" ]; then
    echo "WAITING FOR MERGE: .claude/settings.json was kept as it is. The refresh wrote ${GATEW% } and the new settings.json is in .claude/settings.json$NEWSUF."
    echo "Until you merge it, .claude/verify-harness.sh and the live check above fail (for example DENY RULE MISSING: Bash(eval *)) and the new hooks are not registered. That is expected, not a broken refresh."
    echo "Next: merge .claude/settings.json$NEWSUF into .claude/settings.json structurally (hooks and permissions), delete the $NEWSUF file, then run: bash .claude/verify-harness.sh && bash \"$GEN/harness-live.sh\" ."
  fi
fi
[ "$N_GONE" -eq 0 ] || echo "Report only: $N_GONE recorded file(s) are no longer seeded; nothing was deleted."
if [ "$FAILED" -eq 0 ]; then echo "Review with git diff, then commit the refresh as one change."; fi
if [ "$FAILED" -ne 0 ]; then
  echo "PARTIAL: the tree is partly applied. written:${WLIST:- none}. not written:${NWLIST:- none}."
fi
if [ "$N_MOD" -gt 0 ] && [ "$FAILED" -eq 0 ]; then echo "Exit 1: $N_MOD file(s) wait for a merge; the refresh itself did not fail."; fi
if [ "$N_MOD" -gt 0 ] || [ "$FAILED" -ne 0 ] || [ "$LIVE" -ne 0 ] || [ "$CMP" -ne 0 ]; then exit 1; fi
exit 0
