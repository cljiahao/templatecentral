#!/usr/bin/env bash
# tc-copy.sh — the one script that copies templateCentral's template trees into a project.
#
# Usage: TC_STACK=<stack> TC_PART=<part> [TC_CI=<host>] bash tc-copy.sh <target>
#        TC_PART=leaf TC_LEAF=<add|migrate>/<path/to/leaf-stem> [TC_TREE=<tree>] bash tc-copy.sh <target>
#   TC_STACK  nestjs | nextjs | vite-react | fastapi (not used by TC_PART=leaf)
#   TC_PART   base | settings | ci | late | stack | agents | tail | manifest | leaf   (see skills/scaffold/shared/harness-kit.md, Step 0)
#             manifest writes .claude/harness.json (kit Step E); TC_ADO_WIKI / TC_RICH_README (true|false,
#             default false) set its adoWiki / richReadme fields
#   TC_CI     github | azure | none; required for TC_PART=ci, empty for every other part
#   TC_LEAF   for leaf: the leaf's stem under skills/, e.g. add/auth/nestjs; its template trees and
#             template.manifest sit in skills/<TC_LEAF>/
#   TC_TREE   for leaf: copy only this tree (template or template-<suffix>); empty copies every tree
#   target    the project root; it must be an existing directory
# The inputs carry a TC_ prefix because CI, STACK and PART are common in a caller's environment (CI=true
# is exported by most CI hosts and agent sandboxes).
#
# It finds the trees and manifests from its own location (following a symlink to it), so it works from
# the plugin directory and from the dist layout that scripts/build-agents-dist.sh builds. A refusal
# writes nothing and ends with a STOP: line.
[ -n "${BASH_VERSION-}" ] || { echo "tc-copy.sh: run with bash" >&2; exit 1; }
STACK=${TC_STACK-}
CI=${TC_CI-}
PART=${TC_PART-}
LEAF=${TC_LEAF-}
TREE=${TC_TREE-}
WHAT="scaffold"
if [ "$PART" = tail ]; then WHAT="append the tail"; fi
NL='
'
TAB=$(printf '\t')
stop() { printf 'Refusing to %s: %s\nSTOP: do not rm or overwrite anything; report this to the user.\n' "$WHAT" "$1"; exit 1; }
src=${BASH_SOURCE[0]:-$0}
hops=0
while [ -L "$src" ] && [ "$hops" -lt 40 ]; do
  link=$(readlink -- "$src") || break
  case "$link" in
    /*) src=$link ;;
    *) src=$(dirname -- "$src")/$link ;;
  esac
  hops=$((hops + 1))
done
SH=$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd) || SH=
[ $# -eq 1 ] || stop "want exactly one argument, the target directory (got $#)"
TGT=$1
case "$TGT" in ''|*'<tar'"get>"*) stop "the target path is empty or was not substituted" ;; esac
case "$SH$TGT" in *"$NL"*) stop "a path ends in or contains a newline" ;; esac
case "$TGT" in /*) ;; *) TGT=./$TGT ;; esac
if [ -z "$SH" ] || [ ! -d "$SH" ]; then stop "cannot locate the directory this script lives in"; fi
case "$SH" in
  */shared) ;;
  *) stop "the script must live in a directory named shared" ;;
esac
SK=$SH
[ -d "$TGT" ] || stop "$TGT is not an existing directory"
real=$(cd -- "$TGT" 2>/dev/null && pwd -P) || real=
if [ "$real" = / ]; then stop "$TGT is the filesystem root, not a project directory"; fi
if [ -n "${HOME-}" ] && [ "$real" = "$(cd -- "$HOME" 2>/dev/null && pwd -P)" ]; then stop "$TGT is your home directory, not a project directory"; fi
V=
if [ "$PART" != leaf ]; then
  case "$STACK" in
    nestjs|nextjs|vite-react) V=ts ;;
    fastapi) V=py ;;
    *) stop "unknown STACK '$STACK' (want nestjs, nextjs, vite-react or fastapi)" ;;
  esac
