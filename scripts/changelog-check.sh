#!/usr/bin/env bash
# scripts/changelog-check.sh — PR check: a PR adds a changelog fragment, or is a release PR.
#
# Usage: bash scripts/changelog-check.sh <base-ref>
#   Compares the merge base of <base-ref> and HEAD with HEAD (not commit by commit). Fails closed:
#   a missing base ref or merge base is an error.
#   Every PR: "## [Unreleased]" in CHANGELOG.md at HEAD has no entry. Entries live in fragments.
#   Normal PR (CHANGELOG.md not in the diff): adds at least one valid fragment under changelog.d/
#   and no invalid entry there. It deletes no fragment and does not change the version value in
#   .claude-plugin/plugin.json or .claude/harness.json (other edits are fine). Those two files
#   may only be modified or added: deleted or type-changed fails. Each copy needs exactly one
#   version line; minified JSON or a repeated key fails closed.
#   Migration PR (the only CHANGELOG.md change empties "## [Unreleased]"): the same as a normal
#   PR, and every entry removed from CHANGELOG.md is a line of an added fragment (backticks and *
#   are ignored in that comparison, so a fragment may wrap a stray < in backticks or drop bold).
#   Release PR (any other CHANGELOG.md change): the diff must be exactly what
#   changelog-assemble.sh makes, plus the version bump. Rules, each reported by number when it
#   fails:
#     1. CHANGELOG.md is modified in place: status M, regular file.
#     2. Nothing under changelog.d/ is added or modified; the deleted fragments equal the set at
#        the merge base (all folded, none left).
#     3. Changed paths are CHANGELOG.md, those deletions and the two version files only:
#        .claude-plugin/plugin.json and .claude/harness.json, status M. Each equals its merge-base
#        version except for the version value (one version line, same form); no other file.
#     4. The new top release heading of CHANGELOG.md is "## [N.N.N] — YYYY-MM-DD"; plugin.json
#        "version" and harness.json "templatecentral_version" at HEAD equal N.N.N and are greater
#        than the merge-base values.
#     5. Replay: the merge base CHANGELOG.md and fragments, run through changelog-assemble.sh with
#        that version and date, equal HEAD's CHANGELOG.md byte for byte.
#     6. "## [Unreleased]" has no entry at the merge base or at HEAD.
#   Why only those two files: a dry-run bump on a clone, then the version gates (check-golden.sh
#   8 of 8, regen-golden.sh no change, validate-manifest.sh, check-versions.sh, check-doc-sync.sh),
#   changed nothing else. The golden hashes depend on template content, not on the version, and
#   pristine-hashes.txt is regenerated from the tag after the release, not in the release PR.
#
# Catches: no fragment added; unknown category; empty fragment; a fragment that breaks the rules of
#   changelog-lib.sh, cl_content_ok. Bytes: any control byte but LF (CR, TAB, NUL, ESC, DEL), a
#   last line with no newline, invalid UTF-8 (overlong, surrogate, stray or lone byte), an
#   invisible or reordering character (C1 controls, soft hyphen, zero width, bidi marks and
#   overrides, line and paragraph separators, BOM, tag characters). Lines: a blank line; a line
#   that is not "- text" (first line and after), "  - text" or "  text" (two spaces). Text:
#   starts with anything but a letter, digit, backtick, [ ( " ' or # and a digit (a PR
#   reference); has no letter or digit; starts like a list marker (1. or 1)). Backticks: odd
#   count on a line, two in a row, one after a backslash. Outside backtick spans: < before a
#   letter, / ! or ? (raw HTML, comment, CDATA, PI, autolink), "](", "][" or "] [" (link
#   destination or label), "]:" anywhere (link reference definition), a [ or ] that does not
#   balance on its line (a label cannot run over a line break or hide behind a backslash).
#   So a heading, quote, fence, thematic break, setext underline, table or HTML block is
#   rejected, and the script and Markdown agree on every line break and every code span;
#   symlink, submodule or type-changed fragment; subdirectory; name outside the pattern (incl.
#   spaces, newlines); fragment added then deleted in the same PR; README.md counted as a
#   fragment; missing base ref or merge base; entries left under "## [Unreleased]"; in a normal
#   PR a fragment deleted or modified (policy: a fragment belongs to the PR that added it), a
#   changed, deleted or type-changed version file, a version value change, a minified or
#   duplicate-key version file; a normal PR that edits CHANGELOG.md (it must then pass the replay,
#   so free edits, history rewrites and fake release headings fail); a release PR with a
#   fragment left or added, a path off the allow-list (this includes the assemble script, the
#   lib, this check and the workflow), an extra or duplicate key in a version file, a version
#   that is not greater; CHANGELOG.md deleted or type-changed; a malformed heading.
# Does not catch: a fragment whose text is wrong or meaningless; inline Markdown inside a valid
#   line that cannot open a block or hide a backtick: emphasis, entity references (&lt;), bare
#   URLs of any scheme (javascript: too), "www." hosts and email addresses (some renderers link
#   them), look-alike letters (homoglyphs) and combining marks, a task box ([ ] x), a
#   backslash before another character, a "[text]" that a "[text]:" definition elsewhere in
#   CHANGELOG.md turns into a link, trailing spaces (a hard break); a fragment under
#   the wrong category (a migration PR does not compare the category either); a fragment that
#   duplicates another fragment's text; a normal PR that edits this script,
#   changelog-assemble.sh, changelog-lib.sh, the tests or the workflow, because the checks that
#   run are the PR's own copies and only a release PR is held to the allow-list; a normal PR
#   that edits plugin.json or harness.json in any way other than the version value.
set -uo pipefail
export LC_ALL=C
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/changelog-lib.sh"

