#!/usr/bin/env bash
# scripts/changelog-check.sh — PR check: the PR adds a changelog fragment and leaves CHANGELOG.md alone.
#
# Usage: bash scripts/changelog-check.sh <base-ref>
#   Compares the merge base of <base-ref> and HEAD with HEAD (not commit by commit). Passes when the
#   diff adds at least one valid fragment under changelog.d/, adds no invalid entry there and does
#   not modify CHANGELOG.md. A diff that only deletes fragments and edits CHANGELOG.md (the release
#   PR from changelog-assemble.sh) also passes, when every deleted bullet is in the new CHANGELOG.md.
#   Fails closed: a missing base ref or merge base is an error.
#
# Catches: no fragment added; unknown category; empty or whitespace-only fragment; no bullet line;
#   symlink; subdirectory; name outside the pattern (incl. spaces, newlines); CHANGELOG.md edited
#   with a fragment; fragment added then deleted in the same PR; README.md counted as a fragment;
#   missing base ref or merge base. Rules: allow-list, see scripts/changelog-lib.sh.
# Does not catch: a fragment whose text is wrong or meaningless; a fragment under the wrong
#   category; a PR author who edits this script or its workflow in the same PR.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/changelog-lib.sh"

die() { echo "changelog-check: $*" >&2; exit 1; }
bad() { echo "changelog-check: $*" >&2; n_bad=$((n_bad + 1)); }

[[ $# -eq 1 && -n $1 && $1 != -* ]] || die "usage: changelog-check.sh <base-ref>"
base=$1
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || die "cannot enter $root"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "base ref '$base' not found (fetch it first)"
mb=$(git merge-base "$base" HEAD 2>/dev/null) || die "no merge base between '$base' and HEAD (shallow clone? use fetch-depth: 0)"
[[ -n $mb ]] || die "no merge base between '$base' and HEAD"

work=$(mktemp -d "${TMPDIR:-/tmp}/clcheck.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
git diff --raw -z --no-renames --no-abbrev "$mb" HEAD > "$work/raw" || die "git diff failed"

n_bad=0 n_added=0 n_removed=0 n_other=0 n_cl=0 cl_status=""
removed_blobs=()
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  read -r _om nm osha nsha st <<< "$meta"
  if [[ $path == CHANGELOG.md ]]; then
    n_cl=$((n_cl + 1)); cl_status=$st; continue
  fi
  if [[ $path != "$CL_DIR"/* ]]; then
    n_other=$((n_other + 1)); continue
  fi
  rest=${path#"$CL_DIR"/}
  if [[ $st == D ]]; then
    if cl_name_category "$rest" >/dev/null && [[ $rest != */* ]]; then
      n_removed=$((n_removed + 1)); removed_blobs+=("$osha")
    else
      n_other=$((n_other + 1))
    fi
    continue
  fi
  if [[ $rest == README.md ]]; then n_other=$((n_other + 1)); continue; fi
  label=${path//[^[:print:]]/?}
  if [[ $st != A ]]; then bad "$label: only adding a fragment is allowed here (status $st)"; continue; fi
  if [[ $rest == */* ]]; then bad "$label: fragments cannot live in a subdirectory"; continue; fi
  if ! cl_name_category "$rest" >/dev/null; then bad "$label: name must be <slug>.<${CL_CATEGORIES// /|}>.md"; continue; fi
  if [[ $nm != 100644 && $nm != 100755 ]]; then bad "$label: must be a regular file (mode $nm)"; continue; fi
  git cat-file blob "$nsha" > "$work/frag" || { bad "$label: cannot read blob"; continue; }
  if ! cl_content_ok "$work/frag"; then bad "$label: needs a bullet line ('- text') first, then bullets or indented lines only"; continue; fi
  n_added=$((n_added + 1))
done < "$work/raw"

[[ $n_bad -eq 0 ]] || die "$n_bad invalid entry(ies) under $CL_DIR/"

if [[ $n_cl -gt 0 ]]; then
  [[ $n_added -eq 0 && $n_removed -ge 1 && $n_other -eq 0 && $cl_status == M ]] \
    || die "CHANGELOG.md is modified: add a fragment under $CL_DIR/ instead (see $CL_DIR/README.md)"
  git cat-file blob "HEAD:CHANGELOG.md" > "$work/cl" || die "cannot read CHANGELOG.md at HEAD"
  for b in "${removed_blobs[@]}"; do
    git cat-file blob "$b" > "$work/frag" || die "cannot read a removed fragment"
    grep -Fxv -f "$work/cl" "$work/frag" > "$work/missing"
    [[ $? -le 1 ]] || die "grep failed"
    [[ ! -s $work/missing ]] || die "release PR: a removed fragment line is missing from CHANGELOG.md"
  done
  echo "changelog-check: ok (release PR: $n_removed fragment(s) folded into CHANGELOG.md)"
  exit 0
fi

[[ $n_added -ge 1 ]] || die "no changelog fragment added: create $CL_DIR/<slug>.<${CL_CATEGORIES// /|}>.md (see $CL_DIR/README.md)"
echo "changelog-check: ok ($n_added fragment(s) added)"
