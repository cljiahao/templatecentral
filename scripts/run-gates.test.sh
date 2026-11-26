#!/usr/bin/env bash
# scripts/run-gates.test.sh — tests for scripts/run-gates.sh (the local changed-gates runner).
# Usage: bash scripts/run-gates.test.sh
# Runs the script in scratch git repos under $TMPDIR with stub gates, so it is fast and reads no clock.
# Each rule has a clean control and a case that fails when the rule is removed. The last block checks the
# real workflow and the real map against each other, and plants a drift into copies of both.
# RG_SCRIPT=<file in scripts/> tests another copy of the script (used to try mutants of it).
set -uo pipefail
exec < /dev/null # nothing here may wait on a terminal

REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
RG="${RG_SCRIPT:-$REAL/scripts/run-gates.sh}"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <text> <needle> <description>
  if [[ "$1" == *"$2"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$2] not in output"; fi
}

# A run of this test inside a gate that a broken copy started is refused, so a mutant cannot recurse.
if [ -n "${RG_TEST_NESTED:-}" ]; then echo "run-gates.test.sh: nested run refused" >&2; exit 2; fi
export RG_TEST_NESTED=1

# lim <command...>: run it in its own process group and kill the group after 60 s, so a blocked run fails the check.
lim() {
  perl -e '$s = 60; setpgrp(0, 0); $p = fork; if (!$p) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$$; exit 124 }; alarm $s; waitpid($p, 0); exit($? >> 8)' "$@"
}

