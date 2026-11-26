#!/usr/bin/env bash
# scripts/check-tests-wired.test.sh — tests for scripts/check-tests-wired.sh on scratch trees.
# Each failing case has a clean control (the same shape, with the command in its own plain block). The cases
# cover text that is not a run (echo, a step name, `: cmd`, a comment), every shell construct that can keep a
# line from running (heredoc, quote, function, branch, loop, continuation, exit, trap, errexit off, `||`, `&&`),
# a step `shell`, `working-directory` or `if`, `defaults.run` at job and workflow level, continue-on-error, a
# pull_request trigger with a filter, a workflow that never runs on a pull request, YAML anchors and folded
# blocks, an unparsable workflow, missing PyYAML, and the node and test-*.sh scope. The last case runs the
# check on this repo.
# Usage: bash scripts/check-tests-wired.test.sh   (needs python3 with PyYAML)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-tests-wired.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tests-wired.XXXXXX") || exit 1
trap 'rm -rf "${T:?}"' EXIT
PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
# has <text> <substring> — yes when the text holds the substring; lacks is the reverse.
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
lacks() { case "$1" in *"$2"*) echo no ;; *) echo yes ;; esac; }

# tree <name> — a scratch scripts dir with a.test.sh and b.test.sh and an empty workflow dir.
tree() {
  rm -rf "${T:?}/$1"; mkdir -p "$T/$1/scripts" "$T/$1/wf"
  : > "$T/$1/scripts/a.test.sh"; : > "$T/$1/scripts/b.test.sh"
}
# run <name> — the check's exit code and output on that tree.
run() { OUT=$(bash "$CHECK" "$T/$1/scripts" "$T/$1/wf" 2>&1); RC=$?; }
# wf <name> — a tree whose workflow ci.yml is stdin; runs the check.
wf() {
  tree "$1"
  cat > "$T/$1/wf/ci.yml"
  run "$1"
}
# wired_b <name> — b.test.sh is wired in the workflow on stdin, and a.test.sh always is.
wired_b() {
  tree "$1"
  { printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n'; cat; } > "$T/$1/wf/ci.yml"
  run "$1"
}

HEAD_PR='on:
  pull_request:
    paths: ["scripts/**"]
jobs:'

wf wired <<EOF
$HEAD_PR
  x:
    steps:
      - run: bash scripts/a.test.sh
      - run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: both tests wired passes"
check yes "$(has "$OUT" "OK: all")" "control: prints OK"

tree split
printf 'on: [push, pull_request]\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n' > "$T/split/wf/one.yml"
printf 'on:\n  pull_request: {}\njobs:\n  x:\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/split/wf/two.yaml"
run split
check 0 "$RC" "control: tests spread over two workflow files, .yml and .yaml, with list and map triggers, pass"

wf miss <<EOF
$HEAD_PR
  x:
    steps:
      - run: bash scripts/a.test.sh
EOF
check 1 "$RC" "planted miss: b.test.sh not run fails"
check yes "$(has "$OUT" "scripts/b.test.sh is not run")" "planted miss: names the missing test"
check yes "$(lacks "$OUT" "scripts/a.test.sh is not run")" "planted miss: does not name the wired test"

wf comment <<EOF
$HEAD_PR
  x:
    steps:
      - run: bash scripts/a.test.sh
    # bash scripts/b.test.sh
EOF
check 1 "$RC" "a commented-out run does not count"

wf prefix <<EOF
$HEAD_PR
  x:
    steps:
      - run: bash scripts/a.test.sh
      - run: bash scripts/b.test.sh.bak
EOF
check 1 "$RC" "a longer file name does not count for b.test.sh"

wf dot <<EOF
$HEAD_PR
  x:
    steps:
      - run: bash scripts/a.test.sh
      - run: bash scripts/bxtest.sh
EOF
check 1 "$RC" "the dot in the name is literal"

# ── text that is not a run ──
wired_b echo <<'EOF'
      - run: echo bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: echo of the command does not count"
wired_b echo_ctl <<'EOF'
      - run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: the plain command counts"

wired_b name <<'EOF'
      - name: bash scripts/b.test.sh
        run: echo hello
EOF
check 1 "$RC" "bypass: the command in a step name does not count"
wired_b name_ctl <<'EOF'
      - name: bash scripts/b.test.sh
        run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: a step named like the command and running it counts"

wired_b colon <<'EOF'
      - run: ': bash scripts/b.test.sh'
EOF
check 1 "$RC" "bypass: a colon no-op in front of the command does not count"

wired_b trailing <<'EOF'
      - run: echo done # bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a trailing comment does not count"
wired_b trailing_block <<'EOF'
      - run: |
          echo start
          # bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a comment line in a run block does not count"
wired_b block_ctl <<'EOF'
      - run: |
          bash scripts/b.test.sh --verbose x=1 -n 2
EOF
check 0 "$RC" "control: a command with plain arguments counts"
wired_b comment_line <<'EOF'
      - run: |
          # run b
          bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a comment line is not on the allow-list, so the block wires nothing"
wired_b comment_punct <<'EOF'
      - run: |
          bash scripts/b.test.sh # note: a | b; c || d &
EOF
check 1 "$RC" "bypass: a trailing comment is not on the allow-list, so the block wires nothing"
wired_b quote_arg <<'EOF'
      - run: bash scripts/b.test.sh "x y"
EOF
check 1 "$RC" "bypass: a quoted argument is not on the allow-list"
wired_b two_cmds <<'EOF'
      - run: |
          bash scripts/b.test.sh

          bash scripts/b.test.sh --again
EOF
check 0 "$RC" "control: blank lines and two plain commands in one block count"

wired_b name_only <<'EOF'
      - name: bash scripts/b.test.sh
        uses: actions/checkout@v4
EOF
check 1 "$RC" "bypass: a step with the command in its name and no run does not count"

wired_b quoted <<'EOF'
      - run: |
          echo "
          bash scripts/b.test.sh"
EOF
check 1 "$RC" "bypass: the command inside a quoted multi-line string does not count"

# ── a step or job that cannot run, or whose failure is ignored ──
wired_b step_if <<'EOF'
      - if: false
        run: bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a step with if: false does not count"
wired_b step_if_expr <<'EOF'
      - if: github.ref == 'refs/heads/main'
        run: bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a step with any other if does not count"

tree job_if
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    if: false\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/job_if/wf/ci.yml"
run job_if
check 1 "$RC" "bypass: a job with if: false does not count"
tree job_if_ok
printf "on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    if: github.event_name == 'pull_request'\n    steps:\n      - run: bash scripts/b.test.sh\n" > "$T/job_if_ok/wf/ci.yml"
run job_if_ok
check 0 "$RC" "control: the allow-listed job if (event is pull_request) counts"
tree job_if_other
printf "on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    if: github.event_name == 'push'\n    steps:\n      - run: bash scripts/b.test.sh\n" > "$T/job_if_other/wf/ci.yml"
run job_if_other
check 1 "$RC" "bypass: a job if that is not on the allow-list does not count"

wired_b or_true <<'EOF'
      - run: bash scripts/b.test.sh || true
EOF
check 1 "$RC" "bypass: the command followed by || true does not count"
wired_b piped <<'EOF'
      - run: bash scripts/b.test.sh | cat
EOF
check 1 "$RC" "bypass: the command piped into another does not count"
wired_b background <<'EOF'
      - run: bash scripts/b.test.sh &
EOF
check 1 "$RC" "bypass: the command sent to the background does not count"

wired_b coe_step <<'EOF'
      - continue-on-error: true
        run: bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a step with continue-on-error does not count"
wired_b coe_false <<'EOF'
      - continue-on-error: false
        run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: continue-on-error: false counts"
tree coe_job
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    continue-on-error: true\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/coe_job/wf/ci.yml"
run coe_job
check 1 "$RC" "bypass: a job with continue-on-error does not count"

wired_b set_plus_e <<'EOF'
      - run: |
          set +e
          bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a run block that sets +e does not count"
wired_b set_ctl <<'EOF'
      - run: |
          set -euo pipefail
          bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a set line is not on the allow-list (no setup form is), so the block wires nothing"
wired_b set_split <<'EOF'
      - run: set -euo pipefail
      - run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: the same command in its own step counts"

# ── which workflows count ──
tree dispatch
printf 'on:\n  workflow_dispatch:\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/dispatch/wf/ci.yml"
run dispatch
check 1 "$RC" "bypass: a workflow that only runs on workflow_dispatch fails"
check yes "$(has "$OUT" "no workflow file runs on pull_request")" "workflow_dispatch only: says why"
tree dispatch_ctl
printf 'on:\n  workflow_dispatch:\n  pull_request:\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/dispatch_ctl/wf/ci.yml"
run dispatch_ctl
check 0 "$RC" "control: pull_request beside workflow_dispatch counts"

tree dispatch_mix
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n' > "$T/dispatch_mix/wf/ci.yml"
printf 'on: workflow_dispatch\njobs:\n  x:\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/dispatch_mix/wf/manual.yml"
run dispatch_mix
check 1 "$RC" "bypass: a test run only by the dispatch-only workflow does not count"

tree broken
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/broken/wf/ci.yml"
printf 'jobs: [\n  - this is: not : valid\n' > "$T/broken/wf/bad.yml"
run broken
check 1 "$RC" "bypass: an unparsable workflow fails even when the others wire everything"
check yes "$(has "$OUT" "cannot parse workflow $T/broken/wf/bad.yml")" "unparsable workflow: names the file"
rm -f "$T/broken/wf/bad.yml"
run broken
check 0 "$RC" "control: the same tree without the unparsable workflow passes"

tree notmap
printf -- '- just\n- a list\n' > "$T/notmap/wf/ci.yml"
run notmap
check 1 "$RC" "a workflow that is not a mapping fails"
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/notmap/wf/ok.yml"
run notmap
check 1 "$RC" "bypass: a non-mapping workflow fails even when another workflow wires everything"
rm -f "$T/notmap/wf/ci.yml"
run notmap
check 0 "$RC" "control: the same tree without the non-mapping workflow passes"

tree nowf
run nowf
check 1 "$RC" "no workflow file fails"

rm -rf "${T:?}/notests"; mkdir -p "$T/notests/scripts" "$T/notests/wf"
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n' > "$T/notests/wf/ci.yml"
run notests
check 1 "$RC" "no test file fails"

# ── scope: test-*.sh and adapters/*/*.test.mjs ──
tree scope
mkdir -p "$T/scope/adapters/o"
: > "$T/scope/scripts/test-kit.sh"; : > "$T/scope/adapters/o/h.test.mjs"
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/scope/wf/ci.yml"
run scope
check 1 "$RC" "planted miss: test-kit.sh and the .mjs test are not run"
check yes "$(has "$OUT" "scripts/test-kit.sh is not run")" "scope: names test-kit.sh"
check yes "$(has "$OUT" "adapters/o/h.test.mjs is not run")" "scope: names the .mjs test"
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n      - run: bash scripts/test-kit.sh\n      - run: node adapters/o/h.test.mjs\n' > "$T/scope/wf/ci.yml"
run scope
check 0 "$RC" "control: bash for the .sh and node for the .mjs counts"
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n      - run: bash scripts/test-kit.sh\n      - run: bash adapters/o/h.test.mjs\n' > "$T/scope/wf/ci.yml"
run scope
check 1 "$RC" "the .mjs test run with bash does not count"

# ── shell constructs: the allow-list wires nothing for a block that holds one ──
# blockcase <name> <description> — the block on stdin holds the word CMD where the test command stands.
# The bypass runs the command inside the construct and must not count; the control puts the construct
# around an echo and the command in its own step, which counts.
blockcase() {
  local name=$1 desc=$2 body bypass ctl
  body=$(cat)
  bypass=${body//CMD/bash scripts/b.test.sh}
  ctl=${body//CMD/echo skipped}
  wired_b "$name" <<EOF
      - run: |
$(printf '%s\n' "$bypass" | sed 's/^/          /')
EOF
  check 1 "$RC" "bypass: $desc does not count"
  wired_b "${name}_ctl" <<EOF
      - run: |
$(printf '%s\n' "$ctl" | sed 's/^/          /')
      - run: bash scripts/b.test.sh
EOF
  check 0 "$RC" "control: the construct around an echo and the command in its own step counts ($desc)"
}
blockcase heredoc "a command inside a heredoc body" <<'EOF'
cat <<EOT
CMD
EOT
EOF
blockcase quote1 "a command inside a multi-line single-quoted string" <<'EOF'
echo 'start
CMD'
EOF
blockcase function "a command inside a function body" <<'EOF'
f() {
  CMD
}
EOF
blockcase if_false "a command in an if false block" <<'EOF'
if false; then
  CMD
fi
EOF
blockcase for_empty "a command in a for loop over nothing" <<'EOF'
for i in; do
  CMD
done
EOF
blockcase while_false "a command in a while false loop" <<'EOF'
while false; do
  CMD
done
EOF
blockcase case_none "a command in a case branch that never matches" <<'EOF'
case x in
  y) CMD ;;
esac
EOF
blockcase continuation "a command after a continuation line" <<'EOF'
echo hi \
CMD
EOF
blockcase exit0 "a command after exit 0" <<'EOF'
exit 0
CMD
EOF
blockcase trap "a command after a trap that exits 0" <<'EOF'
trap 'exit 0' EXIT
CMD
EOF
blockcase errexit_off "a command after set +o errexit" <<'EOF'
set +o errexit
CMD
EOF
blockcase or_list "a command after true ||" <<'EOF'
true || CMD
EOF
blockcase and_list "a command after false &&" <<'EOF'
false && CMD
EOF

wired_b folded <<'EOF'
      - run: >
          bash scripts/a.test.sh
          bash scripts/b.test.sh
EOF
check 1 "$RC" "lock: a folded block is one line, so only its first command counts"
wired_b folded_ctl <<'EOF'
      - run: |
          bash scripts/a.test.sh
          bash scripts/b.test.sh
EOF
check 0 "$RC" "control: the same block as a literal block counts both"

wired_b crlf <<'EOF'
      - run: "bash scripts/b.test.sh\r\n"
EOF
check 1 "$RC" "bypass: a carriage return after the command is not on the allow-list"

# ── shell, working directory and defaults.run ──
wired_b step_shell <<'EOF'
      - shell: cat {0}
        run: bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a step with shell: cat {0} does not count"
wired_b step_shell_ctl <<'EOF'
      - run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: the same step without shell counts"
wired_b step_cwd <<'EOF'
      - working-directory: sub
        run: bash scripts/b.test.sh
EOF
check 1 "$RC" "bypass: a step with working-directory does not count"

tree job_shell
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    defaults:\n      run:\n        shell: cat {0}\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/job_shell/wf/ci.yml"
run job_shell
check 1 "$RC" "bypass: a job with defaults.run.shell does not count"
tree job_shell_ctl
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/job_shell_ctl/wf/ci.yml"
run job_shell_ctl
check 0 "$RC" "control: the same job without defaults counts"
tree job_shell_key
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    shell: cat {0}\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/job_shell_key/wf/ci.yml"
run job_shell_key
check 1 "$RC" "bypass: a job with a shell key does not count"
tree job_defaults_other
printf 'on: pull_request\njobs:\n  a:\n    steps:\n      - run: bash scripts/a.test.sh\n  b:\n    defaults:\n      other: x\n    steps:\n      - run: bash scripts/b.test.sh\n' > "$T/job_defaults_other/wf/ci.yml"
run job_defaults_other
check 0 "$RC" "control: a job defaults mapping without run counts"

tree wf_shell
printf 'on: pull_request\ndefaults:\n  run:\n    shell: cat {0}\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/wf_shell/wf/ci.yml"
run wf_shell
check 1 "$RC" "bypass: a workflow with defaults.run.shell wires nothing"
tree wf_shell_ctl
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/wf_shell_ctl/wf/ci.yml"
run wf_shell_ctl
check 0 "$RC" "control: the same workflow without defaults counts"

# ── the pull_request trigger ──
# trig <name> <trigger text> — ci.yml wires a; a second workflow with that trigger wires b.
trig() {
  tree "$1"
  printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n' > "$T/$1/wf/ci.yml"
  { printf 'on:\n%s\njobs:\n  x:\n    steps:\n      - run: bash scripts/b.test.sh\n' "$2"; } > "$T/$1/wf/other.yml"
  run "$1"
}
trig trig_branches '  pull_request:
    branches: [no-such-branch]'
check 1 "$RC" "bypass: pull_request with branches does not count"
trig trig_branches_ignore '  pull_request:
    branches-ignore: ["**"]'
check 1 "$RC" "bypass: pull_request with branches-ignore does not count"
trig trig_types_closed '  pull_request:
    types: [closed]'
check 1 "$RC" "bypass: pull_request with types: [closed] does not count"
trig trig_types_subset '  pull_request:
    types: [opened]'
check 1 "$RC" "bypass: pull_request with a shorter types list does not count"
trig trig_unknown_key '  pull_request:
    surprise: x'
check 1 "$RC" "bypass: pull_request with an unknown key does not count"
trig trig_list '  pull_request: [opened]'
check 1 "$RC" "bypass: pull_request with a list value does not count"
trig trig_empty_list '  pull_request: []'
check 1 "$RC" "bypass: pull_request with an empty list value does not count"
trig trig_paths '  pull_request:
    paths: ["scripts/**"]
    paths-ignore: ["docs/**"]'
check 0 "$RC" "control: pull_request with paths and paths-ignore counts"
trig trig_types_ok '  pull_request:
    types: [synchronize, opened, ready_for_review]'
check 0 "$RC" "control: pull_request with the repo's types list (any order) counts"
trig trig_bare '  pull_request:'
check 0 "$RC" "control: a bare pull_request counts"
tree trig_filtered_only
printf 'on:\n  pull_request:\n    branches: [x]\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/trig_filtered_only/wf/ci.yml"
run trig_filtered_only
check 1 "$RC" "bypass: a filtered pull_request workflow alone leaves no workflow that counts"
check yes "$(has "$OUT" "no workflow file runs on pull_request")" "filtered only: says why"

tree schedule
printf 'on:\n  schedule:\n    - cron: "0 2 * * *"\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/schedule/wf/ci.yml"
run schedule
check 1 "$RC" "bypass: a schedule-only workflow does not count"
check yes "$(has "$OUT" "no workflow file runs on pull_request")" "schedule only: says why"
printf 'on:\n  schedule:\n    - cron: "0 2 * * *"\n  pull_request:\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/schedule/wf/ci.yml"
run schedule
check 0 "$RC" "control: pull_request beside a schedule counts"

# ── YAML anchors, the .bak name and missing PyYAML ──
wired_b anchor <<'EOF'
      - &s {if: false, run: "bash scripts/b.test.sh"}
      - *s
EOF
check 1 "$RC" "bypass: an anchored step with if: false, aliased, does not count"
wired_b anchor_ctl <<'EOF'
      - &s {run: "bash scripts/b.test.sh"}
      - *s
EOF
check 0 "$RC" "control: an anchored plain step counts (the YAML is resolved before the check)"

wired_b bak_ctl <<'EOF'
      - run: bash scripts/b.test.sh.bak
      - run: bash scripts/b.test.sh
EOF
check 0 "$RC" "control: a .bak run beside the real command counts"

tree nopy
printf 'on: pull_request\njobs:\n  x:\n    steps:\n      - run: bash scripts/a.test.sh\n      - run: bash scripts/b.test.sh\n' > "$T/nopy/wf/ci.yml"
printf '#!/bin/sh\nexit 1\n' > "$T/nopy/nopython"; chmod +x "$T/nopy/nopython"
OUT=$(WIRED_PYTHONS="$T/nopy/nopython $T/nopy/missing" bash "$CHECK" "$T/nopy/scripts" "$T/nopy/wf" 2>&1); RC=$?
check 1 "$RC" "bypass: no python with PyYAML fails closed"
check yes "$(has "$OUT" "no python3 with PyYAML")" "no PyYAML: says why"
OUT=$(WIRED_PYTHONS="" bash "$CHECK" "$T/nopy/scripts" "$T/nopy/wf" 2>&1); RC=$?
check 1 "$RC" "bypass: an empty interpreter list fails closed"
run nopy
check 0 "$RC" "control: the default interpreters pass the same tree"

OUT=$(bash "$CHECK" 2>&1); RC=$?
check 0 "$RC" "this repo: every repo test is run by a workflow step ($OUT)"

echo "check-tests-wired.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
