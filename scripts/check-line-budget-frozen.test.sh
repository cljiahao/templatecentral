#!/usr/bin/env bash
# scripts/check-line-budget-frozen.test.sh — tests for scripts/check-line-budget-frozen.sh.
# Usage: bash scripts/check-line-budget-frozen.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROZEN="$REPO_ROOT/scripts/check-line-budget-frozen.sh"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}

T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

F=tests/golden/line-budget.txt
git init -q "$T/r" || exit 2
cd "$T/r" || exit 2
git config user.email t@example.com && git config user.name t
mkdir -p tests/golden skills/add/auth && echo x > README
printf 'a\n' > skills/add/auth/fastapi.md
printf 'b\n' > skills/add/auth/small.md
git add -A && git commit -qm base && git branch -q initial

run() { bash "$FROZEN" "$@" > "$T/out" 2>&1; echo $?; }
commit_all() { git add -A && git commit -qm "$1"; }
rows() { printf '# header\n'; printf '%b' "$1"; }

# the base holds no budget file: the initial capture passes
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all capture
check 0 "$(run initial)" "initial_capture_passes"
git branch -q seeded
check 2 "$(run)" "missing_base_exits_2"
check 2 "$(run no-such-ref)" "unknown_base_exits_2"

# nothing changed, a lowered row, a removed row and a lowered prose count pass
git checkout -q -b slice seeded
check 0 "$(run seeded)" "unchanged_passes"
rows 'add/auth/fastapi.md\t399\t79\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all lower
check 0 "$(run seeded)" "lowered_row_passes"
rows 'add/auth/fastapi.md\t399\t79\n' > "$F"; commit_all drop
check 0 "$(run seeded)" "removed_row_passes"

# a row raised by one line fails and names the file; a raised prose count fails
git checkout -q -b raised seeded
rows 'add/auth/fastapi.md\t401\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all raise
check 1 "$(run seeded)" "raised_max_lines_fails"
case "$(cat "$T/out")" in *"add/auth/fastapi.md: max_lines raised from 400 to 401"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: raised_max_lines names file and counts [$(cat "$T/out")]" ;; esac
git checkout -q -b raised-prose seeded
rows 'add/auth/fastapi.md\t400\t81\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all raise-prose
check 1 "$(run seeded)" "raised_max_prose_fails"
git checkout -q -b kind seeded
rows 'add/auth/fastapi.md\t400\t-\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all kind
check 1 "$(run seeded)" "prose_kind_change_fails"

# a new row never passes after the initial capture: not for a file that existed, not for a new file
git checkout -q -b newrow-existing seeded
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\nadd/auth/small.md\t90\t40\n' > "$F"; commit_all existing
check 1 "$(run seeded)" "new_row_for_existing_file_fails"
git checkout -q -b newrow-new seeded
printf 'c\n' > skills/add/auth/fresh.md
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\nadd/auth/fresh.md\t150\t50\n' > "$F"; commit_all fresh
check 1 "$(run seeded)" "new_row_for_new_file_fails"
case "$(cat "$T/out")" in *"add/auth/fresh.md: new row"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: new_row_names_file [$(cat "$T/out")]" ;; esac
git checkout -q -b renamed seeded
git mv skills/add/auth/small.md skills/add/auth/tiny.md
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all rename-clean
check 0 "$(run seeded)" "renamed_file_without_row_passes"
git checkout -q -b renamed-row seeded
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\n' > "$F"
git mv skills/add/auth/fastapi.md skills/add/auth/fastapi2.md
rows 'add/auth/fastapi2.md\t400\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all rename-row
check 1 "$(run seeded)" "renamed_file_with_renamed_row_fails"

# an unparseable or duplicate head row fails closed
git checkout -q -b garbled seeded
rows 'add/auth/fastapi.md\t400\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all garbled
check 1 "$(run seeded)" "missing_column_fails"
rows 'add/auth/fastapi.md\t400\t80\nadd/auth/fastapi.md\t300\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all dup
check 1 "$(run seeded)" "duplicate_row_fails"

# a CRLF row, a malformed base row and a head file with no data rows fail; the unchanged file passes
git checkout -q -b crlf seeded
rows 'add/auth/fastapi.md\t400\t80\r\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all crlf
check 1 "$(run seeded)" "crlf_row_fails"
git checkout -q -b badbase initial
mkdir -p tests/golden
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\n' > "$F"; commit_all badbase-capture
git branch -q badbase-base
git checkout -q -b badbase-fix badbase-base
rows 'add/auth/fastapi.md\t400\t80\nCONVENTIONS.md\t354\t-\n' > "$F"; commit_all badbase-fix
check 1 "$(run badbase-base)" "malformed_base_row_fails"
git checkout -q -b empty-head seeded
rows '' > "$F"; commit_all empty
check 1 "$(run seeded)" "head_without_data_rows_fails"
case "$(cat "$T/out")" in *"restore it from git"*) PASS=$((PASS + 1)) ;; *) FAIL=$((FAIL + 1)); echo "FAIL: empty_head_says_restore [$(cat "$T/out")]" ;; esac

# a known ref with no merge base is a usage error, not a pass
git checkout -q --orphan unrelated
git rm -rfq . > /dev/null 2>&1
echo y > other; git add -A; git commit -qm unrelated
git checkout -q slice
check 2 "$(run unrelated)" "no_merge_base_exits_2"

# a git error on the merge base tree is exit 2, not an initial capture: drop the tree object in a copy
git clone -q "$T/r" "$T/e" 2> /dev/null
( cd "$T/e" || exit 2
  git config user.email t@example.com; git config user.name t
  git checkout -q -b head2 origin/seeded
  echo z >> README; git add -A; git commit -qm head2
  check 0 "$(run origin/seeded)" "tree_control_runs_on_intact_repo"
  tree=$(git rev-parse "origin/seeded^{tree}")
  obj=".git/objects/${tree:0:2}/${tree:2}"
  if [[ -f "$obj" ]]; then
    rm -f "$obj"
    check 2 "$(run origin/seeded)" "ls_tree_git_error_exits_2"
  else
    echo "FAIL: the tree object is not loose, so the git error path was not built"; FAIL=$((FAIL + 1))
  fi
  echo "$PASS $FAIL" > "$T/counts"
)
read -r PASS FAIL < "$T/counts"

# a missing head file fails (git show errors) and is not read as a pass
git checkout -q -b gone seeded
git rm -q "$F"; commit_all gone
check 2 "$(run seeded)" "missing_head_file_exits_2"

echo "check-line-budget-frozen.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
