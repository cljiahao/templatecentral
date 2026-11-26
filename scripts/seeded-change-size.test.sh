#!/usr/bin/env bash
# scripts/seeded-change-size.test.sh — the seeded check-change-size gate: it fails over the line or file budget, ignores the lockfiles in its exclude file and files marked linguist-generated, weighs binaries by size,
# and fails closed without a base ref. Fixtures are throwaway git repositories; a real run uses a freshly scaffolded nextjs project.
# Usage: bash scripts/seeded-change-size.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="${SEEDED_CHANGE_SIZE_GATE:-$SH/template/scripts/check-change-size.sh}"
EXCLUDE="$SH/template/.claude/change-size-exclude.txt"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/seeded-cs.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

BASH_BIN=$(command -v bash)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# run <dir> [args]: sets OUT and EC from running the gate inside a fixture repository; extra env comes from the caller.
run() {
  local d=$1
  shift
  OUT=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS -u BASE_REF -u CHANGE_SIZE_MAX_LINES -u CHANGE_SIZE_MAX_FILES -u CHANGE_SIZE_EXCLUDE_FILE "$@" "$BASH_BIN" "$GATE" 2>&1)
  EC=$?
}
# rand_bin <n>: writes n bytes that git sees as binary (NUL bytes) and that hold no newline, so the size weight alone decides.
rand_bin() { head -c "$1" /dev/zero; }
# lines <n> <file>: writes n lines.
lines() { seq 1 "$1" > "$2"; }

# repo <name>: a repository with a base commit on main and a work branch checked out; sets D.
repo() {
  D="$T/$1"
  mkdir -p "$D"
  mkdir -p "$D/.claude"
  cp "$EXCLUDE" "$D/.claude/change-size-exclude.txt"
  (cd "$D" && git init -q -b main . && echo base > README.md && git add -A && git commit -q -m base && git checkout -q -b work)
}
commit_all() { (cd "$D" && git add -A && git commit -q -m change); }
# base_commit: puts what is in the working tree onto main as a second base commit and moves the work branch onto it, so the merge base has it.
base_commit() { (cd "$D" && git checkout -q main && git add -A -- "${@:-.}" && git commit -q -m base2 && git checkout -q work && git rebase -q main); }

repo control
lines 10 "$D/a.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: a small change passes ($OUT)"
has "ok (10 lines in 1 files" "$OUT" "control reports the counts"

repo big
lines 900 "$D/big.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "900 changed lines fail the default 800 budget"
has "900 changed lines (budget 800)" "$OUT" "message gives the line count and budget"
has "big.txt" "$OUT" "message names the biggest file"
has "split the change" "$OUT" "message says to split the change"

repo many
for i in $(seq 1 41); do echo x > "$D/f$i.txt"; done
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "41 changed files fail the default 40 budget"
has "in 41 files (budget 40)" "$OUT" "message gives the file count and budget"

repo edge
lines 761 "$D/edge.txt"
for i in $(seq 1 39); do echo x > "$D/f$i.txt"; done
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "exactly at both budgets passes ($OUT)"

repo deleted
lines 600 "$D/a.txt"
commit_all
git -C "$D" checkout -q main
git -C "$D" checkout -q -b work2
git -C "$D" checkout -q work -- a.txt
git -C "$D" commit -q -m add
git -C "$D" rm -q a.txt
lines 500 "$D/b.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "a file added then deleted on the branch counts nothing ($OUT)"

repo excluded
lines 5000 "$D/pnpm-lock.yaml"
lines 5000 "$D/uv.lock"
lines 5000 "$D/requirements.txt"
mkdir -p "$D/web"
lines 5000 "$D/web/package-lock.json"
lines 20 "$D/real.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "the lockfiles in the exclude file are not counted ($OUT)"
has "ok (20 lines in 1 files" "$OUT" "only the real file is counted"

