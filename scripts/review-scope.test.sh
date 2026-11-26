#!/usr/bin/env bash
# Behavioural test for skills/review/review/review-scope.sh.
# Real git fixtures in a temp dir. Every refusal has a clean control that passes, and a mutant of the script (one check removed)
# that lets the bad input through, so the test proves each check is what stops it. No timing, no network.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/skills/review/review/review-scope.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/scopetest.XXXXXX") || exit 1
cleanup() { if [ -d "$T" ]; then chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; fi; }
trap cleanup EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]"; fail=1 ;; esac; }
NL='
'
exists01() { if [ -e "$1" ]; then echo 1; else echo 0; fi; }
changed01() { if [ "$1" != "$2" ]; then echo 1; else echo 0; fi; }
SCRIPT=$T/review-scope.sh
cp "$SRC" "$SCRIPT"
run() { bash "$SCRIPT" "$@"; }
# out <args>: stdout and stderr of a run, then its exit code on the last line
out() { local o rc; o=$(run "$@" 2>&1); rc=$?; o=$(printf '%s\n' "$o" | grep -v '^review-scope: scope computed at HEAD ' || true); o=${o%"$NL"}; if [ -n "$o" ]; then printf '%s\nrc=%s' "$o" "$rc"; else printf 'rc=%s' "$rc"; fi; }
g() { git -C "$1" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null "${@:2}"; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1"; else sha256sum -- "$1"; fi | cut -d' ' -f1; }
treehash() { (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf '%s L %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(sha "$f")"; fi; done | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1); }

# mkrepo <dir>: a repo with two commits; prints nothing
mkrepo() {
  mkdir -p "$1/src" "$1/dir with space"
  g "$1" init -q -b main 2>/dev/null || { git init -q "$1" && g "$1" checkout -q -b main; }
  echo a >"$1/src/a.ts"; echo b >"$1/src/b.ts"
  g "$1" add -A; g "$1" commit -qm one
}
head_of() { g "$1" rev-parse HEAD; }

P=$T/proj
mkrepo "$P"
H1=$(head_of "$P")
echo c >"$P/src/c.ts"; echo s >"$P/dir with space/s p.ts"; echo a2 >>"$P/src/a.ts"
g "$P" add -A; g "$P" commit -qm two
H2=$(head_of "$P")

# --- no baseline
mkdir -p "$P/src"; : >"$P/src/z.ts"; : >"$P/src/zz.ts"; : >"$P/src/new.ts"
before=$(treehash "$P")
check "no baseline, no session: empty scope" "rc=0" "$(out "$P")"
check "no baseline: session paths only, sorted, deduplicated" "src/z.ts${NL}src/zz.ts
rc=0" "$(out "$P" --session src/zz.ts --session src/z.ts --session ./src/z.ts)"
check "scope mode wrote nothing" "$before" "$(treehash "$P")"

# --- baseline present
mkdir -p "$P/.claude"
printf 'last-reviewed-commit: %s\nstack: nextjs\nreviewed-at: 2026-01-01\n' "$H1" >"$P/.claude/review-baseline.md"
check "baseline: committed changes since it, with a path with a space" "dir with space/s p.ts${NL}src/a.ts${NL}src/c.ts
rc=0" "$(out "$P")"
check "baseline: union with session paths, no duplicate" "dir with space/s p.ts${NL}src/a.ts${NL}src/c.ts${NL}src/new.ts
rc=0" "$(out "$P" --session src/a.ts --session src/new.ts)"
check "baseline = HEAD: empty scope" "rc=0" "$(printf 'last-reviewed-commit: %s\n' "$H2" >"$P/.claude/review-baseline.md"; out "$P")"
printf 'last-reviewed-commit: %s\n' "$H1" >"$P/.claude/review-baseline.md"

# --- record
before=$(treehash "$P")
r=$(out "$P" --record-baseline --stack nextjs)
contains "record: success message" "baseline written" "$r"
check "record: file holds HEAD" "last-reviewed-commit: $H2" "$(sed -n 1p "$P/.claude/review-baseline.md")"
check "record: stack line" "stack: nextjs" "$(sed -n 2p "$P/.claude/review-baseline.md")"
contains "record: date line" "reviewed-at: 20" "$(sed -n 3p "$P/.claude/review-baseline.md")"
check "record: three lines only" "3" "$(wc -l <"$P/.claude/review-baseline.md" | tr -d ' ')"
check "scope after record is empty" "rc=0" "$(out "$P")"
check "record differs from before" "1" "$(changed01 "$before" "$(treehash "$P")")"
N=$T/fresh
mkrepo "$N"
check "record creates .claude when absent" "rc=0" "$(out "$N" --record-baseline --stack fastapi | sed -n '$p')"
check "record created the baseline" "1" "$(exists01 "$N/.claude/review-baseline.md")"
NC=$T/nocommit
mkdir -p "$NC/src"; : >"$NC/src/x.ts"; git init -q "$NC"
r=$(out "$NC" --record-baseline --stack nestjs)
contains "no commit: record is skipped with exit 0" "rc=0" "$r"
check "no commit: no baseline written" "0" "$(exists01 "$NC/.claude/review-baseline.md")"
check "no commit, no baseline: scope is the session paths" "src/x.ts
rc=0" "$(out "$NC" --session src/x.ts)"

# --- fail closed: each with a clean control above and a mutant below
expect_refuse() { # name dir [args...]
  local name=$1; shift
  local r; r=$(out "$@")
  case "$r" in *"rc=1") echo "ok   $name" ;; *) echo "FAIL $name: [$r]"; fail=1 ;; esac
}
NG=$T/notgit; mkdir -p "$NG"
expect_refuse "not a git repo" "$NG"
expect_refuse "not a directory" "$T/nope"
bl() { printf '%s' "$1" >"$P/.claude/review-baseline.md"; }
bl "last-reviewed-commit: abc123
"; expect_refuse "baseline: short sha" "$P"
bl "last-reviewed-commit: ${H1%?}Z
"; expect_refuse "baseline: non-hex sha" "$P"
bl "last-reviewed-commit: $(printf '%s' "$H1" | tr 'a-f' 'A-F')
"; expect_refuse "baseline: uppercase hex" "$P"
bl "stack: nextjs
"; expect_refuse "baseline: no last-reviewed-commit line" "$P"
bl "last-reviewed-commit: $H1
last-reviewed-commit: $H2
"; expect_refuse "baseline: repeated key" "$P"
bl "last-reviewed-commit:
"; expect_refuse "baseline: empty value" "$P"
bl "last-reviewed-commit: 0000000000000000000000000000000000000000
"; expect_refuse "baseline: well-formed sha absent from history" "$P"
bl "last-reviewed-commit: $H1
"
check "control: a good baseline passes" "dir with space/s p.ts${NL}src/a.ts${NL}src/c.ts
rc=0" "$(out "$P")"

# not an ancestor: a sibling commit
g "$P" checkout -q -b side "$H1"; echo side >"$P/side.txt"; g "$P" add side.txt; g "$P" commit -qm side
HS=$(head_of "$P"); g "$P" checkout -q main
bl "last-reviewed-commit: $HS
"; expect_refuse "baseline: commit exists but is not an ancestor of HEAD" "$P"
bl "last-reviewed-commit: $H1
"

# symlink / unreadable / not a file
mv "$P/.claude/review-baseline.md" "$T/real-baseline.md"
ln -s "$T/real-baseline.md" "$P/.claude/review-baseline.md"
expect_refuse "baseline: a symlink" "$P"
rm "$P/.claude/review-baseline.md"
ln -s "$T/missing-target" "$P/.claude/review-baseline.md"
expect_refuse "baseline: a dangling symlink" "$P"
rm "$P/.claude/review-baseline.md"
mkdir "$P/.claude/review-baseline.md"
expect_refuse "baseline: a directory" "$P"
rmdir "$P/.claude/review-baseline.md"
bl "last-reviewed-commit: $H1
"
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$P/.claude/review-baseline.md"
  expect_refuse "baseline: unreadable" "$P"
  chmod 644 "$P/.claude/review-baseline.md"
fi
mv "$P/.claude" "$T/real-claude"; ln -s "$T/real-claude" "$P/.claude"
before_claude=$(sha "$T/real-claude/review-baseline.md")
expect_refuse "scope: .claude is a symlink" "$P"
expect_refuse "record: .claude is a symlink" "$P" --record-baseline --stack nextjs
check "record through a symlinked .claude wrote nothing" "$before_claude" "$(sha "$T/real-claude/review-baseline.md")"
rm "$P/.claude"; mv "$T/real-claude" "$P/.claude"

# session paths
expect_refuse "session: absolute path outside the project" "$P" --session /etc/passwd
expect_refuse "session: .. escape" "$P" --session ../outside.ts
expect_refuse "session: embedded .." "$P" --session src/../../outside.ts
expect_refuse "session: empty path" "$P" --session ""
ln -s "$T" "$P/linkdir"
expect_refuse "session: symlink component" "$P" --session linkdir/x.ts
rm "$P/linkdir"
check "control: absolute path inside the project is accepted" "src/x.ts
rc=0" "$(out "$NC" --session "$NC/src/x.ts")"

# usage
check "usage: no project" "2" "$(run >/dev/null 2>&1; echo $?)"
check "usage: unknown flag" "2" "$(run "$P" --bogus >/dev/null 2>&1; echo $?)"
check "usage: record without stack" "2" "$(run "$P" --record-baseline >/dev/null 2>&1; echo $?)"
check "usage: record with a bad stack" "2" "$(run "$P" --record-baseline --stack rails >/dev/null 2>&1; echo $?)"
check "usage: record with --session" "2" "$(run "$P" --record-baseline --stack nextjs --session a >/dev/null 2>&1; echo $?)"
check "usage: --stack without record" "2" "$(run "$P" --stack nextjs >/dev/null 2>&1; echo $?)"

# no commit but a baseline file
printf 'last-reviewed-commit: %s\n' "$H1" >"$NC/.claude-b"; mkdir -p "$NC/.claude"; mv "$NC/.claude-b" "$NC/.claude/review-baseline.md"
expect_refuse "baseline file in a repo with no commit" "$NC"

# --- more traps: each refuses (or is accepted) as stated, with a clean control; mutants below remove the check
NOTROOT=1
if [ "$(id -u)" -eq 0 ]; then NOTROOT=0; fi
mode_of() { if stat --version >/dev/null 2>&1; then stat -c %a -- "$1"; else stat -f %Lp -- "$1"; fi; }
bl "last-reviewed-commit: $H1
"
# a changed file whose name holds a newline (bad repo) and one with a space (control repo)
NR=$T/nlrepo
mkrepo "$NR"
NR1=$(head_of "$NR")
: >"$NR/src/x${NL}y.ts"
g "$NR" add -A; g "$NR" commit -qm two
mkdir -p "$NR/.claude"
printf 'last-reviewed-commit: %s\n' "$NR1" >"$NR/.claude/review-baseline.md"
expect_refuse "a changed file name with a newline" "$NR"
NS=$T/spacerepo
mkrepo "$NS"
NS1=$(head_of "$NS")
: >"$NS/src/x y.ts"
g "$NS" add -A; g "$NS" commit -qm two
mkdir -p "$NS/.claude"
printf 'last-reviewed-commit: %s\n' "$NS1" >"$NS/.claude/review-baseline.md"
check "control: a changed file name with a space is listed" "src/x y.ts
rc=0" "$(out "$NS")"

# a --session path whose last component is a symlink
ln -s "$P/src/a.ts" "$P/src/lnk.ts"
expect_refuse "session: a symlink as the last component" "$P" --session src/lnk.ts
rm "$P/src/lnk.ts"

# a --session path that is in no tree and is no deletion; a deletion is accepted
expect_refuse "session: a path that does not exist and was never in HEAD" "$P" --session src/never.ts
rm "$P/src/b.ts"
check "control: a deleted tracked file is accepted" "src/b.ts
rc=0" "$(printf 'last-reviewed-commit: %s\n' "$H2" >"$P/.claude/review-baseline.md"; out "$P" --session src/b.ts)"
g "$P" checkout -q -- src/b.ts
bl "last-reviewed-commit: $H1
"

# a relative project path with a trailing slash, with the session path relative to the cwd
printf 'last-reviewed-commit: %s\n' "$H2" >"$P/.claude/review-baseline.md"
case "$(cd "$T" && out proj/ --session proj/src/a.ts)" in *"rc=1") echo "ok   relative project dir: a cwd-relative session path is refused (paths are relative to the project)" ;; *) echo "FAIL relative project dir: cwd-relative session path accepted"; fail=1 ;; esac
check "project dir with a trailing slash, session path relative to the project" "src/a.ts
rc=0" "$(cd "$T" && out proj/ --session src/a.ts)"
bl "last-reviewed-commit: $H1
"

