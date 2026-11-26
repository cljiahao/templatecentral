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

# lim <command...>: exit 128 + the signal when the command is killed by one (not 0), else its status. Run it in its own process group and kill the group after 60 s (LIM_S overrides), so a blocked run fails the check.
lim() {
  perl -e '$s = $ENV{LIM_S} || 60; setpgrp(0, 0); $p = fork; if (!$p) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$$; exit 124 }; alarm $s; waitpid($p, 0); exit(($? & 127) ? 128 + ($? & 127) : $? >> 8)' "$@"
}

T=$(mktemp -d "${TMPDIR:-/tmp}/run-gates-test.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
export RAN_LOG="$T/ran.log"
unset STUB_FAIL STUB_ENV
N=0
R=""

stub() { { printf '#!/usr/bin/env bash\n'; cat; } > "$R/scripts/$1"; } # stub <name>: the body comes from stdin

# lim reports a child killed by a signal as 128 + the signal, not 0; a normal exit keeps its status
lim bash -c 'kill -KILL $$'; check 137 "$?" "lim_reports_a_signal_killed_child"
lim bash -c 'exit 3'; check 3 "$?" "lim_keeps_a_normal_exit_status_control"
lim true; check 0 "$?" "lim_zero_status_control"

TPL="$T/template"

# Build the template repo once: stub gates, a stub workflow and map, a base commit on main and origin/main.
build_template() {
  R="$TPL"
  mkdir -p "$R/scripts" "$R/.github/workflows" "$R/skills/a" "$R/skills/c" "$R/skills/f" "$R/docs"
  cp "$RG" "$R/scripts/run-gates.sh"
  stub a.sh <<'EOF'
echo a >> "$RAN_LOG"
if [ -n "${GIT_DIR:-}${GIT_NAMESPACE:-}${GIT_PREFIX:-}${GIT_INDEX_FILE:-}" ]; then echo leaked >> "$RAN_LOG.gitenv"; fi
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
rgv() { # rgv <VAR=value> <args>: like rg, with one variable set for the run
  : > "$RAN_LOG"
  (cd "$R" && declare -x "$1" && TMPDIR="$T/tmp" lim bash scripts/run-gates.sh "${@:2}") > "$T/out" 2>&1
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
stdin_seen=no
if [ -e "$RAN_LOG.stdin" ]; then stdin_seen=yes; fi
check "no" "$stdin_seen" "gate_stdin_is_not_the_callers"
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

# --- parser allow-list: a run line this runner cannot read exactly stops the run, naming file and line ---
WF=".github/workflows/validate-skills.yml"
probe() { # probe <name> <run line> <message fragment>: a workflow with that run line must stop --check with exit 2
  mk; printf '      - run: %s\n' "$2" >> "$R/$WF"
  check 2 "$(rg --check)" "parser_${1}_exit"
  has "$(out)" "$3" "parser_${1}_message"
  has "$(out)" "validate-skills.yml:" "parser_${1}_names_file_and_line"
}
FORM="used in a form this runner does not read"
probe python_script 'python3 scripts/new_gate.py' "$FORM"
probe two_spaces 'bash  scripts/x.sh' "$FORM"
probe dot_slash 'bash ./scripts/x.sh' "$FORM"
probe no_space_after_and 'true &&bash scripts/x.sh' "$FORM"
probe sh_runner 'sh scripts/x.sh' "$FORM"
probe node_in_scripts 'node scripts/x.mjs' "$FORM"
probe cd_into_scripts 'cd scripts && bash x.sh' "a cd into scripts or adapters"
probe pushd_into_adapters 'pushd adapters/opencode' "a cd into scripts or adapters"
# clean controls: the same shapes in a form the runner reads
mk; printf '      - run: bash scripts/a.sh\n' >> "$R/$WF"
check 0 "$(rg --check)" "parser_clean_control_exit"
# a path that only ends in scripts/ (a different word) is not a scripts/ token; the word before it decides
mk; printf '      - run: echo see my-scripts/x.sh and docs_scripts/y.sh\n' >> "$R/$WF"
check 0 "$(rg --check)" "parser_word_ending_in_scripts_is_not_a_token_exit"
mk; printf '      - run: echo hi\n        working-directory: docs\n' >> "$R/$WF"
check 0 "$(rg --check)" "parser_working_directory_elsewhere_control_exit"
mk; printf '      - run: echo hi\n        working-directory: scripts\n' >> "$R/$WF"
check 2 "$(rg --check)" "parser_working_directory_in_scripts_exit"
has "$(out)" "working-directory in scripts or adapters" "parser_working_directory_in_scripts_message"
# a workflow with jobs: before on: is still read
wf_jobs_first() { # wf_jobs_first <trigger>: other.yml with the jobs block ahead of the trigger
  printf 'name: o\njobs:\n  j:\n    steps:\n      - run: bash scripts/new-gate.sh\non:\n  %s:\n' "$1" > "$R/.github/workflows/other.yml"
}
mk; stub new-gate.sh <<< true
wf_jobs_first pull_request
check 2 "$(rg --check)" "jobs_before_on_is_scanned_exit"
has "$(out)" "missing from the map: bash scripts/new-gate.sh" "jobs_before_on_is_scanned_message"
printf 'skills/a/*\tbash scripts/new-gate.sh\n' >> "$R/scripts/run-gates.map"
check 0 "$(rg --check)" "jobs_before_on_with_a_map_row_control_exit"
mk; stub new-gate.sh <<< true
wf_jobs_first push
check 0 "$(rg --check)" "jobs_before_on_push_only_control_exit"
# a plain multi-line run: scalar is read line by line
mk; printf '      - run: true &&\n          bash scripts/x.sh\n' >> "$R/$WF"
check 2 "$(rg --check)" "multiline_run_second_line_is_read_exit"
has "$(out)" "missing from the map: bash scripts/x.sh" "multiline_run_second_line_is_read_message"
mk; printf '      - run: bash\\\n          scripts/x.sh\n' >> "$R/$WF"
check 2 "$(rg --check)" "multiline_run_split_path_exit"
has "$(out)" "$FORM" "multiline_run_split_path_message"
mk; printf '      - run: true &&\n          bash scripts/a.sh\n' >> "$R/$WF"
check 0 "$(rg --check)" "multiline_run_mapped_gate_control_exit"
mk; printf '      - run: echo hi\n        env:\n          K: v\n      - run: bash scripts/a.sh\n' >> "$R/$WF"
check 0 "$(rg --check)" "multiline_run_sibling_key_is_not_a_continuation_control_exit"
# a local uses: (composite action, reusable workflow) stops the run unless an @skip row names it
mk; printf '      - uses: ./.github/actions/foo\n' >> "$R/$WF"
check 2 "$(rg --check)" "local_action_exit"
has "$(out)" "a local uses:" "local_action_message"
has "$(out)" "validate-skills.yml:" "local_action_names_file_and_line"
mk; printf '  reuse:\n    uses: ./.github/workflows/x.yml\n' >> "$R/$WF"
check 2 "$(rg --check)" "local_reusable_workflow_exit"
has "$(out)" "a local uses:" "local_reusable_workflow_message"
mk; printf '      - uses: ./.github/actions/foo\n' >> "$R/$WF"; printf '@skip\t./.github/actions/foo\tcomposite action, reviewed\n' >> "$R/scripts/run-gates.map"
check 0 "$(rg --check)" "local_action_with_a_skip_row_control_exit"
mk; printf '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n' >> "$R/$WF"
check 0 "$(rg --check)" "remote_uses_control_exit"
# every pull_request workflow is scanned; one that does not trigger on pull_request is not
mk; stub new-gate.sh <<< true
printf 'name: o\non:\n  pull_request:\njobs:\n  j:\n    steps:\n      - run: bash scripts/new-gate.sh\n' > "$R/.github/workflows/other.yml"
check 2 "$(rg --check)" "second_pr_workflow_is_scanned_exit"
has "$(out)" "missing from the map: bash scripts/new-gate.sh" "second_pr_workflow_is_scanned_message"
printf 'skills/a/*\tbash scripts/new-gate.sh\n' >> "$R/scripts/run-gates.map"
check 0 "$(rg --check)" "second_pr_workflow_with_a_map_row_control_exit"
mk; stub new-gate.sh <<< true
printf 'name: o\non:\n  push:\njobs:\n  j:\n    steps:\n      - run: bash scripts/new-gate.sh\n' > "$R/.github/workflows/other.yml"
check 0 "$(rg --check)" "push_workflow_is_ignored_exit"
# an @skip row that no run line contains is stale
mk; printf '@skip\tbash scripts/zzz.sh\tnever in a workflow\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "unused_skip_row_exit"
has "$(out)" "no workflow run line contains this @skip command" "unused_skip_row_message"

# --- audit: a gate script that names a mapped path must be selected by that path's row ---
mk; stub d.sh <<'EOF'
cat docs/guide.md
EOF
printf '      - run: bash scripts/d.sh\n' >> "$R/$WF"
printf 'scripts/d.sh\tbash scripts/d.sh\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "audit_drift_exit"
has "$(out)" 'audit: gate [bash scripts/d.sh] names "docs"' "audit_drift_message"
printf 'docs/*\tbash scripts/d.sh\n' >> "$R/scripts/run-gates.map"
check 0 "$(rg --check)" "audit_row_added_control_exit"
cp "$R/scripts/run-gates.map" "$T/audit.map"
grep -v -x -F "$(printf 'docs/*\tbash scripts/d.sh')" "$T/audit.map" > "$R/scripts/run-gates.map"
printf '@noread\tbash scripts/d.sh\tdocs/*\n' >> "$R/scripts/run-gates.map"
check 0 "$(rg --check)" "audit_noread_row_exit"
printf 'docs/*\tbash scripts/d.sh\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "audit_stale_noread_row_exit"
has "$(out)" "@noread row is stale" "audit_stale_noread_row_message"
mk; printf '@noread\tbash scripts/a.sh\tdocs/*\n' >> "$R/scripts/run-gates.map"
check 2 "$(rg --check)" "audit_noread_that_matches_nothing_exit"

# --- a renamed or deleted script named in the map: the message says which row and what to do ---
mk; rm "$R/scripts/c.sh"
check 2 "$(rg --list)" "list_with_a_deleted_script_exit"
has "$(out)" "map row at line" "deleted_script_message_names_the_row"
has "$(out)" "edit or remove that row" "deleted_script_message_says_what_to_do"
# --list --changed prints the resolved base, not the placeholder
mk; put docs/x.md
check 0 "$(rg --list --changed main)" "list_changed_with_base_exit"
has "$(out)" "bash scripts/frozen.sh main" "list_changed_prints_the_resolved_base"
if [[ "$(out)" == *'{BASE}'* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: list_changed_leaves_no_placeholder"; else PASS=$((PASS + 1)); fi

# --- base ref and history edge cases ---
# a base that starts with a dash is refused as a base, not passed to git
mk; put skills/a/x.md
check 2 "$(rg --changed -x)" "dash_base_exit"
check "run-gates: bad base ref: -x" "$(out)" "dash_base_message_is_the_guard_not_the_fetch_hint"
# a base with no common ancestor
mk; put skills/a/x.md
( cd "$R" && git update-ref refs/heads/lone "$(git commit-tree "$(git mktree </dev/null)" -m lone </dev/null)" ) || exit 2
check 2 "$(rg --changed lone)" "no_common_ancestor_exit"
has "$(out)" "no merge base" "no_common_ancestor_message"
check "" "$(ran)" "no_common_ancestor_runs_nothing"
# a renamed file counts as a delete of the old path and an add of the new one
mk; ( cd "$R" && put skills/a/r.md && git add -A && git commit -qm r && git update-ref refs/remotes/origin/main HEAD && git mv skills/a/r.md skills/c/r.md ) || exit 2
check 0 "$(rg --changed main)" "rename_exit"
check "a,b,c," "$(ran)" "rename_selects_the_gates_of_both_paths"
has "$(out)" "renamed: skills/a/r.md -> skills/c/r.md" "rename_is_named_in_the_output"
mk; ( cd "$R" && put skills/a/n.md ) || exit 2
check 0 "$(rg --changed main)" "no_rename_control_exit"
if [[ "$(out)" == *"renamed:"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: no_rename_control_prints_no_rename_line"; else PASS=$((PASS + 1)); fi

# --- a foreign git environment is dropped, so the diff and the gates read this repo ---
rm -f "$RAN_LOG.gitenv"
mk; put skills/a/x.md
check 0 "$(export GIT_NAMESPACE=zz GIT_PREFIX=zz; rg --changed main)" "git_env_control_exit"
check "a,b," "$(ran)" "git_env_selects_this_repos_change"
gl=no
if [ -e "$RAN_LOG.gitenv" ]; then gl=yes; fi
check "no" "$gl" "gate_sees_no_git_variables"
rm -f "$RAN_LOG.gitenv"
mk; put skills/a/x.md
check 0 "$(export GIT_DIR="$T/no-such-git-dir" GIT_WORK_TREE="$T/no-such-tree" GIT_INDEX_FILE="$T/no-such-index"; rg --changed main)" "foreign_git_dir_exit"
check "a,b," "$(ran)" "foreign_git_dir_does_not_move_the_diff"

# --- the scratch dir inside the repo is not a change ---
mk; put skills/a/x.md; mkdir -p "$R/tmpin"
check 0 "$( (cd "$R" && TMPDIR="$R/tmpin" lim bash scripts/run-gates.sh --changed main) > "$T/out" 2>&1; echo $?)" "tmpdir_in_repo_exit"
has "$(out)" "summary: 2 gates run" "tmpdir_inside_the_repo_does_not_select_all"
if [[ "$(out)" == *"all gates selected"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: tmpdir_inside_the_repo_selects_no_all_message"; else PASS=$((PASS + 1)); fi

# --- run state: a one-gate repo ---
mini() { # mini: a repo with one gate, scripts/g.sh, whose body comes from stdin, and one changed path
  mk
  stub g.sh
  printf 'name: s\non: [pull_request]\njobs:\n  j:\n    steps:\n      - run: bash scripts/g.sh\n' > "$R/$WF"
  printf 'skills/*\tbash scripts/g.sh\nscripts/g.sh\tbash scripts/g.sh\n' > "$R/scripts/run-gates.map"
  put skills/x/x.md
}
# gone_check <pid file> <description>: fail when the file holds no pid; poll up to about 1 s for that process to be gone
gone_check() {
  local pid gone=no n=0
  pid=$(cat "$1" 2>/dev/null)
  if [ -z "$pid" ]; then FAIL=$((FAIL + 1)); echo "FAIL: $2 — no pid was recorded"; return 0; fi
  while [ "$n" -lt 10 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then gone=yes; break; fi
    sleep 0.1; n=$((n + 1))
  done
  if [ "$gone" = no ]; then kill -KILL "$pid" 2>/dev/null; fi
  check "yes" "$gone" "$2"
}
# a gate over the time limit fails, is named, and its whole process group dies
rm -f "$RAN_LOG.sleeper"
mini <<'EOF'
sleep 300 &
echo $! > "$RAN_LOG.sleeper"
wait
EOF
check 1 "$(rgv RUN_GATES_TIMEOUT=1 --changed main)" "timeout_exit"
has "$(out)" "timed out after 1s" "timeout_message"
has "$(out)" "FAIL  bash scripts/g.sh" "timeout_is_reported_fail"
gone_check "$RAN_LOG.sleeper" "timeout_kills_the_gates_children"
# control: a gate inside the limit passes and is not reported as timed out
mini <<'EOF'
exit 0
EOF
check 0 "$(rgv RUN_GATES_TIMEOUT=30 --changed main)" "timeout_control_exit"
if [[ "$(out)" == *"timed out"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: timeout_control_is_not_timed_out"; else PASS=$((PASS + 1)); fi
check 2 "$(rgv RUN_GATES_TIMEOUT=abc --all)" "bad_timeout_value_exit"
has "$(out)" "RUN_GATES_TIMEOUT must be" "bad_timeout_value_message"
check 0 "$(rgv RUN_GATES_TIMEOUT=5 --list --all)" "good_timeout_value_control_exit"
# a gate killed by a signal fails, with the signal named
mini <<'EOF'
kill -9 $$
EOF
check 1 "$(rg --changed main)" "signal_killed_gate_exit"
has "$(out)" "killed by signal 9" "signal_killed_gate_message"
has "$(out)" "1 failed" "signal_killed_gate_summary"
mini <<'EOF'
exit 3
EOF
check 1 "$(rg --changed main)" "exit_code_gate_control_exit"
has "$(out)" "(exit 3)" "exit_code_gate_control_message"
# a passing gate that printed SKIP: lines is PASS-WITH-SKIPS, named, with the lines shown; exit stays 0
mini <<'EOF'
echo "SKIP: tool x is not installed"
exit 0
EOF
check 0 "$(rg --changed main)" "skips_exit"
has "$(out)" "PASS-WITH-SKIPS  bash scripts/g.sh" "skips_state_names_the_gate"
has "$(out)" "SKIP: tool x is not installed" "skips_lines_are_shown"
has "$(out)" "passed with skips" "skips_summary"
mini <<'EOF'
echo "all good, nothing skipped here"
exit 0
EOF
check 0 "$(rg --changed main)" "skips_control_exit"
if [[ "$(out)" == *"PASS-WITH-SKIPS"* ]]; then FAIL=$((FAIL + 1)); echo "FAIL: skips_control_is_a_plain_pass"; else PASS=$((PASS + 1)); fi
has "$(out)" "PASS  bash scripts/g.sh" "skips_control_prints_pass"
# a failing gate that also printed SKIP: stays a FAIL
mini <<'EOF'
echo "SKIP: tool x"
exit 1
EOF
check 1 "$(rg --changed main)" "skips_with_failure_exit"
has "$(out)" "FAIL  bash scripts/g.sh" "skips_with_failure_is_fail"
# a SIGINT to the runner stops the gate and its children and removes the scratch dir
rm -f "$RAN_LOG.sleeper"
mini <<'EOF'
sleep 300 &
echo $! > "$RAN_LOG.sleeper"
wait
EOF
rm -rf "$T/tmp3"; mkdir -p "$T/tmp3"
set -m
( cd "$R" && TMPDIR="$T/tmp3" exec bash scripts/run-gates.sh --changed main ) > "$T/out" 2>&1 &
RP=$!
set +m
i=0
while [ ! -s "$RAN_LOG.sleeper" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -INT -- "-$RP" 2>/dev/null
i=0
while kill -0 "$RP" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
hung=no
if kill -0 "$RP" 2>/dev/null; then hung=yes; kill -KILL -- "-$RP" 2>/dev/null; fi
{ wait "$RP"; } 2>/dev/null
st=$?
check "no" "$hung" "sigint_stops_the_runner"
check 130 "$st" "sigint_exit_status"
gone_check "$RAN_LOG.sleeper" "sigint_kills_the_gates_children"
check "" "$(ls -A "$T/tmp3")" "sigint_removes_the_scratch_dir"
has "$(cat "$T/out")" "interrupted by INT" "sigint_message"

# --- the real workflow and the real map agree, in both directions ---
check 0 "$(cd "$REAL" && lim bash "$RG" --check > "$T/out" 2>&1; echo $?)" "real_map_matches_real_workflow"
RW="$REAL/.github/workflows"
RM="$REAL/scripts/run-gates.map"
rgreal() { # rgreal <workflow dir> <map>: --check on the real repo with other copies of the workflows and the map
  (cd "$REAL" && RUN_GATES_WORKFLOWS="$1" RUN_GATES_MAP="$2" lim bash "$RG" --check) > "$T/out" 2>&1
  echo $?
}
check 0 "$(rgreal "$RW" "$RM")" "real_copies_control"
mkdir -p "$T/wf"; cp "$RW"/*.yml "$T/wf/"
printf '      - run: bash scripts/brand-new-gate.sh\n' >> "$T/wf/validate-skills.yml"
check 2 "$(rgreal "$T/wf" "$RM")" "real_new_ci_gate_missing_from_map_exit"
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
has "$(out)" "bash scripts/check-fences-frozen.sh origin/main" "real_list_holds_frozen_gate_with_resolved_base"
has "$(out)" "bash scripts/validate-scaffold-configs.sh" "real_list_holds_the_scaffold_parse_gate"
# the audit on the real repo: a gate that reads CHANGELOG.md or the template-comment exemptions is selected by their rows
check 1 "$(grep -c -x -F "$(printf 'skills/*\t@all')" "$RM")" "real_map_skills_select_all"
drop() { # drop <path> <gate>: --check the real repo with the map row <path><TAB><gate> removed
  grep -v -x -F "$(printf '%s\t%s' "$1" "$2")" "$RM" > "$T/drop.map"
  rgreal "$RW" "$T/drop.map"
}
check 2 "$(drop CHANGELOG.md 'bash scripts/measure-seeded-load.test.sh')" "real_changelog_row_for_measure_seeded_load_exit"
has "$(out)" 'audit: gate [bash scripts/measure-seeded-load.test.sh] names "CHANGELOG.md"' "real_changelog_row_for_measure_seeded_load_message"
check 2 "$(drop CHANGELOG.md 'bash scripts/lint-skills.test.sh')" "real_changelog_row_for_lint_skills_test_exit"
check 2 "$(drop 'changelog.d/*' 'bash scripts/measure-seeded-load.test.sh')" "real_fragment_row_for_measure_seeded_load_exit"
has "$(out)" 'audit: gate [bash scripts/measure-seeded-load.test.sh] names "changelog.d"' "real_fragment_row_for_measure_seeded_load_message"
check 2 "$(drop 'changelog.d/*' 'bash scripts/changelog-check.sh {BASE}')" "real_fragment_row_for_changelog_check_exit"
has "$(out)" 'audit: gate [bash scripts/changelog-check.sh {BASE}] names "changelog.d"' "real_fragment_row_for_changelog_check_message"
has "$(cd "$REAL" && lim bash "$RG" --list 2>&1)" "bash scripts/changelog-check.sh" "real_list_holds_the_changelog_gate"
# the pool test reaches CHANGELOG.md through lint-skills.test.sh, so the audit cannot see it: the row is kept by hand
check 1 "$(grep -c -x -F "$(printf 'CHANGELOG.md\tbash scripts/lint-skills-pool.test.sh')" "$RM")" "real_changelog_row_for_lint_skills_pool_test_present"
check 2 "$(drop scripts/check-template-comments.exempt 'bash scripts/test-harness-kit.sh')" "real_exempt_row_for_harness_kit_exit"
has "$(out)" 'names "scripts/check-template-comments.exempt"' "real_exempt_row_for_harness_kit_message"
check 0 "$(rgreal "$RW" "$RM")" "real_audit_control_exit"

echo "run-gates.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
