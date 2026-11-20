#!/usr/bin/env bash
# scripts/seeded-change-size.test.sh — the seeded check-change-size gate: it fails over the line or file budget, ignores lockfiles, generated files and snapshots,
# and fails closed without a base ref. Fixtures are throwaway git repositories; a real run uses a freshly scaffolded nextjs project.
# Usage: bash scripts/seeded-change-size.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$REPO_ROOT/skills/scaffold/shared"
GATE="$SH/template/scripts/check-change-size.sh"

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
  OUT=$(cd "$d" && env -u CI -u TF_BUILD -u GITHUB_ACTIONS -u BASE_REF -u CHANGE_SIZE_MAX_LINES -u CHANGE_SIZE_MAX_FILES "$@" "$BASH_BIN" "$GATE" 2>&1)
  EC=$?
}
# lines <n> <file>: writes n lines.
lines() { seq 1 "$1" > "$2"; }

# repo <name>: a repository with a base commit on main and a work branch checked out; sets D.
repo() {
  D="$T/$1"
  mkdir -p "$D"
  (cd "$D" && git init -q -b main . && echo base > README.md && git add -A && git commit -q -m base && git checkout -q -b work)
}
commit_all() { (cd "$D" && git add -A && git commit -q -m change); }

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
mkdir -p "$D/src/__snapshots__" "$D/src/generated"
lines 5000 "$D/src/__snapshots__/a.snap"
lines 5000 "$D/src/__snapshots__/b.txt"
lines 5000 "$D/src/api.generated.ts"
lines 5000 "$D/src/generated/types.ts"
lines 5000 "$D/dist.min.js"
lines 20 "$D/real.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "lockfiles, generated files and snapshots are not counted ($OUT)"
has "ok (20 lines in 1 files" "$OUT" "only the real file is counted"

repo notexcluded
lines 5000 "$D/package-lock.json.bak"
commit_all
run "$D" BASE_REF=main
check 1 "$EC" "a file that only looks like a lockfile is counted"

repo binary
head -c 2000 /dev/urandom > "$D/image.bin"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "a binary file counts as a file with no lines ($OUT)"
has "ok (0 lines in 1 files" "$OUT" "binary counts one file"

repo uncommitted
lines 900 "$D/tracked.txt"
commit_all
git -C "$D" checkout -q main
git -C "$D" checkout -q -b work3
echo base2 >> "$D/README.md"
lines 900 "$D/README.md"
run "$D" BASE_REF=main
check 1 "$EC" "uncommitted edits to tracked files count"

repo quoted
mkdir -p "$D/generated" "$D/sp ace"
lines 5000 "$D/generated/café x.ts"
lines 5000 "$D/bun.lock"
printf 'x' > "$D/bun.lockb"
lines 7 "$D/sp ace/naïve file.txt"
commit_all
run "$D" BASE_REF=main
check 0 "$EC" "paths with spaces and non-ASCII names under excluded rules are handled ($OUT)"
has "ok (7 lines in 1 files" "$OUT" "bun.lock, bun.lockb and the generated file are excluded; the spaced path counts once"
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
has "untracked files are" "$OUT" "message says untracked files are counted"
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
OUT=$(cd "$D" && env -u CI "$BASH_BIN" "$GATE" main 2>&1)
check 0 $? "a base ref given as an argument works ($OUT)"

D="$T/notgit"
mkdir -p "$D"
run "$D" BASE_REF=main
check 2 "$EC" "outside a git repository it fails closed"
has "not a git repository" "$OUT" "message says not a git repository"

# Real run: a freshly scaffolded nextjs project, committed as the base, then one real edit.
D="$T/real"
mkdir -p "$D"
TC_STACK=nextjs TC_PART=stack bash "$SH/tc-copy.sh" "$D" > /dev/null
check 0 $? "nextjs scaffold copies"
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