fi
case "$PART" in
  leaf)
    [ -z "$CI" ] || stop "TC_CI must stay empty for TC_PART=leaf"
    case "$SH" in
      */scaffold/shared) SKILLS=${SH%/scaffold/shared} ;;
      *) stop "TC_PART=leaf needs the script in skills/scaffold/shared" ;;
    esac
    case "$LEAF" in
      add/* | migrate/*) ;;
      *) stop "unknown TC_LEAF '$LEAF' (want add/... or migrate/..., the leaf's stem under skills/)" ;;
    esac
    case "/$LEAF/" in
      *//* | */./* | */../*) stop "TC_LEAF '$LEAF' holds an empty, . or .. path segment" ;;
    esac
    case "$LEAF" in
      *[!A-Za-z0-9._/-]*) stop "TC_LEAF '$LEAF' holds a character outside A-Za-z0-9._/-" ;;
    esac
    SK=$SKILLS/$LEAF
    [ -d "$SK" ] || stop "$SK is not a directory: no leaf '$LEAF'"
    if [ -L "$SK" ]; then stop "$SK is a symlink"; fi
    if [ -n "$TREE" ]; then
      case "$TREE" in
        template | template-[a-z0-9]*) ;;
        *) stop "unknown TC_TREE '$TREE' (want template or template-<suffix>)" ;;
      esac
      case "$TREE" in
        *[!a-z0-9-]*) stop "unknown TC_TREE '$TREE' (want template or template-<suffix>)" ;;
      esac
      SEL=$TREE
    else
      SEL=$(cd "$SK" && find . -maxdepth 1 -type d \( -name template -o -name 'template-*' \) | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')
      SEL=${SEL% }
      [ -n "$SEL" ] || stop "no template tree under $SK"
    fi ;;
  base)
    [ -z "$CI" ] || stop "TC_CI must stay empty in Step 0"
    SEL="template template-$V" ;;
  settings | late | tail)
    [ -z "$CI" ] || stop "TC_CI must stay empty for TC_PART=$PART"
    [ -f "$TGT/AGENTS.md" ] || stop "$TGT/AGENTS.md does not exist yet: TC_PART=$PART runs after the stack's AGENTS.md step and its verification gate"
    if [ "$PART" = settings ]; then SEL="template-settings-$V"; else SEL="template-late"; fi ;;
  ci)
    case "$CI" in
      github) SEL="template-ci/github-$V" ;;
      azure) SEL="template-ci/azure template-ci/azure-$V" ;;
      none) SEL= ;;
      *) stop "unknown CI '$CI' (want github, azure or none)" ;;
    esac ;;
  manifest)
    [ -z "$CI" ] || stop "TC_CI must stay empty for TC_PART=manifest"
    SEL= ;;
  stack | agents)
    [ -z "$CI" ] || stop "TC_CI must stay empty for TC_PART=$PART"
    SK=${SH%/shared}/$STACK
    if [ "$PART" = stack ]; then SEL="template"; else SEL="template-agents"; fi ;;
  *) stop "unknown PART '$PART'" ;;
esac
if [ "$PART" = tail ]; then
  case "$STACK" in
    fastapi) TC='python -m pyright src/' ;;
    *) TC='pnpm exec tsc --noEmit --incremental' ;;
  esac
  out=$(TC="$TC" awk 'BEGIN { m = "see delta table for stack command" } { i = index($0, m); if (i) $0 = substr($0, 1, i - 1) ENVIRON["TC"] substr($0, i + length(m)); print }' "$SH/template-tail/AGENTS-tail.md") || stop "cannot read the tail file"
  [ -n "$out" ] || stop "the tail file is empty"
  # The tail sits between fixed markers, so a re-run replaces it instead of appending a second copy.
  BEGIN_M='<!-- BEGIN:templatecentral-tail (managed by templateCentral Step G; edits inside are overwritten; put repo rules outside) -->'
  END_M='<!-- END:templatecentral-tail -->'
  AG="$TGT/AGENTS.md"
  wrapped=$(printf '%s\n%s\n%s\n' "$BEGIN_M" "$out" "$END_M")
  # One pass: marker counts and first line numbers (whole-line matches only, so prose that mentions a marker is
  # ignored), whether a `## AI Harness` heading sits outside a code fence (the fence toggle is a heuristic: a line opening with ``` or ~~~), and the total line count.
  scan=$(awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence }
    !fence && /^<!-- BEGIN:templatecentral-tail \(managed by templateCentral Step G; edits inside are overwritten; put repo rules outside\) -->[[:space:]]*$/ { nb++; if (!bl) bl = NR }
    !fence && /^<!-- END:templatecentral-tail -->[[:space:]]*$/ { ne++; if (!el) el = NR }
    !fence && /^## AI Harness[[:space:]]*$/ { hh = 1 }
    END { print nb + 0, ne + 0, bl + 0, el + 0, hh + 0, NR }' "$AG") || stop "cannot read $AG"
  # shellcheck disable=SC2086
  set -- $scan
  nb=$1 ne=$2 bl=$3 el=$4 hh=$5 tot=$6
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then
    if [ "$hh" -eq 1 ]; then
      stop "$AG has an '## AI Harness' heading but no templatecentral-tail markers: wrap the existing generic tail in the BEGIN:templatecentral-tail and END:templatecentral-tail lines by hand, then re-run"
    fi
    printf '\n%s\n' "$wrapped" >> "$AG" || stop "appending to $AG failed"
    exit 0
  fi
  [ "$nb" -eq 1 ] && [ "$ne" -eq 1 ] || stop "$AG has malformed templatecentral-tail markers ($nb BEGIN, $ne END): want exactly one of each"
  [ "$bl" -lt "$el" ] || stop "$AG has the END:templatecentral-tail marker before BEGIN"
  nonl=0
  [ -z "$(tail -c 1 "$AG")" ] || nonl=1
  # A symlinked AGENTS.md (say to CLAUDE.md) is followed, so the link survives and the target is replaced.
  real=$AG
  hops=0
  while [ -L "$real" ] && [ "$hops" -lt 40 ]; do
    link=$(readlink -- "$real") || break
    case "$link" in
      /*) real=$link ;;
      *) real=$(dirname -- "$real")/$link ;;
    esac
    hops=$((hops + 1))
  done
  [ ! -L "$real" ] || stop "$AG is a symlink loop"
  rdir=$(dirname -- "$real")
  # The temp files sit beside the real file so the final mv stays on one filesystem; cp -p keeps the file mode.
  tmpn=
  tmpo=
  trap 'rm -f "$tmpn" "$tmpo"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  tmpn=$(mktemp "$rdir/.AGENTS.tail.XXXXXX") || stop "cannot create a temp file in $rdir"
  tmpo=$(mktemp "$rdir/.AGENTS.new.XXXXXX") || stop "cannot create a temp file in $rdir"
  printf '%s\n' "$wrapped" > "$tmpn" || stop "cannot write the temp file in $rdir"
  if cp -p "$real" "$tmpo" && awk -v b="$bl" -v e="$el" -v nf="$tmpn" -v nonl="$nonl" -v tot="$tot" '
      NR == b { while ((getline l < nf) > 0) print l; close(nf) }
      NR < b || NR > e { if (nonl && NR == tot) printf "%s", $0; else print }' "$AG" > "$tmpo" && mv "$tmpo" "$real"; then
    rm -f "$tmpn"
    trap - EXIT INT TERM
    exit 0
  fi
  stop "replacing the tail in $AG failed; $AG is unchanged"
fi
if [ "$PART" = manifest ]; then
  # Writes .claude/harness.json: one seeded_files entry per seeded file present in the project, with its
  # sha256 as origin_hash, and the plugin version read from .claude-plugin/plugin.json.
  WHAT="write .claude/harness.json"
  mf=.claude/harness.json
  [ -f "$TGT/AGENTS.md" ] || stop "$TGT/AGENTS.md does not exist yet: run this at kit Step E"
  if [ ! -d "$TGT/.claude" ] || [ -L "$TGT/.claude" ]; then stop "$TGT/.claude is missing or a symlink: run kit Steps 0 through D first"; fi
  if [ -e "$TGT/$mf" ] || [ -L "$TGT/$mf" ]; then stop "$TGT/$mf already exists"; fi
  pj=${SH%/skills/scaffold/shared}/.claude-plugin/plugin.json
  [ -f "$pj" ] || pj=${SH%/scaffold/shared}/../.claude-plugin/plugin.json
  [ -f "$pj" ] || stop "cannot find .claude-plugin/plugin.json next to the plugin's skills directory"
  ver=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$pj" | head -n 1)
  [ -n "$ver" ] || stop "no version in $pj"
  case "$STACK" in
    fastapi) skills=api-verify ;;
    nestjs) skills=nest-verify ;;
    nextjs) skills="next-verify next-migrate" ;;
    vite-react) skills=vite-verify ;;
  esac
  for s in $skills; do [ -f "$TGT/.claude/skills/$s/SKILL.md" ] || stop "$TGT/.claude/skills/$s/SKILL.md is missing: the stack's verify-skill step comes before Step E"; done
  for b in "${TC_ADO_WIKI:-false}" "${TC_RICH_README:-false}"; do
    case "$b" in true | false) ;; *) stop "TC_ADO_WIKI and TC_RICH_README take true or false (got '$b')" ;; esac
  done
  sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }
  # Core seeded files, then every hook (local guards included), in a fixed order. A file that is
  # absent is left out: CLAUDE.md is optional, and Step B3 may seed no CI file.
  list=$(
    printf '%s\n' AGENTS.md CLAUDE.md .claude/settings.json
    for s in $skills; do printf '.claude/skills/%s/SKILL.md\n' "$s"; done
    printf '%s\n' .claude/skills/skill-audit/SKILL.md
    (cd "$TGT" && find .claude/hooks -type f 2>/dev/null | LC_ALL=C sort)
    printf '%s\n' lefthook.yml .lefthook/commit-msg.sh .gitleaks.toml .claude/comment-hygiene-patterns.txt \
      .github/workflows/ci.yml azure-pipelines/templatecentral-gates.yml azure-pipelines.yml .claude/ci-gates.sh \
      .claude/verify-harness.sh .claude/regen-harness.sh
  )
  body=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -L "$TGT/$p" ]; then stop "$TGT/$p is a symlink"; fi
    [ -f "$TGT/$p" ] || continue
    case "$p" in *[\"\\]*) stop "the path $p holds a quote or backslash" ;; esac
    h=$(sha "$TGT/$p") || stop "cannot hash $p"
    body="$body,$NL    \"$p\": { \"origin_hash\": \"$h\", \"path\": \"$p\" }"
  done <<TC_LIST
$list
TC_LIST
  [ -n "$body" ] || stop "no seeded file found in $TGT"
  tmp="$TGT/$mf.tmp.$$"
  {
    printf '{\n  "templatecentral_version": "%s",\n  "stack": "%s",\n  "seeded_at": "%s",\n' "$ver" "$STACK" "$(date -u +%Y-%m-%d)"
    printf '  "adoWiki": %s,\n  "richReadme": %s,\n' "${TC_ADO_WIKI:-false}" "${TC_RICH_README:-false}"
    printf '  "seeded_files": {%s\n  }\n}\n' "${body#,}"
  } > "$tmp" || { rm -f -- "$tmp"; stop "writing $TGT/$mf failed"; }
  mv -- "$tmp" "$TGT/$mf" || { rm -f -- "$tmp"; stop "writing $TGT/$mf failed"; }
  echo "Wrote $TGT/$mf ($(printf '%s' "$body" | grep -c origin_hash) entries, templatecentral_version $ver)."
  exit 0
fi
if [ "$PART" = ci ] && [ "$CI" = none ]; then
  WHAT="remove the CI gate script"
  gate=.claude/ci-gates.sh
  if [ -L "$TGT/.claude" ] || [ -L "$TGT/$gate" ]; then stop "$TGT/.claude or $TGT/$gate is a symlink, so removing the file could delete something outside the project"; fi
  [ -e "$TGT/$gate" ] || { echo "Nothing to remove: $TGT/$gate does not exist."; exit 0; }
  [ -f "$TGT/$gate" ] || stop "$TGT/$gate is not a regular file"
  cmp -s -- "$SK/template/$gate" "$TGT/$gate" || stop "$TGT/$gate differs from the template, so it is not the file Step 0 placed"
  rm -f -- "$TGT/$gate" || stop "rm failed for $TGT/$gate"
  exit 0
fi
for t in $SEL; do
  [ -n "$(find "$SK/$t" -type f 2>/dev/null | head -n 1)" ] || stop "no files under $SK/$t"
  [ -z "$(find "$SK/$t" \( -type l -o -type d -empty \) 2>/dev/null | head -n 1)" ] || stop "$SK/$t holds a symlink or an empty directory"
done
[ -s "$SK/template.manifest" ] || stop "$SK/template.manifest is missing or empty"
plan=$(awk -v sel="$SEL" '
  BEGIN { n = split(sel, s, " ") }
  /^#/ || NF == 0 { next }
  { for (i = 1; i <= n; i++) if (index($1, s[i] "/") == 1) { print $2 "\t" s[i] "\t" substr($1, length(s[i]) + 2); next } }
' "$SK/template.manifest")
listed=$(printf '%s\n' "$plan" | cut -f3 | LC_ALL=C sort)
found=$(for t in $SEL; do (cd "$SK/$t" && find . -type f | sed 's|^\./||'); done | LC_ALL=C sort)
if [ -z "$listed" ] || [ "$listed" != "$found" ]; then
  stop "template.manifest and the template trees ($SEL) disagree.${NL}Only in the manifest:${NL}$(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$found"))${NL}Only in the trees:${NL}$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$found"))"
fi
clash=$(printf '%s\n' "$found" | while IFS= read -r p; do
  p=${p%.tmpl}
  if [ -e "$TGT/$p" ] || [ -L "$TGT/$p" ]; then echo "$p (exists)"; fi
  d=$p
  while [ "${d%/*}" != "$d" ]; do
    d=${d%/*}
    if [ -L "$TGT/$d" ]; then echo "$d (symlink)"; elif [ -e "$TGT/$d" ] && [ ! -d "$TGT/$d" ]; then echo "$d (not a directory)"; fi
  done
done | LC_ALL=C sort -u)
[ -z "$clash" ] || stop "these paths already exist, are symlinks or are not directories in $TGT:$NL$clash"
if [ "$PART" = ci ] || [ "$PART" = settings ] || [ "$PART" = late ]; then
  cmp -s -- "$TGT/lefthook.yml" "$SH/template-$V/lefthook.yml" || stop "$TGT/lefthook.yml is not the one Step 0 copied for STACK=$STACK, so this STACK does not match Step 0 (or Step 0 has not run)"
fi
bad=$(printf '%s\n' "$plan" | while IFS="$TAB" read -r mode t p; do
  [ -r "$SK/$t/$p" ] || echo "$SK/$t/$p (unreadable)"
  d=${p%.tmpl}
  if [ "${d%/*}" != "$d" ]; then d=${d%/*}; else d=; fi
  while [ -n "$d" ] && [ ! -d "$TGT/$d" ]; do
    if [ "${d%/*}" != "$d" ]; then d=${d%/*}; else d=; fi
  done
  if [ -n "$d" ]; then base="$TGT/$d"; else base="$TGT"; fi
  if [ ! -w "$base" ] || [ ! -x "$base" ]; then echo "$base (not writable or not searchable)"; fi
done | LC_ALL=C sort -u)
[ -z "$bad" ] || stop "nothing was written, because the copy would fail part way:$NL$bad"
copied=""
while IFS="$TAB" read -r mode t p; do
  dest=${p%.tmpl}
  d=${dest%/*}
  if [ "$d" != "$dest" ]; then
    mkdir -p -- "$TGT/$d" || stop "mkdir failed for $d; the copy may have created parent directories and files may be partly written in $TGT.${NL}Files already written:$copied"
  fi
  cp -- "$SK/$t/$p" "$TGT/$dest" || stop "copy failed for $dest; the copy may also have written a partial $dest or created parent directories, so files may be partly written in $TGT.${NL}Files already written:$copied"
  copied="$copied$NL$dest"
  chmod -- "$mode" "$TGT/$dest" || stop "chmod failed for $dest; files may be partly written in $TGT.${NL}Files already written:$copied"
done <<TC_PLAN
$plan
TC_PLAN
