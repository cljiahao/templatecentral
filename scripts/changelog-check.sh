#!/usr/bin/env bash
# scripts/changelog-check.sh — PR check: a PR adds a changelog fragment, or is a release PR.
#
# Usage: bash scripts/changelog-check.sh <base-ref>
#   Compares the merge base of <base-ref> and HEAD with HEAD (not commit by commit). Fails closed: a
#   missing base ref or merge base is an error.
#   Normal PR (CHANGELOG.md not in the diff): adds at least one valid fragment under changelog.d/
#   and no invalid entry there. Deleting fragments is not counted.
#   Release PR (CHANGELOG.md in the diff): the diff must be exactly what changelog-assemble.sh
#   makes, plus the release files. Rules, each reported by name when it fails:
#     1. CHANGELOG.md is modified in place (status M, regular file).
#     2. Nothing under changelog.d/ is added or modified; the deleted fragments equal the set at
#        the merge base (all folded, none left).
#     3. Changed paths are CHANGELOG.md, those deletions and this allow-list only. Chosen from the
#        release commits (7.0.0 to 7.2.2): .claude-plugin/plugin.json and .claude/harness.json (the
#        version bump, every release), README.md (version references), skills/scaffold/shared/
#        harness-kit-finalize.md (version marker) and tests/golden/<name>.sha256 (regenerated
#        hashes). All must be status M. Any other path fails.
#     4. The new top release heading of CHANGELOG.md is "## [N.N.N] — YYYY-MM-DD", and plugin.json
#        "version" and harness.json "templatecentral_version" at HEAD equal N.N.N.
#     5. Replay: the merge base CHANGELOG.md and fragments, run through changelog-assemble.sh with
#        that version and date, equal HEAD's CHANGELOG.md byte for byte.
#
# Catches: no fragment added; unknown category; empty or whitespace-only fragment; no bullet line;
#   heading or fence line inside a fragment; symlink, submodule or type-changed fragment;
#   subdirectory; name outside the pattern (incl. spaces, newlines); fragment added then deleted in
#   the same PR; README.md counted as a fragment; missing base ref or merge base; a normal PR that
#   edits CHANGELOG.md (it must then pass the replay, so free edits, history rewrites and fake
#   release headings fail); a release PR with a fragment left, added, or a path outside the
#   allow-list; CHANGELOG.md deleted or type-changed; a malformed heading; a version mismatch.
# Does not catch: a fragment whose text is wrong or meaningless; a fragment under the wrong
#   category; edits to allow-listed release files beyond the version match (README.md, the
#   finalize marker, golden hashes); a PR author who edits this script, changelog-assemble.sh,
#   changelog-lib.sh or the workflow in the same PR (the replay runs the PR's own assemble script).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/changelog-lib.sh"

die() { echo "changelog-check: $*" >&2; exit 1; }
bad() { echo "changelog-check: $*" >&2; n_bad=$((n_bad + 1)); }
rel() { echo "changelog-check: release rule $1 failed: $2" >&2; n_rel=$((n_rel + 1)); }
# Release findings found while reading the diff; shown only when this turns out to be a release PR.
relq() { printf 'changelog-check: release rule %s failed: %s\n' "$1" "$2" >> "$work/relq"; n_relq=$((n_relq + 1)); }
printable() { printf '%s' "${1//[^[:print:]]/?}"; }

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

n_bad=0 n_rel=0 n_relq=0 n_added=0 cl_status="" cl_mode="" cl_seen=0
: > "$work/deleted"
: > "$work/relq"
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  read -r _om nm _osha nsha st <<< "$meta"
  label=$(printable "$path")
  if [[ $path == CHANGELOG.md ]]; then
    cl_seen=1; cl_status=$st; cl_mode=$nm; continue
  fi
  if [[ $path == "$CL_DIR"/* ]]; then
    rest=${path#"$CL_DIR"/}
    if [[ $st == D ]]; then
      if [[ $rest != */* ]] && cl_name_category "$rest" >/dev/null; then
        printf '%s\n' "$rest" >> "$work/deleted"
      else
        relq 2 "$label: only valid fragments may be deleted"
      fi
      continue
    fi
    relq 2 "$label: nothing under $CL_DIR/ may be added or modified in a release PR"
    if [[ $rest == README.md ]]; then continue; fi
    if [[ $st != A ]]; then bad "$label: only adding a fragment is allowed here (status $st)"; continue; fi
    if [[ $rest == */* ]]; then bad "$label: fragments cannot live in a subdirectory"; continue; fi
    if ! cl_name_category "$rest" >/dev/null; then bad "$label: name must be <slug>.<${CL_CATEGORIES// /|}>.md"; continue; fi
    if [[ $nm != 100644 && $nm != 100755 ]]; then bad "$label: must be a regular file (mode $nm)"; continue; fi
    git cat-file blob "$nsha" > "$work/frag" || { bad "$label: cannot read blob"; continue; }
    if ! cl_content_ok "$work/frag"; then bad "$label: needs a bullet line ('- text') first, then bullets or indented text (no heading or fence lines)"; continue; fi
    n_added=$((n_added + 1))
    continue
  fi
  case $path in
    .claude-plugin/plugin.json|.claude/harness.json|README.md|skills/scaffold/shared/harness-kit-finalize.md) ok_path=1 ;;
    tests/golden/*.sha256) if [[ ${path#tests/golden/} != */* ]]; then ok_path=1; else ok_path=0; fi ;;
    *) ok_path=0 ;;
  esac
  if [[ $ok_path -eq 0 ]]; then relq 3 "$label is not on the release allow-list"
  elif [[ $st != M ]]; then relq 3 "$label: release files may only be modified (status $st)"; fi