# glob characters in a session path are literal
mkdir -p "$P/src/[id]" "$P/src/i"
echo p >"$P/src/[id]/page.tsx"; echo q >"$P/src/i/page.tsx"
check "session: a glob character stays literal (a decoy directory matches the expanded form)" "dir with space/s p.ts${NL}src/[id]/page.tsx${NL}src/a.ts${NL}src/c.ts
rc=0" "$(cd "$P" && out . --session 'src/[id]/page.tsx')"
rm -rf "$P/src/[id]" "$P/src/i"

# a shallow clone gets its own message; a full clone with the same baseline is fine
SH=$T/shallow
git clone -q --depth 1 "file://$P" "$SH" 2>/dev/null
mkdir -p "$SH/.claude"
printf 'last-reviewed-commit: %s\n' "$H1" >"$SH/.claude/review-baseline.md"
r=$(out "$SH")
contains "shallow clone: refused" "rc=1" "$r"
contains "shallow clone: the message says shallow and what to fetch" "shallow clone" "$r"
case "$r" in *"history was rewritten"*) echo "FAIL shallow clone: wrong advice (history was rewritten)"; fail=1 ;; *) echo "ok   shallow clone: no wrong advice" ;; esac
FC=$T/fullclone
git clone -q "file://$P" "$FC" 2>/dev/null
mkdir -p "$FC/.claude"
printf 'last-reviewed-commit: %s\n' "$H1" >"$FC/.claude/review-baseline.md"
contains "control: a full clone with the same baseline passes" "rc=0" "$(out "$FC")"