# Names that look generated are counted, unless .gitattributes marks the file.
repo lookalike
mkdir -p "$D/src/generated"
lines 900 "$D/src/api.generated.ts"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a *.generated.* name alone does not exclude a file"
repo lookalike2
mkdir -p "$D/src/generated"
lines 900 "$D/src/generated/types.ts"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a generated/ folder name alone does not exclude a file"
repo lookalike3
lines 900 "$D/app.min.js"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a *.min.js name alone does not exclude a file"
repo lookalike4
lines 900 "$D/app.js.map"
lines 900 "$D/a.snap"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "*.map and *.snap names alone do not exclude a file"

# attrs_repo <name> <.gitattributes text>: a repository whose merge base already carries the attributes.
attrs_repo() {
  repo "$1"
  printf '%s' "$2" > "$D/.gitattributes"
  base_commit
}
generated_files() {
  mkdir -p "$D/src/generated"
  lines 5000 "$D/src/generated/types.ts"
  lines 5000 "$D/src/api.generated.ts"
  lines 5000 "$D/other.ts"
  lines 20 "$D/real.txt"
}
attrs_repo marked 'src/generated/* linguist-generated
*.generated.ts linguist-generated=true
'
generated_files
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "files marked linguist-generated at the merge base are dropped but an unmarked big file still counts"
has "5020 changed lines" "$OUT" "5000 + 20, no generated lines"
attrs_repo marked-all 'src/generated/* linguist-generated
*.generated.ts linguist-generated=true
other.ts linguist-generated
'
generated_files
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "marking the third file too brings the change within budget ($OUT)"
attrs_repo marked-unset 'src/generated/* -linguist-generated
'
generated_files
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "-linguist-generated (unset) does not exclude"

# A change cannot switch off its own gate: attributes and the exclude list come from the merge base.
repo selfattr
(cd "$D" && seq 50000 > big.txt && echo '* linguist-generated' > .gitattributes)
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a .gitattributes added by the change does not exclude the change"
has "changed lines (budget 800)" "$OUT" "message gives the budget"
repo selfattr-uncommitted
(cd "$D" && seq 50000 > big.txt && echo '* linguist-generated' > .gitattributes)
run "$D" BASE_REF=main
check 1 "$EC" "an uncommitted .gitattributes does not exclude the change"
repo selfexclude
(cd "$D" && seq 50000 > big.txt && echo '*' >> .claude/change-size-exclude.txt)
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a catch-all added to the exclude list by the change does not exclude the change"
has "changed lines (budget 800)" "$OUT" "message gives the budget for the exclude repro"
repo selfexclude-uncommitted
(cd "$D" && seq 50000 > big.txt && echo '*' >> .claude/change-size-exclude.txt)
run "$D" BASE_REF=main
check 1 "$EC" "an uncommitted catch-all in the exclude list does not exclude the change"
repo baseexclude
printf 'big.txt\n' >> "$D/.claude/change-size-exclude.txt"
base_commit
(cd "$D" && seq 50000 > big.txt)
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: an exclusion already at the merge base is honoured ($OUT)"
repo baseattr
printf 'big.txt linguist-generated\n' > "$D/.gitattributes"
base_commit
(cd "$D" && seq 50000 > big.txt)
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: an attribute already at the merge base is honoured ($OUT)"

# Without git check-attr --source the attributes cannot be read at the merge base: fail closed, never read the working tree.
repo nosource
lines 10 "$D/a.txt"
commit_all
mkdir -p "$D/shim"
REAL_GIT=$(command -v git)
cat > "$D/shim/git" << EOS
#!/bin/sh
case "\$*" in
  *check-attr*--source*) echo "error: unknown option 'source'" >&2; exit 129 ;;
esac
exec "$REAL_GIT" "\$@"
EOS
chmod +x "$D/shim/git"
run "$D" BASE_REF=main PATH="$D/shim:$PATH"
check 2 "$EC" "a git without check-attr --source fails closed"
has "needs git 2.40 or newer" "$OUT" "message states the minimum git version"
run "$D" BASE_REF=main
check 0 "$EC" "control: the same repository passes with the real git ($OUT)"