done < "$work/raw"

if [[ $cl_seen -eq 0 ]]; then
  [[ $n_bad -eq 0 ]] || die "$n_bad invalid entry(ies) under $CL_DIR/"
  [[ $n_added -ge 1 ]] || die "no changelog fragment added: create $CL_DIR/<slug>.<${CL_CATEGORIES// /|}>.md (see $CL_DIR/README.md)"
  echo "changelog-check: ok ($n_added fragment(s) added)"
  exit 0
fi

echo "changelog-check: CHANGELOG.md is in the diff, so this PR must be a release PR (a normal PR adds a fragment instead)" >&2
cat "$work/relq" >&2
n_rel=$n_relq
if [[ $cl_mode != 100644 && $cl_mode != 100755 ]]; then
  rel 1 "CHANGELOG.md must be modified in place as a regular file (status $cl_status, mode $cl_mode)"
fi
[[ $n_bad -eq 0 && $n_rel -eq 0 ]] || die "not a valid release PR ($n_rel release rule failure(s), $n_bad invalid entry(ies))"

# Rule 2: deleted set equals the merge-base set.
git ls-tree -r -z --name-only "$mb" -- "$CL_DIR" > "$work/basels" || die "cannot list $CL_DIR/ at the merge base"
: > "$work/baseset"
while IFS= read -r -d '' p; do
  name=${p#"$CL_DIR"/}
  [[ $name != README.md ]] || continue
  if [[ $name == */* ]] || ! cl_name_category "$name" >/dev/null; then
    rel 2 "merge base holds an invalid fragment path: $(printable "$p")"; continue
  fi
  printf '%s\n' "$name" >> "$work/baseset"
done < "$work/basels"
LC_ALL=C sort "$work/baseset" > "$work/baseset.s" || die "sort failed"
LC_ALL=C sort "$work/deleted" > "$work/deleted.s" || die "sort failed"
[[ -s $work/baseset.s ]] || rel 2 "the merge base has no fragments to release"
cmp -s "$work/baseset.s" "$work/deleted.s" || rel 2 "deleted fragments differ from the merge-base set (all must be folded, none left)"
[[ $n_rel -eq 0 ]] || die "not a valid release PR ($n_rel release rule failure(s))"

# Rule 4: heading and versions.
git cat-file blob "HEAD:CHANGELOG.md" > "$work/new" || die "cannot read CHANGELOG.md at HEAD"
heading=$(awk '/^## \[Unreleased\]/ { u = 1; next } u && /^## \[/ { print; exit }' "$work/new")
re_h='^## \[([0-9]+\.[0-9]+\.[0-9]+)\] — ([0-9]{4}-[0-9]{2}-[0-9]{2})$'
if [[ ! $heading =~ $re_h ]]; then
  rel 4 "the top release heading must be '## [N.N.N] — YYYY-MM-DD', got '$(printable "$heading")'"
  die "not a valid release PR"
fi
version=${BASH_REMATCH[1]} date=${BASH_REMATCH[2]}
json_version() { # json_version <path> <key>
  git cat-file blob "HEAD:$1" 2>/dev/null | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p'
}
pv=$(json_version .claude-plugin/plugin.json version)
hv=$(json_version .claude/harness.json templatecentral_version)
[[ $pv == "$version" ]] || rel 4 "plugin.json version '$pv' does not equal the heading version $version"
[[ $hv == "$version" ]] || rel 4 "harness.json templatecentral_version '$hv' does not equal the heading version $version"
[[ $n_rel -eq 0 ]] || die "not a valid release PR"

# Rule 5: replay the assemble on the merge-base tree.
mkdir "$work/replay" || die "mkdir failed"
git archive "$mb" CHANGELOG.md "$CL_DIR" | tar -x -C "$work/replay" || die "cannot materialise the merge-base tree"
git -C "$work/replay" init -q || die "git init failed"
(cd "$work/replay" && bash "$here/changelog-assemble.sh" "$version" "$date") > "$work/replay.log" 2>&1 \
  || { cat "$work/replay.log" >&2; rel 5 "changelog-assemble.sh refuses the merge-base fragments"; die "not a valid release PR"; }
cmp -s "$work/replay/CHANGELOG.md" "$work/new" || { rel 5 "CHANGELOG.md differs from the changelog-assemble.sh replay of the merge base"; die "not a valid release PR"; }
echo "changelog-check: ok (release PR $version: replay matches, $(wc -l < "$work/deleted" | tr -d ' ') fragment(s) folded)"