# baseline shapes
bl "last-reviewed-commit: $H1"$'\r'"
"
expect_refuse "baseline: a CRLF line" "$P"
bl "last-reviewed-commit: $(printf '%s' "$H1" | cut -c1-12)
"
expect_refuse "baseline: an abbreviated sha that git would resolve" "$P"
bl "last-reviewed-commit: 0000000000000000000000000000000000000000000000000000000000000000
"
expect_refuse "baseline: a 64-hex id in a sha1 repository" "$P"
S2=$T/sha256repo
if git init -q --object-format=sha256 -b main "$S2" 2>/dev/null; then
  echo a >"$S2/a.ts"; g "$S2" add -A; g "$S2" commit -qm one
  S2H=$(head_of "$S2"); echo b >"$S2/b.ts"; g "$S2" add -A; g "$S2" commit -qm two
  mkdir -p "$S2/.claude"
  printf 'last-reviewed-commit: %s\n' "$S2H" >"$S2/.claude/review-baseline.md"
  check "control: a 64-hex baseline in a sha256 repository works" "b.ts
rc=0" "$(out "$S2")"
else
  echo "skip sha256 repository probe: this git has no --object-format"
fi
bl "last-reviewed-commit: $H1
"

# record refuses when the existing baseline is bad, and leaves it as it was
bl "last-reviewed-commit: abc123
"
bad_before=$(sha "$P/.claude/review-baseline.md")
expect_refuse "record: the existing baseline is bad" "$P" --record-baseline --stack nextjs
check "record: the bad baseline is untouched" "$bad_before" "$(sha "$P/.claude/review-baseline.md")"
bl "last-reviewed-commit: $H1
"

