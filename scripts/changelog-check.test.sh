#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures hold literal backticks on purpose
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

# The scratch base repo is built once; mk copies it, so a case costs a copy, not a git init.
BASE_REPO="$T/.base"; mkdir -p "$BASE_REPO/changelog.d"
git -C "$BASE_REPO" init -q -b main
git -C "$BASE_REPO" config user.email t@example.com; git -C "$BASE_REPO" config user.name t
git -C "$BASE_REPO" config commit.gpgsign false
printf '# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$BASE_REPO/CHANGELOG.md"
printf '# fragments\n' > "$BASE_REPO/changelog.d/README.md"
mkdir -p "$BASE_REPO/.claude-plugin" "$BASE_REPO/.claude" "$BASE_REPO/tests/golden" "$BASE_REPO/skills/scaffold/shared"
printf '{\n  "name": "x",\n  "version": "1.0.0"\n}\n' > "$BASE_REPO/.claude-plugin/plugin.json"
printf '{\n  "templatecentral_version": "1.0.0"\n}\n' > "$BASE_REPO/.claude/harness.json"
printf 'v1.0.0\n' > "$BASE_REPO/README.md"; printf 'v1.0.0\n' > "$BASE_REPO/skills/scaffold/shared/harness-kit-finalize.md"
printf 'h1\n' > "$BASE_REPO/tests/golden/nextjs-github.sha256"
git -C "$BASE_REPO" add -A; git -C "$BASE_REPO" commit -qm base
git -C "$BASE_REPO" checkout -q -b pr

# mk <name>: scratch repo on main, then branch pr checked out. Sets $R.
mk() { R="$T/$1"; cp -R "$BASE_REPO" "$R"; }
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
run "whitespace-only fragment" 1 "breaks the rule"

mk nobullet; printf 'just words\n' > "$R/changelog.d/a.added.md"; commit f
run "no bullet line" 1 "breaks the rule"

mk nonl; printf -- '- ok' > "$R/changelog.d/a.added.md"; commit f
run "no newline at the end" 1 "breaks the rule"
mk spaces; printf '  \n\n' > "$R/changelog.d/a.added.md"; commit f
run "spaces-only fragment" 1 "breaks the rule"

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
# One repo holds every body as its own fragment; the check reports each bad fragment by name.
mk rej-all; n=0; bodies=()
while IFS= read -r body; do
  n=$((n + 1)); bodies[n]=$body; printf -- '%b\n' "$body" > "$R/changelog.d/rej$n.added.md"
