#!/usr/bin/env bash
# tc-copy.sh — the one script that copies templateCentral's template trees into a project.
#
# Usage: STACK=<stack> PART=<part> [CI=<host>] bash tc-copy.sh <target>
#   STACK  nestjs | nextjs | vite-react | fastapi
#   PART   base | settings | ci | late | stack | agents | tail   (see skills/scaffold/shared/harness-kit.md, Step 0)
#   CI     github | azure | none; required for PART=ci, empty for every other part
#   target the project root; it must be an existing directory
#
# It finds the trees and manifests from its own location, so it works from the plugin directory and
# from the dist layout that scripts/build-agents-dist.sh builds. A refusal writes nothing and ends
# with a STOP: line.
SH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd) || SH=
STACK=${STACK-}
CI=${CI-}
PART=${PART-}
WHAT="scaffold"
NL='
'
TAB=$(printf '\t')
stop() { printf 'Refusing to %s: %s\nSTOP: do not rm or overwrite anything; report this to the user.\n' "$WHAT" "$1"; exit 1; }
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
case "$STACK" in
  nestjs|nextjs|vite-react) V=ts ;;
  fastapi) V=py ;;
  *) stop "unknown STACK '$STACK' (want nestjs, nextjs, vite-react or fastapi)" ;;
esac
case "$PART" in
  base)
    [ -z "$CI" ] || stop "CI must stay empty in Step 0"
    SEL="template template-$V" ;;
  settings | late | tail)
    [ -z "$CI" ] || stop "CI must stay empty for PART=$PART"
    [ -f "$TGT/AGENTS.md" ] || stop "$TGT/AGENTS.md does not exist yet: PART=$PART runs after the stack's AGENTS.md step and its verification gate"
    if [ "$PART" = settings ]; then SEL="template-settings-$V"; else SEL="template-late"; fi ;;
  ci)
    case "$CI" in
      github) SEL="template-ci/github-$V" ;;
      azure) SEL="template-ci/azure" ;;
      none) SEL= ;;
      *) stop "unknown CI '$CI' (want github, azure or none)" ;;
    esac ;;
  stack | agents)
    [ -z "$CI" ] || stop "CI must stay empty for PART=$PART"
    SK=${SH%/shared}/$STACK
    if [ "$PART" = stack ]; then SEL="template"; else SEL="template-agents"; fi ;;
  *) stop "unknown PART '$PART'" ;;
esac
if [ "$PART" = tail ]; then
  WHAT="append the tail"
  case "$STACK" in
    fastapi) TC='python -m pyright src/' ;;
    *) TC='pnpm exec tsc --noEmit --incremental' ;;
  esac
  out=$(TC="$TC" awk 'BEGIN { m = "see delta table for stack command" } { i = index($0, m); if (i) $0 = substr($0, 1, i - 1) ENVIRON["TC"] substr($0, i + length(m)); print }' "$SH/template-tail/AGENTS-tail.md") || stop "cannot read the tail file"
  [ -n "$out" ] || stop "the tail file is empty"
  printf '\n%s\n' "$out" >> "$TGT/AGENTS.md" || stop "appending to $TGT/AGENTS.md failed"
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
