#!/usr/bin/env bash
# scripts/changelog-assemble.sh — fold changelog.d/ fragments into a new release section of
# CHANGELOG.md.
#
# Usage: bash scripts/changelog-assemble.sh [--dry-run] <version N.N.N> <date YYYY-MM-DD>
#   Groups fragments by category (Added, Changed, Removed, Fixed, Security), sorts them by file name
#   inside a category, inserts "## [version] — date" after the [Unreleased] block, then deletes
#   the fragments. --dry-run prints the section and changes nothing.
#   Every check runs before the first write. The file is replaced by one mv of a temp file from
#   the same directory, with the same mode as before. The fragments are deleted after that mv.
#   If a delete fails, the run exits non-zero with CHANGELOG.md already updated; a re-run then
#   refuses (the version exists), so nothing is folded twice.
#   Each fragment is copied, validated by cl_content_ok (the check script's rule) and emitted
#   from that copy byte for byte: the validated text is the emitted text.
#   Refuses (non-zero, no change) on: no fragments, an invalid fragment, an existing version
#   heading, a bad version or date, CHANGELOG.md missing or a symlink, no [Unreleased] heading
#   or no release heading after it, any entry still under [Unreleased]. Entries belong in
#   fragments, so move them there first.
set -uo pipefail
export LC_ALL=C
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/changelog-lib.sh"

die() { echo "changelog-assemble: $*" >&2; exit 1; }

dry=0
if [[ ${1:-} == --dry-run ]]; then dry=1; shift; fi
[[ $# -eq 2 ]] || die "usage: changelog-assemble.sh [--dry-run] <version> <date>"
version=$1 date=$2
re_v='^[0-9]+\.[0-9]+\.[0-9]+$'
re_d='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
[[ $version =~ $re_v ]] || die "version must look like N.N.N, got '$version'"
[[ $date =~ $re_d ]] || die "date must look like YYYY-MM-DD, got '$date'"

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || die "cannot enter $root"
[[ -f CHANGELOG.md && ! -L CHANGELOG.md ]] || die "CHANGELOG.md must be a regular file"
[[ -d $CL_DIR && ! -L $CL_DIR ]] || die "$CL_DIR/ must be a directory"

work=$(mktemp -d "${TMPDIR:-/tmp}/clasm.XXXXXX") || die "mktemp failed"
new=""
trap 'rm -rf "$work"; if [[ -n $new ]]; then rm -f "$new"; fi' EXIT

awk -v v="$version" 'index($0, "## [" v "]") == 1 { f = 1 } END { exit f ? 0 : 1 }' CHANGELOG.md \
  && die "CHANGELOG.md already has a section for $version"
awk '/^## \[Unreleased\]/ { u = 1; next }
     u && /^## \[/ { f = 1 }
     END { exit f ? 0 : 1 }' CHANGELOG.md \
  || die "CHANGELOG.md needs '## [Unreleased]' followed by a release heading"

cl_unreleased_entries CHANGELOG.md > "$work/entries" || die "cannot read [Unreleased]"
[[ ! -s $work/entries ]] \
  || die "CHANGELOG.md has entries under '## [Unreleased]'; move them into $CL_DIR/ fragments first"

mkdir "$work/frags" || die "mkdir failed"
find "$CL_DIR" -mindepth 1 -print0 > "$work/all" || die "cannot list $CL_DIR/"
: > "$work/names"
nfrag=0
while IFS= read -r -d '' p; do
  name=${p#"$CL_DIR"/}
  if [[ $name == README.md && -f $p && ! -L $p ]]; then continue; fi
  label=${p//[[:cntrl:]]/?}
  [[ $name != */* && ! ( -d $p && ! -L $p ) ]] \
    || die "$label: fragments cannot live in a subdirectory"
  cl_name_category "$name" >/dev/null || die "$label: not a valid fragment name"
  [[ -f $p && ! -L $p ]] || die "$label: not a valid fragment: not a regular file"
  cp -P "$p" "$work/frags/$name" || die "$label: cannot read it"
  why=$(cl_content_ok "$work/frags/$name") || die "$label: not a valid fragment: $why"
  printf '%s\n' "$name" >> "$work/names"
  nfrag=$((nfrag + 1))
done < "$work/all"
[[ $nfrag -gt 0 ]] || die "no fragments in $CL_DIR/"

LC_ALL=C sort "$work/names" > "$work/sorted" || die "sort failed"
{
  printf '## [%s] — %s\n' "$version" "$date"
  for cat in $CL_CATEGORIES; do
    heading="$(printf '%s' "${cat:0:1}" | tr '[:lower:]' '[:upper:]')${cat:1}"
    first=1
    while IFS= read -r name; do
      [[ $name == *".$cat.md" ]] || continue
      if [[ $first -eq 1 ]]; then printf '\n### %s\n' "$heading"; first=0; fi
      cat "$work/frags/$name" || die "cannot read $name"
    done < "$work/sorted"
  done
  printf '\n---\n\n'
} > "$work/section" || die "cannot build the section"

if [[ $dry -eq 1 ]]; then
  cat "$work/section"
  exit 0
fi

new=$(mktemp "$root/CHANGELOG.md.XXXXXX") || die "mktemp failed"
cp -p CHANGELOG.md "$new" || die "cannot copy CHANGELOG.md mode"
awk -v secf="$work/section" '
  /^## \[Unreleased\]/ { u = 1 }
  u && !done && /^## \[/ && !/^## \[Unreleased\]/ {
    while ((getline l < secf) > 0) print l
    done = 1
  }
  { print }
  END { exit done ? 0 : 1 }
' CHANGELOG.md > "$new" || die "cannot insert the section"
mv "$new" CHANGELOG.md || die "cannot replace CHANGELOG.md"
new=""
while IFS= read -r name; do
  rm -f "$CL_DIR/$name" || die "CHANGELOG.md updated but cannot delete $CL_DIR/$name"
done < "$work/sorted"
echo "changelog-assemble: $version: $nfrag fragment(s) folded into CHANGELOG.md"