done <<'LIST'
> # x
- = x
- ok\n  = x
- < x
- ok\n  < x
- ok\n   three-space continuation
  two-space first line
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
- a\r## [9.9.9] — 2099-01-01\r- b
- a\r\n- b\r
- a\r  ---
- a\r> x
- a\r<script>
- a\0b
- ok\ttab
- ok\x1b[0m escape
- ok\x7f del
- x \\\x60<b>\\\x60 y
- a \x60 b\n  c \x60<script>\x60 d \x60 e
- a \x60b
- a \x60\x60b\x60\x60 c
- a <!-- b\n  c -->
- a <?x ?>
- a <![CDATA[
- [x]: http://example.invalid
- [Unreleased]: http://example.invalid
- ok\n  [x]: http://example.invalid
- ok\n  - [x]: http://example.invalid
- ok\n\n  [x]: http://example.invalid
- ok\n\n- b
- ok\n  \n- b
- see [t](http://example.invalid)
- see [t][ref]
- b\x60c) \x60<i>\x60 d\x60 e
LIST
commit f
out=$(cd "$R" && bash "$CHECK" main 2>&1); rc=$?
if [[ $rc -eq 1 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: rejected bodies: want rc 1, got $rc"; fi
for i in $(seq 1 "$n"); do
  if grep -qF -- "rej$i.added.md: " <<< "$out" && grep -F -- "rej$i.added.md: " <<< "$out" | grep -qF "breaks the rule"; then
    PASS=$((PASS + 1))
  else FAIL=$((FAIL + 1)); echo "FAIL: fragment body rejected: ${bodies[$i]}"; fi
done
# Controls: every allowed first character, as bullet, nested bullet and continuation.
mk keep-all; n=0; bodies=()
while IFS= read -r body; do
  n=$((n + 1)); bodies[n]=$body; printf -- '%b\n' "$body" > "$R/changelog.d/keep$n.added.md"
done <<'LIST'
- letter first
- 3 - 2 = 1
- \x60code\x60 first
- [link] first
- use \x60<b>\x60 in a span
- two \x60a\x60 and \x60<b>\x60 spans
- ok\n  - nested \x60x\x60
- \x60arr[0](1)\x60 inside a span
- see #96 and (a) "b" 'c'
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
- ok\n  - nested - - dash text
- see #12, a - b and --- inside text\n  - nested --flag
- use \x60<h2>\x60 and \x60</div>\x60 in text
- a < b and 3 <4 and <3 hearts
- ok\n  text with \x60<b>\x60 inside\n  more text
- ok   trailing spaces   
LIST
commit f
out=$(cd "$R" && bash "$CHECK" main 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then PASS=$((PASS + n)); else
  FAIL=$((FAIL + 1)); echo "FAIL: control bodies accepted together: rc $rc: $out"; fi

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
mkunrel mig-bt3; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two `a` in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two a in \x60<version>\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR drops a code span of the removed line" 1 "in no added fragment"
mkunrel mig-bt4; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two `a b` in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two \x60a\x60 b in \x60<version>\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR moves the edge of a code span" 1 "in no added fragment"
mkunrel mig-bt5; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two `a` in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two \x60a\x60 in \x60<version>\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
runq "migration PR keeps a span and wraps a < in backticks" 0
mkunrel mig-bt6; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two `a in <version> here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two \x60a in <version> here\x60\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR rewords a line with an odd backtick count" 1 "in no added fragment"
mkunrel mig-bold; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- **two** words/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two words\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
runq "migration PR drops bold markers from a removed line" 0
mkunrel mig-bold2; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- **two** words/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two other words\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR changes a word beside the bold markers" 1 "in no added fragment"
mkunrel mig-bold3; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two words/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two **words**\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
runq "migration PR adds bold markers to a removed line" 0
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
  if [[ $old == 1.0.0 && $new == 1.1.0 && -d $T/.rel ]]; then R="$T/$1"; cp -R "$T/.rel" "$R"; return; fi
  mk "$1"; git -C "$R" checkout -q main
  if [[ $old != 1.0.0 ]]; then sub "$R/$PJ" "s/1\\.0\\.0/$old/"; sub "$R/$HJ" "s/1\\.0\\.0/$old/"; fi
  frag a.added.md; frag b.fixed.md; commit frags; git -C "$R" checkout -q -b rel
  (cd "$R" && bash "$ASM" "$new" 2026-03-04 >/dev/null 2>&1) || echo "FAIL: setup — assemble failed in $1"
  sub "$R/$PJ" "s/$old/$new/"; sub "$R/$HJ" "s/$old/$new/"
  if [[ $old == 1.0.0 && $new == 1.1.0 ]]; then cp -R "$R" "$T/.rel"; fi
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

# Round 7. Content rules called straight from the lib, so the caller's locale is under test.
# cok <name> <want rc> <printf %b body> [msg fragment]: cl_content_ok on a scratch file, in a
# fresh bash that only sources the lib, with the environment words in CENV applied.
CENV=()
cok() {
  local f="$T/cok.md" out rc
  printf '%b' "$3" > "$f"
  out=$(env ${CENV[@]+"${CENV[@]}"} bash -c 'source "$1"; cl_content_ok "$2"' _ \
    "$REPO/scripts/changelog-lib.sh" "$f" 2>&1); rc=$?
  if [[ $rc -ne $2 ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — want rc $2, got $rc: $out"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $1 — lacks '$4': $out"
  else PASS=$((PASS + 1)); fi
}
# Locale: same verdict under each locale setting, for a line with an em dash and an accent.
OKB='- caf\xc3\xa9 \xe2\x80\x94 ok\n'; CRB='- caf\xc3\xa9 \xe2\x80\x94 ok\r\n'
for loc in "LANG=en_US.UTF-8" "LC_ALL=en_US.UTF-8" "LANG=C"; do
  CENV=(-u LC_ALL "$loc"); [[ $loc == LC_ALL=* ]] && CENV=("$loc")
  cok "locale $loc accepts em dash and accent" 0 "$OKB"
  cok "locale $loc rejects CR" 1 "$CRB" "no control byte"
done
CENV=()
# Valid UTF-8 and ordinary non-ASCII pass.
cok "accepts em dash, accent, CJK, emoji" 0 '- a \xe2\x80\x94 \xc3\xa9 \xe4\xb8\xad \xf0\x9f\x98\x80 b\n'
# Invalid UTF-8, one fixture per class.
cok "utf8: lone continuation byte" 1 '- a \x80 b\n' "valid UTF-8"
cok "utf8: byte C0" 1 '- a \xc0\xaf b\n' "valid UTF-8"
cok "utf8: byte C1" 1 '- a \xc1\xbf b\n' "valid UTF-8"
cok "utf8: overlong 3-byte" 1 '- a \xe0\x80\xaf b\n' "valid UTF-8"
cok "utf8: overlong 4-byte" 1 '- a \xf0\x80\x80\xaf b\n' "valid UTF-8"
cok "utf8: surrogate" 1 '- a \xed\xa0\x80 b\n' "valid UTF-8"
cok "utf8: byte F5" 1 '- a \xf5\x80\x80\x80 b\n' "valid UTF-8"
cok "utf8: byte FF" 1 '- a \xff b\n' "valid UTF-8"
cok "utf8: above U+10FFFF" 1 '- a \xf4\x90\x80\x80 b\n' "valid UTF-8"
cok "utf8: truncated sequence" 1 '- a \xe2\x80 b\n' "valid UTF-8"
# Banned code points, one fixture per class.
cok "ban: C1 control U+0085" 1 '- a \xc2\x85 b\n' "invisible"
cok "ban: soft hyphen U+00AD" 1 '- a \xc2\xad b\n' "invisible"
cok "ban: U+061C" 1 '- a \xd8\x9c b\n' "invisible"
cok "ban: U+180E" 1 '- a \xe1\xa0\x8e b\n' "invisible"
cok "ban: zero width space U+200B" 1 '- a \xe2\x80\x8b b\n' "invisible"
cok "ban: U+200F" 1 '- a \xe2\x80\x8f b\n' "invisible"
cok "ban: line separator U+2028" 1 '- a \xe2\x80\xa8 b\n' "invisible"
cok "ban: U+202E" 1 '- a \xe2\x80\xae b\n' "invisible"
cok "ban: word joiner U+2060" 1 '- a \xe2\x81\xa0 b\n' "invisible"
cok "ban: U+206F" 1 '- a \xe2\x81\xaf b\n' "invisible"
cok "ban: BOM U+FEFF" 1 '- a \xef\xbb\xbf b\n' "invisible"
cok "ban: U+FFF9" 1 '- a \xef\xbf\xb9 b\n' "invisible"
cok "ban: U+FFFB" 1 '- a \xef\xbf\xbb b\n' "invisible"
cok "ban: tag character U+E0001" 1 '- a \xf3\xa0\x80\x81 b\n' "invisible"
cok "ban: tag character U+E007F" 1 '- a \xf3\xa0\x81\xbf b\n' "invisible"
cok "control: U+200A and U+2010 pass" 0 '- a \xe2\x80\x8a \xe2\x80\x90 b\n'
# Round 8. Variation selectors, joiners, fillers and the object replacement character.
cok "ban: ZWJ U+200D" 1 '- a \xe2\x80\x8d b\n' "invisible"
cok "ban: ZWNJ U+200C" 1 '- a \xe2\x80\x8c b\n' "invisible"
cok "ban: variation selector U+FE00" 1 '- a \xef\xb8\x80 b\n' "invisible"
cok "ban: variation selector U+FE0F" 1 '- a \xef\xb8\x8f b\n' "invisible"
cok "ban: variation selector U+E0100" 1 '- a \xf3\xa0\x84\x80 b\n' "invisible"
cok "ban: variation selector U+E01EF" 1 '- a \xf3\xa0\x87\xaf b\n' "invisible"
cok "ban: combining grapheme joiner U+034F" 1 '- a \xcd\x8f b\n' "invisible"
cok "ban: Hangul choseong filler U+115F" 1 '- a \xe1\x85\x9f b\n' "invisible"
cok "ban: Hangul jungseong filler U+1160" 1 '- a \xe1\x85\xa0 b\n' "invisible"
cok "ban: Hangul filler U+3164" 1 '- a \xe3\x85\xa4 b\n' "invisible"
cok "ban: halfwidth Hangul filler U+FFA0" 1 '- a \xef\xbe\xa0 b\n' "invisible"
cok "ban: object replacement U+FFFC" 1 '- a \xef\xbf\xbc b\n' "invisible"
cok "ban: all new classes in one line" 1 '- a \xef\xb8\x8f b \xcd\x8f \xe3\x85\xa4 \xef\xbe\xa0 \xf3\xa0\x84\x80\n' "invisible"
cok "control: just outside the new ranges pass" 0 \
  '- a \xef\xb7\xbf \xef\xb8\x90 \xf3\xa0\x83\xbf \xf3\xa0\x87\xb0 \xcd\x8e \xe1\x85\x9e \xe1\x85\xa1 \xe3\x85\xa3 \xef\xbd\x9f \xef\xbe\xa1 \xef\xbf\xbd b\n'
cok "control: emoji without variation selector passes" 0 '- a \xe2\x9d\xa4 \xf0\x9f\x91\x8d b\n'
# A tool that fails stops the check; it never accepts.
FAKE="$T/fakebin"; mkdir -p "$FAKE"; printf '#!/bin/sh\nexit 2\n' > "$FAKE/grep"; chmod +x "$FAKE/grep"
CENV=("PATH=$FAKE:$PATH"); cok "grep failure is an error, not an accept" 1 '- fine text\n' "grep failed"
# Each of the two greps failing alone stops the check: the fake exits 2 for one kind of call and
# runs the real grep for the other (-v marks the UTF-8 call).
REALGREP=$(command -v grep)
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = -v ] && exit 2; done\nexec %s "$@"\n' "$REALGREP" > "$FAKE/grep"
CENV=("PATH=$FAKE:$PATH"); cok "UTF-8 grep failing alone is an error" 1 '- fine text\n' "grep failed"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = -v ] && exec %s "$@"; done\nexit 2\n' "$REALGREP" > "$FAKE/grep"
cok "ban grep failing alone is an error" 1 '- fine text\n' "grep failed"
rm -f "$FAKE/grep"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/grep"; chmod +x "$FAKE/grep"
cok "grep that matches every line rejects" 1 '- fine text\n'; CENV=()
# Link reference definitions and brackets.
cok "bracket: multi-line label" 1 '- [foo\n  bar]: http://evil\n' "breaks the rule"
cok "bracket: 3-line label" 1 '- [x\n  y\n  z]: /u\n' "breaks the rule"
cok "bracket: escaped bracket" 1 '- [a\\]b]: http://evil\n' "breaks the rule"
cok "bracket: footnote definition" 1 '- [^1]: x\n' "breaks the rule"
cok "bracket: ]: mid-line" 1 '- see x]: y\n' "breaks the rule"
cok "bracket: unclosed [" 1 '- see [x here\n' "breaks the rule"
cok "bracket: stray ]" 1 '- see x] here\n' "breaks the rule"
cok "bracket: ] [ (shortcut label pair)" 1 '- see [a] [b]\n' "breaks the rule"
cok "bracket: ][" 1 '- see [a][b]\n' "breaks the rule"
cok "bracket: ](" 1 '- see [a](b)\n' "breaks the rule"
cok "bracket control: [text]" 0 '- see [text] here\n'
cok "bracket control: [a] and [b]" 0 '- see [a] and [b]\n'
cok "bracket control: span holds brackets and ]:" 0 '- see `a]: [b` here\n'
# Long line: 10,000 code spans in 40,000 characters stay fast.
BIGL=$(awk 'BEGIN { printf "- "; for (i = 0; i < 10000; i++) printf "`a` "; printf "end\n" }')
printf '%s\n' "$BIGL" > "$T/big.md"
t0=$SECONDS; bash -c 'source "$1"; cl_content_ok "$2"' _ "$REPO/scripts/changelog-lib.sh" "$T/big.md" >/dev/null 2>&1; bigrc=$?; dt=$((SECONDS - t0))
if [[ $bigrc -eq 0 && $dt -lt 5 ]]; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL: 40k-char line with 10k spans: rc $bigrc, ${dt}s"; fi

# Migration compare: lone * and span lists.
mkunrel mig-star; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- 2 * 3 = 6/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- 2  3 = 6\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR drops a lone * (multiplication)" 1 "in no added fragment"
mkunrel mig-star2; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- 2 3 = 6/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- 2 * 3 = 6\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR adds a lone *" 1 "in no added fragment"
mkunrel mig-star3; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- 2 * 3 = 6/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- 2 * 3 = 6 \x2a\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR keeps a lone * but adds another" 1 "in no added fragment"
mkunrel mig-span; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two x`y`z here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two \x60x\x60y\x60z\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR turns a span x\x60y\x60z into spans x and z" 1 "in no added fragment"

mkunrel mig-span2; git -C "$R" checkout -q main
sub "$R/CHANGELOG.md" 's/^- two$/- two `a`b here/'; commit lt; git -C "$R" checkout -q -B pr2
migfrags; printf -- '- two \x60ab\x60 here\n' > "$R/changelog.d/two.added.md"
printf '%s' "$EMPTIED" > "$R/CHANGELOG.md"; commit f
run "migration PR widens a span from a to ab" 1 "in no added fragment"

echo "changelog-check.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
