#!/usr/bin/env bash
# scripts/changelog-check.test.sh — changelog-check.sh passes a clean PR and fails each planted
#   defect.
# Each case builds a scratch repo: main holds CHANGELOG.md and changelog.d/README.md, branch pr
#   holds the change.
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
# run <name> <want rc> [msg fragment] [text that must be absent]: run the check in $R against main.
run() {
  local out rc
  out=$(cd "$R" && bash "$CHECK" "${BASE:-main}" 2>&1); rc=$?
  if [[ $rc -ne $2 ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc: $out"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — output lacks '$3': $out"
  elif [[ -n "${4:-}" && "$out" == *"$4"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — output has '$4': $out"
  else PASS=$((PASS + 1)); fi
}

mk control; frag good-thing.added.md; commit f
run "control: one valid fragment" 0 "ok"

# runq <name> <want rc> [msg fragment]: like run, and the output has no "release rule" text.
runq() { run "$1" "$2" "${3:-}" "release rule"; }

mk categories; for c in added changed removed fixed security; do frag "x-$c.$c.md"; done; commit f
run "all four categories" 0

mk none; echo x > "$R/other.txt"; commit f
run "no fragment added" 1 "no fragment added"

mk empty-pr; git -C "$R" commit -q --allow-empty -m e
run "empty diff" 1 "no fragment added"

mk badcat; frag a.bogus.md; commit f
run "unknown category" 1 "name must be"

mk emptyfile; : > "$R/changelog.d/a.added.md"; commit f
run "empty fragment" 1 "no bullet line"

mk blank; printf '  \n\n\t\n' > "$R/changelog.d/a.added.md"; commit f
run "whitespace-only fragment" 1 "no bullet line"

mk nobullet; printf 'just words\n' > "$R/changelog.d/a.added.md"; commit f
run "no bullet line" 1 "breaks the rule"

mk emptybullet; printf -- '- \n' > "$R/changelog.d/a.added.md"; commit f
run "bullet with no text" 1 "breaks the rule"

mk fence1; printf -- '- ok\n  ```\n' > "$R/changelog.d/a.added.md"; commit f
run "indented code fence in a fragment" 1 "breaks the rule"
mk fence2; printf -- '- ok\n\t~~~\n' > "$R/changelog.d/a.added.md"; commit f
run "indented tilde fence in a fragment" 1 "breaks the rule"
mk quiet; frag bad.bogus.md; commit f
runq "normal PR with a bad fragment prints no release rule text" 1

mk heading2; printf -- '- ok\n  # H\n' > "$R/changelog.d/a.added.md"; commit f
run "indented heading in a fragment" 1 "breaks the rule"
mk contok; printf -- '- ok\n  continued text\n- two\n' > "$R/changelog.d/a.added.md"; commit f
run "indented continuation text is fine" 0

mk bfence; printf -- '- ```js\n' > "$R/changelog.d/a.added.md"; commit f
run "bullet text starting with a code fence" 1 "breaks the rule"
mk bhead; printf -- '- # H\n' > "$R/changelog.d/a.added.md"; commit f
run "bullet text starting with a heading mark" 1 "breaks the rule"
mk bhead2; printf -- '- ok\n- # H\n' > "$R/changelog.d/a.added.md"; commit f
run "second bullet starting with a heading mark" 1 "breaks the rule"
mk nfence; printf -- '- ok\n  - ~~~\n' > "$R/changelog.d/a.added.md"; commit f
run "nested bullet starting with a tilde fence" 1 "breaks the rule"
mk rule1; printf -- '- ok\n  ---\n' > "$R/changelog.d/a.added.md"; commit f
run "lone --- continuation line" 1 "breaks the rule"
mk rule2; printf -- '- ok\n===\n' > "$R/changelog.d/a.added.md"; commit f
run "lone === line" 1 "breaks the rule"
mk rule3; printf -- '- ok\n  ===\n' > "$R/changelog.d/a.added.md"; commit f
run "indented === line" 1 "breaks the rule"
mk rule4; printf -- '- ---\n' > "$R/changelog.d/a.added.md"; commit f
run "bullet whose text is ---" 1 "breaks the rule"
mk inline; printf -- '- use \x60x\x60 and a - b, see #12 and --- inside text\n  - nested --flag\n' > "$R/changelog.d/a.added.md"; commit f
run "inline backticks, #, --- inside text are fine" 0

# Line grammar: a line is valid only as "- text", then "  - text" or "  text" (two spaces). Text
# starts from a closed set. Bodies below use printf %b; \x60 is a backtick.
n=0
while IFS= read -r body; do
  n=$((n + 1)); mk "rej$n"; printf -- '%b\n' "$body" > "$R/changelog.d/a.added.md"; commit f
  run "fragment body rejected: $body" 1 "breaks the rule"
done <<'LIST'
> # x
- > # x
- ok\n  > # x
- ok\n  > quoted text
- x\n  =
- x\n  --
- x\n  -
- x\n  ---
- <h2>y</h2>
- ok\n  <h2>y</h2>
- ok text <h2>y</h2>
- ok text </div>
- ok \x60unclosed <h2>y</h2>
- use <b>bold</b>
- - \x60\x60\x60js
- - # x
- - - ~~~
- ok\n  - - - # x
- ***
- ___
- - -
- * * *
- ok\n  * * *
- ok\n    _ _ _
- ok\n***
- ok\n  - ***
- ok\n  ----
- ok\n  = = =
- + # x
- * - + # x
- 1. # x
- ok\n  + # x
- ok\n  1) # x
- + \x60\x60\x60js
- 2. ~~~
- + ***
- ok\n1. # x
- ok\n  1. # x
- 12) numbered item
- --flag is new
- **bold** text
- _italic_ text
- + plus marker item
- ok\n  + nested plus item
- ok\n  2) nested numbered item
- + #96 fixed the thing
- ok\n  ** bold: more
- ok\n  -- two dashes only
- ok\n  | table | row |
- ok\n  ~~~
- ok\n\t~~~
- ok\n  \x60\x60\x60
- \x60\x60\x60js
- ok\n   three-space line
- ok\n    four-space line
-   extra space after the dash
- ok\n  (
- ok\n  "
- \x60
- #
- # H
- #x not a reference
- ok\n- # H
- ok\n  # H
- ok\n  - # H
- ok\n  - > # x
- ok\n  - <h2>y</h2>
1. numbered first line
+ plus first line
1) paren first line
* star first line
+ # x
- ok\n+ plus bullet
- ok\n3. numbered bullet
- ok\n1. # x
LIST
# Controls: every allowed first character, as bullet, nested bullet and continuation.
n=0
while IFS= read -r body; do
  n=$((n + 1)); mk "keep$n"; printf -- '%b\n' "$body" > "$R/changelog.d/a.added.md"; commit f
  run "control, fragment body accepted: $body" 0
done <<'LIST'
- letter first
- 3 - 2 = 1
- \x60code\x60 first
- [link](#x) first
- (paren) first
- "quoted" first
- 'single quoted' first
- #96 fixed the thing
- ok\n  letter continuation
- ok\n  3 digit continuation
- ok\n  \x60code\x60 continuation
- ok\n  [link] continuation
- ok\n  (paren) continuation
- ok\n  "quoted" continuation
- ok\n  'quoted' continuation
- ok\n  #12 continuation
- ok\n  - nested letter
- ok\n  - nested \x60code\x60
- ok\n  - nested #12
- ok\n\n- blank line between bullets
- ok\n  - nested - - dash text
- see #12, a - b and --- inside text\n  - nested --flag
- use \x60<h2>\x60 and \x60</div>\x60 in text
- a < b and 3 <4 and <3 hearts
- ok\n  text with \x60<b>\x60 inside\n  more text
- ok   trailing spaces   
LIST

mk q-frag; frag a.added.md; commit f
runq "normal PR adding a fragment prints no release rule text" 0
mk q-readme; frag a.added.md; echo "- x" > "$R/changelog.d/README.md"; commit f
runq "normal PR adding a fragment and editing changelog.d/README.md prints no release rule text" 0
mk q-del; git -C "$R" checkout -q main; frag old.added.md; commit old; git -C "$R" checkout -q -b pr2
git -C "$R" rm -q changelog.d/old.added.md; frag a.added.md; commit f
runq "normal PR deleting another PR's fragment is refused" 1 "only the release PR deletes fragments"
mk q-del-ctl; git -C "$R" checkout -q main; frag old.added.md; commit old; git -C "$R" checkout -q -b pr2
frag a.added.md; commit f
runq "control: normal PR adding a fragment beside an existing one" 0
mk q-del-only; git -C "$R" checkout -q main; frag old.added.md; commit old; git -C "$R" checkout -q -b pr2
git -C "$R" rm -q changelog.d/old.added.md; commit f
runq "normal PR that only deletes a fragment" 1 "only the release PR deletes fragments"
PJN=.claude-plugin/plugin.json; HJN=.claude/harness.json
mk v-ctl; frag a.added.md; printf '{\n  "name": "x",\n  "description": "d",\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit f
runq "control: normal PR edits plugin.json but not the version" 0
mk v-plugin; frag a.added.md; printf '{\n  "name": "x",\n  "version": "1.0.1"\n}\n' > "$R/$PJN"; commit f
runq "normal PR bumps plugin.json version" 1 "\"version\" value changes only in a release PR"
mk v-harness; frag a.added.md; printf '{\n  "templatecentral_version": "1.0.1"\n}\n' > "$R/$HJN"; commit f
runq "normal PR bumps harness.json version" 1 "\"templatecentral_version\" value changes only in a release PR"
mk v-dup; frag a.added.md; printf '{\n  "name": "x",\n  "version": "1.0.0",\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit f
runq "normal PR adds a second version line" 1 "\"version\" value changes only in a release PR"
mk v-min; frag a.added.md; printf '{"name":"x","version":"1.0.0"}\n' > "$R/$PJN"; commit f
runq "normal PR: minified plugin.json fails closed" 1 "\"version\" value changes only in a release PR"
mk v-dup2; frag a.added.md; printf '{\n  "version": "1.0.0",\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit f
runq "normal PR: duplicate version key, value unchanged, fails closed" 1 "\"version\" value changes only in a release PR"
mk v-dupbase; git -C "$R" checkout -q main; printf '{\n  "name": "x",\n  "version": "1.0.0",\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit dup
git -C "$R" checkout -q -b pr2; frag a.added.md; printf '{\n  "name": "y",\n  "version": "1.0.0",\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit f
runq "normal PR: duplicate version key at the base and at HEAD fails closed" 1 "\"version\" value changes only in a release PR"
mk v-del; frag a.added.md; git -C "$R" rm -q "$HJN"; commit f
runq "normal PR deletes harness.json (status D)" 1 "status D"
mk v-typ; frag a.added.md; rm "$R/$PJN"; ln -s -- ../README.md "$R/$PJN"; commit f
runq "normal PR replaces plugin.json with a symlink (status T)" 1 "status T"
mk v-ctl2; frag a.added.md; printf '{\n  "name": "x",\n  "z": 1,\n  "version": "1.0.0"\n}\n' > "$R/$PJN"; commit f
runq "control: normal PR edits plugin.json beside the version" 0

mk trailnl; frag $'a.added.md\n'; commit f
run "name with a trailing newline" 1 "name must be"

mk heading; printf -- '- ok\n## [9.9.9] — fake\n' > "$R/changelog.d/a.added.md"; commit f
run "heading injected after a bullet" 1 "breaks the rule"

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
run "fragment added then deleted in the PR" 1 "no fragment added"

mk readme; echo "- x" > "$R/changelog.d/README.md"; commit f
run "README.md edit does not count" 1 "no fragment added"

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

# sub <file> <sed expr>: in-place sed that works on BSD and GNU sed.
sub() { sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

# Unreleased rule. Base holds entries under [Unreleased]; a migration PR moves them to fragments.
UNREL_BASE=$'# Changelog\n\n## [Unreleased]\n\n### Added\n- one\n  - nested\n- two\n\n### Fixed\n- three\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n'
EMPTIED=$'# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n'
# mkunrel <name>: base commit on main has entries under [Unreleased]; branch pr2 is checked out.
mkunrel() {
  mk "$1"; git -C "$R" checkout -q main
  printf '%s' "$UNREL_BASE" > "$R/CHANGELOG.md"; commit entries; git -C "$R" checkout -q -b pr2
}
migfrags() {
  printf -- '- one\n  - nested\n' > "$R/changelog.d/one.added.md"
  printf -- '- two\n' > "$R/changelog.d/two.added.md"
  printf -- '- three\n' > "$R/changelog.d/three.fixed.md"
}

mkunrel unrel-normal; frag a.added.md; commit f
run "normal PR while [Unreleased] still has entries" 1 "entries under '## [Unreleased]'"
mkunrel unrel-normal-nofrag; echo x > "$R/other.txt"; commit f
run "normal PR with no fragment while [Unreleased] has entries" 1 "entries under '## [Unreleased]'"
mk unrel-head; frag a.added.md
printf '# Changelog\n\n## [Unreleased]\n\n- sneaky\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"; commit f
run "PR adds an [Unreleased] entry by hand" 1 "release rule 6"
mk unrel-nohead; frag a.added.md
printf '# Changelog\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"; commit f
run "PR removes the [Unreleased] heading" 1 "release rule 6"

mkunrel mig-ok; migfrags; printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
runq "control: migration PR moves every [Unreleased] entry into fragments" 0
mkunrel mig-lost; printf -- '- one\n  - nested\n' > "$R/changelog.d/one.added.md"; printf -- '- two\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR drops one entry" 1 "in no added fragment"
mkunrel mig-reword; migfrags; printf -- '- two reworded\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR rewords an entry" 1 "in no added fragment"
mkunrel mig-bt; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two in \x60<version>\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
runq "migration PR wraps a < in backticks, same words" 0
mkunrel mig-bt2; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two on \x60<version>\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR changes a word beside the backticks" 1 "in no added fragment"
mkunrel mig-edit; migfrags; printf '%s' "${EMPTIED/- old/- old2}" > "$R/CHANGELOG.md"; commit f
run "migration PR also edits a released line" 1 "release rule"
mkunrel mig-nofrag; printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "CHANGELOG.md emptied with no fragment added" 1 "release rule"
mkunrel mig-partial; migfrags; printf '%s' "$UNREL_BASE" | grep -vxF -- '- two' > "$R/CHANGELOG.md"; commit f
run "migration PR that leaves entries under [Unreleased]" 1 "release rule"

mkunrel mig-ver; migfrags; printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"
printf '{\n  "name": "x",\n  "version": "2.0.0"\n}\n' > "$R/$PJN"; commit f
runq "migration PR bumps plugin.json version" 1 "\"version\" value changes only in a release PR"

# Release PR: base holds two fragments; the branch runs the real assemble and bumps the version
#   files.
# mkrel <name> [old version] [new version]: base version files hold the old version.
ASM="$REPO/scripts/changelog-assemble.sh"
PJ=.claude-plugin/plugin.json; HJ=.claude/harness.json
mkrel() {
  local old=${2:-1.0.0} new=${3:-1.1.0}
  mk "$1"; git -C "$R" checkout -q main
  if [[ $old != 1.0.0 ]]; then sub "$R/$PJ" "s/1\\.0\\.0/$old/"; sub "$R/$HJ" "s/1\\.0\\.0/$old/"; fi
  frag a.added.md; frag b.fixed.md; commit frags; git -C "$R" checkout -q -b rel
  (cd "$R" && bash "$ASM" "$new" 2026-03-04 >/dev/null 2>&1) || echo "FAIL: setup — assemble failed in $1"
  sub "$R/$PJ" "s/$old/$new/"; sub "$R/$HJ" "s/$old/$new/"
}

mkrel rel-min; commit rel
run "control: release PR with only the two version files" 0 "release PR 1.1.0"
mkrel rel-semver 1.9.0 1.10.0; commit rel
run "control: 1.9.0 to 1.10.0 compares as numbers" 0 "release PR 1.10.0"

mkrel rel-readme; printf 'v1.1.0\n' > "$R/README.md"; commit rel
run "release PR editing README.md" 1 "release rule 3"
mkrel rel-final; printf 'v1.1.0\n' > "$R/skills/scaffold/shared/harness-kit-finalize.md"; commit rel
run "release PR editing the finalize marker" 1 "release rule 3"
mkrel rel-golden; printf 'h2\n' > "$R/tests/golden/nextjs-github.sha256"; commit rel
run "release PR regenerating a golden hash" 1 "release rule 3"
mkrel rel-script; mkdir -p "$R/scripts"; echo '# x' > "$R/scripts/changelog-assemble.sh"; commit rel
run "release PR editing the assemble script" 1 "release rule 3"
mkrel rel-wf; mkdir -p "$R/.github/workflows"; echo 'x: 1' > "$R/.github/workflows/changelog-fragment.yml"; commit rel
run "release PR editing the workflow" 1 "release rule 3"
mkrel rel-extra; echo x > "$R/extra.txt"; commit rel
run "release PR touching a path outside the allow-list" 1 "release rule 3"

mkrel rel-xkey; printf '{\n  "name": "x",\n  "extra": "1",\n  "version": "1.1.0"\n}\n' > "$R/$PJ"; commit rel
run "plugin.json with an extra key" 1 "release rule 3"
mkrel rel-xkey2; printf '{\n  "extra": "1",\n  "templatecentral_version": "1.1.0"\n}\n' > "$R/$HJ"; commit rel
run "harness.json with an extra key" 1 "release rule 3"
mkrel rel-dup; printf '{\n  "name": "x",\n  "version": "1.1.0",\n  "version": "1.1.0"\n}\n' > "$R/$PJ"; commit rel
run "plugin.json with a duplicate version line" 1 "needs exactly one \"version\" line"
mkrel rel-dup2; printf '{\n  "templatecentral_version": "1.1.0",\n  "templatecentral_version": "1.0.0"\n}\n' > "$R/$HJ"; commit rel
run "harness.json with a duplicate version line" 1 "needs exactly one \"templatecentral_version\" line"
mkrel rel-form; sub "$R/$PJ" 's/"version": "1.1.0"/"version":"1.1.0"/'; commit rel
run "plugin.json version line reformatted" 1 "release rule 3"
mkrel rel-lower 1.2.0 1.1.0; commit rel
run "new version lower than the merge-base version" 1 "not greater"
mkrel rel-equal 1.1.0 1.1.0; commit rel
run "new version equal to the merge-base version" 1 "not greater"
mkrel rel-hlower; sub "$R/$HJ" 's/1\.1\.0/1.0.0/'; commit rel
run "harness.json version not bumped" 1 "release rule"
mkrel rel-pv; sub "$R/$PJ" 's/1\.1\.0/1.0.0/'; commit rel
run "plugin.json version not bumped" 1 "release rule"

# Abuse: a normal PR pretends to be a release. Each case names the rule that stops it.
mk abuse-a; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; printf '## [9.9.9] — fake\n- evil\n' >> "$R/CHANGELOG.md"; commit abuse
run "abuse: delete a fragment, append a fake release at the end" 1 \
  "release rule 4 failed: .claude-plugin/plugin.json \"version\" 1.0.0 is not greater than the merge-base 1.0.0"
mk abuse-b; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; sub "$R/CHANGELOG.md" 's/\[1.0.0\] —/[1.0.0] REWRITTEN —/'; commit abuse
run "abuse: delete a fragment and rewrite the old heading" 1 \
  "release rule 4 failed: the top release heading must be '## [N.N.N] — YYYY-MM-DD', got '## [1.0.0] REWRITTEN — 2026-01-01'"
mk abuse-c; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md; printf '\n## [1.1.0] — 2026-03-04\n- evil\n' >> "$R/CHANGELOG.md"
sub "$R/$PJ" 's/1\.0\.0/1.1.0/'; sub "$R/$HJ" 's/1\.0\.0/1.1.0/'; commit abuse
run "abuse: versions bumped, fake release appended below the old one" 1 \
  "release rule 4 failed: .claude-plugin/plugin.json \"version\" '1.1.0' does not equal the heading version 1.0.0"
mk abuse-d; git -C "$R" checkout -q main; frag a.added.md; commit frag; git -C "$R" checkout -q -b abuse
git -C "$R" rm -q changelog.d/a.added.md
printf '# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.1.0] — 2026-03-04\n\n### Added\n- evil\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"
sub "$R/$PJ" 's/1\.0\.0/1.1.0/'; sub "$R/$HJ" 's/1\.0\.0/1.1.0/'; commit abuse
run "abuse: hand-written 1.1.0 section with the versions bumped" 1 \
  "release rule 5 failed: CHANGELOG.md differs from the changelog-assemble.sh replay of the merge base"
# Only the replay can catch a real release plus a fake older section appended at the end.
mkrel abuse-e; printf '\n## [0.9.0] — 2025-01-01\n\n### Added\n- evil\n' >> "$R/CHANGELOG.md"; commit rel
run "abuse: genuine release plus a fake section appended, versions consistent" 1 \
  "release rule 5 failed: CHANGELOG.md differs from the changelog-assemble.sh replay of the merge base" "release rule 4"

mkrel rel-left; frag b.fixed.md; commit rel
run "release PR with one fragment left undeleted" 1 "release rule 2"
mkrel rel-add; frag c.added.md; commit rel
run "release PR that also adds a fragment" 1 "release rule 2"
mkrel rel-readme-del; git -C "$R" rm -q -f changelog.d/README.md; commit rel
run "release PR deleting changelog.d/README.md" 1 "release rule 2"
mkrel rel-byte; printf ' ' >> "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md one byte off the replay" 1 "release rule 5"
mkrel rel-history; sub "$R/CHANGELOG.md" 's/- old/- old REWRITTEN/'; commit rel
run "history line rewritten in a release PR" 1 "release rule 5"
mkrel rel-head; sub "$R/CHANGELOG.md" 's/^## \[1.1.0\] — /## [1.1.0] - /'; commit rel
run "heading with a hyphen instead of an em dash" 1 "release rule 4"
mkrel rel-head2; sub "$R/CHANGELOG.md" 's/^## \[1.1.0\]/## [1.1]/'; commit rel
run "heading version malformed" 1 "release rule 4"
mkrel rel-loc; sub "$R/CHANGELOG.md" 's/2026-03-04/2026-3-04/'; commit rel
LC_ALL=C run "malformed heading message keeps the em dash in the C locale" 1 "— 2026-3-04"

# Unreleased rule inside a release PR.
mkrel rel-unrel-head; printf '\n- late entry\n' >> "$R/CHANGELOG.md"
sub "$R/CHANGELOG.md" 's/^## \[Unreleased\]$/## [Unreleased]\n- late/'; commit rel
run "release PR leaves an entry under [Unreleased]" 1 "release rule"
mk rel-unrel-base; git -C "$R" checkout -q main; printf '%s' "$UNREL_BASE" > "$R/CHANGELOG.md"
frag a.added.md; commit base; git -C "$R" checkout -q -b rel; git -C "$R" rm -q changelog.d/a.added.md
printf '# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.1.0] — 2026-03-04\n\n### Added\n- a\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"
sub "$R/$PJ" 's/1\.0\.0/1.1.0/'; sub "$R/$HJ" 's/1\.0\.0/1.1.0/'; commit rel
run "release PR whose merge base still had [Unreleased] entries" 1 "release rule 6"

# Rule 1: status and mode of CHANGELOG.md.
mkrel rel-cldel; git -C "$R" rm -q -f CHANGELOG.md; commit rel
run "CHANGELOG.md deleted (status D)" 1 "release rule 1"
mkrel rel-clsym; git -C "$R" rm -q -f CHANGELOG.md; (cd "$R" && ln -s real.md CHANGELOG.md); commit rel
run "CHANGELOG.md changed to a symlink (status T, mode 120000)" 1 "release rule 1"
mk rel-cladd; git -C "$R" checkout -q main; git -C "$R" rm -q CHANGELOG.md; commit nocl; git -C "$R" checkout -q -b rel
printf '# Changelog\n\n## [Unreleased]\n\n---\n' > "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md added where the merge base had none (status A)" 1 "release rule 1"
mk rel-clt; git -C "$R" checkout -q main; git -C "$R" rm -q -f CHANGELOG.md; (cd "$R" && ln -s real.md CHANGELOG.md)
commit symcl; git -C "$R" checkout -q -b rel; git -C "$R" rm -q -f CHANGELOG.md
printf '# Changelog\n\n## [Unreleased]\n\n---\n' > "$R/CHANGELOG.md"; commit rel
run "CHANGELOG.md symlink replaced by a regular file (status T, mode 100644)" 1 "release rule 1"
mk rel-nofrag; echo "- entry" >> "$R/CHANGELOG.md"; commit rel
run "CHANGELOG edit with no fragments at the merge base" 1 "release rule"

echo "changelog-check.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