# record keeps the baseline's mode; a failed write leaves the old baseline
chmod 600 "$P/.claude/review-baseline.md"
out "$P" --record-baseline --stack nextjs >/dev/null
check "record: the mode of the old baseline is kept" "600" "$(mode_of "$P/.claude/review-baseline.md")"
chmod 644 "$P/.claude/review-baseline.md"
bl "last-reviewed-commit: $H1
"
if [ "$NOTROOT" -eq 1 ]; then
  old=$(sha "$P/.claude/review-baseline.md")
  chmod a-w "$P/.claude"
  r=$(out "$P" --record-baseline --stack nextjs)
  chmod u+w "$P/.claude"
  contains "record: a directory that cannot take the temp file: refused" "rc=1" "$r"
  contains "record: says the old baseline stays" "old baseline stays" "$r"
  check "record: the old baseline is byte for byte as before" "$old" "$(sha "$P/.claude/review-baseline.md")"
  check "record: no temp file is left behind" "1" "$(find "$P/.claude" -type f | wc -l | tr -d ' ')"
fi

# --- mutants: with one check removed the same bad input gets through
mutant() { # name sed-expr bad-args-run description
  local name=$1 expr=$2; shift 2
  cp "$SRC" "$T/mutant.sh"
  sed "$expr" "$T/mutant.sh" >"$T/mutant2.sh"
  if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant $name: sed expression matched nothing"; fail=1; return; fi
  local r; r=$(cd "${MCWD:-.}" && bash "$T/mutant2.sh" "$@" 2>&1; echo "rc=$?")
  case "$r" in *"rc=0") echo "ok   mutant $name lets the bad input through" ;; *) echo "FAIL mutant $name still refused: [$r]"; fail=1 ;; esac
}
bl "last-reviewed-commit: $HS
"
mutant "no ancestor check" 's|git -c core.warnAmbiguousRefs=false -C "[$]ROOT" merge-base --is-ancestor "[$]BSHA" "[$]HEAD_SHA" 2>/dev/null|true|' "$P"
bl "last-reviewed-commit: $H1
"
mutant "no session outside check" 's|die "session path [$]p is outside the project"|rel=src/a.ts|g' "$P" --session /etc/passwd
mv "$P/.claude/review-baseline.md" "$T/real-baseline.md"; ln -s "$T/real-baseline.md" "$P/.claude/review-baseline.md"
mutant "no symlink check" 's|\[ ! -L "[$]BASE" \] \|\| die "[$]BASE is a symlink"|true|' "$P"
rm "$P/.claude/review-baseline.md"; mv "$T/real-baseline.md" "$P/.claude/review-baseline.md"
mutant "no git check" 's|git -C "[$]ROOT" rev-parse --git-dir >/dev/null 2>&1 \|\| die|true \|\| die|' "$NG"

