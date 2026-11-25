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
  mkdir -p "$R/.claude-plugin" "$R/.claude" "$R/tests/golden" "$R/skills/scaffold/shared"
  printf '{\n  "name": "x",\n  "version": "1.0.0"\n}\n' > "$R/.claude-plugin/plugin.json"
  printf '{\n  "templatecentral_version": "1.0.0"\n}\n' > "$R/.claude/harness.json"
  printf 'v1.0.0\n' > "$R/README.md"; printf 'v1.0.0\n' > "$R/skills/scaffold/shared/harness-kit-finalize.md"
  printf 'h1\n' > "$R/tests/golden/nextjs-github.sha256"
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

mk fence1; printf -- '- ok\n  ```\n' > "$R/changelog.d/a.added.md"; commit f
run "indented code fence in a fragment" 1 "needs a bullet"
mk fence2; printf -- '- ok\n\t~~~\n' > "$R/changelog.d/a.added.md"; commit f
run "indented tilde fence in a fragment" 1 "needs a bullet"
mk quiet; frag bad.bogus.md; commit f
out=$(cd "$R" && bash "$CHECK" main 2>&1)
if [[ "$out" == *"release rule"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: normal PR output mentions release rules: $out"; else PASS=$((PASS + 1)); fi

mk heading2; printf -- '- ok\n  # H\n' > "$R/changelog.d/a.added.md"; commit f
run "indented heading in a fragment" 1 "needs a bullet"
mk contok; printf -- '- ok\n  continued text\n- two\n' > "$R/changelog.d/a.added.md"; commit f
run "indented continuation text is fine" 0

mk trailnl; frag $'a.added.md\n'; commit f
run "name with a trailing newline" 1 "name must be"

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
run "CHANGELOG.md edited with a fragment" 1 "release rule 2"

mk clonly; echo "- sneaky" >> "$R/CHANGELOG.md"; commit f
run "CHANGELOG.md edited alone" 1 "release rule 2"

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

# Normal PR whose fragment changes type (T) or is a submodule (160000).
mk typechg; git -C "$R" checkout -q main; frag old.added.md; commit old; git -C "$R" checkout -q -b pr2
rm "$R/changelog.d/old.added.md"; ln -s -- "- x" "$R/changelog.d/old.added.md"; frag new.added.md; commit t
run "fragment type-changed to a symlink (status T)" 1 "status T"

mk submod; git -C "$R" update-index --add --cacheinfo "160000,$(git -C "$R" rev-parse HEAD),changelog.d/a.added.md"; git -C "$R" commit -qm s
run "fragment as a submodule (mode 160000)" 1 "regular file"

# Release PR: base holds two fragments; the branch runs the real assemble and bumps the version files.
ASM="$REPO/scripts/changelog-assemble.sh"
mkrel() {
  mk "$1"; git -C "$R" checkout -q main
  frag a.added.md; frag b.fixed.md; commit frags; git -C "$R" checkout -q -b rel
  (cd "$R" && bash "$ASM" 1.1.0 2026-03-04 >/dev/null 2>&1) || echo "FAIL: setup — assemble failed in $1"
  sed -i.bak 's/1\.0\.0/1.1.0/' "$R/.claude-plugin/plugin.json" "$R/.claude/harness.json"; rm -f "$R"/.claude*/*.bak
}
mkrel rel-ok
printf 'v1.1.0\n' > "$R/README.md"; printf 'v1.1.0\n' > "$R/skills/scaffold/shared/harness-kit-finalize.md"; printf 'h2\n' > "$R/tests/golden/nextjs-github.sha256"
commit rel
run "control: realistic release PR (version files, README, marker, golden)" 0 "release PR 1.1.0"

mkrel rel-min; commit rel
run "release PR with only the two version files" 0 "replay matches"

# Abuse: a normal PR pretends to be a release.
mk abuse-a; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; printf '## [9.9.9] — fake\n- evil\n' >> "$R/CHANGELOG.md"; echo '- a' >> "$R/CHANGELOG.md"; commit abuse
run "abuse: delete a fragment, append a fake release and the lines" 1 "release rule 5"
mk abuse-b; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; sed -i.bak 's/1.0.0 —/1.0.0 REWRITTEN —/' "$R/CHANGELOG.md"; rm "$R/CHANGELOG.md.bak"; echo '- a' >> "$R/CHANGELOG.md"; commit abuse
run "abuse: delete a fragment and rewrite history" 1 "release rule"
mk abuse-c; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; printf '\n## [1.1.0] — 2026-03-04\n- evil\n' >> "$R/CHANGELOG.md"
sed -i.bak 's/1\.0\.0/1.1.0/' "$R/.claude-plugin/plugin.json" "$R/.claude/harness.json"; rm -f "$R"/.claude*/*.bak; commit abuse
run "abuse: versions bumped, heading malformed position" 1 "release rule"

mkrel rel-left; frag b.fixed.md; commit rel
run "release PR with one fragment left undeleted" 1 "release rule 2"
mkrel rel-add; frag c.added.md; commit rel
run "release PR that also adds a fragment" 1 "release rule 2"
mkrel rel-readme-del; git -C "$R" checkout -q main -- changelog.d/README.md 2>/dev/null; git -C "$R" rm -q -f changelog.d/README.md; commit rel
run "release PR deleting changelog.d/README.md" 1 "release rule 2"
mkrel rel-extra; echo x > "$R/extra.txt"; commit rel
run "release PR touching a path outside the allow-list" 1 "extra.txt is not on the release allow-list"
mkrel rel-nested; mkdir -p "$R/tests/golden/sub"; echo x > "$R/tests/golden/sub/x.sha256"; commit rel
run "release PR with a nested golden path" 1 "release allow-list"
mkrel rel-allowadd; echo x > "$R/tests/golden/new.sha256"; commit rel
run "release PR adding an allow-listed file (status A)" 1 "may only be modified"
mkrel rel-byte; printf ' ' >> "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md one byte off the replay" 1 "release rule 5"
mkrel rel-history; sed -i.bak 's/- old/- old REWRITTEN/' "$R/CHANGELOG.md"; rm "$R/CHANGELOG.md.bak"; commit rel
run "history line rewritten in a release PR" 1 "release rule 5"
mkrel rel-head; sed -i.bak 's/^## \[1.1.0\] — /## [1.1.0] - /' "$R/CHANGELOG.md"; rm "$R/CHANGELOG.md.bak"; commit rel
run "heading with a hyphen instead of an em dash" 1 "release rule 4"
mkrel rel-head2; sed -i.bak 's/^## \[1.1.0\]/## [1.1]/' "$R/CHANGELOG.md"; rm "$R/CHANGELOG.md.bak"; commit rel
run "heading version malformed" 1 "release rule 4"
mkrel rel-pv; sed -i.bak 's/1\.1\.0/1.0.0/' "$R/.claude-plugin/plugin.json"; rm "$R"/.claude*/*.bak; commit rel
run "plugin.json version not bumped" 1 "plugin.json version"
mkrel rel-hv; sed -i.bak 's/1\.1\.0/1.0.0/' "$R/.claude/harness.json"; rm "$R"/.claude*/*.bak; commit rel
run "harness.json version not bumped" 1 "harness.json templatecentral_version"
mkrel rel-cldel; rm "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md deleted" 1 "release rule 1"
mkrel rel-clsym; printf 'x\n' > "$R/real.md"; rm "$R/CHANGELOG.md"; ln -s real.md "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md type-changed to a symlink" 1 "release rule 1"
mk rel-nofrag; echo "- entry" >> "$R/CHANGELOG.md"; commit rel
run "CHANGELOG edit with no fragments at the merge base" 1 "release rule 2"

echo "changelog-check.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
