#!/usr/bin/env bash
# scripts/check-tests-wired.test.sh — tests for scripts/check-tests-wired.sh on scratch trees.
# Each failing case has a clean control (the same shape, with a real run). The cases cover text that is not
# a run (echo, a step name, `: cmd`, a comment), a step or job that cannot run (`if:`, continue-on-error,
# `|| true`, `set +e`), a workflow that never runs on a pull request, an unparsable workflow, and the
# node and test-*.sh scope. The last case runs the check on this repo.
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
          # run b
          echo start
          bash scripts/b.test.sh --verbose "x y"
EOF
check 0 "$RC" "control: a command with arguments in a run block with comments counts"
wired_b comment_punct <<'EOF'
      - run: |
          bash scripts/b.test.sh # note: a | b; c || d &
EOF
check 0 "$RC" "control: a trailing comment holding pipe, list and background marks does not hide a real command"

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
check 0 "$RC" "control: a run block that sets -euo pipefail counts"

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

OUT=$(bash "$CHECK" 2>&1); RC=$?
check 0 "$RC" "this repo: every repo test is run by a workflow step ($OUT)"

echo "check-tests-wired.test: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