# --- mutants for the traps added above
MCWD=.
bl "last-reviewed-commit: $H1
"
mutant "no dotdot check (real path)" 's|\*/\.\./\* \| \*/\./\* \| \*//\*) die|NOMATCH) die|' "$P" --session ../proj/src/a.ts
mutant "no newline check on changed names" 's|case "[$]f" in \*"[$]NL"\*) die "a changed file name holds a newline: refusing" ;; esac|:|' "$NR"

# short, uppercase, repeated-key, unreadable, session symlink, shallow, record-on-bad-baseline, trailing slash, glob, nonexistent path
bl "last-reviewed-commit: $(printf '%s' "$H1" | cut -c1-12)
"
mutant "no length check" "s#40 | 64) ;; \\*) die#*) ;; NOMATCH) die#" "$P"
bl "last-reviewed-commit: $(printf '%s' "$H1" | tr 'a-f' 'A-F')
"
mutant "no hex check" "s#\\*\\[!0-9a-f\\]\\* | '') die#NOMATCH) die#" "$P"
bl "last-reviewed-commit: $H1
last-reviewed-commit: $H2
"
mutant "no repeated-key check" 's|\[ "[$]count" -eq 1 \] \|\| die|true \|\| die|' "$P"
bl "last-reviewed-commit: $H1
"
if [ "$NOTROOT" -eq 1 ]; then
  chmod 000 "$P/.claude/review-baseline.md"
  cp "$SRC" "$T/mutant.sh"
  sed 's|\[ -r "[$]BASE" \] \|\| die|true \|\| die|' "$T/mutant.sh" >"$T/mutant2.sh"
  if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant no readable check: sed matched nothing"; fail=1; fi
  r=$(bash "$T/mutant2.sh" "$P" 2>&1; echo "rc=$?")
  case "$r" in *"is not readable"*) echo "FAIL mutant no readable check still reports it: [$r]"; fail=1 ;; *) echo "ok   mutant without the readable check no longer reports it (the loop's failed redirect is the only backstop)" ;; esac
  chmod 644 "$P/.claude/review-baseline.md"
fi
ln -s "$P/src/a.ts" "$P/src/lnk.ts"
mutant "no session symlink check" 's|\[ ! -L "[$]acc" \] \|\| die "session path [$]p has a symlink component ([$]part)"|:|' "$P" --session src/lnk.ts
rm "$P/src/lnk.ts"
cp "$SRC" "$T/mutant.sh"
sed 's|if \[ "[$]SHALLOW" = true \]; then die "baseline commit|if false; then die "baseline commit|' "$T/mutant.sh" >"$T/mutant2.sh"
if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant shallow: sed matched nothing"; fail=1; fi
r=$(bash "$T/mutant2.sh" "$SH" 2>&1; echo "rc=$?")
case "$r" in *"shallow clone"*) echo "FAIL mutant without the shallow check still says shallow: [$r]"; fail=1 ;; *) echo "ok   mutant without the shallow check gives no shallow message" ;; esac
bl "last-reviewed-commit: abc123
"
mutant "record skips the baseline check" 's|^  read_baseline$|  :|' "$P" --record-baseline --stack nextjs
bl "last-reviewed-commit: $H1
"
printf 'last-reviewed-commit: %s\n' "$H2" >"$P/.claude/review-baseline.md"
cp "$SRC" "$T/mutant.sh"
sed 's|case "[$]PROJ" in \*/) PROJ=[$]{PROJ%/} ;; \*) break ;; esac|break|' "$T/mutant.sh" >"$T/mutant2.sh"
if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant trailing slash: sed matched nothing"; fail=1; fi
ln -s "$P" "$T/plink2"
r=$(bash "$T/mutant2.sh" "$T/plink2/" --session "$T/plink2/src/a.ts" 2>&1; echo "rc=$?")
case "$r" in *"rc=0") echo "FAIL mutant without the PROJ normalisation still accepts the prefix form with a trailing slash: [$r]"; fail=1 ;; *) echo "ok   mutant without the PROJ normalisation refuses the <project>/ prefix form" ;; esac
check "control: a symlinked project path with a trailing slash and the prefix form" "src/a.ts
rc=0" "$(out "$T/plink2/" --session "$T/plink2/src/a.ts")"
rm "$T/plink2"
bl "last-reviewed-commit: $H1
"
mutant "no existence check on a session path" 's|die "session path [$]p is not in the project and is not a file deleted since HEAD"|:|' "$P" --session src/never.ts
mkdir -p "$P/src/[id]" "$P/src/i"
echo p >"$P/src/[id]/page.tsx"; echo q >"$P/src/i/page.tsx"
cp "$SRC" "$T/mutant.sh"
awk '/^while IFS= read -r s; do$/ { print "for s in $SESSION; do"; next } /^done <<<"\$SESSION"$/ { print "done"; next } { print }' "$T/mutant.sh" >"$T/mutant2.sh"
if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant glob: awk matched nothing"; fail=1; fi
r=$(cd "$P" && bash "$T/mutant2.sh" . --session 'src/[id]/page.tsx' 2>&1; echo "rc=$?")
case "$r" in *"src/[id]/page.tsx"*) echo "FAIL mutant with an unquoted session list keeps the literal path: [$r]"; fail=1 ;; *) echo "ok   mutant with an unquoted session list expands the glob to the decoy" ;; esac
rm -rf "$P/src/[id]" "$P/src/i"
if [ "$NOTROOT" -eq 1 ]; then
  cp "$SRC" "$T/mutant.sh"
  sed -e "s#mktemp \"[\$]BASE_DIR/.review-baseline.XXXXXX\"#mktemp \"\${TMPDIR:-/tmp}/rb.XXXXXX\"#" -e "s#mv -f -- \"[\$]TMP\" \"[\$]BASE\"#cat -- \"\$TMP\" >\"\$BASE\"#" "$T/mutant.sh" >"$T/mutant2.sh"
  if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant atomic write: sed matched nothing"; fail=1; fi
  chmod a-w "$P/.claude"
  r=$(bash "$T/mutant2.sh" "$P" --record-baseline --stack nextjs 2>&1; echo "rc=$?")
  chmod u+w "$P/.claude"
  contains "mutant with the old in-place write overwrites the baseline in a read-only directory" "rc=0" "$r"
