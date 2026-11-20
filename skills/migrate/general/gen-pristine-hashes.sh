#!/usr/bin/env bash
# Maintainer tool, run at release time from a templateCentral checkout: writes pristine-hashes.txt beside this script.
# Usage: gen-pristine-hashes.sh [--check]
# One line per file shipped by a released version: <sha256><TAB><version><TAB><project path>.
# harness-refresh.sh treats a project file as pristine only when its hash is on this list, so a file seeded by a released version
# can be replaced and every other file is kept. Source: template.manifest and the files it names, read from every git tag vN.N.N.
# A tag without a template.manifest (before 7.0.0) adds nothing: projects seeded by it get a .templatecentral-new file for every changed file.
# Files that carry a __TC_ placeholder are left out; harness-refresh.sh never replaces them.
# Run it after tagging a release and commit the result. --check exits 1 when the committed list is out of date.
# Needs bash 3.2+, git, awk, sort, and shasum or sha256sum.
set -u

die() { echo "gen-pristine-hashes: $1" >&2; exit 2; }
TAB=$(printf '\t')
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1; }

CHECK=0
case "${1:-}" in
  '') ;;
  --check) CHECK=1 ;;
  *) die "usage: gen-pristine-hashes.sh [--check]" ;;
esac

src=${BASH_SOURCE[0]:-$0}
if ! GEN=$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd -P); then die "cannot locate the script directory"; fi
OUT=$GEN/pristine-hashes.txt
REPO=$(git -C "$GEN" rev-parse --show-toplevel 2>/dev/null) || die "not inside a git checkout"
SHARED=skills/scaffold/shared

TMP=$(mktemp "${TMPDIR:-/tmp}/pristine.XXXXXX") || die "cannot create a temp file"
trap 'rm -f "$TMP"' EXIT

for tag in $(git -C "$REPO" tag --list 'v[0-9]*.[0-9]*.[0-9]*' | LC_ALL=C sort); do
  ver=${tag#v}
  man=$(git -C "$REPO" show "$tag:$SHARED/template.manifest" 2>/dev/null) || continue
  printf '%s\n' "$man" | awk '/^#/ || NF == 0 { next } $3 == "-" { print $1 }' | while IFS= read -r path; do
    rel=${path#*/}
    dest=${rel%.tmpl}
    git -C "$REPO" cat-file -e "$tag:$SHARED/$path" 2>/dev/null || continue
    h=$(git -C "$REPO" show "$tag:$SHARED/$path" | sha)
    printf '%s\t%s\t%s\n' "$h" "$ver" "$dest"
  done >>"$TMP"
done

# One line per hash and path, keeping the earliest version that shipped it.
awk -F "$TAB" '!seen[$1 FS $3]++' "$TMP" | LC_ALL=C sort -t "$TAB" -k3,3 -k1,1 >"$TMP.out"
trap 'rm -f "$TMP" "$TMP.out"' EXIT
if [ ! -s "$TMP.out" ]; then die "no tagged release with a template.manifest found; fetch the tags first"; fi

if [ "$CHECK" -eq 1 ]; then
  if cmp -s "$TMP.out" "$OUT"; then echo "pristine-hashes.txt is current"; exit 0; fi
  echo "pristine-hashes.txt is out of date; run gen-pristine-hashes.sh and commit the result" >&2
  exit 1
fi
mv -f "$TMP.out" "$OUT" || die "cannot write $OUT"
echo "wrote $OUT ($(wc -l <"$OUT" | tr -d ' ') lines)"
