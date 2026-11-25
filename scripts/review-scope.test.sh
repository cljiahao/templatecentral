#!/usr/bin/env bash
# Behavioural test for skills/review/review/review-scope.sh.
# Real git fixtures in a temp dir. Every refusal has a clean control that passes, and a mutant of the script (one check removed)
# that lets the bad input through, so the test proves each check is what stops it. No timing, no network.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/skills/review/review/review-scope.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/scopetest.XXXXXX") || exit 1
trap '[ -d "$T" ] && chmod -R u+rwx "$T" 2>/dev/null; [ -d "$T" ] && rm -rf "$T"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
contains() { case "$3" in *"$2"*) echo "ok   $1" ;; *) echo "FAIL $1: [$2] not in [$3]"; fail=1 ;; esac; }
NL='
'
SCRIPT=$T/review-scope.sh
cp "$SRC" "$SCRIPT"
run() { bash "$SCRIPT" "$@"; }
# out <args>: stdout and stderr of a run, then its exit code on the last line
out() { local o rc; o=$(run "$@" 2>&1); rc=$?; if [ -n "$o" ]; then printf '%s\nrc=%s' "$o" "$rc"; else printf 'rc=%s' "$rc"; fi; }
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
check "record differs from before" "1" "$([ "$before" != "$(treehash "$P")" ] && echo 1 || echo 0)"
N=$T/fresh
mkrepo "$N"
check "record creates .claude when absent" "rc=0" "$(out "$N" --record-baseline --stack fastapi | sed -n '$p')"
check "record created the baseline" "1" "$([ -f "$N/.claude/review-baseline.md" ] && echo 1 || echo 0)"
NC=$T/nocommit
mkdir -p "$NC"; git init -q "$NC"
r=$(out "$NC" --record-baseline --stack nestjs)
contains "no commit: record is skipped with exit 0" "rc=0" "$r"
check "no commit: no baseline written" "0" "$([ -e "$NC/.claude/review-baseline.md" ] && echo 1 || echo 0)"
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

# --- mutants: with one check removed the same bad input gets through
mutant() { # name sed-expr bad-args-run description
  local name=$1 expr=$2; shift 2
  cp "$SRC" "$T/mutant.sh"
  sed "$expr" "$T/mutant.sh" >"$T/mutant2.sh"
  if cmp -s "$T/mutant.sh" "$T/mutant2.sh"; then echo "FAIL mutant $name: sed expression matched nothing"; fail=1; return; fi
  local r; r=$(bash "$T/mutant2.sh" "$@" 2>&1; echo "rc=$?")
  case "$r" in *"rc=0") echo "ok   mutant $name lets the bad input through" ;; *) echo "FAIL mutant $name still refused: [$r]"; fail=1 ;; esac
}
bl "last-reviewed-commit: $HS
"
mutant "no ancestor check" 's|git -C "[$]ROOT" merge-base --is-ancestor "[$]BSHA" "[$]HEAD_SHA" 2>/dev/null|true|' "$P"
bl "last-reviewed-commit: $H1
"
mutant "no session outside check" 's|/\*) die "session path [$]p is outside the project" ;;|/*) rel=x ;;|' "$P" --session /etc/passwd
mutant "no dotdot check" 's|\*/\.\./\* \| \*/\./\* \| \*//\*) die|NOMATCH) die|' "$P" --session ../outside.ts
mv "$P/.claude/review-baseline.md" "$T/real-baseline.md"; ln -s "$T/real-baseline.md" "$P/.claude/review-baseline.md"
mutant "no symlink check" 's|\[ ! -L "[$]BASE" \] \|\| die "[$]BASE is a symlink"|true|' "$P"
rm "$P/.claude/review-baseline.md"; mv "$T/real-baseline.md" "$P/.claude/review-baseline.md"
mutant "no git check" 's|git -C "[$]ROOT" rev-parse --git-dir >/dev/null 2>&1 \|\| die|true \|\| die|' "$NG"

if [ "$fail" -ne 0 ]; then echo "review-scope tests FAILED"; exit 1; fi
echo "review-scope tests passed"