fi


# --- round 2: environment, relative project path, --at, directories, shapes
# mutant_ne <name> <sed-expr> <expected> <args...>: the mutant must NOT give the expected output (stdout+stderr, rc line last)
mutant_ne() {
  local name=$1 expr=$2 want=$3; shift 3
  cp "$SRC" "$T/mutant.sh"
  sed "$expr" "$T/mutant.sh" >"$T/mutant2.sh"
  if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant $name: sed expression matched nothing"; fail=1; return; fi
  local o rc; o=$(cd "${MCWD:-.}" && bash "$T/mutant2.sh" "$@" 2>&1); rc=$?
  o=$(printf '%s\n' "$o" | grep -v '^review-scope: scope computed at HEAD ' || true); o=${o%"$NL"}
  if [ -n "$o" ]; then o=$o${NL}rc=$rc; else o=rc=$rc; fi
  if [ "$o" = "$want" ]; then echo "FAIL mutant $name still gives the right answer: [$o]"; fail=1; else echo "ok   mutant $name gives a different answer"; fi
}
MCWD=.
bl "last-reviewed-commit: $H1
"
WANT="dir with space/s p.ts${NL}src/a.ts${NL}src/c.ts
rc=0"
OTHER=$T/other
mkrepo "$OTHER"; echo zz >"$OTHER/zz.ts"; g "$OTHER" add -A; g "$OTHER" commit -qm zz
check "env: GIT_DIR pointing at another repo is ignored" "$WANT" "$(GIT_DIR=$OTHER/.git out "$P")"
check "env: GIT_WORK_TREE and GIT_INDEX_FILE are ignored" "$WANT" "$(GIT_WORK_TREE=$OTHER GIT_INDEX_FILE=$OTHER/nope out "$P")"
GIT_DIR=$OTHER/.git mutant_ne "no unset of GIT_DIR (env set)" 's|^unset CDPATH GIT_DIR.*$|:|' "$WANT" "$P"
mkdir -p "$T/cd/proj"
check "env: CDPATH is ignored for a relative project path" "$WANT" "$(cd "$T" && CDPATH=$T/cd out proj)"
CDPATH=$T/cd MCWD=$T mutant_ne "no unset of CDPATH" 's|^unset CDPATH GIT_DIR.*$|:|' "$WANT" proj
MCWD=.
check "usage: the revision range ends with --" "1" "$(grep -c $'"\\$BSHA..HEAD" --' "$SRC")"
g "$P" tag -f "$H1" -m x >/dev/null 2>&1 || true
# a file named like the revision range must not be read as a path
check "control: scope with a tag named like the baseline stays right" "$WANT" "$(out "$P")"

# relative project path plus a session path that looks like the prefix form
mkdir -p "$T/rel/app/app"
mkrepo "$T/rel/app" >/dev/null 2>&1 || true
mkdir -p "$T/rel/app/app"; echo x >"$T/rel/app/app/x.ts"; echo y >"$T/rel/app/x.ts"
check "relative project, session path app/x.ts is the project's own app/x.ts" "app/x.ts
rc=0" "$(cd "$T/rel" && out app --session app/x.ts)"
MCWD=$T/rel mutant_ne "prefix form read for a relative project" $'s|^    [*]) rel=[$]{p#./} ;;$|    *) rel=${p#"$PROJ"/}; rel=${rel#./} ;;|' "app/x.ts
rc=0" app --session app/x.ts || true
MCWD=.
ln -s "$P" "$T/plink"
check "absolute project path through a symlink: the <project>/ prefix form is read" "$WANT" "$(out "$T/plink" --session "$T/plink/src/a.ts")"
expect_refuse "absolute project path: an absolute path outside it" "$P" --session "$T/other/zz.ts"
rm "$T/plink"

