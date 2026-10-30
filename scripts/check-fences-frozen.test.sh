#!/usr/bin/env bash
# scripts/check-fences-frozen.test.sh — tests for scripts/check-fences-frozen.sh.
# Usage: bash scripts/check-fences-frozen.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROZEN="$REPO_ROOT/scripts/check-fences-frozen.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

G=tests/golden/fences
git init -q "$T/r" && cd "$T/r" || exit 2
git config user.email t@example.com && git config user.name t
mkdir -p "$G/moved.d" && echo x > README
git add -A && git commit -qm base && git branch -q initial

run() { bash "$FROZEN" "$@" > "$T/out" 2>&1; echo $?; }
commit_all() { git add -A && git commit -qm "$1"; }

# the base holds no snapshot: the initial capture passes
printf 'row\n' > "$G/add.tsv"; commit_all capture
check 0 "$(run initial)" "initial_capture_passes"
git branch -q main-with-snapshot
check 2 "$(run)" "missing_base_exits_2"
check 2 "$(run no-such-ref)" "unknown_base_exits_2"

# nothing changed, and a moved.d change, pass
git checkout -q -b slice main-with-snapshot
check 0 "$(run main-with-snapshot)" "unchanged_passes"
printf 'a\tb\t0\tc\n' > "$G/moved.d/slice-a.tsv"; commit_all slice
check 0 "$(run main-with-snapshot)" "moved_d_change_passes"

# a snapshot edit fails, and passes only with the opt-in
printf 'row2\n' > "$G/add.tsv"; commit_all edit
check 1 "$(run main-with-snapshot)" "snapshot_edit_fails"
case "$(cat "$T/out")" in *"tests/golden/fences/add.tsv"*"fence-snapshot-change"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: snapshot_edit names the file and the label [$(cat "$T/out")]" ;; esac
check 0 "$(FENCE_SNAPSHOT_CHANGE_OK=1 run main-with-snapshot)" "snapshot_edit_with_opt_in_passes"
check 1 "$(FENCE_SNAPSHOT_CHANGE_OK=yes run main-with-snapshot)" "opt_in_must_be_1"

# a new snapshot file and a deleted one fail
git checkout -q -b added main-with-snapshot
printf 'row\n' > "$G/migrate.tsv"; commit_all add-file
check 1 "$(run main-with-snapshot)" "added_snapshot_file_fails"
git checkout -q -b removed main-with-snapshot
git rm -q "$G/add.tsv"; commit_all rm
check 1 "$(run main-with-snapshot)" "deleted_snapshot_file_fails"

echo "check-fences-frozen.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
