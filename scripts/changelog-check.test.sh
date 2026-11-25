#!/usr/bin/env bash
# scripts/changelog-check.test.sh — changelog-check.sh passes a clean PR and fails each planted defect.
# Each case builds a scratch repo: main holds CHANGELOG.md and changelog.d/README.md, branch pr holds the change.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO/scripts/changelog-check.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/clchk.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0

# mk <name>: scratch repo on main, then branch pr checked out. Sets $R.
mk() {
  R="$T/$1"; mkdir -p "$R/changelog.d"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.com; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  printf '# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"
  printf '# fragments\n' > "$R/changelog.d/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm base
  git -C "$R" checkout -q -b pr
}
commit() { git -C "$R" add -A; git -C "$R" commit -qm "$1"; }
frag() { printf '%s\n' "- entry" > "$R/changelog.d/$1"; }
# run <name> <want rc> [msg fragment]: run the check in $R against main.
run() {
  local out rc
  out=$(cd "$R" && bash "$CHECK" "${BASE:-main}" 2>&1); rc=$?
  if [[ $rc -ne $2 ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc: $out"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — output lacks '$3': $out"
  else PASS=$((PASS + 1)); fi
}

mk control; frag good-thing.added.md; commit f
run "control: one valid fragment" 0 "ok"

mk categories; for c in added changed fixed security; do frag "x-$c.$c.md"; done; commit f
run "all four categories" 0

mk none; echo x > "$R/other.txt"; commit f
run "no fragment added" 1 "no changelog fragment"

mk empty-pr; git -C "$R" commit -q --allow-empty -m e
run "empty diff" 1 "no changelog fragment"

mk badcat; frag a.bogus.md; commit f
run "unknown category" 1 "name must be"

mk emptyfile; : > "$R/changelog.d/a.added.md"; commit f
run "empty fragment" 1 "needs a bullet"

mk blank; printf '  \n\n\t\n' > "$R/changelog.d/a.added.md"; commit f
run "whitespace-only fragment" 1 "needs a bullet"

mk nobullet; printf 'just words\n' > "$R/changelog.d/a.added.md"; commit f
run "no bullet line" 1 "needs a bullet"

mk emptybullet; printf -- '- \n' > "$R/changelog.d/a.added.md"; commit f
run "bullet with no text" 1 "needs a bullet"

mk heading; printf -- '- ok\n## [9.9.9] — fake\n' > "$R/changelog.d/a.added.md"; commit f
run "heading injected after a bullet" 1 "needs a bullet"

mk symlink; ln -s -- "- real" "$R/changelog.d/a.added.md"; commit f
run "symlink fragment" 1 "regular file"

mk subdir; mkdir "$R/changelog.d/sub"; frag sub/a.added.md; commit f
run "fragment in subdirectory" 1 "subdirectory"

mk badname1; frag Upper.added.md; commit f
run "uppercase name" 1 "name must be"
mk badname2; frag a.added.txt; commit f
run "wrong extension" 1 "name must be"
mk badname3; frag a.md; commit f
run "no category" 1 "name must be"
mk badname4; frag .added.md; commit f
run "empty slug" 1 "name must be"
mk badname5; frag "has space.added.md"; commit f
run "name with a space" 1 "name must be"
mk badname6; frag $'new\nline.added.md'; commit f
run "name with a newline" 1 "name must be"
mk badname7; frag a.added.md.bak; commit f
run "trailing suffix" 1 "name must be"

mk clmod; frag a.added.md; echo "- sneaky" >> "$R/CHANGELOG.md"; commit f
run "CHANGELOG.md edited with a fragment" 1 "CHANGELOG.md is modified"

mk clonly; echo "- sneaky" >> "$R/CHANGELOG.md"; commit f
run "CHANGELOG.md edited alone" 1 "CHANGELOG.md is modified"

mk addrm; frag a.added.md; commit f; git -C "$R" rm -q changelog.d/a.added.md; commit rm
run "fragment added then deleted in the PR" 1 "no changelog fragment"

mk readme; echo "- x" > "$R/changelog.d/README.md"; commit f
run "README.md edit does not count" 1 "no changelog fragment"

mk readme2; echo "- x" > "$R/changelog.d/README.md"; frag a.added.md; commit f
run "README.md edit beside a fragment is tolerated" 0

mk modfrag; git -C "$R" checkout -q main; frag old.added.md; commit old; git -C "$R" checkout -q -b pr2
echo "- more" >> "$R/changelog.d/old.added.md"; commit mod
BASE=main run "modifying an existing fragment is not an add" 1 "only adding"

mk nobase; frag a.added.md; commit f
BASE=nope run "missing base ref" 1 "not found"

mk nomb; frag a.added.md; commit f; git -C "$R" checkout -q --orphan lone; git -C "$R" rm -rqf . ; echo x > "$R/f"; commit orphan
run "no merge base" 1 "no merge base"

mk dashbase; frag a.added.md; commit f
BASE=--all run "base ref starting with a dash" 1 "usage"

# Release PR: fragments deleted, CHANGELOG.md edited. Base keeps the fragment.
mkrel() {
  mk "$1"; git -C "$R" checkout -q main
  frag a.added.md; frag b.fixed.md; commit frags; git -C "$R" checkout -q -b rel
  git -C "$R" rm -q changelog.d/a.added.md changelog.d/b.fixed.md
  printf -- '- entry\n' >> "$R/CHANGELOG.md"
}
mkrel rel-ok; commit rel
run "release PR passes" 0 "release PR"

mkrel rel-missing; sed -i.bak '$d' "$R/CHANGELOG.md"; rm "$R/CHANGELOG.md.bak"; echo "- other" >> "$R/CHANGELOG.md"; commit rel
run "release PR whose CHANGELOG lacks the fragment text" 1 "missing from CHANGELOG.md"

mkrel rel-extra; echo x > "$R/extra.txt"; commit rel
run "release PR touching another file" 1 "CHANGELOG.md is modified"

mkrel rel-add; frag c.added.md; commit rel
run "release PR that also adds a fragment" 1 "CHANGELOG.md is modified"

mk rel-nodel; echo "- entry" >> "$R/CHANGELOG.md"; commit rel
run "CHANGELOG edit with no fragment deleted is not a release PR" 1 "CHANGELOG.md is modified"

echo "changelog-check.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