# a --session path naming a directory
expect_refuse "session: a directory" "$P" --session src
mutant "no directory check" 's|if \[ -d "[$]ROOT/[$]rel" \]; then die "session path [$]p is a directory: name its files"; fi|:|' "$P" --session src

# --at
printf 'last-reviewed-commit: %s\n' "$H1" >"$P/.claude/review-baseline.md"
r=$(run "$P" 2>&1 >/dev/null)
contains "scope: stderr names the HEAD the scope was computed at" "scope computed at HEAD $H2" "$r"
oldb=$(sha "$P/.claude/review-baseline.md")
expect_refuse "record --at: HEAD is another commit" "$P" --record-baseline --stack nextjs --at "$H1"
check "record --at: a refused record leaves the baseline untouched" "$oldb" "$(sha "$P/.claude/review-baseline.md")"
contains "record --at: the message names both commits" "$H1" "$(out "$P" --record-baseline --stack nextjs --at "$H1")"
check "control: record --at HEAD works" "1" "$(out "$P" --record-baseline --stack nextjs --at "$H2" | grep -c 'baseline written')"
printf 'last-reviewed-commit: %s\n' "$H1" >"$P/.claude/review-baseline.md"
mutant "no --at check" 's|if \[ -n "[$]AT" \] \&\& \[ "[$]AT" != "[$]HEAD_SHA" \]; then die .*$|:|' "$P" --record-baseline --stack nextjs --at "$H1"
check "usage: --at without record" "2" "$(run "$P" --at "$H2" >/dev/null 2>&1; echo $?)"
check "usage: --at with a non-hex value" "2" "$(run "$P" --record-baseline --stack nextjs --at zz >/dev/null 2>&1; echo $?)"
check "usage: --at without a value" "2" "$(run "$P" --record-baseline --stack nextjs --at >/dev/null 2>&1; echo $?)"

# .claude shapes while recording
mv "$P/.claude" "$T/claude-real"
ln -s "$T/missing-claude" "$P/.claude"
expect_refuse "record: .claude is a dangling symlink" "$P" --record-baseline --stack nextjs
rm "$P/.claude"; : >"$P/.claude"
expect_refuse "record: .claude is a regular file" "$P" --record-baseline --stack nextjs
rm "$P/.claude"; mv "$T/claude-real" "$P/.claude"
ln -s "$P/.claude" "$T/claude-link"
mv "$P/.claude" "$T/claude-real2"; ln -s "$T/claude-real2" "$P/.claude"
mutant "no .claude symlink check (scope)" 's|\[ ! -L "[$]BASE_DIR" \] \|\| die "[$]BASE_DIR is a symlink"|:|' "$P"
rm "$P/.claude"; mv "$T/claude-real2" "$P/.claude"; rm -f "$T/claude-link"

# detached HEAD
DH=$T/detached
git clone -q "file://$P" "$DH" 2>/dev/null
g "$DH" checkout -q --detach "$H2"
mkdir -p "$DH/.claude"; printf 'last-reviewed-commit: %s\n' "$H1" >"$DH/.claude/review-baseline.md"
check "detached HEAD: scope works" "$WANT" "$(out "$DH")"
contains "detached HEAD: record works" "baseline written" "$(out "$DH" --record-baseline --stack nextjs)"
check "detached HEAD: the baseline holds the detached commit" "last-reviewed-commit: $H2" "$(sed -n 1p "$DH/.claude/review-baseline.md")"

# project in a subdirectory of the repository
MONO=$T/mono
mkdir -p "$MONO/backend/src" "$MONO/other"; git init -q -b main "$MONO" 2>/dev/null || git init -q "$MONO"
echo a >"$MONO/backend/src/a.ts"; echo b >"$MONO/other/b.ts"; g "$MONO" add -A; g "$MONO" commit -qm one
M1=$(head_of "$MONO")
echo a2 >>"$MONO/backend/src/a.ts"; echo b2 >>"$MONO/other/b.ts"; g "$MONO" add -A; g "$MONO" commit -qm two
mkdir -p "$MONO/backend/.claude"; printf 'last-reviewed-commit: %s\n' "$M1" >"$MONO/backend/.claude/review-baseline.md"
check "subdirectory project: only its own files, relative to it" "src/a.ts
rc=0" "$(out "$MONO/backend")"
mutant_ne "no --relative" 's|--name-only --relative -z|--name-only -z|' "src/a.ts
rc=0" "$MONO/backend"
contains "subdirectory project: record writes inside the project" "baseline written" "$(out "$MONO/backend" --record-baseline --stack nestjs)"
check "subdirectory project: the baseline is in the subdirectory only" "0" "$(exists01 "$MONO/.claude/review-baseline.md")"