# The exclude file is data: a line there is honoured when it is at the merge base.
repo custom
lines 5000 "$D/vendor-data.txt"
printf 'vendor-data.txt\n' >> "$D/.claude/change-size-exclude.txt"
base_commit .claude/change-size-exclude.txt
lines 20 "$D/real.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "a line in the exclude file at the merge base is honoured ($OUT)"
printf '# only comments\n' > "$D/other-exclude.txt"
run "$D" BASE_REF=main CHANGE_SIZE_EXCLUDE_FILE=other-exclude.txt
check 1 "$EC" "CHANGE_SIZE_EXCLUDE_FILE points the gate at another list"
# With no list at the merge base nothing is excluded, and the working-tree list is never read.
repo noexclude
rm "$D/.claude/change-size-exclude.txt"
base_commit
lines 10 "$D/a.txt"
lines 5000 "$D/pnpm-lock.yaml"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "with no list at the merge base a lockfile counts"
has "Exclusions apply once the file is on the base branch" "$OUT" "message says exclusions apply once the file is on the base branch"
repo noexclude-self
rm "$D/.claude/change-size-exclude.txt"
base_commit
mkdir -p "$D/.claude"
echo '*' > "$D/.claude/change-size-exclude.txt"
seq 50000 > "$D/big.txt"
run "$D" BASE_REF=main
check 1 "$EC" "a catch-all list added by the change is not read when the base has none"
has "changed lines (budget 800)" "$OUT" "message gives the budget"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "the same catch-all list, committed, is not read either"
repo withexclude
lines 5000 "$D/pnpm-lock.yaml"
lines 10 "$D/a.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: the same lockfile with the list at the merge base passes ($OUT)"
hasnt_msg() { if [[ "$2" == *"$1"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] in [$2]"; else PASS=$((PASS + 1)); fi; }
hasnt_msg "Exclusions apply once" "$OUT" "control prints no missing-list line"

# Overrides that can widen the gate are refused in CI.
repo ci
lines 900 "$D/big.txt"
commit_all
printf 'big.txt\n' > "$D/ex.txt"
for ci in GITHUB_ACTIONS=true TF_BUILD=True; do
  run "$D" BASE_REF=main "$ci" CHANGE_SIZE_MAX_LINES=5000
  check 2 "$EC" "CHANGE_SIZE_MAX_LINES is refused with $ci"
  has "not allowed in CI" "$OUT" "line-budget refusal under $ci says why"
  run "$D" BASE_REF=main "$ci" CHANGE_SIZE_MAX_FILES=500
  check 2 "$EC" "CHANGE_SIZE_MAX_FILES is refused with $ci"
  run "$D" BASE_REF=main "$ci" CHANGE_SIZE_EXCLUDE_FILE=ex.txt
  check 2 "$EC" "CHANGE_SIZE_EXCLUDE_FILE is refused with $ci"
done
run "$D" BASE_REF=main CHANGE_SIZE_MAX_LINES=5000
check 0 "$EC" "CHANGE_SIZE_MAX_LINES is allowed outside CI ($OUT)"
run "$D" BASE_REF=main CHANGE_SIZE_EXCLUDE_FILE=ex.txt
check 0 "$EC" "CHANGE_SIZE_EXCLUDE_FILE is allowed outside CI ($OUT)"
run "$D" BASE_REF=main GITHUB_ACTIONS=true
check 1 "$EC" "CI without overrides still measures"

repo notexcluded
lines 5000 "$D/package-lock.json.bak"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a file that only looks like a lockfile is counted"

repo binary
rand_bin 2000 > "$D/image.bin"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "a small binary counts one line ($OUT)"
has "ok (1 lines in 1 files" "$OUT" "2000 bytes weigh one line"

repo bigbinary
rand_bin 5000000 > "$D/video.bin"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a 5 MB committed binary fails the line budget"
has "1221 changed lines" "$OUT" "5000000 bytes weigh 1221 lines (4 KB each, rounded up)"

repo binuntracked
rand_bin 5000000 > "$D/video.bin"
run "$D" BASE_REF=main
check 1 "$EC" "a 5 MB untracked binary fails the line budget"
has "1221 changed lines" "$OUT" "an untracked binary weighs the same"

repo bindeleted
rand_bin 5000000 > "$D/video.bin"
commit_all
git -C "$D" checkout -q main
git -C "$D" checkout -q -b work4
git -C "$D" checkout -q work -- video.bin
git -C "$D" commit -q -m addbin
git -C "$D" checkout -q -b work5
git -C "$D" rm -q video.bin
git -C "$D" commit -q -m rmbin
git -C "$D" checkout -q work4
git -C "$D" reset -q --hard main
git -C "$D" checkout -q work -- video.bin
git -C "$D" commit -q -m addbin2
git -C "$D" rm -q video.bin
run "$D" BASE_REF=main
check 0 "$EC" "a binary added and removed again counts nothing ($OUT)"

repo uncommitted
lines 900 "$D/tracked.txt"
commit_all
git -C "$D" checkout -q main
git -C "$D" checkout -q -b work3
echo base2 >> "$D/README.md"
lines 900 "$D/README.md"
run "$D" BASE_REF=main
check 1 "$EC" "uncommitted edits to tracked files count"

attrs_repo quoted 'web/café?x.lock linguist-generated
'
mkdir -p "$D/sp ace" "$D/web"
lines 5000 "$D/web/café x.lock"
lines 5000 "$D/bun.lock"
printf 'x' > "$D/bun.lockb"
lines 7 "$D/sp ace/naïve file.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "paths with spaces and non-ASCII names under excluded rules are handled ($OUT)"
has "ok (7 lines in 1 files" "$OUT" "bun.lock, bun.lockb and the marked file are excluded; the spaced path counts"
lines 900 "$D/sp ace/naïve file.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a spaced non-ASCII path is counted in full"
has "naïve file.txt" "$OUT" "message prints the path unquoted"

repo untracked
lines 900 "$D/new.txt"
run "$D" BASE_REF=main
check 1 "$EC" "an untracked file counts toward the budget"
has "900 changed lines (budget 800)" "$OUT" "message counts the untracked lines"
has "new.txt" "$OUT" "message names the untracked file"
has "untracked files and binaries" "$OUT" "message says untracked files are counted"
printf 'new.txt\n' > "$D/.gitignore"
run "$D" BASE_REF=main
check 0 "$EC" "an ignored file does not count ($OUT)"
lines 5000 "$D/pnpm-lock.yaml"
run "$D" BASE_REF=main
check 0 "$EC" "an untracked lockfile does not count ($OUT)"

repo override
lines 900 "$D/big.txt"
commit_all
run "$D" BASE_REF=main CHANGE_SIZE_MAX_LINES=1000
check 0 "$EC" "CHANGE_SIZE_MAX_LINES raises the line budget ($OUT)"
run "$D" BASE_REF=main CHANGE_SIZE_MAX_LINES=100
check 1 "$EC" "CHANGE_SIZE_MAX_LINES lowers the line budget"
has "budget 100" "$OUT" "message shows the overridden budget"
run "$D" BASE_REF=main CHANGE_SIZE_MAX_FILES=0
check 1 "$EC" "CHANGE_SIZE_MAX_FILES lowers the file budget"
run "$D" BASE_REF=main CHANGE_SIZE_MAX_LINES=lots
check 2 "$EC" "a non-numeric budget fails closed"
has "budgets must be whole numbers" "$OUT" "message names the bad budget"

repo base
lines 10 "$D/a.txt"
commit_all
run "$D" BASE_REF=nonexistent
check 2 "$EC" "a missing base ref fails closed"
has "base ref 'nonexistent' not found" "$OUT" "message names the missing ref"
has "git fetch origin main" "$OUT" "message says how to fix it"
run "$D"
check 2 "$EC" "the default origin/main is missing here, so it fails closed"
has "base ref 'origin/main' not found" "$OUT" "default base is origin/main"
OUT=$(cd "$D" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD "$BASH_BIN" "$GATE" main 2>&1)
check 0 $? "a base ref given as an argument works ($OUT)"

D="$T/notgit"
mkdir -p "$D"
run "$D" BASE_REF=main
check 2 "$EC" "outside a git repository it fails closed"
has "not a git repository" "$OUT" "message says not a git repository"

# Attributes added by the change must not make a text file look binary (a binary weighs one line per 4 KB, text one per line).
# attr_change <name> <attributes text> <path>: three 20000-line files under src/ plus the attributes file at <path>, all in the change.
attr_change() {
  repo "$1"
  mkdir -p "$D/src" "$D/sub"
  for i in 1 2 3; do seq 1 20000 > "$D/src/f$i.txt"; done
  if [ -n "$2" ]; then printf '%s\n' "$2" > "$D/$3"; fi
  commit_all
  run "$D" BASE_REF=main
}
attr_change attrclean "" ""
check 1 "$EC" "control: three 20000-line text files fail the budget"
has "60000 changed lines" "$OUT" "control counts every line"
attr_change attrdiff 'src/** -diff' .gitattributes
check 1 "$EC" "a -diff attribute added by the change does not hide the lines"
has "60001 changed lines" "$OUT" "-diff attribute: every line still counted"
attr_change attrbinary 'src/** binary' .gitattributes
check 1 "$EC" "a binary attribute added by the change does not hide the lines"
has "60001 changed lines" "$OUT" "binary attribute: every line still counted"
attr_change attrsub '* -diff' sub/.gitattributes
check 1 "$EC" "a -diff attribute in a subfolder does not hide the lines"
attr_change attrsub2 '* -diff' src/.gitattributes
check 1 "$EC" "a -diff attribute in the changed folder does not hide the lines"
has "60001 changed lines" "$OUT" "folder attribute: every line still counted"
repo attrbase
printf 'src/** -diff\n' > "$D/.gitattributes"
base_commit
mkdir -p "$D/src"
for i in 1 2 3; do seq 1 20000 > "$D/src/f$i.txt"; done
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a -diff attribute, even one already on the base branch, cannot lower the count"
has "60000 changed lines" "$OUT" "-diff at the base: every line still counted"
repo attrbin
mkdir -p "$D/src"
rand_bin 5000000 > "$D/src/video.bin"
printf 'src/** -diff\n' > "$D/.gitattributes"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a real binary is still weighed by size under a -diff attribute"
has "1222 changed lines" "$OUT" "5000000 bytes plus the attributes line"

# A content trick must not make a file weigh less than its lines: one leading NUL byte makes git call a text file binary (numstat "- -").
nul_lead() { # nul_lead <n> <file>: n text lines behind one NUL byte
  { printf '\0'; seq 1 "$1"; } > "$2"
}
repo nulled
nul_lead 20000 "$D/big.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a committed 20000-line text file led by a NUL byte fails the budget"
has "20000 changed lines" "$OUT" "the NUL-led file weighs its newline count"

repo nulleduntracked
nul_lead 20000 "$D/big.txt"
run "$D" BASE_REF=main
check 1 "$EC" "the same NUL-led file, untracked, fails the budget"
has "20000 changed lines" "$OUT" "the untracked NUL-led file weighs its newline count"

repo nulledcontrol
seq 1 20000 > "$D/big.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "control: the same 20000 lines without the NUL byte fail the same way"
has "20000 changed lines" "$OUT" "the clean text file weighs its lines"

repo nulledsmall
nul_lead 100 "$D/small.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: a small NUL-led file still passes ($OUT)"

repo nulledmod
seq 1 20000 > "$D/big.txt"
base_commit big.txt
nul_lead 20000 "$D/big.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a base text file turned binary by a NUL byte weighs the old and new newline counts"
has "40000 changed lines" "$OUT" "old plus new newlines"

# Attributes in .git/info/attributes (the author's own file, never part of the change) cannot lower a count either.
repo infoattr
lines 2000 "$D/a.txt"
printf 'a.txt -diff\n' >> "$D/.git/info/attributes"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a -diff line in .git/info/attributes does not hide 2000 lines"
has "2000 changed lines" "$OUT" "info/attributes -diff: every line counted"

repo infogen
lines 2000 "$D/a.txt"
printf 'a.txt linguist-generated\n' >> "$D/.git/info/attributes"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "linguist-generated in .git/info/attributes does not drop the file"
has "2000 changed lines" "$OUT" "info/attributes linguist-generated: every line counted"

repo infocontrol
lines 2000 "$D/a.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "control: the same 2000 lines with no attributes fail"
has "2000 changed lines" "$OUT" "control counts 2000 lines"

repo infobase
lines 2000 "$D/a.txt"
printf 'a.txt linguist-generated\n' > "$D/.gitattributes"
base_commit a.txt .gitattributes
lines 2100 "$D/a.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: linguist-generated at the merge base is still honoured ($OUT)"

# A tracked text file weighs the bytes on its changed lines too: one huge line, CR-only line ends, a huge deleted file and a huge added line all weigh their size, and a one-line edit to a large file stays small.
# oneline <bytes> <file>: writes one line of that many bytes with a trailing newline.
oneline() { { head -c "$1" /dev/zero | tr '\0' x; echo; } > "$2"; }
# crlines <n> <file>: writes n ten-byte records separated by CR only, with no newline at all.
crlines() { yes recordNNN | head -n "$1" | tr '\n' '\r' > "$2"; }

repo tcontrol
lines 3 "$D/t.txt"
base_commit t.txt
echo changed > "$D/t.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: a small edit to a tracked text file passes ($OUT)"

repo tbig
lines 3 "$D/t.txt"
base_commit t.txt
oneline 5000000 "$D/t.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a tracked text file replaced by one 5 MB line fails"
has "t.txt" "$OUT" "the 5 MB line message names the file"
has "1221 lines  t.txt" "$OUT" "the 5 MB line weighs one line per 4 KB"

repo tgrow
lines 10 "$D/t.txt"
base_commit t.txt
oneline 5000000 "$D/extra.txt"
{ cat "$D/extra.txt"; } >> "$D/t.txt"
rm "$D/extra.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a modified tracked file that grows by one 5 MB line fails"

repo tcr
lines 3 "$D/t.txt"
base_commit t.txt
crlines 400000 "$D/t.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a tracked file of 400000 CR-only records (4 MB, no newline) fails"

repo tcrcontrol
lines 3 "$D/t.txt"
base_commit t.txt
crlines 4000 "$D/t.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "control: a small CR-only tracked file passes ($OUT)"

repo tmix
lines 3 "$D/a.txt"
lines 3 "$D/b.txt"
base_commit a.txt b.txt
oneline 3000000 "$D/a.txt"
crlines 200000 "$D/b.txt"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a 3 MB one-line file and a 2 MB CR-only file together exceed the budget"

repo tdel
oneline 5000000 "$D/huge.txt"
base_commit huge.txt
(cd "$D" && git rm -q huge.txt && git commit -qm del)
run "$D" BASE_REF=main
check 1 "$EC" "deleting a tracked 5 MB one-line file fails"

repo tdelcontrol
lines 3 "$D/small.txt"
base_commit small.txt
(cd "$D" && git rm -q small.txt && git commit -qm del)
run "$D" BASE_REF=main
check 0 "$EC" "control: deleting a small tracked file passes ($OUT)"

repo tedit
seq 1 50000 > "$D/large.txt"
base_commit large.txt
(cd "$D" && awk 'NR == 25000 { print "edited"; next } { print }' large.txt > l2 && mv l2 large.txt)
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "a one-line edit to a large tracked file stays small ($OUT)"
has "ok (2 lines in 1 files" "$OUT" "the one-line edit weighs what git reports"

repo dashpath
lines 10 "$D/-dash.txt"
run "$D" BASE_REF=main
check 0 "$EC" "an untracked path that starts with a dash is read as a file ($OUT)"
has "ok (10 lines in 1 files" "$OUT" "the dash path weighs its lines"

repo dashbin
{ rand_bin 5000000; } > "$D/-bin.dat"
run "$D" BASE_REF=main
check 1 "$EC" "a 5 MB untracked dash-named binary fails on size, not on a read error"

# A changed file's name is data, not a pathspec: names that look like pathspec magic weigh like any other file, and git is never asked to read them as magic.
# magic_case <label> <file name>: a tracked 3-line file of that name replaced by one 5 MB line fails the gate (a clean control with a small edit passes).
magic_case() {
  repo "mg-$1-control"
  lines 3 "$D/$2"
  base_commit
  echo changed > "$D/$2"
  commit_all
  run "$D" BASE_REF=main
  check 0 "$EC" "control: a small edit to a tracked file named $2 passes ($OUT)"
  repo "mg-$1"
  lines 3 "$D/$2"
  base_commit
  oneline 5000000 "$D/$2"
  commit_all
  run "$D" BASE_REF=main
  check 1 "$EC" "a tracked 5 MB one-line file named $2 goes over budget ($OUT)"
  has "1221 lines" "$OUT" "the file named $2 weighs one line per 4 KB"
}
magic_case plain ":name"
magic_case glob ":(glob)x"
magic_case top ":(top)zz"
magic_case icase ":(icase)ZZ"
magic_case attr ":(attr:foo)bar"
magic_case bad ":(bad)x"

# Fail closed: when git counts lines for a path but its own per-file diff holds no hunk, the gate stops with exit 2 instead of weighing the file at its line count.
repo nohunk
lines 3 "$D/t.txt"
base_commit
oneline 5000000 "$D/t.txt"
commit_all
mkdir -p "$T/nohunk-shim"
cat > "$T/nohunk-shim/git" << EOS
#!/bin/sh
case "\$*" in
  *" -U0 "*) exit 0 ;;
esac
exec "$(command -v git)" "\$@"
EOS
chmod +x "$T/nohunk-shim/git"
run "$D" BASE_REF=main
check 1 "$EC" "control: the real git weighs the 5 MB line ($OUT)"
run "$D" BASE_REF=main PATH="$T/nohunk-shim:$PATH"
check 2 "$EC" "a per-file diff with no hunk fails closed ($OUT)"
has "has no hunk" "$OUT" "the no-hunk message says why"

# Real run: a freshly scaffolded nextjs project, committed as the base, then one real edit.
D="$T/real"
mkdir -p "$D"
TC_STACK=nextjs TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
check 0 $? "nextjs scaffold copies"
mkdir -p "$D/.claude"
cp "$EXCLUDE" "$D/.claude/change-size-exclude.txt"
(cd "$D" && git init -q -b main . && git add -A && git commit -q -m scaffold && git checkout -q -b feature && printf '\n// change\n' >> next.config.ts && git commit -qam change)
run "$D" BASE_REF=main
check 0 "$EC" "real nextjs scaffold with a small edit passes ($OUT)"
echo "real run small edit: $OUT"
(cd "$D" && lines 900 src/bulk.ts && git add -A && git commit -qm bulk)
run "$D" BASE_REF=main
check 1 "$EC" "real nextjs scaffold with a bulk edit fails"
echo "real run bulk edit:"
printf '%s\n' "$OUT"

echo "seeded-change-size.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