T=$(mktemp -d "${TMPDIR:-/tmp}/run-gates-test.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
export RAN_LOG="$T/ran.log"
unset STUB_FAIL STUB_ENV
N=0
R=""

stub() { { printf '#!/usr/bin/env bash\n'; cat; } > "$R/scripts/$1"; } # stub <name>: the body comes from stdin

TPL="$T/template"

# Build the template repo once: stub gates, a stub workflow and map, a base commit on main and origin/main.
build_template() {
  R="$TPL"
  mkdir -p "$R/scripts" "$R/.github/workflows" "$R/skills/a" "$R/skills/c" "$R/skills/f" "$R/docs"
  cp "$RG" "$R/scripts/run-gates.sh"
  stub a.sh <<'EOF'
echo a >> "$RAN_LOG"
if IFS= read -r -t 1 _l; then echo got >> "$RAN_LOG.stdin"; fi
EOF
  stub b.test.sh <<'EOF'
echo b >> "$RAN_LOG"
EOF
  stub c.sh <<'EOF'
echo "c${1:+:$1}" >> "$RAN_LOG"
EOF
  stub f.sh <<'EOF'
echo f >> "$RAN_LOG"; if [ "${STUB_FAIL:-}" = 1 ]; then echo "boom: stub failed"; exit 1; fi
EOF
  stub frozen.sh <<'EOF'
echo "frozen:$1" >> "$RAN_LOG"
EOF
  stub envg.sh <<'EOF'
echo "env:${STUB_ENV:-unset}" >> "$RAN_LOG"
EOF
  cat > "$R/.github/workflows/validate-skills.yml" <<'EOF'
name: stub
on: [pull_request]
jobs:
  j:
    runs-on: x
    steps:
      - name: a
        run: bash scripts/a.sh
      - name: b
        run: bash scripts/b.test.sh
      - name: c probe, then c
        run: |
          rc=0
          bash scripts/c.sh --probe || rc=$?
          bash scripts/c.sh
      - name: f
        run: bash scripts/f.sh
      - name: frozen
        env:
          BASE_REF: main
        run: bash scripts/frozen.sh "origin/$BASE_REF"
      - name: env
        run: bash scripts/envg.sh
EOF
  {
    printf '# stub map\n'
    printf '@skip\tbash scripts/c.sh --probe\tprobe\n'
    printf 'skills/a/*\tbash scripts/a.sh\n'
    printf 'skills/a/*\tbash scripts/b.test.sh\n'
    printf 'skills/c/*\tbash scripts/c.sh\n'
    printf 'skills/f/*\tbash scripts/f.sh\n'
    printf 'docs/*\tbash scripts/frozen.sh {BASE}\n'
    printf 'docs/*\tSTUB_ENV=1 bash scripts/envg.sh\n'
    printf 'skills/*\t@all\n'
    printf 'scripts/a.sh\tbash scripts/a.sh\n'
    printf 'scripts/a.sh\tbash scripts/b.test.sh\n'
    printf 'scripts/run-gates.sh\tbash scripts/a.sh\n'
    printf 'scripts/run-gates.map\tbash scripts/a.sh\n'
    printf '.github/*\tbash scripts/a.sh\n'
  } > "$R/scripts/run-gates.map"
  echo base > "$R/README"
  (
    cd "$R" || exit 2
    git init -q . && git checkout -q -b main
    git config user.email t@example.com && git config user.name t && git config commit.gpgsign false
    git add -A && git commit -qm base
    git update-ref refs/remotes/origin/main HEAD
  ) || exit 2
}

# Make a scratch repo $R as a copy of the template.
mk() {
  N=$((N + 1))
  R="$T/r$N"
  cp -R "$TPL" "$R" || exit 2
  mkdir -p "$T/tmp"
}

# rg <args>: run the script in $R, output in $T/out, print the exit status. Clears the ran log first.
rg() {
  : > "$RAN_LOG"
  (cd "$R" && TMPDIR="$T/tmp" lim bash scripts/run-gates.sh "$@") > "$T/out" 2>&1
  echo $?
}
ran() { tr '\n' ',' < "$RAN_LOG"; } # the gates that ran, in order, comma-terminated
out() { cat "$T/out"; }
put() { # put <relative path>: write a file in $R, making its directory
  mkdir -p "$R/$(dirname "$1")" && printf 'x\n' > "$R/$1"
}

build_template
ALL='a,b,c,f,frozen:origin/main,env:1,'

# --- clean control: a known path selects exactly its gates (untracked file) ---
mk; put skills/a/x.md
check 0 "$(rg --changed main)" "control_exit"
check "a,b," "$(ran)" "control_selects_exactly_its_gates"
has "$(out)" "summary: 2 gates run, 2 passed, 0 failed" "control_summary"
# the CPU column counts the gate's own CPU seconds: a gate that burns CPU does not show 0.0s
mk
stub burn.sh <<'EOF'
awk 'BEGIN { for (i = 0; i < 30000000; i++) x += i }'
EOF
printf '      - name: burn\n        run: bash scripts/burn.sh\n' >> "$R/.github/workflows/validate-skills.yml"
{ printf 'skills/b/*\tbash scripts/burn.sh\n'; cat "$R/scripts/run-gates.map"; } > "$T/burn.map" && cp "$T/burn.map" "$R/scripts/run-gates.map"
(cd "$R" && git add -A && git commit -q -m burn) || exit 2
put skills/b/x.md
check 0 "$(rg --changed main)" "burn_gate_exit"
if [[ "$(out)" =~ PASS\ \ bash\ scripts/burn.sh\ +([0-9]+\.[0-9])s\ cpu ]]; then
  if [[ "${BASH_REMATCH[1]}" != "0.0" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: cpu_column_counts_gate_cpu — shows 0.0s"; fi
else FAIL=$((FAIL + 1)); echo "FAIL: cpu_column_counts_gate_cpu — no PASS line for burn.sh"; fi
# a gate never reads the caller's stdin: with a pipe full of input on the script, the gate still sees EOF
rm -f "$RAN_LOG.stdin"; mk; put skills/a/x.md
check 0 "$(yes | rg --changed main)" "stdin_piped_exit"
check "no" "$([ -e "$RAN_LOG.stdin" ] && echo yes || echo no)" "gate_stdin_is_not_the_callers"
if [[ "$(out)" =~ PASS\ \ bash\ scripts/a.sh\ +[0-9]+\.[0-9]s\ cpu ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: pass_line_has_name_and_cpu_seconds"; fi
has "$(out)" "CI runs the full set" "summary_says_ci_is_the_authority"

# another known path selects only its own gate
mk; put skills/c/x.md
check 0 "$(rg --changed main)" "c_exit"
check "c," "$(ran)" "c_path_selects_only_c"

# --- unmapped path selects all ---
mk; put other/x.txt
check 0 "$(rg --changed main)" "unmapped_exit"
check "a,b,c,f,frozen:main,env:1," "$(ran)" "unmapped_selects_all_with_the_given_base"
# a path that only the catch-all row `skills/*` maps keeps selecting all
mk; put skills/zzz/x.md
rg --changed main > /dev/null
check "a,b,c,f,frozen:main,env:1," "$(ran)" "all_row_selects_all"

# --- change to the script or the map selects all, though no row lists them ---
mk; printf '# edit\n' >> "$R/scripts/run-gates.sh"
rg --changed main > /dev/null
check "a,b,c,f,frozen:main,env:1," "$(ran)" "script_change_selects_all"
mk; printf '# edit\n' >> "$R/scripts/run-gates.map"
rg --changed main > /dev/null
check "a,b,c,f,frozen:main,env:1," "$(ran)" "map_change_selects_all"
# .github change selects all
mk; put .github/other.yml
rg --changed main > /dev/null
check "a,b,c,f,frozen:main,env:1," "$(ran)" "github_change_selects_all"

# --- a script change runs its own test and the gates that call it (rows) ---
mk; printf '# edit\n' >> "$R/scripts/a.sh"
rg --changed main > /dev/null
check "a,b," "$(ran)" "script_change_selects_own_gate_and_test"

# --- the three kinds of change are seen: committed, staged, unstaged, untracked ---
mk; ( cd "$R" && git checkout -q -b topic && put skills/a/c.md && git add -A && git commit -qm c ) || exit 2
rg --changed main > /dev/null
check "a,b," "$(ran)" "committed_change_seen"
# the change made on main after the branch point is not this branch's change
mk; ( cd "$R" && git checkout -q -b topic && git checkout -q main && put docs/new.md && git add -A && git commit -qm m && git checkout -q topic ) || exit 2
check 0 "$(rg --changed main)" "main_moved_exit"
has "$(out)" "no changes" "main_moved_is_not_this_branchs_change"
mk; put skills/a/s.md; ( cd "$R" && git add skills/a/s.md ) || exit 2
rg --changed main > /dev/null
check "a,b," "$(ran)" "staged_change_seen"
mk; ( cd "$R" && put skills/c/u.md && git add -A && git commit -qm u && git update-ref refs/remotes/origin/main HEAD~1 && printf 'more\n' >> skills/c/u.md ) || exit 2
rg --changed origin/main > /dev/null
check "c," "$(ran)" "unstaged_change_seen"
mk; put skills/f/untracked.md
rg --changed main > /dev/null
check "f," "$(ran)" "untracked_change_seen"
# a git-ignored file is not a change
mk; printf 'skills/ignored/\n' > "$R/.gitignore"; ( cd "$R" && git add -A && git commit -qm ig && git update-ref refs/remotes/origin/main HEAD ) || exit 2
put skills/ignored/x.md
check 0 "$(rg --changed main)" "ignored_exit"
has "$(out)" "no changes" "ignored_file_is_not_a_change"
# a deleted file is a change
mk; ( cd "$R" && put skills/c/gone.md && git add -A && git commit -qm g && git update-ref refs/remotes/origin/main HEAD && rm skills/c/gone.md ) || exit 2
rg --changed main > /dev/null
check "c," "$(ran)" "deleted_file_seen"

# --- default base is origin/main ---
mk; put skills/a/d.md
check 0 "$(rg --changed)" "default_base_exit"
check "a,b," "$(ran)" "default_base_runs"

# --- paths with a space or a newline map by their real name ---
mk; put "skills/c/my file.md"
rg --changed main > /dev/null
check "c," "$(ran)" "path_with_space_maps"
mk; put "skills/c/two
lines.md"
rg --changed main > /dev/null
check "c," "$(ran)" "path_with_newline_maps"
mk; put "my dir/x y.txt"
rg --changed main > /dev/null
check "a,b,c,f,frozen:main,env:1," "$(ran)" "unmapped_path_with_space_selects_all"

# --- bad base ref, no git ---
mk; put skills/a/x.md
check 2 "$(rg --changed no-such-ref)" "bad_base_exit"
has "$(out)" "bad base ref" "bad_base_message"
check "" "$(ran)" "bad_base_runs_nothing"
check 2 "$(rg --changed --evil)" "option_as_base_is_not_a_base_exit"
mk; rm -rf "$R/.git"; put skills/a/x.md
check 2 "$(rg --changed main)" "no_git_exit"
has "$(out)" "run-gates:" "no_git_message"
check "" "$(ran)" "no_git_runs_nothing"

# --- a failing gate: non-zero exit, named ---
mk; put skills/f/x.md
export STUB_FAIL=1
check 1 "$(rg --changed main)" "failing_gate_exit"
unset STUB_FAIL
has "$(out)" "FAIL  bash scripts/f.sh" "failing_gate_named"
has "$(out)" "boom: stub failed" "failing_gate_log_tail_shown"
has "$(out)" "1 failed" "failing_gate_summary"
# the same change passes when the gate passes (clean control)
mk; put skills/f/x.md
check 0 "$(rg --changed main)" "passing_gate_exit"
# a failing gate does not stop the next one
mk; put docs/x.md; put skills/f/y.md
export STUB_FAIL=1
check 1 "$(rg --changed main)" "failure_does_not_stop_others_exit"
unset STUB_FAIL
has "$(ran)" "f," "failure_does_not_stop_others_f_ran"

# --- empty diff ---
mk
check 0 "$(rg --changed main)" "empty_diff_exit"
has "$(out)" "no changes" "empty_diff_message"
check "" "$(ran)" "empty_diff_runs_nothing"
if [[ "$(out)" == *"all passed"* || "$(out)" == *summary* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: empty_diff_prints_no_pass_claim"; else PASS=$((PASS + 1)); fi

# --- --list runs nothing ---
mk; put skills/a/x.md
check 0 "$(rg --list --changed main)" "list_changed_exit"
check "" "$(ran)" "list_runs_nothing"
check "bash scripts/a.sh
bash scripts/b.test.sh" "$(cat "$T/out")" "list_changed_prints_the_gates"
check 0 "$(rg --list)" "list_all_exit"
check "" "$(ran)" "list_all_runs_nothing"
check 6 "$(grep -c . "$T/out")" "list_all_prints_every_runnable_gate"
if grep -q -- '--probe' "$T/out"; then FAIL=$((FAIL + 1)); echo "FAIL: list_all_leaves_out_the_skip_row"; else PASS=$((PASS + 1)); fi

# --- --all runs every gate, with the env of its map row and the default base ---
mk
check 0 "$(rg --all)" "all_exit"
check "$ALL" "$(ran)" "all_runs_every_gate_env_and_base"

# --- usage errors ---
check 2 "$(rg)" "no_mode_exit"
check 2 "$(rg --all --changed)" "all_and_changed_exit"
check 2 "$(rg --frob)" "unknown_argument_exit"

# --- nothing is written in the repo or outside TMPDIR; a pass leaves no scratch dir behind ---
mk; put skills/a/x.md
before=$(cd "$R" && git status --porcelain)
rm -rf "$T/tmp"; mkdir -p "$T/tmp"
rg --changed main > /dev/null
check "$before" "$(cd "$R" && git status --porcelain)" "repo_unchanged_by_a_run"
check "" "$(ls -A "$T/tmp")" "pass_leaves_no_scratch_dir"

# --- map and workflow checks (stub repo: clean control, then each drift) ---
mk
check 0 "$(rg --check)" "stub_check_control"
mk; printf '      - run: bash scripts/new-gate.sh\n' >> "$R/.github/workflows/validate-skills.yml"; stub new-gate.sh <<< true
check 2 "$(rg --check)" "workflow_command_missing_from_map_exit"
has "$(out)" "missing from the map: bash scripts/new-gate.sh" "workflow_command_missing_from_map_message"
mk; printf 'skills/a/*\tbash scripts/ghost.sh\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "map_gate_not_in_workflow_exit"
has "$(out)" "not in the workflow: bash scripts/ghost.sh" "map_gate_not_in_workflow_message"
mk; rm "$R/scripts/c.sh"
check 2 "$(rg --check)" "map_script_missing_exit"
has "$(out)" "does not exist: scripts/c.sh" "map_script_missing_message"
mk; printf 'docs/gone.md\tbash scripts/a.sh\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "map_path_missing_exit"
has "$(out)" "path that does not exist: docs/gone.md" "map_path_missing_message"
mk; rm "$R/scripts/run-gates.map"
put skills/a/x.md
check 2 "$(rg --changed main)" "unreadable_map_exit"
has "$(out)" "cannot read the map" "unreadable_map_message"
check "" "$(ran)" "unreadable_map_runs_nothing"
mk; rm "$R/.github/workflows/validate-skills.yml"
check 2 "$(rg --all)" "missing_workflow_exit"
mk; cat >> "$R/.github/workflows/validate-skills.yml" <<'EOF'
      - run: bash scripts/a.sh "$X"
EOF
check 2 "$(rg --check)" "unreadable_workflow_command_exit"
# a drifted map stops a changed run too, before any gate runs
mk; printf 'skills/a/*\tbash scripts/ghost.sh\n' >> "$R/scripts/run-gates.map"; put skills/a/x.md
check 2 "$(rg --changed main)" "drift_stops_a_changed_run_exit"
check "" "$(ran)" "drift_stops_a_changed_run_runs_nothing"

# --- the real workflow and the real map agree, in both directions ---
check 0 "$(cd "$REAL" && lim bash "$RG" --check > "$T/out" 2>&1; echo $?)" "real_map_matches_real_workflow"
RW="$REAL/.github/workflows/validate-skills.yml"
RM="$REAL/scripts/run-gates.map"
rgreal() { # rgreal <workflow> <map>: --check on the real repo with other copies of the two files
  (cd "$REAL" && RUN_GATES_WORKFLOW="$1" RUN_GATES_MAP="$2" lim bash "$RG" --check) > "$T/out" 2>&1
  echo $?
}
check 0 "$(rgreal "$RW" "$RM")" "real_copies_control"
cp "$RW" "$T/w.yml"; printf '      - run: bash scripts/brand-new-gate.sh\n' >> "$T/w.yml"
check 2 "$(rgreal "$T/w.yml" "$RM")" "real_new_ci_gate_missing_from_map_exit"
has "$(out)" "missing from the map: bash scripts/brand-new-gate.sh" "real_new_ci_gate_missing_from_map_message"
grep -v 'check-doc-sync.sh' "$RM" > "$T/m.map"
check 2 "$(rgreal "$RW" "$T/m.map")" "real_map_missing_a_gate_exit"
has "$(out)" "missing from the map: bash scripts/check-doc-sync.sh" "real_map_missing_a_gate_message"
cp "$RM" "$T/m2.map"; printf 'README.md\tbash scripts/not-a-script.sh\n' >> "$T/m2.map"
check 2 "$(rgreal "$RW" "$T/m2.map")" "real_map_names_missing_script_exit"
has "$(out)" "does not exist: scripts/not-a-script.sh" "real_map_names_missing_script_message"
cp "$RM" "$T/m3.map"; printf 'README.md\tbash scripts/lint-skills.sh skills/ extra\n' >> "$T/m3.map"
check 2 "$(rgreal "$RW" "$T/m3.map")" "real_map_gate_not_in_workflow_exit"
# the real map selects its own test and every gate in the workflow has a row
check 0 "$(cd "$REAL" && lim bash "$RG" --list > "$T/out" 2>&1; echo $?)" "real_list_all_exit"
has "$(out)" "bash scripts/run-gates.test.sh" "real_list_holds_this_test"
has "$(out)" "bash scripts/check-fences-frozen.sh {BASE}" "real_list_holds_frozen_gate_with_base"

echo "run-gates.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