# die, bad and rel print a failure; relq holds a release finding until the PR is known to be a
# release PR, so a normal PR never sees release text.
die() { echo "changelog-check: $*" >&2; exit 1; }
bad() { echo "changelog-check: $*" >&2; n_bad=$((n_bad + 1)); }
rel() { echo "changelog-check: release rule $1 failed: $2" >&2; n_rel=$((n_rel + 1)); }
relq() { printf 'changelog-check: release rule %s failed: %s\n' "$1" "$2" >> "$work/relq"; }
# Control characters become "?"; other bytes pass, so the message reads the same in any locale.
printable() { printf '%s' "${1//[[:cntrl:]]/?}"; }

[[ $# -eq 1 && -n $1 && $1 != -* ]] || die "usage: changelog-check.sh <base-ref>"
base=$1
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || die "cannot enter $root"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null \
  || die "base ref '$base' not found (fetch it first)"
mb=$(git merge-base "$base" HEAD 2>/dev/null) \
  || die "no merge base between '$base' and HEAD (shallow clone? use fetch-depth: 0)"
[[ -n $mb ]] || die "no merge base between '$base' and HEAD"

work=$(mktemp -d "${TMPDIR:-/tmp}/clcheck.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
git diff --raw -z --no-renames --no-abbrev "$mb" HEAD > "$work/raw" || die "git diff failed"

n_bad=0 n_rel=0 n_added=0 n_del=0 cl_status="" cl_mode="" cl_seen=0
: > "$work/deleted"
: > "$work/verfiles"
: > "$work/verbad"
: > "$work/relq"
: > "$work/fragtext"
: > "$work/fragpairs"
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  read -r _om nm _osha nsha st <<< "$meta"
  label=$(printable "$path")
  if [[ $path == CHANGELOG.md ]]; then
    cl_seen=1; cl_status=$st; cl_mode=$nm; continue
  fi
  if [[ $path == "$CL_DIR"/* ]]; then
    rest=${path#"$CL_DIR"/}
    if [[ $st == D ]]; then
      n_del=$((n_del + 1))
      if [[ $rest != */* ]] && cl_name_category "$rest" >/dev/null; then
        printf '%s\n' "$rest" >> "$work/deleted"
      else
        relq 2 "$label: only valid fragments may be deleted"
      fi
      continue
    fi
    relq 2 "$label: nothing under $CL_DIR/ may be added or modified in a release PR"
    if [[ $rest == README.md ]]; then continue; fi
    if [[ $st != A ]]; then
      bad "$label: only adding a fragment is allowed here (status $st)"; continue
    fi
    if [[ $rest == */* ]]; then bad "$label: fragments cannot live in a subdirectory"; continue; fi
    if ! cl_name_category "$rest" >/dev/null; then
      bad "$label: name must be <slug>.<${CL_CATEGORIES// /|}>.md"; continue
    fi
    if [[ $nm != 100644 && $nm != 100755 ]]; then
      bad "$label: must be a regular file (mode $nm)"; continue
    fi
    git cat-file blob "$nsha" > "$work/frag" || { bad "$label: cannot read blob"; continue; }
    if ! why=$(cl_content_ok "$work/frag"); then
      bad "$label: $why"
      continue
    fi
    cat "$work/frag" >> "$work/fragtext"
    awk '{ o = $0; gsub(/[`*]/, ""); print $0 "\t" o }' "$work/frag" >> "$work/fragpairs"
    n_added=$((n_added + 1))
    continue
  fi
  case $path in
    .claude-plugin/plugin.json|.claude/harness.json)
      if [[ $st == M || $st == A ]]; then
        printf '%s\n' "$path" >> "$work/verfiles"
      else
        printf '%s\t%s\n' "$path" "$st" >> "$work/verbad"
      fi ;;
    *) relq 3 "$label is not on the release allow-list"; continue ;;
  esac
  if [[ $st != M ]]; then relq 3 "$label: release files may only be modified (status $st)"; fi
done < "$work/raw"

# Rule 6 at HEAD, every PR: no entry under [Unreleased].
git cat-file blob "HEAD:CHANGELOG.md" > "$work/new" 2>/dev/null || cp /dev/null "$work/new"
cl_unreleased_entries "$work/new" > "$work/entries"; es=$?
if [[ $cl_seen -eq 0 ]]; then
  [[ $es -eq 0 ]] || die "CHANGELOG.md at HEAD has no '## [Unreleased]' heading"
  if [[ -s $work/entries ]]; then
    first=$(sed -n '1p' "$work/entries")
    bad "CHANGELOG.md has entries under '## [Unreleased]'; move each into a $CL_DIR/ fragment"
    bad "first entry: $(printable "${first:0:80}")"
  fi
fi

# Migration PR: the only CHANGELOG.md change empties [Unreleased] into the added fragments.
migration=0 bt=$(printf '\x60')
# Succeeds when the removed line $1 is a reworded fragment line: the same text once backticks
# and * are dropped, every code span of the removed line kept in order in the fragment line (a
# reword may wrap more text in backticks, but not drop, move or change a span), and the same
# number of lone * (a * with a space or a line edge on both sides is
# a multiplication or a bullet, not emphasis: it may not appear or vanish). Odd backtick counts
# fail closed. Used only when no fragment line equals the removed line exactly.
spans_of() {
  local parts i=1 out=""
  IFS=$bt read -r -a parts <<< "${1}x"
  parts[${#parts[@]}-1]=${parts[${#parts[@]}-1]%x}
  while [[ $i -lt ${#parts[@]} ]]; do out=$out${parts[$i]}$'\x1f'; i=$((i + 2)); done
  printf '%s' "$out"
}
# Succeeds when every span of the list $1 occurs, in order, in the list $2 (both from spans_of).
spans_kept() {
  local want have w h=0 sep=$'\x1f'
  IFS=$sep read -r -a want <<< "$1"
  IFS=$sep read -r -a have <<< "$2"
  for w in ${want[@]+"${want[@]}"}; do
    while [[ $h -lt ${#have[@]} && ${have[$h]} != "$w" ]]; do h=$((h + 1)); done
    if [[ $h -ge ${#have[@]} ]]; then return 1; fi
    h=$((h + 1))
  done
  return 0
}
lone_stars() {
  local parts i=0 n=0
  IFS='*' read -r -a parts <<< " ${1} "
  while [[ $i -lt $((${#parts[@]} - 1)) ]]; do
    if [[ ${parts[$i]} == *' ' && ${parts[$((i + 1))]} == ' '* ]]; then n=$((n + 1)); fi
    i=$((i + 1))
  done
  printf '%s' "$n"
}
reword_ok() {
  local line=$1 cand spans stars only
  only=${line//[!$bt]/}
  if [[ $(( ${#only} % 2 )) -ne 0 ]]; then return 1; fi
  spans=$(spans_of "$line"); stars=$(lone_stars "$line")
  while IFS= read -r cand; do
    if spans_kept "$spans" "$(spans_of "$cand")" && [[ $(lone_stars "$cand") == "$stars" ]]; then
      return 0
    fi
  done < <(S="${line//[$bt*]/}" awk -F '\t' '$1 == ENVIRON["S"] { print $2 }' "$work/fragpairs")
  return 1
}
if [[ $cl_seen -eq 1 && $cl_status == M && ! -s $work/entries && $n_added -ge 1 && $n_bad -eq 0 ]] \
  && git cat-file blob "$mb:CHANGELOG.md" > "$work/base" 2>/dev/null; then
  cl_unreleased_emptied "$work/base" > "$work/base.emptied"
  cl_unreleased_entries "$work/base" > "$work/gone"
  if [[ -s $work/gone ]] && cmp -s "$work/base.emptied" "$work/new"; then
    migration=1
    while IFS= read -r line; do
      t=${line#"${line%%[![:space:]]*}"}
      if [[ $t == '### '* ]]; then continue; fi
      if grep -aqxF -- "$line" "$work/fragtext"; then continue; fi
      if ! reword_ok "$line"; then
        bad "an entry removed from [Unreleased] is in no added fragment:"
        bad "  $(printable "${line:0:80}")"
      fi
    done < "$work/gone"
  fi
fi

# Loads <p> at the merge base and at HEAD into $work/jb and $work/jh and succeeds when each copy
# has exactly one line for the version <key>. Returns 1 when a copy is missing and 2 when a copy
# has no such line (minified JSON) or more than one (duplicate key): both fail closed. Sets
# VL_NB and VL_NH to the line counts and VL_PAT to the line pattern. Shared by ver_same and
# json_check.
ver_load() {
  local p=$1 key=$2 pat
  pat='^[[:space:]]*"'$key'"[[:space:]]*:'
  VL_PAT=$pat
  git cat-file blob "$mb:$p" > "$work/jb" 2>/dev/null || return 1
  git cat-file blob "HEAD:$p" > "$work/jh" 2>/dev/null || return 1
  VL_NB=$(grep -cE "$pat" "$work/jb"); VL_NH=$(grep -cE "$pat" "$work/jh")
  [[ $VL_NB -eq 1 && $VL_NH -eq 1 ]] || return 2
}

# Succeeds when the version <key> line of <path> is the same at the merge base and at HEAD, with
# exactly one such line in each copy. Used in a normal PR, where the version never changes. A
# file new at HEAD has no earlier value and passes the value test.
ver_same() {
  local p=$1 key=$2
  if ! git cat-file -e "$mb:$p" 2>/dev/null; then return 0; fi
  ver_load "$p" "$key" || return 1
  grep -E "$VL_PAT" "$work/jb" > "$work/vb"
  grep -E "$VL_PAT" "$work/jh" > "$work/vh"
  cmp -s "$work/vb" "$work/vh"
}

if [[ $cl_seen -eq 0 || $migration -eq 1 ]]; then
  if [[ $n_del -gt 0 ]]; then
    bad "$n_del fragment deletion(s): only the release PR deletes fragments"
  fi
  while IFS=$'\t' read -r p st; do
    bad "$p: status $st; a version file may only be modified or added in a normal PR"
  done < "$work/verbad"
  while IFS= read -r p; do
    key=version
    if [[ $p == .claude/harness.json ]]; then key=templatecentral_version; fi
    ver_same "$p" "$key" || bad "$p: the \"$key\" value changes only in a release PR"
  done < "$work/verfiles"
  [[ $n_bad -eq 0 ]] || die "$n_bad invalid entry(ies)"
  [[ $n_added -ge 1 ]] \
    || die "no fragment added: create $CL_DIR/<slug>.<${CL_CATEGORIES// /|}>.md ($CL_DIR/README.md)"
  echo "changelog-check: ok ($n_added fragment(s) added)"
  exit 0
fi

echo "changelog-check: CHANGELOG.md is in the diff, so this PR must be a release PR" >&2
cat "$work/relq" >&2
n_rel=$(wc -l < "$work/relq" | tr -d ' ')
if [[ $cl_status != M || ( $cl_mode != 100644 && $cl_mode != 100755 ) ]]; then
  rel 1 "CHANGELOG.md must be modified in place as a file (status $cl_status, mode $cl_mode)"
fi
if [[ $es -ne 0 ]]; then rel 6 "CHANGELOG.md at HEAD has no '## [Unreleased]' heading"; fi
if [[ -s $work/entries ]]; then
  rel 6 "CHANGELOG.md at HEAD has entries under '## [Unreleased]'"
fi
[[ $n_bad -eq 0 && $n_rel -eq 0 ]] \
  || die "not a valid release PR ($n_rel release rule failure(s), $n_bad invalid entry(ies))"

# Rule 2: the deleted set equals the merge-base set. Rule 6: no entry at the merge base.
git ls-tree -r -z --name-only "$mb" -- "$CL_DIR" > "$work/basels" \
  || die "cannot list $CL_DIR/ at the merge base"
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
cmp -s "$work/baseset.s" "$work/deleted.s" \
  || rel 2 "deleted fragments differ from the merge-base set (all must be folded, none left)"
git cat-file blob "$mb:CHANGELOG.md" > "$work/base" 2>/dev/null \
  || die "CHANGELOG.md is missing at the merge base"
cl_unreleased_entries "$work/base" > "$work/baseentries"; bs=$?
[[ $bs -eq 0 ]] || rel 6 "CHANGELOG.md at the merge base has no '## [Unreleased]' heading"
[[ ! -s $work/baseentries ]] \
  || rel 6 "CHANGELOG.md at the merge base has entries under '## [Unreleased]'"
[[ $n_rel -eq 0 ]] || die "not a valid release PR ($n_rel release rule failure(s))"

# Rule 4: the heading.
heading=$(awk '/^## \[Unreleased\]/ { u = 1; next } u && /^## \[/ { print; exit }' "$work/new")
re_h='^## \[([0-9]+\.[0-9]+\.[0-9]+)\] — ([0-9]{4}-[0-9]{2}-[0-9]{2})$'
if [[ ! $heading =~ $re_h ]]; then
  shown=$(printable "$heading")
  rel 4 "the top release heading must be '## [N.N.N] — YYYY-MM-DD', got '$shown'"
  die "not a valid release PR"
fi
version=${BASH_REMATCH[1]} date=${BASH_REMATCH[2]}

# Succeeds when version $1 is greater than $2 (N.N.N, compared as numbers).
semver_gt() {
  local a1 a2 a3 b1 b2 b3
  read -r a1 a2 a3 <<< "${1//./ }"
  read -r b1 b2 b3 <<< "${2//./ }"
  if (( 10#$a1 != 10#$b1 )); then (( 10#$a1 > 10#$b1 )); return; fi
  if (( 10#$a2 != 10#$b2 )); then (( 10#$a2 > 10#$b2 )); return; fi
  (( 10#$a3 > 10#$b3 ))
}

# Rules 3 and 4 for one version file: json_check <path> <key>. One version line in each copy,
# the copies equal once the version value is masked, new version equals the heading and is
# greater than the old one.
json_check() {
  local p=$1 key=$2 vb vh rc
  ver_load "$p" "$key"; rc=$?
  if [[ $rc -eq 1 ]]; then rel 3 "$p: missing at the merge base or at HEAD"; return; fi
  if [[ $rc -eq 2 ]]; then
    rel 3 "$p: needs exactly one \"$key\" line in each copy (merge base $VL_NB, HEAD $VL_NH)"
    return
  fi
  local mask='s/^\([[:space:]]*"'$key'"[[:space:]]*:[[:space:]]*\)"[0-9][0-9.]*"/\1"V"/'
  sed "$mask" "$work/jb" > "$work/jb.m"; sed "$mask" "$work/jh" > "$work/jh.m"
  cmp -s "$work/jb.m" "$work/jh.m" \
    || { rel 3 "$p: differs from the merge base by more than the \"$key\" value"; return; }
  local ex='s/^[[:space:]]*"'$key'"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p'
  vb=$(sed -n "$ex" "$work/jb"); vh=$(sed -n "$ex" "$work/jh")
  if [[ $vh != "$version" ]]; then
    rel 4 "$p \"$key\" '$vh' does not equal the heading version $version"; return
  fi
  [[ -n $vb ]] || { rel 4 "$p: the merge-base \"$key\" is not N.N.N"; return; }
  semver_gt "$vh" "$vb" || rel 4 "$p \"$key\" $vh is not greater than the merge-base $vb"
}
json_check .claude-plugin/plugin.json version
json_check .claude/harness.json templatecentral_version
[[ $n_rel -eq 0 ]] || die "not a valid release PR"

# Rule 5: replay the assemble on the merge-base tree.
mkdir "$work/replay" || die "mkdir failed"
git archive "$mb" CHANGELOG.md "$CL_DIR" | tar -x -C "$work/replay" \
  || die "cannot materialise the merge-base tree"
git -C "$work/replay" init -q || die "git init failed"
asm="$here/changelog-assemble.sh"
if ! (cd "$work/replay" && bash "$asm" "$version" "$date") > "$work/replay.log" 2>&1; then
  cat "$work/replay.log" >&2
  rel 5 "changelog-assemble.sh refuses the merge-base tree"
  die "not a valid release PR"
fi
if ! cmp -s "$work/replay/CHANGELOG.md" "$work/new"; then
  rel 5 "CHANGELOG.md differs from the changelog-assemble.sh replay of the merge base"
  die "not a valid release PR"
fi
nfold=$(wc -l < "$work/deleted" | tr -d ' ')
echo "changelog-check: ok (release PR $version: replay matches, $nfold fragment(s) folded)"