# the baseline file is not part of its own scope once it is committed
BC=$T/bcommit
mkrepo "$BC"
run "$BC" --record-baseline --stack nextjs >/dev/null 2>&1
g "$BC" add -A; g "$BC" commit -qm baseline
check "a committed baseline: an empty scope (the baseline file does not list itself)" "rc=0" "$(out "$BC")"
mkdir -p "$BC/sub/.claude"; echo x >"$BC/sub/.claude/review-baseline.md"; echo y >"$BC/src/c.ts"; g "$BC" add -A; g "$BC" commit -qm more
check "control: a file named like the baseline in another directory, and a source file, are listed" "src/c.ts${NL}sub/.claude/review-baseline.md
rc=0" "$(out "$BC")"
mutant_ne "no baseline exclude" $'s|-- \':(exclude,literal).claude/review-baseline.md\' ||' "src/c.ts${NL}sub/.claude/review-baseline.md
rc=0" "$BC"
BM=$T/bmono
mkdir -p "$BM/backend/src" "$BM/other"; git init -q -b main "$BM" 2>/dev/null || git init -q "$BM"
echo a >"$BM/backend/src/a.ts"; echo b >"$BM/other/b.ts"; g "$BM" add -A; g "$BM" commit -qm one
run "$BM/backend" --record-baseline --stack nestjs >/dev/null 2>&1
echo b2 >>"$BM/other/b.ts"; g "$BM" add -A; g "$BM" commit -qm two
check "a committed baseline in a subdirectory project: an empty scope" "rc=0" "$(out "$BM/backend")"
mutant_ne "no baseline exclude (subdirectory project)" $'s|-- \':(exclude,literal).claude/review-baseline.md\' ||' "rc=0" "$BM/backend"

# rename and deletion in the diff
RD=$T/rd
mkrepo "$RD"; RD1=$(head_of "$RD")
g "$RD" mv src/a.ts src/renamed.ts; g "$RD" rm -q src/b.ts; g "$RD" commit -qm rd
mkdir -p "$RD/.claude"; printf 'last-reviewed-commit: %s\n' "$RD1" >"$RD/.claude/review-baseline.md"
check "rename and deletion in the diff: the new name and the deleted name" "src/b.ts${NL}src/renamed.ts
rc=0" "$(out "$RD")"

# baseline shapes: trailing text, extra spaces, a tab
for shape in "x" "  " $'\t'; do
  case "$shape" in x) v="$H1 trailing" ;; "  ") v=" $H1" ;; *) v="$shape$H1" ;; esac
  bl "last-reviewed-commit: $v
"
  expect_refuse "baseline: odd shape [$(printf '%s' "$shape" | tr '\t' T)]" "$P"
done
bl "last-reviewed-commit:$H1
"
check "baseline: no space after the colon is accepted" "$WANT" "$(out "$P")"
bl "last-reviewed-commit:"$'\t'"$H1
"
expect_refuse "baseline: a tab after the colon" "$P"
bl "last-reviewed-commit: $H1
"
if [ "$NOTROOT" -eq 1 ]; then
  chmod 000 "$P/.claude/review-baseline.md"
  contains "baseline: unreadable gives the readable message" "is not readable" "$(out "$P")"
  chmod 644 "$P/.claude/review-baseline.md"
fi
# the mode of a new baseline
chmod 644 "$P/.claude/review-baseline.md"
out "$P" --record-baseline --stack nextjs >/dev/null
check "record: a 644 baseline stays 644" "644" "$(mode_of "$P/.claude/review-baseline.md")"
cp "$SRC" "$T/mutant.sh"
sed 's|chmod "[$]MODE" "[$]TMP" \|\| die "cannot set the mode of the new baseline; the old baseline stays"|:|' "$T/mutant.sh" >"$T/mutant2.sh"
if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant no chmod: sed matched nothing"; fail=1; fi
bash "$T/mutant2.sh" "$P" --record-baseline --stack nextjs >/dev/null 2>&1
check "mutant without the chmod leaves the temp file's mode (600)" "600" "$(mode_of "$P/.claude/review-baseline.md")"
chmod 644 "$P/.claude/review-baseline.md"
bl "last-reviewed-commit: $H1
"

if [ "$fail" -ne 0 ]; then echo "review-scope tests FAILED"; exit 1; fi
echo "review-scope tests passed"
