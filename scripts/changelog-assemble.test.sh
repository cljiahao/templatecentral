#!/usr/bin/env bash
# scripts/changelog-assemble.test.sh — changelog-assemble.sh builds the release section and
#   refuses each planted defect.
# Each case builds a committed scratch repo; a refusal must leave `git status` empty.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASM="$REPO/scripts/changelog-assemble.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/clasm-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
ok() { PASS=$((PASS + 1)); }

# mk <name>: committed scratch repo with a CHANGELOG.md and a fragment README. Sets $R.
mk() {
  R="$T/$1"; mkdir -p "$R/changelog.d"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.com; git -C "$R" config user.name t
  git -C "$R" config commit.gpgsign false
  printf '# Changelog\n\n---\n\n## [Unreleased]\n\n---\n\n## [1.0.0] — 2026-01-01\n\n### Added\n- old\n' > "$R/CHANGELOG.md"
  printf '# fragments\n' > "$R/changelog.d/README.md"
}
commit() { git -C "$R" add -A; git -C "$R" commit -qm "${1:-c}"; }
frag() { printf '%s\n' "${2:-- entry $1}" > "$R/changelog.d/$1"; }
# refuse <name> <msg fragment> [args...]: assembling must fail, print the message and change
#   nothing.
refuse() {
  local n=$1 msg=$2; shift 2
  local out rc
  out=$(cd "$R" && bash "$ASM" "$@" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then fail "$n — expected refusal"
  elif [[ "$out" != *"$msg"* ]]; then fail "$n — output lacks '$msg': $out"
  elif [[ -n "$(git -C "$R" status --porcelain)" ]]; then fail "$n — changed files: $(git -C "$R" status --porcelain)"
  else ok; fi
}
V=(2.0.0 2026-03-04)

mk control
frag zeta.added.md; frag alpha.added.md "- alpha one
  continued
- alpha two"; frag m.fixed.md; frag c.changed.md; frag r.removed.md; frag s.security.md
commit
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
want='## [Unreleased]

---

## [2.0.0] — 2026-03-04

### Added
- alpha one
  continued
- alpha two
- entry zeta.added.md

### Changed
- entry c.changed.md

### Removed
- entry r.removed.md

### Fixed
- entry m.fixed.md

### Security
- entry s.security.md

---

## [1.0.0] — 2026-01-01'
got=$(sed -n '/^## \[Unreleased\]/,/^## \[1\.0\.0\]/p' "$R/CHANGELOG.md")
if [[ $rc -ne 0 ]]; then fail "control — rc $rc: $out"
elif [[ "$got" != "$want" ]]; then fail "control — CHANGELOG mismatch: $got"
elif [[ -n "$(ls "$R/changelog.d")" && "$(ls "$R/changelog.d")" != "README.md" ]]; then fail "control — fragments left: $(ls "$R/changelog.d")"
elif [[ ! -f "$R/changelog.d/README.md" ]]; then fail "control — README.md removed"
elif compgen -G "$R/CHANGELOG.md.*" >/dev/null; then fail "control — temp file left"
else ok; fi

mk dry; frag a.added.md; commit
out=$(cd "$R" && bash "$ASM" --dry-run "${V[@]}" 2>&1); rc=$?
if [[ $rc -ne 0 || "$out" != *"## [2.0.0] — 2026-03-04"* || "$out" != *"- entry a.added.md"* ]]; then fail "dry-run output: $out"
elif [[ -n "$(git -C "$R" status --porcelain)" ]]; then fail "dry-run changed files"
else ok; fi

mk none; commit
refuse "no fragments" "no fragments" "${V[@]}"
mk onlyreadme; commit
refuse "only README.md" "no fragments" "${V[@]}"

mk badcat; frag a.added.md; frag b.bogus.md; commit
refuse "invalid category" "not a valid fragment name" "${V[@]}"
mk badbody; frag a.added.md; frag b.fixed.md "just words"; commit
refuse "invalid content" "not a valid fragment" "${V[@]}"
mk empty; frag a.added.md; : > "$R/changelog.d/b.fixed.md"; commit
refuse "empty fragment" "not a valid fragment" "${V[@]}"
mk sym; frag a.added.md; echo "- x" > "$R/t.txt"; ln -s ../t.txt "$R/changelog.d/b.fixed.md"; commit
refuse "symlink fragment" "not a valid fragment" "${V[@]}"
mk sub; frag a.added.md; mkdir "$R/changelog.d/d"; frag d/b.fixed.md; commit
refuse "subdirectory" "subdirectory" "${V[@]}"
mk fenced; frag a.added.md; frag b.fixed.md "- x
  ~~~"; commit
refuse "fence line in a fragment" "not a valid fragment" "${V[@]}"
mk hashed; frag a.added.md; frag b.fixed.md "- x
    # heading"; commit
refuse "heading line in a fragment" "not a valid fragment" "${V[@]}"

mk hidden; frag a.added.md; frag .hidden.added.md; commit
refuse "hidden file" "not a valid fragment name" "${V[@]}"

mk dupver; frag a.added.md; commit
refuse "existing version" "already has a section" 1.0.0 2026-03-04
mk badver; frag a.added.md; commit
refuse "bad version" "N.N.N" 2.0 2026-03-04
refuse "bad version text" "N.N.N" v2.0.0 2026-03-04
refuse "bad date" "YYYY-MM-DD" 2.0.0 2026-13-01
refuse "bad date text" "YYYY-MM-DD" 2.0.0 tomorrow
refuse "missing args" "usage" 2.0.0

mk nocl; frag a.added.md; rm "$R/CHANGELOG.md"; commit
refuse "CHANGELOG.md missing" "regular file" "${V[@]}"
mk symcl; frag a.added.md; mv "$R/CHANGELOG.md" "$R/real.md"; ln -s real.md "$R/CHANGELOG.md"; commit
refuse "CHANGELOG.md symlink" "regular file" "${V[@]}"
mk nounrel; frag a.added.md; printf '# Changelog\n\n## [1.0.0] — x\n' > "$R/CHANGELOG.md"; commit
refuse "no Unreleased heading" "Unreleased" "${V[@]}"
mk norel; frag a.added.md; printf '# Changelog\n\n## [Unreleased]\n- a\n' > "$R/CHANGELOG.md"; commit
refuse "no release heading after Unreleased" "Unreleased" "${V[@]}"

# [Unreleased] must be empty: entries there are refused, and the control passes without them.
mk unrel-entry; frag a.added.md
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n- legacy\n\n---\n\n## [1.0.0] — 2026-01-01\n' > "$R/CHANGELOG.md"; commit
refuse "entries under [Unreleased]" "entries under '## [Unreleased]'" "${V[@]}"
mk unrel-entry2; frag a.added.md
printf '# Changelog\n\n## [Unreleased]\n- x\n\n---\n\n## [1.0.0] — 2026-01-01\n' > "$R/CHANGELOG.md"; commit
refuse "bullet right under [Unreleased]" "entries under '## [Unreleased]'" "${V[@]}"
mk unrel-empty; frag a.added.md
printf '# Changelog\n\n## [Unreleased]\n\n---\n\n## [1.0.0] — 2026-01-01\n' > "$R/CHANGELOG.md"; commit
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "empty [Unreleased] control refused: $out"; fi

# Lib screening: a line fits the allow-list grammar of cl_content_ok or the fragment is refused.
n=0
for body in '- - ```js' '- - # x' '- ***' '- - -' '* * *' '- ok
  ___' '- ```js' '- # H' '- ok
- # H' '- ok
  - ~~~' '- ok
  ---' '- ok
===' '- ---' \
  '> # x' '- ok
  =' '- <h2>y</h2>' '- ok
  <h2>y</h2>' '- + # x' '- 1. # x' \
  '- x \`<b>\` y' '- a `b
  c `<script>` d ` e' '- a `b' '- a ``b`` c' '- a <!-- b
  c -->' '- a <?x ?>' '- a <![CDATA[' '- [x]: http://example.invalid' \
  '- [Unreleased]: http://example.invalid' '- ok
  [x]: http://example.invalid' '- ok

  [x]: http://example.invalid' '- ok

- b' '- see [t](http://example.invalid)' '- see [t][ref]'; do
  n=$((n + 1)); mk "lib-bad$n"; frag a.added.md; frag b.fixed.md "$body"; commit
  refuse "lib rejects: ${body//$'\n'/ | }" "not a valid fragment" "${V[@]}"
done
# Bytes the shell cannot hold in a variable: lone CR, CRLF, NUL, TAB, DEL, no final newline, empty.
n=0
for body in '- a\r## [9.9.9] — 2099-01-01\r- b\n' '- a\r\n- b\r\n' '- a\r  ---\n' '- a\r> x\n' \
  '- a\r<script>\n' '- a\0b\n' '- a\tb\n' '- a\177b\n' '- ok' ''; do
  n=$((n + 1)); mk "lib-byte$n"; frag a.added.md; printf -- "$body" > "$R/changelog.d/b.fixed.md"; commit
  refuse "lib rejects bytes: $body" "not a valid fragment" "${V[@]}"
done
mk lib-ok; frag a.added.md; bt='`'; frag b.fixed.md "- use ${bt}x${bt}, see #12 and --- inline
  - nested --flag"; commit
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "lib control refused inline text: $out"; fi
mk lib-ok3; frag a.added.md; frag b.fixed.md "- use ${bt}<b>${bt} in a span and ${bt}x${bt} too
  - nested ${bt}<i>${bt}"; commit
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
if [[ $rc -ne 0 ]]; then fail "lib control refused spans: $out"
elif ! grep -qF -- "- use ${bt}<b>${bt} in a span and ${bt}x${bt} too" "$R/CHANGELOG.md" \
  || ! grep -qF -- "  - nested ${bt}<i>${bt}" "$R/CHANGELOG.md"; then fail "lib control: text not emitted as written"
else ok; fi
mk lib-ok2; frag a.added.md; frag b.fixed.md '- the --flag is new
- text with **bold**
  - nested _it_ and 3 - 2 = 1'; commit
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "lib control refused flag, bold and italic text: $out"; fi

# Mode of CHANGELOG.md survives the replace.
mk mode; frag a.added.md; chmod 755 "$R/CHANGELOG.md"; commit
(cd "$R" && bash "$ASM" "${V[@]}" >/dev/null 2>&1)
if [[ -x "$R/CHANGELOG.md" ]]; then ok; else fail "CHANGELOG.md lost its executable bit"; fi
mk mode2; frag a.added.md; chmod 600 "$R/CHANGELOG.md"; commit
(cd "$R" && bash "$ASM" "${V[@]}" >/dev/null 2>&1)
if [[ ! -r "$R/CHANGELOG.md" || -n "$(find "$R/CHANGELOG.md" -perm -044)" ]]; then fail "CHANGELOG.md mode widened"; else ok; fi

# A failed fragment delete leaves CHANGELOG.md updated; the re-run refuses, so nothing folds twice.
if [[ $(id -u) -ne 0 ]]; then
  mk rmfail; frag a.added.md; commit
  chmod 555 "$R/changelog.d"
  out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
  chmod 755 "$R/changelog.d"
  if [[ $rc -eq 0 || "$out" != *"cannot delete"* ]]; then fail "failed delete not reported: $out"; else ok; fi
  before=$(cat "$R/CHANGELOG.md")
  refuse_out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1); rc=$?
  if [[ $rc -eq 0 || "$refuse_out" != *"already has a section"* || "$(cat "$R/CHANGELOG.md")" != "$before" ]]; then fail "re-run after a failed delete folded again: $refuse_out"; else ok; fi
fi

# Two branches add fragments in the same category and merge without a conflict.
mk merge; commit base
git -C "$R" checkout -q -b one; frag one.added.md; commit one
git -C "$R" checkout -q main; git -C "$R" checkout -q -b two; frag two.added.md; commit two
git -C "$R" checkout -q one
if git -C "$R" merge -q --no-edit two >/dev/null 2>&1 && [[ -f "$R/changelog.d/one.added.md" && -f "$R/changelog.d/two.added.md" ]]; then ok; else fail "fragments from two branches conflict"; fi
out=$(cd "$R" && bash "$ASM" "${V[@]}" 2>&1)
if [[ "$(grep -c '^- entry' "$R/CHANGELOG.md")" == 2 ]]; then ok; else fail "merged fragments not both assembled: $out"; fi

echo "changelog-assemble.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
